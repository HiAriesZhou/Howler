# Howler 手动验收清单 / Manual Acceptance Checklist

在一台 macOS 14+ 的 Mac 上，用 Release 中的 `Howler.dmg`（或 `Howler.zip`）逐项验证。每项打 ✅ / ❌ 并备注。
Run on macOS 14+ with the released `Howler.dmg` (or `Howler.zip`). Mark each item ✅ / ❌.

环境 / Environment：macOS 版本 ______ · 芯片 Apple Silicon / Intel · 版本 v______

## 1. 安装与启动 / Install & launch

- [ ] 打开 `Howler.dmg`：窗口中有 Howler 与 Applications 快捷方式，拖入后可推出磁盘映像
- [ ] 安装后直接双击即可打开，没有 Gatekeeper 警告；`spctl --assess --type execute -vv /Applications/Howler.app` 显示 `source=Notarized Developer ID`
- [ ] 菜单栏出现图标；**Dock 中没有图标**；⌘Tab 中不出现
- [ ] 首次启动（未配置）自动弹出 Settings 窗口
- [ ] Finder、DMG 中的 Howler.app 显示羽毛笔火漆图标（不是空白应用图标）
- [ ] 菜单栏图标为刻着 H 的火漆剪影，随浅色 / 深色菜单栏变色；菜单包含：Open Howler（⌥H）、Settings…、Quit Howler；Quit 可正常退出

## 2. 全局快捷键与面板 / Hotkey & panel

- [ ] 在任意应用（Finder、Safari、全屏应用）中按 ⌥H 呼出信纸，位于当前屏幕上方居中，带纸张落下的动画与火漆印“盖章”动画
- [ ] 再按 ⌥H：信纸从底边起火烧掉（约 1 秒），然后消失
- [ ] 信纸出现时输入框自动获得焦点，可直接输入；前台应用不会被切走（菜单栏仍显示原应用名）
- [ ] 中文输入法：可正常输入拼音选词；选词过程中按 Esc 只取消组字，不关闭信纸
- [ ] ⌘V / ⌘C / ⌘A / ⌘Z 在输入框中可用
- [ ] Esc 烧掉信纸；点击纸张外部（包括纸张阴影区域）烧掉信纸
- [ ] 燃烧中再按 ⌥H：立即出现一张新的空白信纸
- [ ] 从菜单或火漆印打开 Settings：信纸直接收起，不燃烧
- [ ] 多显示器：在鼠标所在屏幕上弹出
- [ ] 未配置时，信纸显示 “This parchment has no ink yet.” 与 “Open Settings” 按钮，点击打开设置

## 2a. 信纸交互 / Letter interactions

- [ ] 空白信纸：毛边、纤维纹理、中间折痕；左上角为当前模型服务的深红火漆印（蜡滴、下陷压印、浮雕字母、高光）；中间有花体提示
- [ ] 系统为深色模式时纸张变暗为“烛光”色，文字与占位符仍为深色墨水
- [ ] 右上角为淡色虚线圆圈 “+ Attach”；点击弹出菜单：Paste from Clipboard、Capture Screen Region…
- [ ] 复制一段文字后选择 Paste from Clipboard：右上角压上琥珀色火漆印（刻符文、文档图标），下方写 “Pasted text / N chars”；输入框**不**包含这段文字
- [ ] 复制一张图片（如在预览中 ⌘C）后在输入框按 ⌘V：封成 “Pasted image / 宽×高” 火漆印（图片图标）
- [ ] 向输入框粘贴 300 字以上文本：文本不留在输入框，变成 “Pasted text” 火漆印；短文本照常进入输入框
- [ ] 剪贴板为空时选择 Paste from Clipboard：显示 “There's no text or picture on the clipboard.”
- [ ] Capture Screen Region…（首次）：提示到“录屏与系统录音”中允许 Howler；允许后再次选择：信纸让开，出现十字准星，拖出区域后信纸带着原对话回来，压上 “Screenshot / 宽×高” 火漆印；Esc 取消时信纸原样回来
- [ ] 点火漆印：展开预览卡片（文字显示前几行，图片显示缩略图），可 Remove
- [ ] 有火漆印、输入框为空时按 ↩：以 “Explain this.” 发送
- [ ] 带火漆印发送：问题前出现 ✦，回答针对附件内容（截图问 “图里写了什么”）；之后的问题不再附带
- [ ] DeepSeek 下带图片发送：请求照常发出；模型能读图则回答图片内容，不能则显示 DeepSeek 返回的错误（Howler 不预先拦截）
- [ ] 不主动粘贴或截屏时，Howler 从不读取剪贴板（macOS 15.4+ 不会弹出“允许粘贴”提示）
- [ ] 点左上角火漆印：菜单显示 “Written by <模型>”（悬停显示完整配置）与 Settings…；页脚显示 “模型 · 主机”
- [ ] 发送后先出现悬停的羽毛笔与 “The quill is thinking…”，2 秒后显示秒数
- [ ] 回答逐字显现、新字带金色微光；macOS 15+ 羽毛笔停在最后一个字之后；macOS 14 停在段落末尾
- [ ] 纸张随回答向下变长；超过 A4 比例或屏幕可用高度后改为滚动，顶部文字在书写线下渐隐
- [ ] 书写中向上滚动阅读：不会被拉回底部；滚回底部后继续跟随
- [ ] 回答写完后出现 ❧ Copy；点击或按 ⇧⌘C 复制整条回答，显示 ✓ Copied
- [ ] 多轮对话之间有 ❦ 花饰分隔；新问题发送后滚动到底部
- [ ] 系统设置开启“减少动态效果”：无落纸、盖章、火漆光晕、燃烧和逐字动画，文字随到随显，关闭时直接消失

