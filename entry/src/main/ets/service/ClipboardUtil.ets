import { pasteboard } from '@kit.BasicServicesKit';
import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { ImageUtil } from './ImageUtil';

export const PERMISSION_READ_PASTEBOARD: Permissions = 'ohos.permission.READ_PASTEBOARD';

export class ClipContent {
  text: string = '';
  pixelMap: image.PixelMap | null = null;
}

function stripHtml(html: string): string {
  return html.replace(new RegExp('<[^>]+>', 'g'), '').replace(new RegExp('&nbsp;', 'g'), ' ').trim();
}

export class ClipboardUtil {
  /** 最近一次由本应用写入剪贴板的时间，用来忽略自己触发的变化通知 */
  static lastSelfCopyAt: number = 0;

  /**
   * 读取剪贴板里的文字或图片。
   * 需要用户刚点过系统“粘贴”安全控件，或应用已获得 READ_PASTEBOARD 权限，否则会抛错。
   */
  static async read(): Promise<ClipContent> {
    const out = new ClipContent();
    const data = await pasteboard.getSystemPasteboard().getData();
    if (data.hasType(pasteboard.MIMETYPE_TEXT_PLAIN)) {
      out.text = data.getPrimaryText();
    } else if (data.hasType(pasteboard.MIMETYPE_PIXELMAP)) {
      out.pixelMap = data.getPrimaryPixelMap();
    } else if (data.hasType(pasteboard.MIMETYPE_TEXT_HTML)) {
      out.text = stripHtml(data.getPrimaryHtml());
    } else if (data.hasType(pasteboard.MIMETYPE_TEXT_URI)) {
      // 多为从相册/截图复制的图片文件
      out.pixelMap = await ImageUtil.pixelMapFromUri(data.getPrimaryUri());
    }
    return out;
  }

  static async copyText(text: string): Promise<void> {
    ClipboardUtil.lastSelfCopyAt = Date.now();
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    await pasteboard.getSystemPasteboard().setData(data);
  }

  /** 是否已获得后台读取剪贴板的权限（未在 module.json5 声明时恒为 false） */
  static hasReadPermission(): boolean {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const status = abilityAccessCtrl.createAtManager()
        .checkAccessTokenSync(info.appInfo.accessTokenId, PERMISSION_READ_PASTEBOARD);
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (e) {
      return false;
    }
  }

  /** 向用户申请读取剪贴板权限，返回是否授予 */
  static async requestReadPermission(ctx: common.UIAbilityContext): Promise<boolean> {
    if (ClipboardUtil.hasReadPermission()) {
      return true;
    }
    try {
      const res = await abilityAccessCtrl.createAtManager()
        .requestPermissionsFromUser(ctx, [PERMISSION_READ_PASTEBOARD]);
      return res.authResults.length > 0 && res.authResults[0] === 0;
    } catch (e) {
      return false;
    }
  }
}
