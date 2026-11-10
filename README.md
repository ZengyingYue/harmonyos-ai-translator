# AI 翻译（HarmonyOS）

基于大模型的鸿蒙翻译应用：悬浮球常驻在其他应用之上，支持复制翻译、截屏翻译，API Key 与服务商由用户自己配置。

## 功能

| 功能 | 说明 |
| --- | --- |
| 悬浮窗 | 首页打开“悬浮窗”开关后出现可拖动的“译”字悬浮球，点开是翻译面板，可收起、可拖动 |
| 复制翻译 | 在任意应用复制文字 → 点悬浮球 → 点“粘贴”。拿到剪贴板权限后可以复制即自动翻译 |
| 截屏翻译 | 悬浮面板里点“截屏”，同意系统的屏幕采集提示后翻译当前画面；也可以从相册选截图 |
| 分享翻译 | 任意应用里选中文字或打开图片 → “分享” → “AI 翻译”（不依赖悬浮窗权限） |
| 模型配置 | 支持 OpenAI 兼容（Chat Completions）、Anthropic（Messages）、Google Gemini 三种格式，可添加多个服务商并切换 |
| 预设 | OpenAI、Claude、Gemini、DeepSeek、通义千问、智谱、Moonshot、豆包、硅基流动、OpenRouter、自定义 |
| 其他 | 流式输出、自动识别语种、目标语言互换、自定义翻译要求、深色模式、连接测试 |

图片有两种翻译方式（设置里切换）：

- **本机识别文字**（默认）：用系统 Core Vision Kit 在手机上 OCR，再把文字交给模型，任何模型都能用，图片不上传。
- **多模态模型**：把图片直接发给模型，需要所选模型支持图片输入。

## 构建与运行

需要 DevEco Studio 5.0 及以上（Windows / macOS；Linux 没有 DevEco Studio，只能用命令行工具构建）。

1. 用 DevEco Studio 打开本目录，等待同步完成。若提示升级工程结构，按提示升级即可。
2. `File > Project Structure > Signing Configs`，登录华为账号并勾选 **Automatically generate signature**。
3. 手机开启开发者模式和 USB 调试，连接后点运行。
4. 打开应用 → 设置 → 添加服务商 → 填入自己的 API Key → “测试连接” → 保存。

发布前请把 `AppScope/app.json5` 里的 `bundleName`（现为 `com.example.aitranslator`）改成自己的包名。

## 权限说明

| 权限 | 用途 | 类型 |
| --- | --- | --- |
| `ohos.permission.INTERNET` | 调用模型接口 | 普通权限 |
| `ohos.permission.SYSTEM_FLOAT_WINDOW` | 悬浮窗 | 受限开放权限（ACL） |
| `ohos.permission.READ_PASTEBOARD` | 复制后自动翻译（可选，默认未声明） | 受限开放权限（ACL），用户授权 |

受限开放权限必须包含在签名用的 Profile 里，否则 **安装会失败**：

- 调试：新版 DevEco Studio 的自动签名可以直接申请受限开放权限；老版本需要在 AppGallery Connect 手动申请调试 Profile 并勾选对应权限。
- 上架：需要在 AppGallery Connect 按场景申请，审核通过后才能使用。

如果安装时报权限相关的错误，先把 `entry/src/main/module.json5` 中 `SYSTEM_FLOAT_WINDOW` 那一行删掉，应用仍然可以通过“分享”入口和应用内翻译使用，只是没有悬浮窗。

要开启“复制即自动翻译”，在签名拿到 `READ_PASTEBOARD` 授权后，取消 `module.json5` 里那段注释，然后在 设置 → 悬浮窗 里点“申请权限”。没有这个权限时，复制后悬浮球会亮红点，点开按系统“粘贴”按钮即可（粘贴按钮是系统安全控件，不需要权限）。

## 目录结构

```
AppScope/                        应用级配置与图标
entry/src/main/
  module.json5                   权限、分享入口声明
  ets/
    entryability/EntryAbility.ets  应用入口，接收系统分享
    pages/
      Index.ets                  首页
      Settings.ets               设置
      ProviderEdit.ets           服务商编辑、连接测试
      FloatPage.ets              悬浮窗内容（悬浮球 + 面板）
    components/TranslatePanel.ets  首页与悬浮窗共用的翻译面板
    service/
      LlmClient.ets              三种 API 格式的请求与流式解析
      Translator.ets             提示词、文本/图片翻译流程
      FloatWindowManager.ets     悬浮窗创建、展开收起、拖动、剪贴板监听
      ScreenCapture.ets          截屏（AVScreenCapture 录一小段后取帧）
      ClipboardUtil.ets          剪贴板读写与权限
      ImageUtil.ets              图片解码、压缩、base64
      SettingsStore.ets          设置持久化（用户首选项）
    common/                      类型、预设、工具函数
```

## 已知限制

- **悬浮窗权限在手机上能否获批取决于华为的审核政策。** 该权限早期只对平板 / 2in1 开放，手机上请以 AppGallery Connect 的最新说明为准。
- **截屏每次都会弹系统授权提示。** 鸿蒙没有给三方应用提供静默截屏接口，这里用系统录屏接口录不到一秒再取最后一帧，截的是整屏，暂不支持框选区域。
- **应用被系统挂起后悬浮球可能不响应剪贴板变化。** 这时点开悬浮球手动“粘贴”仍然可用。
- API Key 以明文保存在应用沙箱的首选项里，不会上传到模型服务商以外的任何地方。
- Anthropic 格式的 `max_tokens` 固定为 16000，如果接入的是输出上限更低的旧模型或第三方网关，需要在 `LlmClient.ets` 里调小 `ANTHROPIC_MAX_TOKENS`。
