# QuickAsk 手动验收清单 / Manual Acceptance Checklist

在一台 macOS 14+ 的 Mac 上，用 Release 中的 `QuickAsk.zip` 逐项验证。每项打 ✅ / ❌ 并备注。
Run on macOS 14+ with the released `QuickAsk.zip`. Mark each item ✅ / ❌.

环境 / Environment：macOS 版本 ______ · 芯片 Apple Silicon / Intel · 版本 v______

## 1. 安装与启动 / Install & launch

- [ ] 解压后 `QuickAsk.app` 可通过右键 → 打开（或 `xattr -dr com.apple.quarantine`）启动
- [ ] 菜单栏出现图标；**Dock 中没有图标**；⌘Tab 中不出现
- [ ] 首次启动（未配置）自动弹出 Settings 窗口
- [ ] 菜单包含：Open QuickAsk（⌥Space）、Settings…、Quit QuickAsk；Quit 可正常退出

## 2. 全局快捷键与面板 / Hotkey & panel

- [ ] 在任意应用（Finder、Safari、全屏应用）中按 ⌥Space 呼出面板，面板位于当前屏幕上方居中
- [ ] 再按 ⌥Space 关闭面板
- [ ] 面板出现时输入框自动获得焦点，可直接输入；前台应用不会被切走（菜单栏仍显示原应用名）
- [ ] 中文输入法：可正常输入拼音选词；选词过程中按 Esc 只取消组字，不关闭面板
- [ ] Esc 关闭面板；点击面板外部关闭面板
- [ ] 多显示器：在鼠标所在屏幕上弹出
- [ ] 未配置时，面板只显示 “Configure in Settings” 按钮，点击打开设置

## 3. 设置 / Settings

- [ ] 列表显示 6 个服务商，每个带单色图标（SF Symbol 或字母），无商标 Logo
- [ ] 单选：选中服务商后出现 API Key（SecureField，不明文）与 Model 输入框，Model 占位符为默认模型
- [ ] 输入错误 Key → Save → 显示 `<服务商> · ✗ HTTP 401: …`（含服务商返回的错误信息）
- [ ] 输入正确 Key → Save → 显示 `<服务商> · ✓ Connected`
- [ ] 已保存 Key 的服务商在列表中显示 🔑；当前服务商显示 ✓
- [ ] 留空 Key 再次 Save 会保留原 Key 并重新测试
- [ ] 填写不存在的模型名 → Save → 显示 ✗ 及服务商的错误信息
- [ ] Remove Key 后该服务商 🔑 消失；若为当前服务商，面板回到 “Configure in Settings”
- [ ] 打开“钥匙串访问”，搜索 `io.github.hiarieszhou.quickask` 可看到条目（账户名为服务商 id）
- [ ] 退出并重启应用：服务商、模型、Key 仍然有效

## 4. 各服务商真实流式 / Per-provider real streaming

对每个服务商：保存 Key（模型留空用默认值），呼出面板，发送下列提示词。
For each provider: save a key (default model), open the panel, send the prompts below.

提示词 / Prompts：
1. `用三段话介绍一下 SSE（Server-Sent Events）`（长回答，观察**逐字流式**而不是一次性出现）
2. `再用一句话总结`（验证**多轮上下文**：回答应基于上一条）
3. `写一个 Swift 函数计算斐波那契数，并用列表说明复杂度`（验证 Markdown：代码块、复制按钮、列表、加粗）

| 服务商 | ✓ Connected | 1. 流式 | 2. 多轮 | 3. Markdown | 停止按钮 | 备注（模型） |
| --- | --- | --- | --- | --- | --- | --- |
| OpenAI | | | | | | |
| Anthropic | | | | | | |
| Google Gemini | | | | | | |
| xAI | | | | | | |
| DeepSeek | | | | | | |
| OpenRouter | | | | | | |

额外 / Extra：
- [ ] DeepSeek 使用 `deepseek-reasoner`：只显示最终回答，不显示推理内容
- [ ] OpenRouter 使用其他模型（如 `anthropic/claude-sonnet-5.5` 或任一可用模型）正常流式
- [ ] 生成中点击 ⏹：立即停止，已生成内容保留，可继续提问

## 5. 会话与隐私 / Session & privacy

- [ ] 关闭面板后再打开：对话已清空
- [ ] 生成过程中关闭面板：请求被取消，再打开为空白，不会出现旧回答
- [ ] `~/Library/Containers`、`~/Library/Application Support`、`~/Library/Caches` 中没有 QuickAsk 的对话文件
- [ ] `defaults read io.github.hiarieszhou.quickask` 只包含 `provider` 与 `models`
- [ ] Console.app 中按进程 QuickAsk 过滤，发送消息时没有对话内容日志

## 6. 错误处理 / Errors

- [ ] 断网后发送：面板内显示红色错误信息，不崩溃
- [ ] Key 失效（在服务商后台删除）后发送：显示服务商返回的错误信息
- [ ] ⌥Space 被其他应用占用时：菜单显示提示，通过菜单 Open 仍可使用

## 7. 改名 / Rename

- [ ] 修改 `app.config` 中 `APP_NAME="AskBox"` 后 `make app`：得到 `build/AskBox.app` 与 `build/AskBox.zip`，菜单项、设置窗口标题均显示 AskBox
