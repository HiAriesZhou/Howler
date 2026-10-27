# Howler

一个极简的 macOS 菜单栏 AI 对话小工具：按 **⌥Space（Option+空格）** 呼出类似 Spotlight 的浮动输入框，提问、流式看到回答，按 **Esc** 关闭，对话随即清空。

- 支持 6 家服务商，均为官方 API 的真实流式（SSE）输出：OpenAI、Anthropic、Google Gemini、xAI、DeepSeek、OpenRouter
- 只在菜单栏显示图标，没有 Dock 图标（`LSUIElement`）
- 回答支持 Markdown（行内格式、标题、列表、代码块 + 一键复制）
- 不保存任何对话；API Key 存在系统钥匙串（Keychain）
- 纯 Swift + SwiftUI/AppKit，无第三方依赖，要求 macOS 14+

> **从 Napkin 或 QuickAsk 升级？** 项目已依次从 QuickAsk、Napkin 更名为 Howler，GitHub 仓库也随之改名：本地克隆请执行 `git remote set-url origin https://github.com/HiAriesZhou/Howler.git`。
> 新的 Bundle ID `com.hiarieszhou.howler` 与旧的 `com.hiarieszhou.napkin`、`io.github.hiarieszhou.quickask` 互不相通：钥匙串中的 API Key、`UserDefaults` 设置以及系统授予的隐私权限（TCC）都**不会**沿用，升级后需在 Settings 中重新填入 API Key。请删除旧的 `Napkin.app` / `QuickAsk.app`（否则会争抢 ⌥Space）；旧的钥匙串条目可在“钥匙串访问”中搜索 `com.hiarieszhou.napkin` 或 `io.github.hiarieszhou.quickask` 手动删除。

## 安装

