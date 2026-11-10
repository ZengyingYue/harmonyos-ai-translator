import { common } from '@kit.AbilityKit';
import { TranslatePanel } from '../components/TranslatePanel';
import { KEY_FLOAT_SHOWN, KEY_SETTINGS_VERSION } from '../common/Types';
import { errCode, errText } from '../common/Util';
import { FloatWindowManager } from '../service/FloatWindowManager';
import { SettingsStore } from '../service/SettingsStore';

const ERR_PERMISSION_DENIED: number = 201;

@Entry
@Component
struct Index {
  /** 悬浮窗的真实状态（由 FloatWindowManager 写入） */
  @StorageProp(KEY_FLOAT_SHOWN) @Watch('syncFloatSwitch') floatShown: boolean = false;
  /** 开关的显示状态 */
  @State floatOn: boolean = false;
  @StorageProp(KEY_SETTINGS_VERSION) @Watch('refreshProviderState') settingsVersion: number = 0;
  @State hasProvider: boolean = false;

  aboutToAppear(): void {
    this.floatOn = this.floatShown;
    this.refreshProviderState();
  }

  syncFloatSwitch(): void {
    this.floatOn = this.floatShown;
  }

  refreshProviderState(): void {
    this.hasProvider = SettingsStore.activeProvider() !== null;
  }

  private openSettings(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/Settings' });
  }

  private toggleFloat(on: boolean): void {
    if (on === FloatWindowManager.isShown()) {
      return;
    }
    if (!on) {
      FloatWindowManager.close();
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    FloatWindowManager.show(ctx).then(() => {
      this.getUIContext().getPromptAction().showToast({
        message: '悬浮球已开启，可以切到其他应用使用',
        duration: 2500
      });
    }).catch((e: Error) => {
      this.floatOn = false;
      const denied = errCode(e) === ERR_PERMISSION_DENIED;
      this.getUIContext().showAlertDialog({
        title: '无法开启悬浮窗',
        message: denied
          ? '应用没有获得悬浮窗权限（ohos.permission.SYSTEM_FLOAT_WINDOW）。\n' +
            '这是受限开放权限，需要在签名证书里授权，申请方法见项目 README。\n\n' +
            '在此之前，仍可以在其他应用里选中文字或截图后点“分享”，选择“AI 翻译”来翻译。'
          : errText(e),
        confirm: {
          value: '知道了',
          action: () => {
          }
        }
      });
    });
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text('AI 翻译')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('悬浮窗')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
        Toggle({ type: ToggleType.Switch, isOn: $$this.floatOn })
          .selectedColor($r('app.color.brand'))
          .onChange((isOn: boolean) => {
            this.toggleFloat(isOn);
          })
        Button('设置', { type: ButtonType.Capsule })
          .height(34)
          .fontSize(14)
          .fontColor($r('app.color.brand'))
          .backgroundColor($r('app.color.brand_soft'))
          .onClick(() => {
            this.openSettings();
          })
      }
      .width('100%')

      if (!this.hasProvider) {
        Row() {
          Text('还没有配置模型服务，点这里添加服务商并填写 API Key')
            .fontSize(14)
            .fontColor($r('app.color.brand'))
            .layoutWeight(1)
          Text('›')
            .fontSize(20)
            .fontColor($r('app.color.brand'))
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor($r('app.color.brand_soft'))
        .onClick(() => {
          this.openSettings();
        })
      }

      Column() {
        TranslatePanel({ compact: false })
      }
      .layoutWeight(1)
      .width('100%')
      .padding(12)
      .borderRadius(16)
      .backgroundColor($r('app.color.card_bg'))
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 16 })
    .backgroundColor($r('app.color.page_bg'))
  }
}
