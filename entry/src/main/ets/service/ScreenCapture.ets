import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { delay, errText } from '../common/Util';
import { MAX_IMAGE_EDGE } from './ImageUtil';
import { LongStitcher, StitchResult } from './LongStitcher';

const START_TIMEOUT_MS: number = 60000;
/** 用户同意后再等一会儿，让系统授权弹窗的退场动画结束 */
const SETTLE_MS: number = 900;
/** 滚动截屏最长录多久 */
const SCROLL_MAX_MS: number = 40000;
/** 滚动截屏拼接时使用的画面宽度（px）。越大越清晰，也越占内存 */
const SCROLL_FRAME_WIDTH: number = 720;

/**
 * 截取当前屏幕（可以是任意应用的画面）。
 *
 * ArkTS 没有面向三方应用的“静默截屏”接口，这里用系统屏幕录制（AVScreenCapture）
 * 录一小段视频再取帧。每次都会由系统弹出授权弹窗，由用户确认后才开始采集。
 */
export class ScreenCapture {
  /** 普通截屏：取当前这一屏 */
  static async captureOnce(ctx: Context): Promise<image.PixelMap> {
    const path = ctx.cacheDir + '/capture_' + Date.now() + '.mp4';
    try {
      await ScreenCapture.record(path, async (): Promise<void> => {
        await delay(SETTLE_MS);
      });
      return await ScreenCapture.lastFrame(path);
    } finally {
      ScreenCapture.remove(path);
    }
  }

  /**
   * 滚动截屏：录屏期间由用户手动向上滚动页面，结束后拼成长图。
   * @param onRecording 系统授权通过、真正开始录制时回调
   * @param shouldStop 返回 true 时结束录制（用户点了“完成”）
   */
  static async captureScrolling(ctx: Context, onRecording: () => void, shouldStop: () => boolean,
    onProgress: (message: string) => void): Promise<StitchResult> {
    const path = ctx.cacheDir + '/scroll_' + Date.now() + '.mp4';
    try {
      const durationMs = await ScreenCapture.record(path, async (ended: () => boolean): Promise<void> => {
        onRecording();
        const begin = Date.now();
        while (!shouldStop() && !ended() && Date.now() - begin < SCROLL_MAX_MS) {
          await delay(80);
        }
      });
      onProgress('正在处理录屏…');
      return await ScreenCapture.stitch(path, durationMs, onProgress);
    } finally {
      ScreenCapture.remove(path);
    }
  }

  private static remove(path: string): void {
    try {
      fileIo.unlinkSync(path);
    } catch (e) {
      // 文件可能还没创建
    }
  }

  /**
   * 录屏到 path。
   * @param hold 开始录制后调用，返回时停止录制；参数 ended() 表示录制已被系统或用户从外部结束
   * @returns 实际录制时长（毫秒）
   */
  private static async record(path: string, hold: (ended: () => boolean) => Promise<void>): Promise<number> {
    const file = fileIo.openSync(path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    let recorder: media.AVScreenCaptureRecorder | null = null;
    try {
      recorder = await media.createAVScreenCaptureRecorder();
      let started = false;
      let endedOutside = false;
      let failure = '';
      recorder.on('stateChange', (state: media.AVScreenCaptureStateCode) => {
        if (state === media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_STARTED) {
          started = true;
        } else if (state === media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_CANCELED) {
          failure = '已取消截屏';
        } else if (state === media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_STOPPED_BY_USER ||
          state === media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_INTERRUPTED_BY_OTHER ||
          state === media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_STOPPED_BY_CALL) {
          // 用户点了系统录屏胶囊上的停止，或被来电等打断：已经录到的部分照常使用
          endedOutside = true;
        }
        // 其余状态（麦克风静音等）不影响取画面
      });
      recorder.on('error', (err: BusinessError) => {
        failure = '截屏失败：' + errText(err);
      });

      const config: media.AVScreenCaptureRecordConfig = { fd: file.fd };
      await recorder.init(config);
      await recorder.setMicEnabled(false);
      await recorder.startRecording();

      const begin = Date.now();
      while (!started && failure.length === 0) {
        if (Date.now() - begin > START_TIMEOUT_MS) {
          failure = '等待截屏授权超时';
          break;
        }
        await delay(100);
      }
      if (failure.length > 0) {
        throw new Error(failure);
      }
      const startedAt = Date.now();
      await hold((): boolean => endedOutside);
      const durationMs = Date.now() - startedAt;
      if (!endedOutside) {
        await recorder.stopRecording();
      }
      return durationMs;
    } finally {
      if (recorder !== null) {
        try {
          await recorder.release();
        } catch (e) {
          // 忽略释放失败
        }
      }
      fileIo.closeSync(file);
    }
  }

  private static async lastFrame(path: string): Promise<image.PixelMap> {
    const size = fileIo.statSync(path).size;
    if (size <= 0) {
      throw new Error('截屏没有采集到画面');
    }
    const d = display.getDefaultDisplaySync();
    const longEdge = Math.max(d.width, d.height);
    const scale = longEdge > MAX_IMAGE_EDGE ? MAX_IMAGE_EDGE / longEdge : 1;
    const param: media.PixelMapParams = {
      width: Math.round(d.width * scale),
      height: Math.round(d.height * scale)
    };

    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    const generator = await media.createAVImageGenerator();
    try {
      generator.fdSrc = { fd: file.fd, offset: 0, length: size };
      // 取一个远大于录制时长的时间点，得到最接近的（即最后一）帧
      let pm: image.PixelMap | null = null;
      try {
        pm = await generator.fetchFrameByTime(60 * 1000 * 1000,
          media.AVImageQueryOptions.AVIMAGE_QUERY_CLOSEST, param);
      } catch (e) {
        pm = null;
      }
      if (pm === null || pm === undefined) {
        pm = await generator.fetchFrameByTime(0, media.AVImageQueryOptions.AVIMAGE_QUERY_NEXT_SYNC, param);
      }
      if (pm === null || pm === undefined) {
        throw new Error('无法从录屏中取出画面');
      }
      return pm;
    } finally {
      try {
        await generator.release();
      } catch (e) {
        // 忽略释放失败
      }
      fileIo.closeSync(file);
    }
  }

  private static async stitch(path: string, durationMs: number,
    onProgress: (message: string) => void): Promise<StitchResult> {
    const size = fileIo.statSync(path).size;
    if (size <= 0) {
      throw new Error('截屏没有采集到画面');
    }
    const d = display.getDefaultDisplaySync();
    const scale = d.width > SCROLL_FRAME_WIDTH ? SCROLL_FRAME_WIDTH / d.width : 1;
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    const generator = await media.createAVImageGenerator();
    try {
      generator.fdSrc = { fd: file.fd, offset: 0, length: size };
      const stitcher = new LongStitcher(generator, Math.round(d.width * scale), Math.round(d.height * scale));
      return await stitcher.stitch(SETTLE_MS, Math.max(SETTLE_MS, durationMs), onProgress);
    } finally {
      try {
        await generator.release();
      } catch (e) {
        // 忽略释放失败
      }
      fileIo.closeSync(file);
    }
  }
}
