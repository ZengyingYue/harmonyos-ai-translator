import { common } from '@kit.AbilityKit';
import {
  formatLabel,
  IMAGE_MODE_OCR,
  IMAGE_MODE_VISION,
  langIndex,
  LANGS,
  ProviderConfig
} from '../common/Types';
import { ClipboardUtil } from '../service/ClipboardUtil';
import { SettingsStore } from '../service/SettingsStore';

/** 传给服务商编辑页的参数；id 为空表示新建 */
interface EditParams {
  id: string;
}

@Entry
@Component
struct Settings {
  @State providers: ProviderConfig[] = [];
  @State activeId: string = '';
  @State secondIdx: number = 0;
  @State imageMode: string = IMAGE_MODE_OCR;
  @State stream: boolean = true;
  @State autoClipboard: boolean = true;
  @State customPrompt: string = '';
  @State clipGranted: boolean = false;

  aboutToAppear(): void {
    // 开关的初始状态在首次构建时确定，必须先读出设置
    this.reload();
  }

  onPageShow(): void {
    // 从服务商编辑页返回时刷新列表
    this.reload();
  }

  private reload(): void {
    const s = SettingsStore.get();
    this.providers = s.providers;
    this.activeId = s.activeId;
    this.secondIdx = Math.max(0, langIndex(s.secondLang));
    this.imageMode = s.imageMode;
    this.stream = s.stream;
    this.autoClipboard = s.autoClipboard;
    this.customPrompt = s.customPrompt;
    this.clipGranted = ClipboardUtil.hasReadPermission();
  }

  private persist(): void {
    const s = SettingsStore.get();
    s.activeId = this.activeId;
    s.secondLang = LANGS[this.secondIdx].code;
    s.imageMode = this.imageMode;
    s.stream = this.stream;
    s.autoClipboard = this.autoClipboard;
    s.customPrompt = this.customPrompt;
    SettingsStore.save(s);
  }

  private editProvider(id: string): void {
    const params: EditParams = { id: id };
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ProviderEdit', params: params });
  }

  private languageOptions(): SelectOption[] {
    const list: SelectOption[] = [];
    for (let i = 0; i < LANGS.length; i++) {
      list.push({ value: LANGS[i].name });
    }
    return list;
  }

