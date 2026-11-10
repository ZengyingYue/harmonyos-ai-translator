import { TranslatePanel } from '../components/TranslatePanel';
import { KEY_CLIP_HINT, KEY_FLOAT_CAPTURING, KEY_FLOAT_EXPANDED } from '../common/Types';
import { px } from '../common/Util';
import { BALL_SIZE_VP, FloatWindowManager } from '../service/FloatWindowManager';

/** 手指移动超过这个距离（vp）才算拖动，否则算点击 */
const DRAG_THRESHOLD_VP: number = 6;

/** 悬浮窗内容：收起时是悬浮球，展开后是翻译面板 */
@Entry
@Component
struct FloatPage {
  @StorageProp(KEY_FLOAT_EXPANDED) expanded: boolean = false;
  @StorageProp(KEY_FLOAT_CAPTURING) capturing: boolean = false;
  @StorageProp(KEY_CLIP_HINT) clipHint: boolean = false;
  private downX: number = 0;
  private downY: number = 0;
  private originX: number = 0;
  private originY: number = 0;
  private dragging: boolean = false;

  /**
   * 拖动窗口。用屏幕坐标（displayX/Y）计算位移，窗口跟手移动时不会抖动。
   * @returns 手指抬起且期间没有发生拖动时返回 true（即一次点击）
   */
  private handleDrag(event: TouchEvent): boolean {
    if (event.touches.length === 0) {
      return false;
    }
    const t = event.touches[0];
    if (event.type === TouchType.Down) {
      this.downX = t.displayX;
      this.downY = t.displayY;
      const origin = FloatWindowManager.position();
      this.originX = origin.x;
      this.originY = origin.y;
      this.dragging = false;
    } else if (event.type === TouchType.Move) {
      const dx = t.displayX - this.downX;
      const dy = t.displayY - this.downY;
      if (!this.dragging && Math.abs(dx) + Math.abs(dy) > DRAG_THRESHOLD_VP) {
        this.dragging = true;
      }
      if (this.dragging) {
        FloatWindowManager.moveTo(this.originX + px(dx), this.originY + px(dy));
      }
    } else if (event.type === TouchType.Up) {
      const wasDragging = this.dragging;
      this.dragging = false;
      return !wasDragging;
    } else if (event.type === TouchType.Cancel) {
      this.dragging = false;
    }
    return false;
  }

  @Builder
  Ball() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Text('译')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .width('100%')
        .height('100%')
      if (this.clipHint) {
        // 剪贴板有新内容，点开后按“粘贴”即可翻译
        Circle()
          .width(12)
          .height(12)
          .fill('#FF4D4F')
          .stroke(Color.White)
          .strokeWidth(2)
      }
    }
    .width(BALL_SIZE_VP)
    .height(BALL_SIZE_VP)
    .borderRadius(BALL_SIZE_VP / 2)
    .linearGradient({ angle: 135, colors: [['#406EFF', 0], ['#7C4DFF', 1]] })
    .onTouch((event: TouchEvent) => {
      if (this.handleDrag(event)) {
        FloatWindowManager.expand();
      } else if (event.type === TouchType.Up) {
        FloatWindowManager.snapToEdge();
      }
    })
  }

  @Builder
  HeaderButton(label: string, onTap: () => void) {
    Text(label)
      .fontSize(16)
      .fontColor($r('app.color.text_secondary'))
      .textAlign(TextAlign.Center)
      .width(36)
      .height(36)
      .onClick(onTap)
  }

  @Builder
  Panel() {
    Column() {
      Row() {
        // 按住标题栏可以拖动面板
        Text('AI 翻译')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .height(36)
          .layoutWeight(1)
          .onTouch((event: TouchEvent) => {
            this.handleDrag(event);
          })
        this.HeaderButton('—', () => {
          FloatWindowManager.collapse();
        })
        this.HeaderButton('✕', () => {
          FloatWindowManager.close();
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
    .padding({ left: 12, right: 12, top: 6, bottom: 8 })
    .borderRadius(18)
    .borderWidth(1)
    .borderColor($r('app.color.divider'))
    .backgroundColor($r('app.color.card_bg'))
  }

  build() {
    Stack() {
      // 两者都常驻，只切换可见性：面板收起后仍保留上次的译文，并继续响应剪贴板变化
      Column() {
        this.Ball()
      }
      .visibility(this.expanded ? Visibility.None : Visibility.Visible)

      Column() {
        this.Panel()
      }
      .width('100%')
      .height('100%')
      .visibility(this.expanded ? Visibility.Visible : Visibility.None)
    }
    .width('100%')
    .height('100%')
    .opacity(this.capturing ? 0 : 1)
  }
}
