import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import {
  KEY_CLIP_HINT,
  KEY_CLIP_SEQ,
  KEY_SETTINGS_VERSION,
  KEY_SHARE_IMAGE,
  KEY_SHARE_SEQ,
  KEY_SHARE_TEXT,
  LANG_AUTO,
  LANGS,
  langIndex
} from '../common/Types';
import { delay, errText } from '../common/Util';
import { ClipboardUtil, ClipContent } from '../service/ClipboardUtil';
import { FloatWindowManager } from '../service/FloatWindowManager';
import { HistoryItem, HistoryStore, IMAGE_SOURCE_MARK } from '../service/HistoryStore';
import { ImageUtil } from '../service/ImageUtil';
import { LlmTask } from '../service/LlmClient';
import { LengthMetrics } from '@kit.ArkUI';
import { ScreenCapture } from '../service/ScreenCapture';
import { StitchResult } from '../service/LongStitcher';
import { SettingsStore } from '../service/SettingsStore';
import { Translator } from '../service/Translator';

type Job = (task: LlmTask, onDelta: (full: string) => void) => Promise<string>;

/**
 * 翻译面板：输入/粘贴/图片/截屏 → 译文。
 * 主页面、悬浮窗、分享面板共用。
 * compact：紧凑布局；floating：位于悬浮窗内（多一个“截屏”按钮，并响应剪贴板变化）。
 */
@Component
export struct TranslatePanel {
  @Prop compact: boolean = false;
  @Prop floating: boolean = false;
  @State inputText: string = '';
  @State result: string = '';
  @State errorMsg: string = '';
  @State statusText: string = '';
  @State busy: boolean = false;
  @State preview: image.PixelMap | null = null;
  /** 0 表示自动检测，其余为 LANGS 下标 + 1 */
  @State srcIdx: number = 0;
  @State tgtIdx: number = 0;
  @State providerLabel: string = '';
  @State showHistory: boolean = false;
  @State history: HistoryItem[] = [];
  @StorageProp(KEY_SETTINGS_VERSION) @Watch('onSettingsChanged') settingsVersion: number = 0;
  @StorageProp(KEY_SHARE_SEQ) @Watch('onShare') shareSeq: number = 0;
  @StorageProp(KEY_CLIP_SEQ) @Watch('onClipboardChanged') clipSeq: number = 0;
  private task: LlmTask | null = null;
  private runId: number = 0;
  private lastClipText: string = '';

  aboutToAppear(): void {
    this.loadSettings();
    if (!this.floating && this.shareSeq > 0) {
      // 冷启动时分享数据可能先于页面到达
      this.onShare();
    }
  }

  aboutToDisappear(): void {
    this.cancel();
  }

  // ---------- 设置 ----------
  private loadSettings(): void {
    const s = SettingsStore.get();
    this.srcIdx = s.sourceLang === LANG_AUTO ? 0 : Math.max(0, langIndex(s.sourceLang) + 1);
    this.tgtIdx = Math.max(0, langIndex(s.targetLang));
    const p = SettingsStore.activeProvider();
    this.providerLabel = p === null ? '未配置模型' : p.name + ' · ' + p.model;
  }

  onSettingsChanged(): void {
    this.loadSettings();
  }

  private saveLanguages(): void {
    const s = SettingsStore.get();
    s.sourceLang = this.srcIdx === 0 ? LANG_AUTO : LANGS[this.srcIdx - 1].code;
    s.targetLang = LANGS[this.tgtIdx].code;
    SettingsStore.save(s);
  }

  private sourceOptions(): SelectOption[] {
    const list: SelectOption[] = [{ value: '自动检测' }];
    for (let i = 0; i < LANGS.length; i++) {
      list.push({ value: LANGS[i].name });
    }
    return list;
  }

  private targetOptions(): SelectOption[] {
    const list: SelectOption[] = [];
    for (let i = 0; i < LANGS.length; i++) {
      list.push({ value: LANGS[i].name });
    }
    return list;
  }

  private swapLanguages(): void {
    if (this.srcIdx === 0) {
      this.toast('源语言为“自动检测”时无需互换');
      return;
    }
    const src = this.srcIdx - 1;
    this.srcIdx = this.tgtIdx + 1;
    this.tgtIdx = src;
    this.saveLanguages();
  }