  private requestClipboardPermission(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ClipboardUtil.requestReadPermission(ctx).then((granted: boolean) => {
      this.clipGranted = granted;
      if (!granted) {
        this.getUIContext().getPromptAction().showToast({
          message: '未获得权限。复制后悬浮球会亮起红点，点开按“粘贴”即可翻译',
          duration: 3500
        });
      }
    });
  }

  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 4, top: 8 })
  }

  @Builder
  SwitchRow(title: string, desc: string, isOn: boolean, onChange: (value: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        if (desc.length > 0) {
          Text(desc)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
      }
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor($r('app.color.brand'))
        .onChange(onChange)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  ModeButton(label: string, mode: string) {
    Button(label, { type: ButtonType.Capsule })
      .height(34)
      .fontSize(14)
      .fontColor(this.imageMode === mode ? Color.White : $r('app.color.text_primary'))
      .backgroundColor(this.imageMode === mode ? $r('app.color.brand') : $r('app.color.field_bg'))
      .layoutWeight(1)
      .onClick(() => {
        this.imageMode = mode;
        this.persist();
      })
  }

  @Builder
  ProviderRow(p: ProviderConfig) {
    Row({ space: 12 }) {
      Radio({ value: p.id, group: 'activeProvider' })
        .checked(this.activeId === p.id)
        .radioStyle({ checkedBackgroundColor: $r('app.color.brand') })
        .onChange((checked: boolean) => {
          if (checked && this.activeId !== p.id) {
            this.activeId = p.id;
            this.persist();
          }
        })
      Column({ space: 2 }) {
        Text(p.name)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(formatLabel(p.format) + ' · ' + (p.model.length > 0 ? p.model : '未填写模型') +
          (p.apiKey.length > 0 ? '' : ' · 未填写 Key'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)

      Text('编辑 ›')
        .fontSize(14)
        .fontColor($r('app.color.brand'))
        .padding({ top: 8, bottom: 8, left: 8 })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      this.editProvider(p.id);
    })
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text('‹')
          .fontSize(30)
          .fontColor($r('app.color.text_primary'))
          .padding({ right: 8 })
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
        Text('设置')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(48)

      Scroll() {
        Column({ space: 8 }) {
          this.SectionTitle('模型服务（选中的那一个用于翻译）')
          Column() {
            ForEach(this.providers, (p: ProviderConfig) => {
              this.ProviderRow(p)
            }, (p: ProviderConfig) => p.id + '|' + p.name + '|' + p.model + '|' + p.format + '|' + p.apiKey.length)
            if (this.providers.length === 0) {
              Text('还没有服务商。添加一个并填写你自己的 API Key 即可开始使用。')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .padding({ top: 8, bottom: 8 })
            }
            Button('＋ 添加服务商', { type: ButtonType.Capsule })
              .width('100%')
              .height(40)
              .margin({ top: 8 })
              .fontColor($r('app.color.brand'))
              .backgroundColor($r('app.color.brand_soft'))
              .onClick(() => {
                this.editProvider('');
              })
          }
          .width('100%')
          .padding(12)
          .borderRadius(16)
          .backgroundColor($r('app.color.card_bg'))

          this.SectionTitle('翻译')
          Column() {
            Row() {
              Column({ space: 2 }) {
                Text('备用目标语言')
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')
                Text('原文已经是目标语言时，改为翻译成它')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              .layoutWeight(1)

              Select(this.languageOptions())
                .selected(this.secondIdx)
                .value(LANGS[this.secondIdx].name)
                .font({ size: 14 })
                .onSelect((index: number) => {
                  this.secondIdx = index;
                  this.persist();
                })
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })

            Column({ space: 8 }) {
              Text('图片 / 截屏翻译方式')
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Row({ space: 8 }) {
                this.ModeButton('本机识别文字', IMAGE_MODE_OCR)
                this.ModeButton('多模态模型', IMAGE_MODE_VISION)
              }
              .width('100%')

              Text(this.imageMode === IMAGE_MODE_OCR
                ? '先在手机上识别出文字，再交给模型翻译。任何模型都能用，图片不会上传。'
                : '把图片直接发给模型识别并翻译。排版复杂或手写内容效果更好，需要所选模型支持图片输入。')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })

            this.SwitchRow('流式输出', '边生成边显示译文', this.stream, (value: boolean) => {
              this.stream = value;
              this.persist();
            })

            Column({ space: 8 }) {
              Text('自定义翻译要求（可选）')
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              TextArea({ text: this.customPrompt, placeholder: '例如：使用口语化的表达；专业术语保留英文原文' })
                .height(80)
                .fontSize(14)
                .backgroundColor($r('app.color.field_bg'))
                .borderRadius(12)
                .onChange((value: string) => {
                  this.customPrompt = value;
                })
                .onBlur(() => {
                  this.persist();
                })
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
          }
          .width('100%')
          .padding(12)
          .borderRadius(16)
          .backgroundColor($r('app.color.card_bg'))

          this.SectionTitle('悬浮窗')
          Column() {
            this.SwitchRow('留意剪贴板变化', '悬浮窗开启时，复制内容后提醒或自动翻译', this.autoClipboard,
              (value: boolean) => {
                this.autoClipboard = value;
                this.persist();
              })
            Row({ space: 12 }) {
              Text(this.clipGranted
                ? '已获得读取剪贴板权限：复制后会自动弹出译文。'
                : '未获得读取剪贴板权限：复制后悬浮球会亮起红点，点开按“粘贴”翻译。')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .layoutWeight(1)
              if (!this.clipGranted) {
                Button('申请权限', { type: ButtonType.Capsule })
                  .height(32)
                  .fontSize(13)
                  .fontColor($r('app.color.brand'))
                  .backgroundColor($r('app.color.brand_soft'))
                  .onClick(() => {
                    this.requestClipboardPermission();
                  })
              }
            }
            .width('100%')
            .padding({ top: 4, bottom: 8 })
          }
          .width('100%')
          .padding(12)
          .borderRadius(16)
          .backgroundColor($r('app.color.card_bg'))

          this.SectionTitle('怎么在其他应用里用')
          Text('1. 回到首页打开“悬浮窗”，屏幕边缘会出现“译”字悬浮球，可以拖动。\n' +
            '2. 复制翻译：在任意应用里复制文字，点悬浮球，再点“粘贴”。\n' +
            '3. 截屏翻译：点悬浮球里的“截屏”，同意系统的屏幕采集提示后自动翻译当前画面。\n' +
            '4. 不开悬浮窗也可以：选中文字或打开截图后点“分享”，选择“AI 翻译”。')
            .fontSize(13)
            .lineHeight(21)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding(12)
            .borderRadius(16)
            .backgroundColor($r('app.color.card_bg'))
        }
        .width('100%')
        .padding({ bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8 })
    .backgroundColor($r('app.color.page_bg'))
  }
}