## 3. 设置 / Settings

- [ ] 设置窗口顶部有 General、Prompt 两个工具栏标签，窗口标题随标签变化；General 页依次是模型卡片、快捷键与开机启动、隐私说明（提醒不要粘贴或截取敏感信息）；设置页任何地方都不要求输入 API Key
- [ ] 切换标签：两页同高，只交叉淡入，窗口大小不变；Prompt 页的编辑框填满剩余高度；开启“减弱动态效果”后直接切换；未配置模型时打开设置总是停在 General 页
- [ ] 在 Prompt 编辑框里输入后切到 General 再按 Delete / ⌘A：系统提示词不被改动
- [ ] Check 失败使 General 变高：窗口平滑变高、上边缘不动，Prompt 页编辑框随之变高
- [ ] 未配置：Model 显示问号火漆印、“No model yet”，下方 “Set up a model” 与 Copy Setup Prompt；没有 Check 按钮
- [ ] 已配置：深红火漆印（DeepSeek 为 “D”、Gemini 为 ✦，其他服务为域名首字母）、模型名、“主机 · 格式”，状态为 Ready / Not checked yet / Failed / No API key
- [ ] Copy Setup Prompt：按钮短暂显示 ✓ Copied；粘贴出的提示词包含本机可执行文件路径与当前配置（未配置时为 “not set up yet”），要求助手用 `pbpaste | Howler config set api-key --stdin` 写入 Key
- [ ] 把提示词交给 Claude Code（或 Codex）：助手询问服务与模型，运行 `config schema` → `config set` → 请你复制 Key 后运行 `pbpaste | … --stdin` → `check` → `config show`；全程 Key 不出现在聊天与输出中
- [ ] 应用运行时在终端执行 `config set model=…`：设置页与信纸页脚立即显示新模型，状态变为 Not checked yet
- [ ] 点 Check：显示 Checking…，正确配置变为绿色 Ready；在终端执行 `config show` 的 check 一行为 passed
- [ ] 错误 Key 或不存在的模型 → Check：红色 Failed，下方显示服务返回的错误（如 HTTP 401）
- [ ] 打开“钥匙串访问”，搜索 `com.hiarieszhou.howler` 可看到账户名为 `api-key` 的条目
- [ ] 从配置了服务商的旧版本升级：首次启动后原服务商、模型与 Key 自动迁移，设置页直接显示该模型（状态 Not checked yet），发送可用
- [ ] 退出并重启应用：模型服务、Key、快捷键仍然有效
- [ ] 从 v0.1.4 升级：没改过快捷键（或曾点过 ↺ 恢复 ⌥Space）的，升级后默认为 ⌥H；录制过其他快捷键的保持不变；升级后再特意录制 ⌥Space，重启后仍是 ⌥Space

### 3a. 命令行 / Command line

`H=/Applications/Howler.app/Contents/MacOS/Howler`

- [ ] `$H help`、`$H config schema` 输出用法与全部字段、预设、格式；不启动菜单栏图标
- [ ] `$H config set model=x`（未配置时）：报缺少 format、base-url，退出码 1
- [ ] `$H config set api-key=sk-…`：拒绝，提示用 `--stdin` / `--env` / `--file`
- [ ] `$H config set api-key --stdin` 直接在终端运行（无管道）：拒绝并给出 `pbpaste | …` 用法
- [ ] `$H config set 'body={"messages":[]}'`、`'headers={"Authorization":"x"}'`、`base-url=http://example.com`：均被拒绝并说明原因
- [ ] `$H config set preset=deepseek 'body={"thinking":{"type":"disabled"}}'` 后 `$H config show`：显示 endpoint、body；api-key 只显示 saved in Keychain / not set
- [ ] `$H check --verbose`：打印请求 URL、请求头（认证头为 `••••`）与请求体，失败时显示 HTTP 状态与错误
- [ ] 本机 Ollama 等：`$H config set format=chat-completions base-url=http://localhost:11434/v1 model=<本地模型>` 后 `check` 通过，信纸可正常流式回答
- [ ] `$H config reset`：配置与 Key 被删除，设置页回到 “No model yet”

### 3b. 通用 / General

