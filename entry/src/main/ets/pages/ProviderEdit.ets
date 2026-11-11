import {
  FORMAT_ANTHROPIC,
  FORMAT_GEMINI,
  FORMAT_OPENAI,
  PRESETS,
  ProviderConfig,
  ProviderPreset
} from '../common/Types';
import { errText } from '../common/Util';
import { LlmClient, LlmTask } from '../service/LlmClient';
import { SettingsStore } from '../service/SettingsStore';

interface EditParams {
  id: string;
}

@Entry
@Component
struct ProviderEdit {
  @State name: string = '';
  @State format: string = FORMAT_OPENAI;
  @State baseUrl: string = '';
  @State apiKey: string = '';
  @State model: string = '';
  @State isNew: boolean = true;
  @State testing: boolean = false;
  @State testOk: boolean = false;
  @State testMsg: string = '';
  private id: string = '';
  private testTask: LlmTask | null = null;

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as EditParams | undefined;
    const id = params !== undefined && params !== null && params.id !== undefined ? params.id : '';
    if (id.length === 0) {
      this.applyPreset(PRESETS[0]);
      return;
    }
    const providers = SettingsStore.get().providers;
    for (let i = 0; i < providers.length; i++) {
      if (providers[i].id === id) {
        const p = providers[i];
        this.id = id;
        this.isNew = false;
        this.name = p.name;
        this.format = p.format;
        this.baseUrl = p.baseUrl;
        this.apiKey = p.apiKey;
        this.model = p.model;
        return;
      }
    }
    this.applyPreset(PRESETS[0]);
  }

  aboutToDisappear(): void {
    if (this.testTask !== null) {
      this.testTask.cancel();
    }
  }

  private applyPreset(preset: ProviderPreset): void {
    this.name = preset.name;
    this.format = preset.format;
    this.baseUrl = preset.baseUrl;
    this.model = preset.model;
    this.testMsg = '';
  }

  private current(): ProviderConfig {
    return {
      id: this.id,
      name: this.name.trim().length > 0 ? this.name.trim() : '未命名服务',
      format: this.format,
      baseUrl: this.baseUrl.trim(),
      apiKey: this.apiKey.trim(),
      model: this.model.trim()
    };
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2500 });
  }

  private validate(): boolean {
    if (this.baseUrl.trim().length === 0) {
      this.toast('请填写 Base URL');
      return false;
    }
    if (this.model.trim().length === 0) {
      this.toast('请填写模型名称');
      return false;
    }
    return true;
  }

  private save(): void {
    if (!this.validate()) {
      return;
    }
    const s = SettingsStore.get();
    const p = this.current();
    if (this.isNew) {
      p.id = 'p' + Date.now();
      s.providers.push(p);
      // 新添加的服务商直接设为当前使用
      s.activeId = p.id;
    } else {
      for (let i = 0; i < s.providers.length; i++) {
        if (s.providers[i].id === p.id) {
          s.providers[i] = p;
        }
      }
    }
    SettingsStore.save(s);
    this.getUIContext().getRouter().back();
  }

  private confirmRemove(): void {
    this.getUIContext().showAlertDialog({
      title: '删除服务商',
      message: '确定删除“' + this.name + '”吗？保存的 API Key 会一并删除。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.remove();
        }
      }
    });
  }

  private remove(): void {
    const s = SettingsStore.get();
    s.providers = s.providers.filter((p: ProviderConfig) => p.id !== this.id);
    if (s.activeId === this.id) {
      s.activeId = s.providers.length > 0 ? s.providers[0].id : '';
    }
    SettingsStore.save(s);
    this.getUIContext().getRouter().back();
  }

  /** 用当前填写的内容发一次最小请求，确认地址、Key、模型都可用 */
  private async test(): Promise<void> {
    if (!this.validate() || this.testing) {
      return;
    }
    const task = new LlmTask();
    this.testTask = task;
    this.testing = true;
    this.testMsg = '';
    try {
      const reply = await LlmClient.complete(this.current(),
        'You are a connectivity check. Reply with the single word OK.', 'ping', [], false,
        (full: string) => {
        }, task);
      this.testOk = true;
      this.testMsg = '连接成功，模型回复：' + reply.trim().substring(0, 60);
    } catch (e) {
      if (!task.cancelled) {
        this.testOk = false;
        this.testMsg = errText(e);
      }
    } finally {
      this.testing = false;
      this.testTask = null;
    }
  }

  @Builder
  FieldLabel(label: string) {
    Text(label)
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .margin({ top: 6 })
  }

  @Builder
  FormatButton(label: string, value: string) {
    Button(label, { type: ButtonType.Capsule })
      .height(34)
      .fontSize(13)
      .fontColor(this.format === value ? Color.White : $r('app.color.text_primary'))
      .backgroundColor(this.format === value ? $r('app.color.brand') : $r('app.color.field_bg'))
      .layoutWeight(1)
      .onClick(() => {
        this.format = value;
      })
  }

  private urlHint(): string {
    if (this.format === FORMAT_ANTHROPIC) {
      return '会自动补全为 …/v1/messages';
    }
    if (this.format === FORMAT_GEMINI) {
      return '会自动补全为 …/models/{模型}:generateContent';
    }
    return '会自动补全为 …/chat/completions，适用于各类 OpenAI 兼容服务';
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
        Text(this.isNew ? '添加服务商' : '编辑服务商')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (!this.isNew) {
          Text('删除')
            .fontSize(15)
            .fontColor($r('app.color.danger'))
            .padding(8)
            .onClick(() => {
              this.confirmRemove();
            })
        }
      }
      .width('100%')
      .height(48)

      Scroll() {
        Column({ space: 6 }) {
          this.FieldLabel('从预设填入（之后仍可修改）')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(PRESETS, (preset: ProviderPreset) => {
              Text(preset.name)
                .fontSize(13)
                .fontColor($r('app.color.brand'))
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .margin({ right: 8, bottom: 8 })
                .borderRadius(16)
                .backgroundColor($r('app.color.brand_soft'))
                .onClick(() => {
                  this.applyPreset(preset);
                })
            }, (preset: ProviderPreset) => preset.name)
          }
          .width('100%')

          Column({ space: 6 }) {
            this.FieldLabel('名称')
            TextInput({ text: this.name, placeholder: '便于自己识别的名字' })
              .backgroundColor($r('app.color.field_bg'))
              .onChange((value: string) => {
                this.name = value;
              })

            this.FieldLabel('API 格式')
            Row({ space: 8 }) {
              this.FormatButton('OpenAI 兼容', FORMAT_OPENAI)
              this.FormatButton('Anthropic', FORMAT_ANTHROPIC)
              this.FormatButton('Gemini', FORMAT_GEMINI)
            }
            .width('100%')

            this.FieldLabel('Base URL')
            TextInput({ text: this.baseUrl, placeholder: 'https://…' })
              .type(InputType.URL)
              .backgroundColor($r('app.color.field_bg'))
              .onChange((value: string) => {
                this.baseUrl = value;
              })
            Text(this.urlHint())
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

            this.FieldLabel('API Key')
            TextInput({ text: this.apiKey, placeholder: '只保存在本机' })
              .type(InputType.Password)
              .backgroundColor($r('app.color.field_bg'))
              .onChange((value: string) => {
                this.apiKey = value;
              })

            this.FieldLabel('模型')
            TextInput({ text: this.model, placeholder: '服务商提供的模型 ID' })
              .backgroundColor($r('app.color.field_bg'))
              .onChange((value: string) => {
                this.model = value;
              })
          }
          .width('100%')
          .padding(12)
          .borderRadius(16)
          .backgroundColor($r('app.color.card_bg'))

          if (this.testMsg.length > 0) {
            Text(this.testMsg)
              .fontSize(13)
              .fontColor(this.testOk ? $r('app.color.brand') : $r('app.color.danger'))
              .copyOption(CopyOptions.LocalDevice)
              .width('100%')
              .padding(12)
              .borderRadius(12)
              .backgroundColor($r('app.color.card_bg'))
          }

          Row({ space: 12 }) {
            Button(this.testing ? '测试中…' : '测试连接', { type: ButtonType.Capsule })
              .height(44)
              .layoutWeight(1)
              .enabled(!this.testing)
              .fontColor($r('app.color.brand'))
              .backgroundColor($r('app.color.brand_soft'))
              .onClick(() => {
                this.test();
              })
            Button('保存', { type: ButtonType.Capsule })
              .height(44)
              .layoutWeight(1)
              .backgroundColor($r('app.color.brand'))
              .onClick(() => {
                this.save();
              })
          }
          .width('100%')
          .margin({ top: 12 })
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
