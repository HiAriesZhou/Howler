# Howler

一个极简的 macOS 菜单栏 AI 对话小工具。按 **⌥Space（Option+空格，可自定义）**，一封用火漆封着的羊皮纸信落在屏幕上：在纸上写下问题，羽毛笔把回答一笔一笔写在下面；按 **Esc**，信纸从底边燃起，连同这次对话一起烧成灰烬，什么都不留下。

- **一张纸，不是输入框**：毛边羊皮纸、纤维纹理、折痕；左上角是模型服务的深红火漆印，问题写在横线上，回答用书卷字体写在下方。纸张随内容向下展开，最高到 A4 比例（或屏幕高度），超出后随笔迹滚动
- **羽毛笔书写**：流式回答按手写节奏逐字显现，新墨先泛起金光再沉为墨色，羽毛笔始终停在最后一个字后面（macOS 15+；macOS 14 上羽毛笔停在段落末尾）；等待首字时羽毛笔悬停并显示思考秒数
- **火漆附件**：点右上角的「+ Attach」，选择「从剪贴板粘贴」或「截取屏幕区域」；直接 ⌘V 粘贴长文本或图片也一样。附件会封成右上角刻着符文的琥珀色火漆印，而不是塞进输入框；点火漆印可查看或移除。剪贴板只在你明确粘贴时读取，从不自动读取
- **读完即焚**：关闭时信纸从底边起火，焦痕、火光和火星一路烧到顶上的火漆印（约 1 秒）；打开设置时直接收起，开启“减少动态效果”时也不播放
- **一个模型服务，交给 AI 助手配置**：设置页只显示当前模型、地址和状态，以及「Copy Setup Prompt」按钮；把提示词交给 Claude Code、Codex 等能运行命令的 AI 助手，它会用 Howler 自带的命令行写好配置并检查，API Key 不经过聊天
- 支持三种请求格式，均为真实流式（SSE）输出：Chat Completions（OpenAI 及兼容接口，含本机的 Ollama / LM Studio）、Anthropic Messages、Gemini generateContent；内置 OpenAI、Anthropic、Google Gemini、xAI、DeepSeek、OpenRouter 预设；回答被截断、被拦截或连接中途断开都会明确提示
- 只在菜单栏显示图标，没有 Dock 图标（`LSUIElement`）；可设置登录时启动
- 回答支持 Markdown（行内格式、标题、列表、代码块 + 一键复制），整条回答可一键复制（⇧⌘C）
- 不保存任何对话；API Key 存在系统钥匙串（Keychain）
- 纯 Swift + SwiftUI/AppKit，无第三方依赖，要求 macOS 14+

> **从 Napkin 或 QuickAsk 升级？** 项目已依次从 QuickAsk、Napkin 更名为 Howler，GitHub 仓库也随之改名：本地克隆请执行 `git remote set-url origin https://github.com/HiAriesZhou/Howler.git`。
> 新的 Bundle ID `com.hiarieszhou.howler` 与旧的 `com.hiarieszhou.napkin`、`io.github.hiarieszhou.quickask` 互不相通：钥匙串中的 API Key、`UserDefaults` 设置以及系统授予的隐私权限（TCC）都**不会**沿用，升级后需重新配置模型服务（见下方“配置”）。请删除旧的 `Napkin.app` / `QuickAsk.app`（否则会争抢 ⌥Space）；旧的钥匙串条目可在“钥匙串访问”中搜索 `com.hiarieszhou.napkin` 或 `io.github.hiarieszhou.quickask` 手动删除。

## 安装

