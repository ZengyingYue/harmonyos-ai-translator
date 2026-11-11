import { display, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  KEY_CLIP_HINT,
  KEY_CLIP_SEQ,
  KEY_FLOAT_CAPTURING,
  KEY_FLOAT_EXPANDED,
  KEY_FLOAT_SCROLLING,
  KEY_FLOAT_SHOWN,
  KEY_SCROLL_STOP
} from '../common/Types';
import { px } from '../common/Util';
import { ClipboardUtil } from './ClipboardUtil';
import { SettingsStore } from './SettingsStore';

const WINDOW_NAME: string = 'ai_translator_float';
const FLOAT_PAGE: string = 'pages/FloatPage';
export const BALL_SIZE_VP: number = 52;
const EDGE_MARGIN_VP: number = 6;
const PANEL_MAX_WIDTH_VP: number = 360;
const PANEL_MAX_HEIGHT_VP: number = 500;
const SAFE_TOP_VP: number = 40;
/** 滚动截屏时“完成”按钮的大小 */
export const STOP_SIZE_VP: number = 52;

export class Point {
  x: number = 0;
  y: number = 0;
}

/**
 * 悬浮窗：收起时是一个可拖动的悬浮球，展开后是翻译面板。
 * 窗口类型为 TYPE_FLOAT，需要 ohos.permission.SYSTEM_FLOAT_WINDOW。
 */
export class FloatWindowManager {
  private static win: window.Window | null = null;
  private static ctx: common.UIAbilityContext | null = null;
  private static expanded: boolean = false;
  /** 当前窗口位置与尺寸（px） */
  private static curX: number = 0;
  private static curY: number = 0;
  private static curW: number = 0;
  private static curH: number = 0;
  /** 悬浮球收起时停靠的位置（px） */
  private static ballX: number = 0;
  private static ballY: number = 0;
  /** 进入滚动截屏前面板的位置与尺寸，结束后恢复 */
  private static savedX: number = 0;
  private static savedY: number = 0;
  private static savedW: number = 0;
  private static savedH: number = 0;
  private static scrolling: boolean = false;
  private static clipSeq: number = 0;
  private static clipListener: (() => void) | null = null;

  static isShown(): boolean {
    return FloatWindowManager.win !== null;
  }

  static context(): common.UIAbilityContext | null {
    return FloatWindowManager.ctx;
  }

  static position(): Point {
    const p = new Point();
    p.x = FloatWindowManager.curX;
    p.y = FloatWindowManager.curY;
    return p;
  }

  /** 创建并显示悬浮球。没有悬浮窗权限时抛出错误（错误码 201） */
  static async show(ctx: common.UIAbilityContext): Promise<void> {
    if (FloatWindowManager.win !== null) {
      return;
    }
    FloatWindowManager.ctx = ctx;
    const d = display.getDefaultDisplaySync();
    const ball = px(BALL_SIZE_VP);
    FloatWindowManager.ballX = d.width - ball - px(EDGE_MARGIN_VP);
    FloatWindowManager.ballY = Math.round(d.height * 0.42);

    const config: window.Configuration = {
      name: WINDOW_NAME,
      windowType: window.WindowType.TYPE_FLOAT,
      ctx: ctx
    };
    const win = await window.createWindow(config);
    try {
      await win.moveWindowTo(FloatWindowManager.ballX, FloatWindowManager.ballY);
      await win.resize(ball, ball);
      await win.setUIContent(FLOAT_PAGE);
      win.setWindowBackgroundColor('#00000000');
      await win.showWindow();
    } catch (e) {
      try {
        await win.destroyWindow();
      } catch (e2) {
        // 忽略
      }
      throw e as Error;
    }
    FloatWindowManager.win = win;
    FloatWindowManager.expanded = false;
    FloatWindowManager.curX = FloatWindowManager.ballX;
    FloatWindowManager.curY = FloatWindowManager.ballY;
    FloatWindowManager.curW = ball;
    FloatWindowManager.curH = ball;
    AppStorage.setOrCreate(KEY_FLOAT_EXPANDED, false);
    AppStorage.setOrCreate(KEY_FLOAT_CAPTURING, false);
    AppStorage.setOrCreate(KEY_FLOAT_SCROLLING, false);
    AppStorage.setOrCreate(KEY_SCROLL_STOP, false);
    AppStorage.setOrCreate(KEY_CLIP_HINT, false);
    AppStorage.setOrCreate(KEY_FLOAT_SHOWN, true);
    FloatWindowManager.watchClipboard();
  }

