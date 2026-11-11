import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { delay } from '../common/Util';

/** 每行取多少个采样点做比对 */
const SAMPLE_COLS: number = 8;
/** 抽帧间隔 */
const FRAME_STEP_MS: number = 120;
/** 长图最多多少行像素（约 6～7 屏），防止占用过多内存 */
const MAX_TOTAL_ROWS: number = 10000;
/** 两帧在正确位移处的平均亮度差上限（0～255），超过说明没对上 */
const MATCH_THRESHOLD: number = 6;
/** 小于这个位移（行）视为画面没动 */
const MIN_SHIFT_ROWS: number = 8;
const BYTES_PER_PIXEL: number = 4;

export class StitchResult {
  /** 完整长图，用于预览 */
  full: image.PixelMap;
  /** 按屏切开的分段，用于识别/翻译 */
  slices: image.PixelMap[];
  /** 拼进去了多少次滚动 */
  steps: number;

  constructor(full: image.PixelMap, slices: image.PixelMap[], steps: number) {
    this.full = full;
    this.slices = slices;
    this.steps = steps;
  }
}

class Step {
  timeUs: number = 0;
  shift: number = 0;
}

class Match {
  shift: number = 0;
  score: number = 255;
}

/**
 * 把一段“边录边向上滚动”的录屏拼成一张长图。
 *
 * 做法：按固定间隔抽帧，对相邻两帧在画面中部找出内容上移了多少行，
 * 每一帧只把新露出来的那一条接到长图末尾。顶部和底部的固定栏只保留一份。
 * 只支持内容向上滚动（手指上滑）。
 */
export class LongStitcher {
  private gen: media.AVImageGenerator;
  private width: number = 0;
  private height: number = 0;
  private reqWidth: number;
  private reqHeight: number;
  private frame: Uint8Array = new Uint8Array(0);

  constructor(gen: media.AVImageGenerator, reqWidth: number, reqHeight: number) {
    this.gen = gen;
    this.reqWidth = reqWidth;
    this.reqHeight = reqHeight;
  }

  /** 取一帧并把像素（BGRA）读进 this.frame。返回 false 表示取帧失败或尺寸变了（如旋转屏幕） */
  private async load(timeUs: number): Promise<boolean> {
    let pm: image.PixelMap | null = null;
    try {
      const param: media.PixelMapParams = { width: this.reqWidth, height: this.reqHeight };
      pm = await this.gen.fetchFrameByTime(timeUs, media.AVImageQueryOptions.AVIMAGE_QUERY_CLOSEST, param);
    } catch (e) {
      return false;
    }
    if (pm === null || pm === undefined) {
      return false;
    }
    try {
      const size = pm.getImageInfoSync().size;
      if (this.width === 0) {
        this.width = size.width;
        this.height = size.height;
        this.frame = new Uint8Array(this.width * this.height * BYTES_PER_PIXEL);
      } else if (size.width !== this.width || size.height !== this.height) {
        return false;
      }
      const area: image.PositionArea = {
        pixels: this.frame.buffer as ArrayBuffer,
        offset: 0,
        stride: this.width * BYTES_PER_PIXEL,
        region: { x: 0, y: 0, size: { width: this.width, height: this.height } }
      };
      pm.readPixelsSync(area);
      return true;
    } catch (e) {
      return false;
    } finally {
      pm.release();
    }
  }

  /** 当前帧每一行的亮度采样，避开左右边缘（滚动条、侧边按钮） */
  private signature(): Uint8Array {
    const sig = new Uint8Array(this.height * SAMPLE_COLS);
    const stride = this.width * BYTES_PER_PIXEL;
    for (let y = 0; y < this.height; y++) {
      for (let k = 0; k < SAMPLE_COLS; k++) {
        const x = Math.floor(this.width * (0.1 + 0.8 * (k + 0.5) / SAMPLE_COLS));
        const o = y * stride + x * BYTES_PER_PIXEL;
        sig[y * SAMPLE_COLS + k] = (this.frame[o] + 2 * this.frame[o + 1] + this.frame[o + 2]) >> 2;
      }
    }
    return sig;
  }

  /** 求 cur 相对 prev 内容上移的行数：cur 的第 y 行 ≈ prev 的第 y + shift 行 */
  private findShift(prev: Uint8Array, cur: Uint8Array): Match {
    const h = this.height;
    const bandTop = Math.floor(h * 0.2);
    const bandLen = Math.floor(h * 0.3);
    const maxShift = Math.floor(h * 0.45);
    const samples = Math.ceil(bandLen / 2) * SAMPLE_COLS;
    const best = new Match();
    let bestSum = Number.MAX_VALUE;
    for (let d = 0; d <= maxShift; d++) {
      let sum = 0;
      for (let y = bandTop; y < bandTop + bandLen && sum < bestSum; y += 2) {
        const a = y * SAMPLE_COLS;
        const b = (y + d) * SAMPLE_COLS;
        for (let k = 0; k < SAMPLE_COLS; k++) {
          sum += Math.abs(cur[a + k] - prev[b + k]);
        }
      }
      if (sum < bestSum) {
        bestSum = sum;
        best.shift = d;
      }
    }
    best.score = bestSum / samples;
    return best;
  }