- [ ] General → Keyboard shortcut：点按钮后按 ⌃⌥K，菜单栏 “Open Howler” 显示新快捷键，⌃⌥K 可呼出、⌥H 不再响应；录制中按 Esc 取消
- [ ] Keyboard shortcut：只含 ⇧ 的组合提示需加 ⌘/⌥/⌃；⌘V、⌘C、⌘Space 等系统快捷键被拒绝；被其他应用占用时显示红色提示；点 ↺ 恢复 ⌥H
- [ ] Keyboard shortcut：开始录制后切到其他窗口或关闭设置窗口，录制自动结束，原快捷键恢复可用
- [ ] General → Launch at login：打开后注销重新登录，Howler 自动启动（若提示需批准，按提示到“登录项”中允许）

### 3c. 系统提示词 / System prompt

- [ ] 首次打开 Prompt 页：System Prompt 标题旁为灰色 ↺ Reset，下方显示 🔒 `Current date: <今天的 UTC 日期> (UTC).`（不可编辑），下方是完整的建议指令；底部说明 “Suggested for the letter…”
- [ ] 修改指令：Reset 变为蓝色可点，底部变为 “Edited. Leave it empty to turn the system prompt off…”；关闭再打开设置、重启应用后修改仍在
- [ ] 点 Reset：恢复建议指令，Reset 变灰；把指令改回与建议完全相同的文字，Reset 同样变灰
- [ ] 清空指令：日期一行变为 “Off: nothing is sent, not even the date.”；`$H check --verbose` 的请求里没有任何系统提示词；恢复建议后，请求体首条为 system 消息（Anthropic 为 `system`，Gemini 为 `systemInstruction`），内容为日期 + 指令
- [ ] `$H config show` 的 prompt 一行显示 suggested / your instructions / off
- [ ] 问 “2026 GitHub Universe 总结” 之类训练截止之后的事：回答不再断言“尚未举办”，而是说明可能没有相关数据
- [ ] 让模型对比几样东西：回答不用 `|` 表格（信纸会把表格显示成原样符号）

## 4. 各服务真实流式 / Per-service real streaming

对每个预设：用 `config set preset=…` 写入并保存 Key、`check` 通过后，呼出面板，发送下列提示词。
For each preset: `config set preset=…`, save a key, pass `check`, open the panel, send the prompts below.

提示词 / Prompts：
1. `用三段话介绍一下 SSE（Server-Sent Events）`（长回答，观察**逐字流式**而不是一次性出现）
2. `再用一句话总结`（验证**多轮上下文**：回答应基于上一条）
3. `写一个 Swift 函数计算斐波那契数，并用列表说明复杂度`（验证 Markdown：代码块、复制按钮、列表、加粗）

| 预设 | ✓ check | 1. 流式 | 2. 多轮 | 3. Markdown | 停止按钮 | 备注（模型） |
| --- | --- | --- | --- | --- | --- | --- |
| OpenAI | | | | | | |
| Anthropic | | | | | | |
| Google Gemini | | | | | | |
| xAI | | | | | | |
| DeepSeek | | | | | | |
| OpenRouter | | | | | | |

额外 / Extra：
- [ ] DeepSeek 使用会输出推理内容的模型（如 `deepseek-v4-pro`）：只显示最终回答，不显示推理内容
- [ ] OpenRouter 使用其他模型（如 `anthropic/claude-sonnet-5.5` 或任一可用模型）正常流式
- [ ] 生成中点击 ⏹：立即停止，已生成内容保留，可继续提问
- [ ] 用很小的输出上限或长回答触发截断：回答保留，下方显示 “The reply was cut off…”（OpenAI 兼容 / Anthropic / Gemini 各验证一家）
- [ ] 回答中途断网：已写内容保留，显示 “The connection closed before the reply finished…”

## 5. 会话与隐私 / Session & privacy

- [ ] 关闭面板后再打开：对话已清空
- [ ] 生成过程中关闭面板：请求被取消，再打开为空白，不会出现旧回答
- [ ] `~/Library/Containers`、`~/Library/Application Support`、`~/Library/Caches` 中没有 Howler 的对话文件
- [ ] `defaults read com.hiarieszhou.howler` 只包含 `service`、检查过时的 `serviceCheck`、`hotKeyDefaultChecked`，以及改过时的 `hotKey`；其中没有 API Key
- [ ] Console.app 中按进程 Howler 过滤，发送消息时没有对话内容日志

## 6. 错误处理 / Errors

- [ ] 断网后发送：面板内显示红色错误信息，不崩溃
- [ ] Key 失效（在服务商后台删除）后发送：显示服务商返回的错误信息
- [ ] 快捷键被其他应用占用时：菜单与设置中显示提示，通过菜单 Open 仍可使用

## 7. 改名 / Rename

- [ ] 修改 `app.config` 中 `APP_NAME="AskBox"` 后 `make app`：得到 `build/stage.noindex/AskBox.app` 与 `build/AskBox.zip`，菜单项、设置窗口标题均显示 AskBox

## 8. 发布 / Release

- [ ] 推送与 `app.config` 中 `VERSION` 一致的 tag（如 `v0.1.2`）：CI 创建 pre-release 并附上 `Howler.zip` 与 `Howler.dmg`
- [ ] 推送不一致的 tag：CI 的 “Publish release” 步骤失败并说明原因
