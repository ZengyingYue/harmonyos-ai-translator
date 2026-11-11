import { ShareExtensionAbility, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KEY_SHARE_IMAGE, KEY_SHARE_SEQ, KEY_SHARE_TEXT } from '../common/Types';
import { errText } from '../common/Util';
import { SettingsStore } from '../service/SettingsStore';

const TAG: string = 'AiTranslator';

/**
 * 系统分享面板里的“AI 翻译”入口。
 * 在任意应用选中文字 →“分享”→“AI 翻译”，译文面板直接叠在当前应用之上，不用跳转到本应用。
 */
export default class ShareExtAbility extends ShareExtensionAbility {
  private seq: number = 0;

  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    SettingsStore.init(this.context);
    const storage = new LocalStorage();
    storage.setOrCreate('session', session);

    systemShare.getSharedData(want).then((data: systemShare.SharedData) => {
      let text = '';
      let imageUri = '';
      const records = data.getRecords();
      for (let i = 0; i < records.length; i++) {
        const r = records[i];
        if (r.content !== undefined && r.content !== null && r.content.length > 0) {
          text = text.length > 0 ? text + '\n' + r.content : r.content;
        } else if (r.uri !== undefined && r.uri !== null && r.uri.length > 0 && imageUri.length === 0) {
          imageUri = r.uri;
        }
      }
      AppStorage.setOrCreate(KEY_SHARE_TEXT, text);
      AppStorage.setOrCreate(KEY_SHARE_IMAGE, text.length > 0 ? '' : imageUri);
      this.seq++;
      AppStorage.setOrCreate(KEY_SHARE_SEQ, this.seq);
      session.loadContent('pages/SharePage', storage);
    }).catch((e: Error) => {
      hilog.error(0x0000, TAG, 'getSharedData failed: %{public}s', errText(e));
      // 拿不到分享内容时仍然打开面板，用户可以手动粘贴
      session.loadContent('pages/SharePage', storage);
    });
  }
}