  /** 两帧底部连续有多少行完全没变（固定的底栏） */
  private staticBottomRows(prev: Uint8Array, cur: Uint8Array): number {
    let rows = 0;
    for (let y = this.height - 1; y >= 0; y--) {
      let sum = 0;
      const a = y * SAMPLE_COLS;
      for (let k = 0; k < SAMPLE_COLS; k++) {
        sum += Math.abs(cur[a + k] - prev[a + k]);
      }
      if (sum > SAMPLE_COLS * 4) {
        break;
      }
      rows++;
    }
    return rows;
  }

  /**
   * @param fromMs 录屏里可用画面的起点（跳过授权弹窗退场）
   * @param toMs 录屏时长
   */
  async stitch(fromMs: number, toMs: number, onProgress: (message: string) => void): Promise<StitchResult> {
    // ---------- 第一遍：只算每一帧的位移 ----------
    if (!await this.load(fromMs * 1000)) {
      throw new Error('无法从录屏中取出画面');
    }
    const h = this.height;
    const stride = this.width * BYTES_PER_PIXEL;
    let prevSig = this.signature();
    const steps: Step[] = [];
    let totalShift = 0;
    let footer = Math.floor(h * 0.3);
    for (let t = fromMs + FRAME_STEP_MS; t <= toMs && h + totalShift < MAX_TOTAL_ROWS; t += FRAME_STEP_MS) {
      onProgress('分析滚动画面 ' + Math.round((t - fromMs) * 100 / Math.max(1, toMs - fromMs)) + '%');
      if (!await this.load(t * 1000)) {
        continue;
      }
      const sig = this.signature();
      const m = this.findShift(prevSig, sig);
      if (m.score > MATCH_THRESHOLD || m.shift < MIN_SHIFT_ROWS) {
        // 画面没动，或滚得太快/有动画对不上：跳过这一帧，下一帧仍与上一张已采用的帧比对
        continue;
      }
      footer = Math.min(footer, this.staticBottomRows(prevSig, sig));
      const step = new Step();
      step.timeUs = t * 1000;
      step.shift = Math.min(m.shift, MAX_TOTAL_ROWS - h - totalShift);
      steps.push(step);
      totalShift += step.shift;
      prevSig = sig;
      await delay(0);
    }

    // ---------- 第二遍：按位移把像素拼起来 ----------
    // 每帧新增的内容取自底栏正上方的一条；底栏本身只在最后补一次
    const contentBottom = h - footer;
    const totalRows = h + totalShift;
    const canvas = new Uint8Array(totalRows * stride);
    if (!await this.load(fromMs * 1000)) {
      throw new Error('无法从录屏中取出画面');
    }
    canvas.set(this.frame.subarray(0, contentBottom * stride), 0);
    let row = contentBottom;
    for (let i = 0; i < steps.length; i++) {
      onProgress('拼接长图 ' + (i + 1) + '/' + steps.length);
      if (!await this.load(steps[i].timeUs)) {
        throw new Error('拼接长图时读取画面失败');
      }
      const d = steps[i].shift;
      canvas.set(this.frame.subarray((contentBottom - d) * stride, contentBottom * stride), row * stride);
      row += d;
      await delay(0);
    }
    canvas.set(this.frame.subarray(contentBottom * stride, h * stride), row * stride);

    // ---------- 输出：整张预览 + 按屏分段 ----------
    const slices: image.PixelMap[] = [];
    let pos = 0;
    while (pos < totalRows) {
      let end = Math.min(totalRows, pos + h);
      if (end < totalRows) {
        end = this.findCutRow(canvas, end, pos + Math.floor(h / 2));
      }
      slices.push(this.toPixelMap(canvas.buffer.slice(pos * stride, end * stride) as ArrayBuffer, end - pos));
      pos = end;
    }
    const full = this.toPixelMap(canvas.buffer as ArrayBuffer, totalRows);
    return new StitchResult(full, slices, steps.length);
  }

  /** 从 target 往上找一行纯色（文字行之间的空隙）作为分段位置，避免把一行字切成两半 */
  private findCutRow(canvas: Uint8Array, target: number, lowest: number): number {
    const stride = this.width * BYTES_PER_PIXEL;
    const cols = 24;
    for (let y = target; y > lowest; y--) {
      let min = 255;
      let max = 0;
      for (let k = 0; k < cols; k++) {
        const x = Math.floor(this.width * (k + 0.5) / cols);
        const v = canvas[y * stride + x * BYTES_PER_PIXEL + 1];
        min = Math.min(min, v);
        max = Math.max(max, v);
      }
      if (max - min < 10) {
        return y;
      }
    }
    return target;
  }

  private toPixelMap(buffer: ArrayBuffer, rows: number): image.PixelMap {
    const opts: image.InitializationOptions = {
      size: { width: this.width, height: rows },
      srcPixelFormat: image.PixelMapFormat.BGRA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: false
    };
    return image.createPixelMapSync(buffer, opts);
  }
}