  // ---------- 翻译流程 ----------
  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2500 });
  }

  private cancel(): void {
    const t = this.task;
    this.task = null;
    if (t !== null) {
      t.cancel();
    }
    this.runId++;
    this.busy = false;
    this.statusText = '';
  }

  private async run(status: string, job: Job): Promise<void> {
    this.cancel();
    const id = this.runId;
    const task = new LlmTask();
    this.task = task;
    this.busy = true;
    this.statusText = status;
    this.errorMsg = '';
    this.result = '';
    try {
      const out = await job(task, (full: string) => {
        if (id === this.runId) {
          this.statusText = '';
          this.result = full;
        }
      });
      if (id === this.runId) {
        this.result = out;
        HistoryStore.add(this.inputText, out);
      }
    } catch (e) {
      if (id === this.runId && !task.cancelled) {
        this.errorMsg = errText(e);
      }
    } finally {
      if (id === this.runId) {
        this.busy = false;
        this.statusText = '';
        this.task = null;
      }
    }
  }

  private async translateInput(): Promise<void> {
    const text = this.inputText.trim();
    if (text.length === 0) {
      this.toast('请先输入或粘贴要翻译的内容');
      return;
    }
    this.preview = null;
    await this.run('翻译中…', (task: LlmTask, onDelta: (full: string) => void) =>
    Translator.translateText(text, onDelta, task));
  }

  private async translateImage(pm: image.PixelMap): Promise<void> {
    await this.translateImages(pm, [pm]);
  }

  /**
   * @param preview 显示在面板里的预览图
   * @param parts 实际送去识别/翻译的图片（长截屏是按屏切开的多张）
   */
  private async translateImages(preview: image.PixelMap, parts: image.PixelMap[]): Promise<void> {
    this.preview = preview;
    this.inputText = '';
    await this.run('识别并翻译图片中…', (task: LlmTask, onDelta: (full: string) => void) =>
    Translator.translateImages(parts, (source: string) => {
      this.inputText = source;
    }, onDelta, task));
  }

  private async handleClip(clip: ClipContent): Promise<void> {
    if (clip.pixelMap !== null) {
      await this.translateImage(clip.pixelMap);
    } else if (clip.text.trim().length > 0) {
      this.lastClipText = clip.text;
      this.inputText = clip.text;
      await this.translateInput();
    } else {
      this.toast('剪贴板里没有可翻译的文字或图片');
    }
  }

  /** 用户点了系统“粘贴”安全控件并获得授权 */
  private async pasteAndTranslate(): Promise<void> {
    try {
      await this.handleClip(await ClipboardUtil.read());
    } catch (e) {
      this.errorMsg = '读取剪贴板失败：' + errText(e);
    }
  }

  private async pickImage(): Promise<void> {
    try {
      const option = new photoAccessHelper.PhotoSelectOptions();
      option.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      option.maxSelectNumber = 1;
      const picked = await new photoAccessHelper.PhotoViewPicker().select(option);
      if (picked.photoUris.length === 0) {
        return;
      }
      await this.translateImage(await ImageUtil.pixelMapFromUri(picked.photoUris[0]));
    } catch (e) {
      this.errorMsg = '选择图片失败：' + errText(e);
    }
  }

  /** 悬浮窗里的“截屏”：截下当前屏幕（其他应用的画面）并翻译 */
  private async captureScreen(): Promise<void> {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    this.cancel();
    this.errorMsg = '';
    let pm: image.PixelMap | null = null;
    FloatWindowManager.setCapturing(true);
    try {
      await delay(120);
      pm = await ScreenCapture.captureOnce(ctx);
    } catch (e) {
      this.errorMsg = errText(e) + '\n也可以先用系统截屏，再点“相册”选择截图，或在截图预览里“分享”到本应用。';
    } finally {
      FloatWindowManager.setCapturing(false);
    }
    if (pm !== null) {
      await this.translateImage(pm);
    }
  }

  /**
   * 悬浮窗里的“长截屏”：录屏期间用户手动向上滚动页面，点“完成”后拼成长图再翻译。
   * 三方应用无法替用户滚动别的应用，所以滚动这一步需要手动做。
   */
  private async captureScrolling(): Promise<void> {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    this.cancel();
    this.errorMsg = '';
    this.result = '';
    let stitched: StitchResult | null = null;
    await FloatWindowManager.enterScrollMode();
    try {
      stitched = await ScreenCapture.captureScrolling(ctx, () => {
        this.toast('开始录制：请慢慢向上滑动页面，滑完后点右上角“完成”');
      }, () => FloatWindowManager.scrollStopRequested(), (message: string) => {
        // 第一次进度回调说明录制已结束：先把面板恢复出来，再显示拼接进度
        FloatWindowManager.exitScrollMode();
        this.statusText = message;
      });
    } catch (e) {
      this.errorMsg = errText(e);
    } finally {
      await FloatWindowManager.exitScrollMode();
      this.statusText = '';
    }
    if (stitched === null) {
      return;
    }
    if (stitched.steps === 0) {
      this.toast('没有检测到滚动，按普通截屏翻译');
    }
    await this.translateImages(stitched.full, stitched.slices);
  }

  // ---------- 外部触发 ----------
  /** 其他应用分享进来的文字/图片（悬浮窗不处理） */
  onShare(): void {
    if (this.floating) {
      return;
    }
    const text = AppStorage.get<string>(KEY_SHARE_TEXT) ?? '';
    const uri = AppStorage.get<string>(KEY_SHARE_IMAGE) ?? '';
    AppStorage.setOrCreate(KEY_SHARE_TEXT, '');
    AppStorage.setOrCreate(KEY_SHARE_IMAGE, '');
    if (text.length > 0) {
      this.inputText = text;
      this.translateInput();
    } else if (uri.length > 0) {
      ImageUtil.pixelMapFromUri(uri).then((pm: image.PixelMap) => {
        this.translateImage(pm);
      }).catch((e: Error) => {
        this.errorMsg = '读取分享的图片失败：' + errText(e);
      });
    }
  }

  /** 悬浮窗开启期间剪贴板发生变化（仅悬浮窗处理） */
  onClipboardChanged(): void {
    if (!this.floating) {
      return;
    }
    if (!ClipboardUtil.hasReadPermission()) {
      // 没有后台读取权限：在悬浮球上亮起提示，用户点开后按“粘贴”即可
      AppStorage.setOrCreate(KEY_CLIP_HINT, true);
      return;
    }
    ClipboardUtil.read().then((clip: ClipContent) => {
      if (clip.pixelMap === null && (clip.text.trim().length === 0 || clip.text === this.lastClipText)) {
        return;
      }
      FloatWindowManager.expand().then(() => {
        this.handleClip(clip);
      });
    }).catch(() => {
      AppStorage.setOrCreate(KEY_CLIP_HINT, true);
    });
  }

  private copyResult(): void {
    if (this.result.length === 0) {
      return;
    }
    ClipboardUtil.copyText(this.result).then(() => {
      this.toast('译文已复制');
    }).catch((e: Error) => {
      this.toast('复制失败：' + errText(e));
    });
  }

  // ---------- 历史记录 ----------
  private openHistory(): void {
    this.history = HistoryStore.list();
    this.showHistory = true;
  }

  /** 点一条历史：把原文和译文放回面板 */
  private restore(item: HistoryItem): void {
    this.cancel();
    this.preview = null;
    this.errorMsg = '';
    this.inputText = item.source === IMAGE_SOURCE_MARK ? '' : item.source;
    this.result = item.result;
    this.showHistory = false;
  }

  private removeHistory(id: number): void {
    HistoryStore.remove(id);
    this.history = HistoryStore.list();
  }

  private confirmClearHistory(): void {
    this.getUIContext().showAlertDialog({
      title: '清空历史',
      message: '确定删除全部 ' + this.history.length + ' 条翻译记录吗？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清空',
        fontColor: $r('app.color.danger'),
        action: () => {
          HistoryStore.clear();
          this.history = [];
        }
      }
    });
  }

  private timeLabel(ms: number): string {
    const d = new Date(ms);
    const two = (n: number): string => (n < 10 ? '0' : '') + n;
    return two(d.getMonth() + 1) + '-' + two(d.getDate()) + ' ' + two(d.getHours()) + ':' + two(d.getMinutes());
  }

  // ---------- 界面 ----------
  @Builder
  HistoryView() {
    Row({ space: 8 }) {
      Text('翻译历史')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      if (this.history.length > 0) {
        this.ActionButton('清空', () => {
          this.confirmClearHistory();
        })
      }
      this.ActionButton('返回', () => {
        this.showHistory = false;
      })
    }
    .width('100%')

    if (this.history.length === 0) {
      Text('还没有翻译记录')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .layoutWeight(1)
    } else {
      List({ space: 8 }) {
        ForEach(this.history, (item: HistoryItem) => {
          ListItem() {
            Row({ space: 4 }) {
              Column({ space: 4 }) {
                Text(item.source)
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                Text(item.result)
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                Text(this.timeLabel(item.id))
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              .layoutWeight(1)

              Text('✕')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Center)
                .width(32)
                .height(32)
                .onClick(() => {
                  this.removeHistory(item.id);
                })
            }
            .width('100%')
            .padding({ left: 12, right: 4, top: 10, bottom: 10 })
            .borderRadius(12)
            .backgroundColor($r('app.color.field_bg'))
            .onClick(() => {
              this.restore(item);
            })
          }
        }, (item: HistoryItem) => item.id.toString())
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
    }
  }

  @Builder
  ActionButton(label: string, onTap: () => void) {
    Button(label, { type: ButtonType.Capsule })
      .height(36)
      .fontSize(14)
      .fontColor($r('app.color.brand'))
      .backgroundColor($r('app.color.brand_soft'))
      .padding({ left: 14, right: 14 })
      .onClick(onTap)
  }

  build() {
    Column({ space: this.compact ? 8 : 12 }) {
      if (this.showHistory) {
        this.HistoryView()
      } else {
        this.MainView()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  MainView() {
      // 语言选择
      Row() {
        Select(this.sourceOptions())
          .selected(this.srcIdx)
          .value(this.srcIdx === 0 ? '自动检测' : LANGS[this.srcIdx - 1].name)
          .font({ size: 14 })
          .layoutWeight(1)
          .onSelect((index: number) => {
            this.srcIdx = index;
            this.saveLanguages();
          })
        Text('⇄')
          .fontSize(20)
          .fontColor($r('app.color.brand'))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .onClick(() => {
            this.swapLanguages();
          })
        Select(this.targetOptions())
          .selected(this.tgtIdx)
          .value(LANGS[this.tgtIdx].name)
          .font({ size: 14 })
          .layoutWeight(1)
          .onSelect((index: number) => {
            this.tgtIdx = index;
            this.saveLanguages();
          })
      }
      .width('100%')

      // 原文
      Stack({ alignContent: Alignment.TopEnd }) {
        TextArea({ text: this.inputText, placeholder: '输入、粘贴要翻译的文字，或选择图片' })
          .height(this.compact ? 84 : 150)
          .fontSize(15)
          .backgroundColor($r('app.color.field_bg'))
          .borderRadius(12)
          .padding({ left: 12, right: 30, top: 10, bottom: 10 })
          .onChange((value: string) => {
            this.inputText = value;
          })
        if (this.inputText.length > 0) {
          Text('✕')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .padding(10)
            .onClick(() => {
              this.inputText = '';
              this.preview = null;
            })
        }
      }
      .width('100%')

      if (this.preview !== null) {
        Image(this.preview as image.PixelMap)
          .height(this.compact ? 56 : 110)
          .objectFit(ImageFit.Contain)
          .borderRadius(8)
          .alignSelf(ItemAlign.Start)
      }

      // 操作（按钮较多，窄屏时自动换行）
      Flex({
        wrap: FlexWrap.Wrap,
        alignItems: ItemAlign.Center,
        space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) }
      }) {
        PasteButton({ icon: PasteIconStyle.LINES, text: PasteDescription.PASTE, buttonType: ButtonType.Capsule })
          .height(36)
          .fontSize(14)
          .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
            if (result === PasteButtonOnClickResult.SUCCESS) {
              this.pasteAndTranslate();
            } else {
              this.toast('未获得粘贴授权');
            }
          })
        this.ActionButton('相册', () => {
          this.pickImage();
        })
        if (this.floating) {
          this.ActionButton('截屏', () => {
            this.captureScreen();
          })
          this.ActionButton('长截屏', () => {
            this.captureScrolling();
          })
        }
        Button(this.busy ? '停止' : '翻译', { type: ButtonType.Capsule })
          .height(36)
          .fontSize(14)
          .backgroundColor(this.busy ? $r('app.color.danger') : $r('app.color.brand'))
          .padding({ left: 18, right: 18 })
          .onClick(() => {
            if (this.busy) {
              this.cancel();
            } else {
              this.translateInput();
            }
          })
      }
      .width('100%')

      // 译文
      Scroll() {
        Column({ space: 6 }) {
          if (this.errorMsg.length > 0) {
            Text(this.errorMsg)
              .fontSize(13)
              .fontColor($r('app.color.danger'))
              .copyOption(CopyOptions.LocalDevice)
              .width('100%')
          }
          if (this.statusText.length > 0) {
            Row({ space: 8 }) {
              LoadingProgress().width(18).height(18).color($r('app.color.brand'))
              Text(this.statusText).fontSize(13).fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
          }
          if (this.result.length > 0) {
            Text(this.result)
              .fontSize(16)
              .lineHeight(24)
              .fontColor($r('app.color.text_primary'))
              .copyOption(CopyOptions.LocalDevice)
              .width('100%')
          } else if (this.errorMsg.length === 0 && this.statusText.length === 0) {
            Text('译文会显示在这里')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
        }
        .width('100%')
        .padding(12)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
      .backgroundColor($r('app.color.field_bg'))
      .borderRadius(12)

      Row({ space: 8 }) {
        Text(this.providerLabel)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        this.ActionButton('历史', () => {
          this.openHistory();
        })
        if (this.result.length > 0) {
          this.ActionButton('复制译文', () => {
            this.copyResult();
          })
        }
      }
      .width('100%')
      .height(36)
  }
}
