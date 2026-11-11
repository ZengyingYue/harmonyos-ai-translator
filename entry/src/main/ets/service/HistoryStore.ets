import { preferences } from '@kit.ArkData';

const PREF_NAME: string = 'translator_history';
const PREF_KEY: string = 'items';
/** 最多保留多少条 */
const MAX_ITEMS: number = 100;
/** 单条原文/译文最多保存多少字符，避免长截屏把存储撑大 */
const MAX_TEXT_LENGTH: number = 4000;
/** 图片翻译且没有识别出原文（多模态模式）时的原文占位 */
export const IMAGE_SOURCE_MARK: string = '[图片]';

export interface HistoryItem {
  /** 创建时间戳（毫秒），同时作为唯一标识 */
  id: number;
  source: string;
  result: string;
}

function clip(text: string): string {
  return text.length > MAX_TEXT_LENGTH ? text.substring(0, MAX_TEXT_LENGTH) + '…' : text;
}

/** 翻译历史，只保存在本机的应用沙箱里 */
export class HistoryStore {
  private static ctx: Context | null = null;

  static init(ctx: Context): void {
    HistoryStore.ctx = ctx;
  }

  private static open(): preferences.Preferences | null {
    const ctx = HistoryStore.ctx;
    if (ctx === null) {
      return null;
    }
    const opt: preferences.Options = { name: PREF_NAME };
    try {
      // 主应用和分享面板可能运行在不同进程，丢掉内存缓存以读到对方刚写入的记录
      preferences.removePreferencesFromCacheSync(ctx, opt);
    } catch (e) {
      // 尚未缓存
    }
    return preferences.getPreferencesSync(ctx, opt);
  }

  /** 最新的在最前 */
  static list(): HistoryItem[] {
    try {
      const pref = HistoryStore.open();
      if (pref === null) {
        return [];
      }
      const json = pref.getSync(PREF_KEY, '') as string;
      if (json.length === 0) {
        return [];
      }
      return JSON.parse(json) as HistoryItem[];
    } catch (e) {
      return [];
    }
  }

  private static save(items: HistoryItem[]): void {
    try {
      const pref = HistoryStore.open();
      if (pref === null) {
        return;
      }
      pref.putSync(PREF_KEY, JSON.stringify(items));
      pref.flush();
    } catch (e) {
      // 历史记录写入失败不影响翻译
    }
  }

  static add(source: string, result: string): void {
    const src = clip(source.trim().length > 0 ? source.trim() : IMAGE_SOURCE_MARK);
    const res = clip(result.trim());
    if (res.length === 0) {
      return;
    }
    const items = HistoryStore.list();
    if (items.length > 0 && items[0].source === src && items[0].result === res) {
      return;
    }
    const item: HistoryItem = { id: Date.now(), source: src, result: res };
    items.unshift(item);
    if (items.length > MAX_ITEMS) {
      items.splice(MAX_ITEMS, items.length - MAX_ITEMS);
    }
    HistoryStore.save(items);
  }

  static remove(id: number): void {
    HistoryStore.save(HistoryStore.list().filter((it: HistoryItem) => it.id !== id));
  }

  static clear(): void {
    HistoryStore.save([]);
  }
}
