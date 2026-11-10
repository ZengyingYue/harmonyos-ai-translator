import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { FORMAT_ANTHROPIC, FORMAT_GEMINI, ProviderConfig } from '../common/Types';
import { delay, errText } from '../common/Util';

export interface ImageInput {
  /** 不带 data: 前缀的 base64 */
  base64: string;
  mime: string;
}

/** 一次请求的句柄，用于取消 */
export class LlmTask {
  cancelled: boolean = false;
  private req: http.HttpRequest | null = null;

  attach(req: http.HttpRequest): void {
    this.req = req;
  }

  /** 释放连接；重复调用安全 */
  finish(): void {
    const r = this.req;
    this.req = null;
    if (r !== null) {
      try {
        r.destroy();
      } catch (e) {
        // 已经销毁
      }
    }
  }

  cancel(): void {
    this.cancelled = true;
    this.finish();
  }
}

// ---------- OpenAI Chat Completions ----------
interface OaImageUrl {
  url: string;
}

interface OaPart {
  type: string;
  text?: string;
  image_url?: OaImageUrl;
}

interface OaMessage {
  role: string;
  content: string | OaPart[];
}

interface OaBody {
  model: string;
  messages: OaMessage[];
  stream: boolean;
}

interface OaRespMessage {
  content?: string | null;
}

interface OaChoice {
  delta?: OaRespMessage;
  message?: OaRespMessage;
}

interface ApiError {
  message?: string;
}

interface OaResp {
  choices?: OaChoice[];
  error?: ApiError;
}

// ---------- Anthropic Messages ----------
interface AnSource {
  type: string;
  media_type: string;
  data: string;
}

interface AnBlock {
  type: string;
  text?: string;
  source?: AnSource;
}

interface AnMessage {
  role: string;
  content: AnBlock[];
}

interface AnBody {
  model: string;
  max_tokens: number;
  system: string;
  messages: AnMessage[];
  stream: boolean;
}

interface AnDelta {
  type?: string;
  text?: string;
  stop_reason?: string;
}

/** 既是流式事件，也是非流式的完整响应 */
interface AnResp {
  type?: string;
  delta?: AnDelta;
  content?: AnBlock[];
  stop_reason?: string;
  error?: ApiError;
}

// ---------- Google Gemini ----------
interface GmInline {
  mime_type: string;
  data: string;
}

interface GmPart {
  text?: string;
  inline_data?: GmInline;
}

interface GmContent {
  role?: string;
  parts?: GmPart[];
}

interface GmBody {
  system_instruction: GmContent;
  contents: GmContent[];
}

interface GmCandidate {
  content?: GmContent;
}

interface GmResp {
  candidates?: GmCandidate[];
  error?: ApiError;
}

// ---------- 通用 ----------
interface ErrWrap {
  error?: ApiError | string;
  message?: string;
}

class StreamState {
  /** 尚未凑成整行的 SSE 数据 */
  lineBuf: string = '';
  /** 已累计的译文 */
  full: string = '';
  /** 接口在流里返回的错误 */
  err: string = '';
  refused: boolean = false;
}

const ANTHROPIC_VERSION: string = '2023-06-01';
const ANTHROPIC_MAX_TOKENS: number = 16000;
const RAW_KEEP_LIMIT: number = 64 * 1024;

