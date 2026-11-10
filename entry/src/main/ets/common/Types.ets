/** 支持的 API 协议格式 */
export const FORMAT_OPENAI: string = 'openai';
export const FORMAT_ANTHROPIC: string = 'anthropic';
export const FORMAT_GEMINI: string = 'gemini';

/** 图片翻译方式：本地 OCR 后翻译文本 / 直接把图片发给多模态模型 */
export const IMAGE_MODE_OCR: string = 'ocr';
export const IMAGE_MODE_VISION: string = 'vision';

/** AppStorage 键 */
export const KEY_SETTINGS_VERSION: string = 'settingsVersion';
export const KEY_SHARE_SEQ: string = 'shareSeq';
export const KEY_SHARE_TEXT: string = 'shareText';
export const KEY_SHARE_IMAGE: string = 'shareImageUri';
export const KEY_CLIP_SEQ: string = 'clipSeq';
export const KEY_CLIP_HINT: string = 'clipHint';
export const KEY_FLOAT_SHOWN: string = 'floatShown';
export const KEY_FLOAT_EXPANDED: string = 'floatExpanded';
export const KEY_FLOAT_CAPTURING: string = 'floatCapturing';

export interface ProviderConfig {
  id: string;
  name: string;
  /** openai | anthropic | gemini */
  format: string;
  baseUrl: string;
  apiKey: string;
  model: string;
}

export interface AppSettings {
  providers: ProviderConfig[];
  activeId: string;
  /** 'auto' 或语言代码 */
  sourceLang: string;
  targetLang: string;
  /** 原文已经是目标语言时，改为翻译成该语言 */
  secondLang: string;
  imageMode: string;
  stream: boolean;
  /** 悬浮窗开启时监听剪贴板变化 */
  autoClipboard: boolean;
  customPrompt: string;
}

export interface LangItem {
  code: string;
  /** 界面显示名 */
  name: string;
  /** 写入提示词的英文名 */
  en: string;
}

export const LANG_AUTO: string = 'auto';

export const LANGS: LangItem[] = [
  { code: 'zh-Hans', name: '简体中文', en: 'Simplified Chinese' },
  { code: 'en', name: 'English', en: 'English' },
  { code: 'zh-Hant', name: '繁體中文', en: 'Traditional Chinese' },
  { code: 'ja', name: '日本語', en: 'Japanese' },
  { code: 'ko', name: '한국어', en: 'Korean' },
  { code: 'fr', name: 'Français', en: 'French' },
  { code: 'de', name: 'Deutsch', en: 'German' },
  { code: 'es', name: 'Español', en: 'Spanish' },
  { code: 'ru', name: 'Русский', en: 'Russian' },
  { code: 'pt', name: 'Português', en: 'Portuguese' },
  { code: 'it', name: 'Italiano', en: 'Italian' },
  { code: 'ar', name: 'العربية', en: 'Arabic' },
  { code: 'th', name: 'ไทย', en: 'Thai' },
  { code: 'vi', name: 'Tiếng Việt', en: 'Vietnamese' }
];

export function langIndex(code: string): number {
  for (let i = 0; i < LANGS.length; i++) {
    if (LANGS[i].code === code) {
      return i;
    }
  }
  return -1;
}

export function langEnglishName(code: string): string {
  const i = langIndex(code);
  return i >= 0 ? LANGS[i].en : 'English';
}

export interface ProviderPreset {
  name: string;
  format: string;
  baseUrl: string;
  model: string;
}

/** 常见服务商预设，Base URL 与模型名都可以在编辑页修改 */
export const PRESETS: ProviderPreset[] = [
  { name: 'OpenAI', format: FORMAT_OPENAI, baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o-mini' },
  { name: 'Anthropic Claude', format: FORMAT_ANTHROPIC, baseUrl: 'https://api.anthropic.com', model: 'claude-opus-5-5' },
  { name: 'Google Gemini', format: FORMAT_GEMINI, baseUrl: 'https://generativelanguage.googleapis.com/v1beta', model: 'gemini-2.5-flash' },
  { name: 'DeepSeek', format: FORMAT_OPENAI, baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-chat' },
  { name: '通义千问', format: FORMAT_OPENAI, baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-plus' },
  { name: '智谱 GLM', format: FORMAT_OPENAI, baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4-flash' },
  { name: 'Moonshot', format: FORMAT_OPENAI, baseUrl: 'https://api.moonshot.cn/v1', model: 'moonshot-v1-8k' },
  { name: '豆包（火山方舟）', format: FORMAT_OPENAI, baseUrl: 'https://ark.cn-beijing.volces.com/api/v3', model: '' },
  { name: '硅基流动', format: FORMAT_OPENAI, baseUrl: 'https://api.siliconflow.cn/v1', model: '' },
  { name: 'OpenRouter', format: FORMAT_OPENAI, baseUrl: 'https://openrouter.ai/api/v1', model: '' },
  { name: '自定义（OpenAI 兼容）', format: FORMAT_OPENAI, baseUrl: '', model: '' }
];

export function formatLabel(format: string): string {
  if (format === FORMAT_ANTHROPIC) {
    return 'Anthropic';
  }
  if (format === FORMAT_GEMINI) {
    return 'Gemini';
  }
  return 'OpenAI 兼容';
}
