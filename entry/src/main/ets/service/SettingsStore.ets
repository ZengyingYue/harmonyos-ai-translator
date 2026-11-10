import { preferences } from '@kit.ArkData';
import {
  AppSettings,
  IMAGE_MODE_OCR,
  KEY_SETTINGS_VERSION,
  LANG_AUTO,
  ProviderConfig
} from '../common/Types';

const PREF_NAME: string = 'translator_settings';
const PREF_KEY: string = 'settings';

function defaults(): AppSettings {
  return {
    providers: [],
    activeId: '',
    sourceLang: LANG_AUTO,
    targetLang: 'zh-Hans',
    secondLang: 'en',
    imageMode: IMAGE_MODE_OCR,
    stream: true,
    autoClipboard: true,
    customPrompt: ''
  };
}

/**
 * 设置持久化（用户首选项）。数据保存在应用沙箱内，API Key 不会离开本机，
 * 只在请求时发往用户自己配置的 Base URL。
 */
export class SettingsStore {
  private static pref: preferences.Preferences | null = null;
  private static json: string = '';
  private static version: number = 0;

  static init(ctx: Context): void {
    if (SettingsStore.pref !== null) {
      return;
    }
    const opt: preferences.Options = { name: PREF_NAME };
    SettingsStore.pref = preferences.getPreferencesSync(ctx, opt);
    SettingsStore.json = SettingsStore.pref.getSync(PREF_KEY, '') as string;
    AppStorage.setOrCreate(KEY_SETTINGS_VERSION, SettingsStore.version);
  }

  /** 每次返回一份独立副本，调用方可以随意修改后再 save */
  static get(): AppSettings {
    const d = defaults();
    if (SettingsStore.json.length === 0) {
      return d;
    }
    try {
      const s = JSON.parse(SettingsStore.json) as AppSettings;
      if (s.providers === undefined || s.providers === null) {
        s.providers = d.providers;
      }
      if (s.activeId === undefined) {
        s.activeId = d.activeId;
      }
      if (s.sourceLang === undefined) {
        s.sourceLang = d.sourceLang;
      }
      if (s.targetLang === undefined) {
        s.targetLang = d.targetLang;
      }
      if (s.secondLang === undefined) {
        s.secondLang = d.secondLang;
      }
      if (s.imageMode === undefined) {
        s.imageMode = d.imageMode;
      }
      if (s.stream === undefined) {
        s.stream = d.stream;
      }
      if (s.autoClipboard === undefined) {
        s.autoClipboard = d.autoClipboard;
      }
      if (s.customPrompt === undefined) {
        s.customPrompt = d.customPrompt;
      }
      return s;
    } catch (e) {
      return d;
    }
  }

  static save(s: AppSettings): void {
    SettingsStore.json = JSON.stringify(s);
    if (SettingsStore.pref !== null) {
      SettingsStore.pref.putSync(PREF_KEY, SettingsStore.json);
      SettingsStore.pref.flush();
    }
    SettingsStore.version++;
    AppStorage.setOrCreate(KEY_SETTINGS_VERSION, SettingsStore.version);
  }

  static activeProvider(): ProviderConfig | null {
    const s = SettingsStore.get();
    for (let i = 0; i < s.providers.length; i++) {
      if (s.providers[i].id === s.activeId) {
        return s.providers[i];
      }
    }
    return s.providers.length > 0 ? s.providers[0] : null;
  }
}
