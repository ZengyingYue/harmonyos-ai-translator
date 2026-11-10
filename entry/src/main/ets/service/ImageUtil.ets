import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

/** 发给模型/OCR 的图片最长边上限，兼顾清晰度与流量 */
export const MAX_IMAGE_EDGE: number = 1568;

export class ImageUtil {
  /** 从文件 URI（相册、分享、剪贴板）解码图片，并按最长边等比缩小 */
  static async pixelMapFromUri(uri: string): Promise<image.PixelMap> {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const src = image.createImageSource(file.fd);
      try {
        const info = await src.getImageInfo();
        const longEdge = Math.max(info.size.width, info.size.height);
        const scale = longEdge > MAX_IMAGE_EDGE ? MAX_IMAGE_EDGE / longEdge : 1;
        const opts: image.DecodingOptions = {
          desiredSize: {
            width: Math.max(1, Math.round(info.size.width * scale)),
            height: Math.max(1, Math.round(info.size.height * scale))
          }
        };
        return await src.createPixelMap(opts);
      } finally {
        await src.release();
      }
    } finally {
      fileIo.closeSync(file);
    }
  }

  static async toJpegBase64(pm: image.PixelMap): Promise<string> {
    const packer = image.createImagePacker();
    try {
      const opt: image.PackingOption = { format: 'image/jpeg', quality: 85 };
      const buf = await packer.packing(pm, opt);
      return new util.Base64Helper().encodeToStringSync(new Uint8Array(buf));
    } finally {
      await packer.release();
    }
  }
}