1. 从 [Releases](https://github.com/HiAriesZhou/Howler/releases) 下载 `Howler.zip` 并解压，把 `Howler.app` 拖进“应用程序”。
2. 应用只做了 ad-hoc 签名，未经过 Apple 公证，首次打开会被 Gatekeeper 拦截。任选一种方式放行：
   - 在 Finder 中**右键点击 `Howler.app` → 打开**，在弹窗中再点“打开”（macOS 15 起可能需要到“系统设置 → 隐私与安全性”中点“仍要打开”）；
   - 或在终端执行：
     ```bash
     xattr -dr com.apple.quarantine /Applications/Howler.app
     ```
3. 启动后菜单栏会出现 ✉ 信封图标。首次启动若未配置，会自动打开设置窗口。

## 使用

| 操作 | 说明 |
| --- | --- |
| ⌥Space（可在 Settings → General 修改） | 呼出信纸；再按一次烧掉（全局快捷键，任何应用中都可用） |
| ↩ | 发送 |
| ⌥↩ | 换行 |
| ⇧⌘C | 复制最新一条回答（也可点回答下方的 ❧ Copy） |
| 点左上角火漆印 | 查看当前模型，打开设置 |
| 点右上角「+ Attach」 | 从剪贴板粘贴（文字或图片），或截取屏幕区域（拖出一个框，Esc 取消） |
| ⌘V | 短文字进输入框；280 字以上的文字或图片封成火漆附件 |
| 点右上角火漆印 | 查看 / 移除附带的上下文 |
| Esc / 点击纸外 | 烧掉信纸，**同时清空本次对话** |
| 菜单栏图标 → Settings… | 打开设置 |
| 菜单栏图标 → Quit | 退出 |

同一张纸上支持多轮上下文，每轮之间用花饰分隔；烧掉即丢弃。生成过程中可点右上角的 ⏹ 停止，已写下的内容会保留。

附件说明：附上内容后不写问题直接按 ↩，会以 “Explain this.” 发送。附件只随下一个问题发给当前模型服务，请不要粘贴或截取密码、密钥等敏感信息。

- **截屏**：首次使用需要在“系统设置 → 隐私与安全性 → 录屏与系统录音”中允许 Howler，然后再试一次。截屏时信纸会暂时让开，截完带着原来的对话回来。由于应用是 ad-hoc 签名，重新构建安装后可能需要重新授权。
- **图片**：缩放到长边不超过 1568 像素后发送（OpenAI 兼容格式用 `image_url`，Anthropic 用 `image` 块，Gemini 用 `inline_data`）。能否读图取决于所选模型，Howler 不预先拦截；模型不支持时显示服务返回的错误。
- **从剪贴板粘贴**：macOS 15.4 起读取剪贴板可能弹出系统询问，选“允许”即可，信纸会保持打开。

若快捷键已被其他应用占用，菜单和设置中都会提示，此时可换一个快捷键，或通过菜单 “Open Howler” 打开。

## 配置

Howler 只连接**一个模型服务**。设置页（菜单栏图标 → **Settings…**）的 **Model** 一栏只显示当前模型、地址、请求格式和状态（Ready / Not checked yet / Failed / No API key），以及两个按钮：

- **Check**：发送一次极小的真实请求，确认能拿到回答；
- **Copy Setup Prompt**：复制一段配置提示词，交给 Claude Code、Codex 等能运行命令的 AI 助手。助手会问你想用哪家服务和哪个模型，查官方文档确定端点和参数，用 Howler 的命令行写入配置并检查通过。它不会让你把 API Key 发到聊天里，而是请你先复制 Key，再运行 `pbpaste | Howler config set api-key --stdin`。

也可以自己在终端里运行命令行（就是应用本身的可执行文件）：

```bash
H=/Applications/Howler.app/Contents/MacOS/Howler
$H config schema                                   # 全部字段与示例
$H config set preset=deepseek                      # 用预设填好 format / base-url / 默认模型
$H config set model=deepseek-flash 'body={"thinking":{"type":"disabled"}}'
pbpaste | $H config set api-key --stdin            # 也可 --env NAME、--file PATH；Key 从不出现在参数或输出里
$H check                                           # 失败时加 --verbose 查看请求（Key 已遮盖）和错误
$H config show
```

字段：`format`（`chat-completions` / `anthropic-messages` / `gemini-generate-content`）、`base-url`（必须 https，本机 http://localhost 例外）、`model`、`body`（合并进请求体的 JSON，例如关闭思考、设置输出上限）、`headers`（额外请求头，不能放 Key）。预设：

| 预设 | 格式 | base-url | 默认模型 |
| --- | --- | --- | --- |
| `openai` | chat-completions | `https://api.openai.com/v1` | `gpt-5.4-mini` |
| `anthropic` | anthropic-messages | `https://api.anthropic.com/v1` | `claude-opus-5-5` |
| `gemini` | gemini-generate-content | `https://generativelanguage.googleapis.com/v1beta` | `gemini-3.6-flash` |
| `xai` | chat-completions | `https://api.x.ai/v1` | `grok-4.6` |
| `deepseek` | chat-completions | `https://api.deepseek.com` | `deepseek-flash` |
| `openrouter` | chat-completions | `https://openrouter.ai/api/v1` | `openrouter/auto` |

命令行修改配置后，正在运行的 Howler 会立即生效，设置页同步刷新。未配置时，信纸上只显示 “Open Settings” 按钮。

**General**：**Keyboard shortcut**（点按钮后按下组合键，Esc 取消；需包含 ⌘、⌥ 或 ⌃，F 键可单独使用，⌘V、⌘Space 等系统快捷键不可用）与 **Launch at login**。

说明：

- 模型名会过时，可随时用 `config set model=…` 改成服务当前提供的模型。
- Anthropic Messages 默认发送 `max_tokens: 64000`（可用 `body` 覆盖）和 `anthropic-version: 2026-10-21`；连接 `api.anthropic.com` 且模型支持时（`claude-opus-5-5` 等）会附带 `fallbacks: "default"`，在安全分类器拒答时由服务端改用推荐的回退模型。
- 从本应用更早的版本升级时，原先正在使用的服务商、模型和 Key 会自动迁移为新的模型服务；其他服务商的 Key 留在钥匙串中不再使用，可在“钥匙串访问”中搜索 `com.hiarieszhou.howler` 删除。
- 由于是 ad-hoc 签名，**更新应用后**首次读取 Key 时 macOS 可能弹出钥匙串授权提示，点“始终允许”即可。

## 隐私

- **不保存任何对话历史**：消息只在内存中，关闭面板即清空，退出应用即消失。
- 持久化的只有：模型服务配置、最近一次检查结果、快捷键（`UserDefaults`），以及 API Key（钥匙串，service 为应用的 Bundle ID，账户名 `api-key`）。
- 剪贴板与屏幕：只在你按 ⌘V、选择“从剪贴板粘贴”或“截取屏幕区域”时读取；截屏的临时文件读取后立即删除。附件只随下一个问题发给你配置的模型服务。
- 不记录任何日志，不含统计/遥测；网络请求使用 ephemeral `URLSession`，不写磁盘缓存。
- 请求直接发往你配置的模型服务，不经过任何中转服务器（OpenRouter 本身即为聚合服务）。
- 命令行从不打印 API Key：`check --verbose` 中的认证头显示为 `••••`，`config show` 只显示 “saved in Keychain”。

## 图标说明

设置页和信纸上的火漆印使用 SF Symbols 或单色字母标记（如 “O”、“A”、✦；其他服务取域名首字母），**没有打包任何服务商的商标 Logo**。各名称与商标归其各自所有者所有，本项目与它们无关联。

## 改名

应用身份集中在仓库根目录的 [`app.config`](app.config)：

```bash
APP_NAME="Howler"                    # 应用名 / .app 名 / zip 名 / 菜单与窗口标题
BUNDLE_ID="com.hiarieszhou.howler"   # Bundle ID（也是钥匙串 service）
VERSION="0.1.2"
```

修改后重新执行 `make app`。`scripts/bundle.sh` 会据此生成 `Info.plist`，应用运行时从 `Info.plist` 读取名称，界面文字会自动跟随。注意：

- 修改 `BUNDLE_ID` 后，钥匙串中旧 Key 与旧的 `UserDefaults` 不会被新 ID 读取，需要重新配置。
- SwiftPM 的 target/product 名（`Howler` / `HowlerCore`）是内部名称，不随 `APP_NAME` 变化，也不影响用户看到的名字；如也想改，同时修改 `Package.swift`、`Sources/`、`Tests/` 下的目录名、`import` 语句和 `app.config` 中的 `EXECUTABLE_PRODUCT`。
- 若 CI 产物名需要变化，同步修改 `.github/workflows/build.yml` 中的 artifact `name`。

## 从源码构建

需要 Xcode 15.3+（或对应的 Swift 5.10+ 工具链）和 macOS 14+：

```bash
make test   # swift test：模型服务配置、请求构建、SSE 解析、各格式增量与结束信号、文字与图片附件、多模态请求、快捷键、书写节奏
make app    # 构建 universal release，组装并 ad-hoc 签名 build/Howler.app，打包 build/Howler.zip
make run    # 构建并打开
```

调试构建自带演示模式，不需要 API Key、不发网络请求，用于检查信纸、火漆印、羽毛笔和燃烧动画：

```bash
swift build
HOWLER_DEMO=1 .build/debug/Howler        # 附带一段文字火漆印，羽毛笔写一段示例回答
HOWLER_DEMO=long .build/debug/Howler     # 超过 A4 高度后的滚动
HOWLER_DEMO=multi .build/debug/Howler    # 多轮对话
HOWLER_DEMO=burn .build/debug/Howler     # 写完后烧掉
HOWLER_DEMO=setup .build/debug/Howler    # 未配置模型
HOWLER_DEMO=image .build/debug/Howler    # 附带截屏火漆印
HOWLER_DEMO=settings .build/debug/Howler # 设置页（加 HOWLER_DEMO_PROVIDER=deepseek 显示一个已就绪的示例服务）
HOWLER_DEMO_DARK=1 HOWLER_DEMO=1 .build/debug/Howler  # 深色模式下的“烛光”纸张
```

发布：把 `app.config` 的 `VERSION` 改好后推送同名 tag（如 `v0.1.2`），CI 会校验版本一致、构建并创建（或更新）GitHub Release。

代码结构：

```
app.config                 应用名 / Bundle ID / 版本（唯一需要改的地方）
Package.swift
Sources/HowlerCore/        纯逻辑库：ModelService / ServiceConfig（配置与校验）、SetupGuide（提示词与字段说明）、Provider（预设）、
                           RequestBuilder、SSEParser、StreamDecoder、ChatClient、MarkdownBlocks、
                           ContextAttachment（文字 / 图片）、HotKeyCombo、QuillPacing
Sources/Howler/            App：菜单栏、Carbon 全局快捷键、信纸面板（Parchment / HowlerView / Transcript /
                           Seals / Quill / InkText / Burn）、剪贴板与截屏、单页设置、CLI（config / check）、
                           ServiceStore + Keychain、DEBUG 演示模式
Tests/HowlerCoreTests/     XCTest
scripts/bundle.sh          组装 .app、Info.plist（LSUIElement）、codesign、zip
.github/workflows/build.yml  macos-latest 上测试 + 打包 + 上传 artifact
```

手动验收清单见 [ACCEPTANCE.md](ACCEPTANCE.md)。

---

## English

**Howler** is a minimal macOS (14+) menu-bar AI chat shell. Press **Option+Space** (configurable) and an enchanted letter settles on screen: write your question on its line, and a quill writes the answer beneath it, ink blooming from gold into sepia as it streams. Press **Esc** and the letter catches fire at its bottom edge and burns away, taking the conversation with it — nothing is kept.

- **Paper, not a text box:** deckled parchment, fibers, a fold crease; the model service's mark is a crimson wax seal top-left (click it to see the model or open Settings). The sheet grows with the answer up to an A4 page (or the screen), then follows the quill.
- **Wax-sealed context:** "+ Attach" in the corner pastes from the clipboard or captures a screen region (⌘V of a long text or a picture works too). It rides along as a rune-cut amber wax seal instead of filling the question; click it to read or remove it, or just press ↩ to send it with "Explain this." The clipboard is read only when you paste; images go as each API's image part; whether the model can read them is up to the service, whose error is shown if not. Screen capture needs Screen & System Audio Recording permission. Don't paste or capture secrets — attachments go to your model service with the next question.
- **Burn after reading:** dismissing the letter (Esc, a click outside, the hotkey) sets it alight — scorch, glowing edge and sparks, about a second. Opening Settings and Reduce Motion skip the fire.
- **Honest endings:** truncation, safety blocks and dropped connections are reported instead of looking like a finished answer.
- **Settings (one page):** the model in use, its host and format, a status (Ready / Not checked yet / Failed / No API key) with **Check**, and **Copy Setup Prompt**. Below: keyboard shortcut and launch at login. ⇧⌘C copies the latest answer.
- **Demo mode (debug builds):** `HOWLER_DEMO=1 .build/debug/Howler` shows the letter writing a scripted answer with no key or network (`long`, `multi`, `burn`, `image`, `setup`, `settings`; `HOWLER_DEMO_DARK=1`).

> **Upgrading from Napkin or QuickAsk?** The project and its GitHub repo were renamed (QuickAsk → Napkin → Howler); update old clones with `git remote set-url origin https://github.com/HiAriesZhou/Howler.git`. The new bundle ID `com.hiarieszhou.howler` does not share state with `com.hiarieszhou.napkin` or `io.github.hiarieszhou.quickask`: Keychain entries, UserDefaults and any TCC (privacy) grants are reset, so set up the model service again after upgrading. Delete the old `Napkin.app` / `QuickAsk.app` (they would compete for ⌥Space); their Keychain items can be removed in Keychain Access by searching for the old bundle IDs.

- **One model service:** any API speaking Chat Completions (OpenAI and compatible, including local Ollama / LM Studio), Anthropic Messages or Gemini `streamGenerateContent`, with real SSE streaming. Presets: OpenAI, Anthropic, Google Gemini, xAI, DeepSeek, OpenRouter.
- **Install:** download `Howler.zip` from Releases, unzip, move `Howler.app` to Applications. It is ad-hoc signed (not notarized), so right-click → **Open** the first time, or run `xattr -dr com.apple.quarantine /Applications/Howler.app`.
- **Configure:** Settings → **Copy Setup Prompt** and give it to an AI assistant that can run commands (Claude Code, Codex, …). It asks which service and model you want, reads the docs, and drives Howler's own command line — `Howler config schema`, `config set field=value …`, `pbpaste | Howler config set api-key --stdin`, `check [--verbose]`, `config show` — where `Howler` is `/Applications/Howler.app/Contents/MacOS/Howler`. You can run those commands yourself too. The key goes straight into the Keychain and is never printed; the running app picks up changes immediately.
- **Privacy:** no chat history is ever written to disk; only the model service, its last check and the hotkey (UserDefaults) and the API key (Keychain) are stored. The clipboard and screen are read only when you paste or capture. No logging, no telemetry.
- **Glyphs:** SF Symbols / monochrome letter marks pressed into wax — no trademarked provider logos are bundled.
- **Rename:** edit `app.config` (`APP_NAME`, `BUNDLE_ID`) and run `make app`; the app reads its display name from the generated Info.plist.
- **Build:** `make test`, `make app` (Xcode 15.3+ / Swift 5.10+). Push a `v<VERSION>` tag to have CI publish the release.

License: MIT.