  static async close(): Promise<void> {
    FloatWindowManager.unwatchClipboard();
    const win = FloatWindowManager.win;
    FloatWindowManager.win = null;
    FloatWindowManager.expanded = false;
    FloatWindowManager.scrolling = false;
    // 若正在滚动截屏，让它结束
    AppStorage.setOrCreate(KEY_SCROLL_STOP, true);
    AppStorage.setOrCreate(KEY_FLOAT_SCROLLING, false);
    AppStorage.setOrCreate(KEY_FLOAT_SHOWN, false);
    AppStorage.setOrCreate(KEY_FLOAT_EXPANDED, false);
    if (win !== null) {
      try {
        await win.destroyWindow();
      } catch (e) {
        // 窗口可能已随应用退出被销毁
      }
    }
  }

  /** 悬浮球 → 翻译面板 */
  static async expand(): Promise<void> {
    const win = FloatWindowManager.win;
    if (win === null || FloatWindowManager.expanded) {
      return;
    }
    const d = display.getDefaultDisplaySync();
    const margin = px(12);
    const w = Math.min(d.width - margin * 2, px(PANEL_MAX_WIDTH_VP));
    const h = Math.min(d.height - px(SAFE_TOP_VP) * 3, px(PANEL_MAX_HEIGHT_VP));
    const x = Math.round((d.width - w) / 2);
    let y = FloatWindowManager.ballY - Math.round(h / 3);
    y = Math.max(px(SAFE_TOP_VP), Math.min(y, d.height - h - px(SAFE_TOP_VP)));
    FloatWindowManager.expanded = true;
    try {
      await win.resize(w, h);
      await win.moveWindowTo(x, y);
    } catch (e) {
      // 尺寸受系统限制时仍然切到面板界面
    }
    FloatWindowManager.curX = x;
    FloatWindowManager.curY = y;
    FloatWindowManager.curW = w;
    FloatWindowManager.curH = h;
    AppStorage.setOrCreate(KEY_CLIP_HINT, false);
    AppStorage.setOrCreate(KEY_FLOAT_EXPANDED, true);
  }

  /** 翻译面板 → 悬浮球 */
  static async collapse(): Promise<void> {
    const win = FloatWindowManager.win;
    if (win === null || !FloatWindowManager.expanded) {
      return;
    }
    const ball = px(BALL_SIZE_VP);
    FloatWindowManager.expanded = false;
    AppStorage.setOrCreate(KEY_FLOAT_EXPANDED, false);
    try {
      await win.resize(ball, ball);
      await win.moveWindowTo(FloatWindowManager.ballX, FloatWindowManager.ballY);
    } catch (e) {
      // 忽略
    }
    FloatWindowManager.curX = FloatWindowManager.ballX;
    FloatWindowManager.curY = FloatWindowManager.ballY;
    FloatWindowManager.curW = ball;
    FloatWindowManager.curH = ball;
  }

  /** 拖动：把窗口移到指定位置（px），自动限制在屏幕内 */
  static moveTo(x: number, y: number): void {
    const win = FloatWindowManager.win;
    if (win === null) {
      return;
    }
    const d = display.getDefaultDisplaySync();
    const nx = Math.round(Math.max(0, Math.min(x, d.width - FloatWindowManager.curW)));
    const ny = Math.round(Math.max(px(SAFE_TOP_VP), Math.min(y, d.height - FloatWindowManager.curH)));
    FloatWindowManager.curX = nx;
    FloatWindowManager.curY = ny;
    if (!FloatWindowManager.expanded) {
      FloatWindowManager.ballX = nx;
      FloatWindowManager.ballY = ny;
    }
    win.moveWindowTo(nx, ny).catch(() => {
      // 拖动过程中的偶发失败可以忽略
    });
  }