function stripSlash(u: string): string {
  let s = u.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/** Base URL 是否只有域名、没有路径（例如 https://api.deepseek.com） */
function hasNoPath(base: string): boolean {
  const i = base.indexOf('://');
  const rest = i >= 0 ? base.substring(i + 3) : base;
  return rest.indexOf('/') < 0;
}

function buildUrl(p: ProviderConfig, stream: boolean): string {
  const base = stripSlash(p.baseUrl);
  if (p.format === FORMAT_ANTHROPIC) {
    if (base.endsWith('/messages')) {
      return base;
    }
    return base.endsWith('/v1') ? base + '/messages' : base + '/v1/messages';
  }
  if (p.format === FORMAT_GEMINI) {
    const root = hasNoPath(base) ? base + '/v1beta' : base;
    const method = stream ? ':streamGenerateContent?alt=sse' : ':generateContent';
    return root + '/models/' + encodeURIComponent(p.model.trim()) + method;
  }
  if (base.endsWith('/chat/completions')) {
    return base;
  }
  return hasNoPath(base) ? base + '/v1/chat/completions' : base + '/chat/completions';
}

function buildHeaders(p: ProviderConfig): Record<string, string> {
  const key = p.apiKey.trim();
  const h: Record<string, string> = { 'Content-Type': 'application/json' };
  if (p.format === FORMAT_ANTHROPIC) {
    h['x-api-key'] = key;
    h['anthropic-version'] = ANTHROPIC_VERSION;
  } else if (p.format === FORMAT_GEMINI) {
    h['x-goog-api-key'] = key;
  } else if (key.length > 0) {
    // 本地模型（如 Ollama）可以不填 Key
    h['Authorization'] = 'Bearer ' + key;
  }
  return h;
}

function buildBody(p: ProviderConfig, system: string, userText: string, img: ImageInput | null,
  stream: boolean): string {
  const model = p.model.trim();
  if (p.format === FORMAT_ANTHROPIC) {
    const blocks: AnBlock[] = [];
    if (img !== null) {
      blocks.push({ type: 'image', source: { type: 'base64', media_type: img.mime, data: img.base64 } });
    }
    blocks.push({ type: 'text', text: userText });
    const body: AnBody = {
      model: model,
      max_tokens: ANTHROPIC_MAX_TOKENS,
      system: system,
      messages: [{ role: 'user', content: blocks }],
      stream: stream
    };
    return JSON.stringify(body);
  }
  if (p.format === FORMAT_GEMINI) {
    const parts: GmPart[] = [];
    if (img !== null) {
      parts.push({ inline_data: { mime_type: img.mime, data: img.base64 } });
    }
    parts.push({ text: userText });
    const body: GmBody = {
      system_instruction: { parts: [{ text: system }] },
      contents: [{ role: 'user', parts: parts }]
    };
    return JSON.stringify(body);
  }
  let content: string | OaPart[] = userText;
  if (img !== null) {
    const parts: OaPart[] = [
      { type: 'text', text: userText },
      { type: 'image_url', image_url: { url: 'data:' + img.mime + ';base64,' + img.base64 } }
    ];
    content = parts;
  }
  const body: OaBody = {
    model: model,
    messages: [
      { role: 'system', content: system },
      { role: 'user', content: content }
    ],
    stream: stream
  };
  return JSON.stringify(body);
}

/** 解析一段 JSON（流式的一条 data，或非流式的完整响应），把文本追加到 state.full */
function consumeJson(format: string, payload: string, st: StreamState): void {
  if (format === FORMAT_ANTHROPIC) {
    const r = JSON.parse(payload) as AnResp;
    if (r.error !== undefined && r.error !== null) {
      st.err = r.error.message ?? 'Anthropic 接口返回错误';
      return;
    }
    if (r.type === 'content_block_delta' && r.delta !== undefined && r.delta.type === 'text_delta') {
      st.full += r.delta.text ?? '';
    }
    if (r.type === 'message_delta' && r.delta !== undefined && r.delta.stop_reason === 'refusal') {
      st.refused = true;
    }
    if (r.stop_reason === 'refusal') {
      st.refused = true;
    }
    if (r.content !== undefined && r.content !== null) {
      for (let i = 0; i < r.content.length; i++) {
        if (r.content[i].type === 'text') {
          st.full += r.content[i].text ?? '';
        }
      }
    }
    return;
  }
  if (format === FORMAT_GEMINI) {
    const r = JSON.parse(payload) as GmResp;
    if (r.error !== undefined && r.error !== null) {
      st.err = r.error.message ?? 'Gemini 接口返回错误';
      return;
    }
    if (r.candidates !== undefined && r.candidates !== null && r.candidates.length > 0) {
      const c = r.candidates[0].content;
      if (c !== undefined && c !== null && c.parts !== undefined && c.parts !== null) {
        for (let i = 0; i < c.parts.length; i++) {
          st.full += c.parts[i].text ?? '';
        }
      }
    }
    return;
  }
  const r = JSON.parse(payload) as OaResp;
  if (r.error !== undefined && r.error !== null) {
    st.err = r.error.message ?? '接口返回错误';
    return;
  }
  if (r.choices !== undefined && r.choices !== null && r.choices.length > 0) {
    const ch = r.choices[0];
    if (ch.delta !== undefined && ch.delta !== null) {
      st.full += ch.delta.content ?? '';
    }
    if (ch.message !== undefined && ch.message !== null) {
      st.full += ch.message.content ?? '';
    }
  }
}

/** 处理已经收到的完整 SSE 行 */
function drainLines(format: string, st: StreamState, onDelta: (full: string) => void): void {
  let idx = st.lineBuf.indexOf('\n');
  let changed = false;
  while (idx >= 0) {
    const line = st.lineBuf.substring(0, idx).trim();
    st.lineBuf = st.lineBuf.substring(idx + 1);
    if (line.startsWith('data:')) {
      const payload = line.substring(5).trim();
      if (payload.length > 0 && payload !== '[DONE]') {
        const before = st.full.length;
        try {
          consumeJson(format, payload, st);
        } catch (e) {
          // 个别网关会插入非 JSON 的保活行，忽略
        }
        if (st.full.length !== before) {
          changed = true;
        }
      }
    }
    idx = st.lineBuf.indexOf('\n');
  }
  if (changed) {
    onDelta(st.full);
  }
}

/** 从非 2xx 的响应体里取出错误说明 */
function extractHttpError(code: number, raw: string): string {
  let detail = '';
  const text = raw.trim();
  try {
    let w: ErrWrap | null = null;
    if (text.startsWith('[')) {
      const arr = JSON.parse(text) as ErrWrap[];
      w = arr.length > 0 ? arr[0] : null;
    } else if (text.startsWith('{')) {
      w = JSON.parse(text) as ErrWrap;
    }
    if (w !== null) {
      const er = w.error;
      if (typeof er === 'string') {
        detail = er;
      } else if (er !== undefined && er !== null && er.message !== undefined) {
        detail = er.message;
      } else if (w.message !== undefined) {
        detail = w.message;
      }
    }
  } catch (e) {
    // 响应体不是 JSON
  }
  if (detail.length === 0) {
    detail = text.length > 300 ? text.substring(0, 300) + '…' : text;
  }
  let hint = '';
  if (code === 401 || code === 403) {
    hint = '请检查 API Key 是否正确、是否有该模型的权限。';
  } else if (code === 404) {
    hint = '请检查 Base URL 和模型名称。';
  } else if (code === 429) {
    hint = '请求过于频繁或额度不足。';
  }
  return 'HTTP ' + code + (detail.length > 0 ? '：' + detail : '') + (hint.length > 0 ? '\n' + hint : '');
}

export class LlmClient {
  /**
   * 调用大模型并返回完整文本。
   * @param onDelta 流式输出时回调，参数是到目前为止累计的全文
   */
  static async complete(p: ProviderConfig, system: string, userText: string, img: ImageInput | null,
    stream: boolean, onDelta: (full: string) => void, task: LlmTask): Promise<string> {
    if (p.baseUrl.trim().length === 0) {
      throw new Error('尚未填写 Base URL');
    }
    if (p.model.trim().length === 0) {
      throw new Error('尚未填写模型名称');
    }
    const url = buildUrl(p, stream);
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: buildHeaders(p),
      extraData: buildBody(p, system, userText, img, stream),
      connectTimeout: 30000,
      readTimeout: 300000
    };

    const req = http.createHttp();
    task.attach(req);
    const decoder = util.TextDecoder.create('utf-8');
    const st = new StreamState();
    let raw = '';
    let ended = false;
    let lastDataAt = Date.now();

    req.on('dataReceive', (data: ArrayBuffer) => {
      lastDataAt = Date.now();
      const chunk = decoder.decodeToString(new Uint8Array(data), { stream: true });
      // 非流式需要完整响应体；流式只留开头一段用于报错
      if (!stream || raw.length < RAW_KEEP_LIMIT) {
        raw += chunk;
      }
      if (stream) {
        st.lineBuf += chunk;
        drainLines(p.format, st, onDelta);
      }
    });
    req.on('dataEnd', () => {
      ended = true;
    });

    let code = 0;
    try {
      code = await req.requestInStream(url, options);
      // 等最后一批数据回调落地：收到 dataEnd，或数据静默超过 1.5 秒
      while (!ended && !task.cancelled && Date.now() - lastDataAt < 1500) {
        await delay(50);
      }
    } catch (e) {
      task.finish();
      if (task.cancelled) {
        throw new Error('已取消');
      }
      throw new Error('网络请求失败：' + errText(e));
    }
    task.finish();
    if (task.cancelled) {
      throw new Error('已取消');
    }

    if (code < 200 || code >= 300) {
      throw new Error(extractHttpError(code, raw));
    }
    if (stream) {
      // 处理没有以换行结尾的最后一行
      if (st.lineBuf.trim().length > 0) {
        st.lineBuf += '\n';
        drainLines(p.format, st, onDelta);
      }
    }
    if (st.full.length === 0 && st.err.length === 0) {
      // 非流式响应；或服务端忽略了 stream 参数直接返回了整段 JSON
      try {
        consumeJson(p.format, raw.trim(), st);
      } catch (e) {
        // 留给下面统一报错
      }
    }
    if (st.err.length > 0) {
      throw new Error(st.err);
    }
    if (st.full.length === 0) {
      if (st.refused) {
        throw new Error('模型拒绝了这次请求，可以换一个模型或服务商再试。');
      }
      throw new Error('模型没有返回内容。请检查模型名称与 API 格式是否匹配。');
    }
    return st.full;
  }
}