1. 从 [Releases](https://github.com/HiAriesZhou/Howler/releases) 下载 `Howler.zip` 并解压，把 `Howler.app` 拖进“应用程序”。
2. 应用只做了 ad-hoc 签名，未经过 Apple 公证，首次打开会被 Gatekeeper 拦截。任选一种方式放行：
   - 在 Finder 中**右键点击 `Howler.app` → 打开**，在弹窗中再点“打开”（macOS 15 起可能需要到“系统设置 → 隐私与安全性”中点“仍要打开”）；
   - 或在终端执行：
     ```bash
     xattr -dr com.apple.quarantine /Applications/Howler.app
     ```
3. 启动后菜单栏会出现 💬 图标。首次启动若未配置，会自动打开设置窗口。

## 使用

| 操作 | 说明 |
| --- | --- |
| ⌥Space | 呼出 / 隐藏对话面板（全局快捷键，任何应用中都可用） |
| ↩ | 发送 |
| ⌥↩ | 换行 |
| Esc / 点击面板外 | 关闭面板，**同时清空本次对话** |
| 菜单栏图标 → Settings… | 打开设置 |
| 菜单栏图标 → Quit | 退出 |

面板内同一次会话支持多轮上下文；关闭面板即丢弃。生成过程中可点输入框右侧的 ⏹ 停止。

若 ⌥Space 已被其他应用占用，菜单中会提示，此时可通过菜单 “Open Howler” 打开面板。

## 配置

1. 菜单栏图标 → **Settings…**
2. 在列表中选择一个服务商（单选）。
3. 填入 API Key（`SecureField`，不明文显示）；可选填写模型名，留空则使用默认模型：

   | 服务商 | 接口 | 默认模型 |
   | --- | --- | --- |
   | OpenAI | `api.openai.com/v1/chat/completions` | `gpt-5.4-mini` |
   | Anthropic | `api.anthropic.com/v1/messages` | `claude-opus-5-5` |
   | Google Gemini | `generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse` | `gemini-3.6-flash` |
   | xAI | `api.x.ai/v1/chat/completions` | `grok-4.6` |
   | DeepSeek | `api.deepseek.com/chat/completions` | `deepseek-flash` |
   | OpenRouter | `openrouter.ai/api/v1/chat/completions` | `openrouter/auto` |

4. 点击 **Save**：Key 写入钥匙串，然后发送一次极小的真实请求进行测试，结果显示为 `OpenAI · ✓ Connected` 或 `OpenAI · ✗ 错误信息`。
5. 保存的服务商即为当前使用的服务商。未配置时，面板只显示 “Configure in Settings” 按钮。

说明：

- 模型名会过时，可随时在设置里改成服务商当前提供的任意模型。
- Anthropic 使用 `anthropic-version: 2026-10-21`；对支持的模型（`claude-opus-5-5` 等）会附带 `fallbacks: "default"`，在安全分类器拒答时由服务端自动改用推荐的回退模型。
- 由于是 ad-hoc 签名，**更新应用后**首次读取 Key 时 macOS 可能弹出钥匙串授权提示，点“始终允许”即可。

## 隐私

- **不保存任何对话历史**：消息只在内存中，关闭面板即清空，退出应用即消失。
- 持久化的只有：当前服务商与每个服务商的模型名（`UserDefaults`）、API Key（钥匙串，service 为应用的 Bundle ID）。
- 不记录任何日志，不含统计/遥测；网络请求使用 ephemeral `URLSession`，不写磁盘缓存。
- 请求直接发往你选择的服务商，不经过任何中转服务器（OpenRouter 本身即为聚合服务）。

## 图标说明

服务商列表使用 SF Symbols 或单色字母标记（如 “O”、“A”、✦），**没有打包任何服务商的商标 Logo**。各名称与商标归其各自所有者所有，本项目与它们无关联。

## 改名

应用身份集中在仓库根目录的 [`app.config`](app.config)：

```bash
APP_NAME="Howler"                    # 应用名 / .app 名 / zip 名 / 菜单与窗口标题
BUNDLE_ID="com.hiarieszhou.howler"   # Bundle ID（也是钥匙串 service）
VERSION="0.1.1"
```

修改后重新执行 `make app`。`scripts/bundle.sh` 会据此生成 `Info.plist`，应用运行时从 `Info.plist` 读取名称，界面文字会自动跟随。注意：

- 修改 `BUNDLE_ID` 后，钥匙串中旧 Key 与旧的 `UserDefaults` 不会被新 ID 读取，需要重新配置。
- SwiftPM 的 target/product 名（`Howler` / `HowlerCore`）是内部名称，不随 `APP_NAME` 变化，也不影响用户看到的名字；如也想改，同时修改 `Package.swift`、`Sources/`、`Tests/` 下的目录名、`import` 语句和 `app.config` 中的 `EXECUTABLE_PRODUCT`。
- 若 CI 产物名需要变化，同步修改 `.github/workflows/build.yml` 中的 artifact `name`。

## 从源码构建

需要 Xcode 15.3+（或对应的 Swift 5.10+ 工具链）和 macOS 14+：

```bash
make test   # swift test：请求构建、SSE 解析、各服务商增量解析的单元测试
make app    # 构建 universal release，组装并 ad-hoc 签名 build/Howler.app，打包 build/Howler.zip
make run    # 构建并打开
```

代码结构：

```
app.config                 应用名 / Bundle ID / 版本（唯一需要改的地方）
Package.swift
Sources/HowlerCore/        纯逻辑库：Provider、RequestBuilder、SSEParser、StreamDecoder、ChatClient、MarkdownBlocks
Sources/Howler/            App：菜单栏、Carbon 全局快捷键、浮动面板、设置、Keychain
Tests/HowlerCoreTests/     XCTest
scripts/bundle.sh          组装 .app、Info.plist（LSUIElement）、codesign、zip
.github/workflows/build.yml  macos-latest 上测试 + 打包 + 上传 artifact
```

手动验收清单见 [ACCEPTANCE.md](ACCEPTANCE.md)。

---

## English

**Howler** is a minimal macOS (14+) menu-bar AI chat shell. Press **Option+Space** for a Spotlight-like floating panel, ask, watch the answer stream in, press **Esc** to close — the conversation is discarded.

> **Upgrading from Napkin or QuickAsk?** The project and its GitHub repo were renamed (QuickAsk → Napkin → Howler); update old clones with `git remote set-url origin https://github.com/HiAriesZhou/Howler.git`. The new bundle ID `com.hiarieszhou.howler` does not share state with `com.hiarieszhou.napkin` or `io.github.hiarieszhou.quickask`: Keychain entries, UserDefaults and any TCC (privacy) grants are reset, so re-enter your API key in Settings after upgrading. Delete the old `Napkin.app` / `QuickAsk.app` (they would compete for ⌥Space); their Keychain items can be removed in Keychain Access by searching for the old bundle IDs.

- **Providers:** OpenAI, Anthropic, Google Gemini, xAI, DeepSeek, OpenRouter — real SSE streaming against each official API (OpenAI-compatible `chat/completions`, Anthropic `/v1/messages`, Gemini `streamGenerateContent?alt=sse`).
- **Install:** download `Howler.zip` from Releases, unzip, move `Howler.app` to Applications. It is ad-hoc signed (not notarized), so right-click → **Open** the first time, or run `xattr -dr com.apple.quarantine /Applications/Howler.app`.
- **Configure:** menu-bar icon → Settings… → pick a provider → paste the API key (optionally a model) → **Save**. The key goes to the Keychain and a tiny live request verifies it: `Provider · ✓ Connected` / `✗ error`.
- **Privacy:** no chat history is ever written to disk; only the provider/model (UserDefaults) and the API key (Keychain) are stored. No logging, no telemetry.
- **Glyphs:** SF Symbols / monochrome letter marks only — no trademarked provider logos are bundled.
- **Rename:** edit `app.config` (`APP_NAME`, `BUNDLE_ID`) and run `make app`; the app reads its display name from the generated Info.plist.
- **Build:** `make test`, `make app` (Xcode 15.3+ / Swift 5.10+).

License: MIT.