  /** 松手后把悬浮球吸附到最近的屏幕左右边缘 */
  static snapToEdge(): void {
    if (FloatWindowManager.expanded) {
      return;
    }
    const d = display.getDefaultDisplaySync();
    const ball = px(BALL_SIZE_VP);
    const margin = px(EDGE_MARGIN_VP);
    const toLeft = FloatWindowManager.curX + ball / 2 < d.width / 2;
    FloatWindowManager.moveTo(toLeft ? margin : d.width - ball - margin, FloatWindowManager.curY);
  }

  /**
   * 滚动截屏开始：把窗口缩成右上角的一个“完成”按钮，
   * 这样用户可以滚动下面的应用，按钮也只会出现在长图最顶部一次。
   */
  static async enterScrollMode(): Promise<void> {
    const win = FloatWindowManager.win;
    if (win === null || FloatWindowManager.scrolling) {
      return;
    }
    FloatWindowManager.scrolling = true;
    FloatWindowManager.savedX = FloatWindowManager.curX;
    FloatWindowManager.savedY = FloatWindowManager.curY;
    FloatWindowManager.savedW = FloatWindowManager.curW;
    FloatWindowManager.savedH = FloatWindowManager.curH;
    const d = display.getDefaultDisplaySync();
    const size = px(STOP_SIZE_VP);
    AppStorage.setOrCreate(KEY_SCROLL_STOP, false);
    AppStorage.setOrCreate(KEY_FLOAT_SCROLLING, true);
    try {
      await win.resize(size, size);
      await win.moveWindowTo(d.width - size - px(EDGE_MARGIN_VP), px(SAFE_TOP_VP));
    } catch (e) {
      // 忽略
    }
  }

  /** 滚动截屏结束：恢复成之前的翻译面板 */
  static async exitScrollMode(): Promise<void> {
    const win = FloatWindowManager.win;
    if (!FloatWindowManager.scrolling) {
      return;
    }
    FloatWindowManager.scrolling = false;
    if (win !== null) {
      try {
        await win.resize(FloatWindowManager.savedW, FloatWindowManager.savedH);
        await win.moveWindowTo(FloatWindowManager.savedX, FloatWindowManager.savedY);
      } catch (e) {
        // 忽略
      }
    }
    AppStorage.setOrCreate(KEY_FLOAT_SCROLLING, false);
    AppStorage.setOrCreate(KEY_SCROLL_STOP, false);
  }

  static requestScrollStop(): void {
    AppStorage.setOrCreate(KEY_SCROLL_STOP, true);
  }

  static scrollStopRequested(): boolean {
    return AppStorage.get<boolean>(KEY_SCROLL_STOP) === true;
  }

  /** 截屏前把悬浮窗变透明，避免挡住要翻译的内容 */
  static setCapturing(capturing: boolean): void {
    AppStorage.setOrCreate(KEY_FLOAT_CAPTURING, capturing);
  }

  private static watchClipboard(): void {
    if (FloatWindowManager.clipListener !== null) {
      return;
    }
    const listener = (): void => {
      // 忽略自己点“复制译文”引起的变化
      if (Date.now() - ClipboardUtil.lastSelfCopyAt < 1500) {
        return;
      }
      if (!SettingsStore.get().autoClipboard) {
        return;
      }
      FloatWindowManager.clipSeq++;
      AppStorage.setOrCreate(KEY_CLIP_SEQ, FloatWindowManager.clipSeq);
    };
    try {
      pasteboard.getSystemPasteboard().on('update', listener);
      FloatWindowManager.clipListener = listener;
    } catch (e) {
      // 监听失败时仍可手动点“粘贴”
    }
  }

  private static unwatchClipboard(): void {
    const listener = FloatWindowManager.clipListener;
    FloatWindowManager.clipListener = null;
    if (listener !== null) {
      try {
        pasteboard.getSystemPasteboard().off('update', listener);
      } catch (e) {
        // 忽略
      }
    }
  }
}
