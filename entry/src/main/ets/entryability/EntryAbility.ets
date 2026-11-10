import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KEY_SHARE_IMAGE, KEY_SHARE_SEQ, KEY_SHARE_TEXT } from '../common/Types';
import { errText } from '../common/Util';
import { FloatWindowManager } from '../service/FloatWindowManager';
import { SettingsStore } from '../service/SettingsStore';

const TAG: string = 'AiTranslator';
const ACTION_SEND_DATA: string = 'ohos.want.action.sendData';

export default class EntryAbility extends UIAbility {
  private shareSeq: number = 0;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    SettingsStore.init(this.context);
    this.handleShare(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleShare(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'loadContent failed: %{public}s', errText(err));
      }
    });
  }

  onDestroy(): void {
    FloatWindowManager.close();
  }

  /** 其他应用通过系统分享面板发来的文字或图片 */
  private handleShare(want: Want): void {
    if (want.action !== ACTION_SEND_DATA) {
      return;
    }
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
      if (text.length === 0 && imageUri.length === 0) {
        return;
      }
      AppStorage.setOrCreate(KEY_SHARE_TEXT, text);
      AppStorage.setOrCreate(KEY_SHARE_IMAGE, text.length > 0 ? '' : imageUri);
      this.shareSeq++;
      AppStorage.setOrCreate(KEY_SHARE_SEQ, this.shareSeq);
    }).catch((e: Error) => {
      hilog.error(0x0000, TAG, 'getSharedData failed: %{public}s', errText(e));
    });
  }
}
