import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { delay, errText } from '../common/Util';
import { MAX_IMAGE_EDGE } from './ImageUtil';

const START_TIMEOUT_MS: number = 60000;
/** 用户同意后再等一会儿，让系统授权弹窗的退场动画结束 */
const SETTLE_MS: number = 900;

/**
 * 截取当前屏幕（可以是任意应用的画面）。
 *
 * ArkTS 没有面向三方应用的“静默截屏”接口，这里用系统屏幕录制（AVScreenCapture）
 * 录一小段视频再取最后一帧。每次都会由系统弹出授权弹窗，由用户确认后才开始采集。
 */
export class ScreenCapture {
  static async captureOnce(ctx: Context): Promise<image.PixelMap> {
    const path = ctx.cacheDir + '/capture_' + Date.now() + '.mp4';
    try {
      await ScreenCapture.record(path);
      return await ScreenCapture.lastFrame(path);
    } finally {
      try {
        fileIo.unlinkSync(path);
      } catch (e) {
        // 文件可能还没创建
      }
    }
  }

  private static async record(path: string): Promise<void> {
    const file = fileIo.openSync(path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    let recorder: media.AVScreenCaptureRecorder | null = null;
    try {
      recorder = await media.createAVScreenCaptureRecorder();
      let started = false;
      let failure = '';
      recorder.on('stateChange', (state: media.AVScreenCaptureStateCode) => {
        if (state === media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_STARTED) {
          started = true;
        } else if (state === media.AVScreenCaptureStateCode.SCREENCAPTURE_STATE_CANCELED) {
          failure = '已取消截屏';
        }
        // 其余状态（麦克风静音、被其他录屏打断等）不影响取一帧画面
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
      await delay(SETTLE_MS);
      await recorder.stopRecording();
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
}
