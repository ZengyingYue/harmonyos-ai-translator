import { BusinessError } from '@kit.BasicServicesKit';
import { display } from '@kit.ArkUI';

/** 把 catch 到的任意错误转成可读文本 */
export function errText(e: Object | null | undefined): string {
  if (e === null || e === undefined) {
    return '未知错误';
  }
  const be = e as BusinessError;
  if (be.message !== undefined && be.message !== null && be.message.length > 0) {
    if (be.code !== undefined && be.code !== null) {
      return be.message + '（' + be.code + '）';
    }
    return be.message;
  }
  if (be.code !== undefined && be.code !== null) {
    return '错误码 ' + be.code;
  }
  return JSON.stringify(e);
}

export function errCode(e: Object | null | undefined): number {
  if (e === null || e === undefined) {
    return 0;
  }
  const be = e as BusinessError;
  return typeof be.code === 'number' ? be.code : 0;
}

export function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

/** vp 转物理像素 */
export function px(vp: number): number {
  return Math.round(vp * display.getDefaultDisplaySync().densityPixels);
}
