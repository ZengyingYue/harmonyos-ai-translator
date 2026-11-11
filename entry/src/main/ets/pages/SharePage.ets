import { UIExtensionContentSession } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { TranslatePanel } from '../components/TranslatePanel';

const storage = LocalStorage.getShared();

/** 分享入口的译文面板：叠在发起分享的应用之上 */
@Entry(storage)
@Component
struct SharePage {
  private session: UIExtensionContentSession | undefined = storage.get<UIExtensionContentSession>('session');

  private close(): void {
    if (this.session === undefined) {
      return;
    }
    this.session.terminateSelfWithResult({ resultCode: systemShare.ShareAbilityResultCode.CLOSE });
  }

  build() {
    Column() {
      Row() {
        Text('AI 翻译')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text('✕')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .width(40)
          .height(40)
          .onClick(() => {
            this.close();
          })
      }
      .width('100%')

      Column() {
        TranslatePanel({ compact: true })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 12 })
    .backgroundColor($r('app.color.card_bg'))
  }
}
