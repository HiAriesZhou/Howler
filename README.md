<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Howler's icon: a crimson wax seal cut with an H, a raven quill, and parchment burning from below">
</p>

<h1 align="center">Howler</h1>

<p align="center">
  <strong><em>Burn after reading.</em></strong>
</p>

<p align="center">
  A sealed letter for your quick questions on macOS.<br>
  Write on the parchment, a quill writes the answer back, and the letter burns when you're done.
</p>

<p align="center">
  <a href="https://github.com/HiAriesZhou/Howler/releases"><img src="https://img.shields.io/github/v/release/HiAriesZhou/Howler?include_prereleases&style=flat-square&color=a0211b&label=release" alt="Latest release"></a>
  <a href="https://github.com/HiAriesZhou/Howler/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/HiAriesZhou/Howler/build.yml?branch=main&style=flat-square&label=build" alt="Build status"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-3b2f25?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.10">
  <img src="https://img.shields.io/badge/dependencies-none-b5801f?style=flat-square" alt="No dependencies">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/HiAriesZhou/Howler?style=flat-square&color=5e3b08" alt="MIT license"></a>
</p>

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img src="docs/images/letter.png" width="720" alt="A Howler letter: a question beside a crimson wax seal, the answer written beneath it in ink">
</p>

---

## The letter

Press **⌥Space** anywhere. A letter settles at the top of the screen, already sealed in wax.

- **Parchment, not a text box.** The paper has deckled edges, fibers and a fold crease. Your question sits on a ruled line, and the answer is set in a book face below it. The sheet grows with the answer up to an A4 page, then follows the quill.
- **A quill that writes.** Answers stream in at a hand's pace. Fresh ink glows gold before it settles to sepia, and the quill rests after the last word. While the model thinks, the quill hovers and counts the seconds.
- **Wax seals.** The crimson seal names the model writing to you. Paste a long text or a picture, or capture a region of the screen, and it is sealed into an amber seal cut with runes instead of filling your question.
- **Burn after reading.** Press Esc or click outside, and the letter catches fire at its bottom edge. Scorch, embers and sparks climb to the seal, and the conversation goes with them. Nothing is saved.

<table>
  <tr>
    <td width="50%"><img src="docs/images/burning.png" alt="The letter burning from its bottom edge"></td>
    <td width="50%"><img src="docs/images/letter-dark.png" alt="The letter on candlelit paper in Dark Mode"></td>
  </tr>
  <tr>
    <td align="center"><em>Esc, and it burns</em></td>
    <td align="center"><em>Candlelit paper in Dark Mode</em></td>
  </tr>
</table>

Reduce Motion turns off the falling paper, the stamping, the ink shimmer and the fire. The text simply appears.

## Install

1. Download `Howler.dmg` from [Releases](https://github.com/HiAriesZhou/Howler/releases), open it, and drag Howler onto Applications. `Howler.zip` holds the same app.
2. The app is ad-hoc signed and not notarized, so Gatekeeper stops it the first time. Right-click it and choose **Open** (on macOS 15+, use **System Settings › Privacy & Security › Open Anyway**), or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Howler.app
   ```
3. A small wax seal marked H appears in the menu bar. Howler has no Dock icon.

## Set up a model

Howler writes with one model service. The setup is short enough to hand to an AI assistant.

<p align="center">
  <img src="docs/images/settings.png" width="460" alt="Howler Settings: the model, its host and status, Check and Copy Setup Prompt">
</p>

Open **Settings › Copy Setup Prompt** and paste it into Claude Code, Codex or another assistant that can run commands. It asks which service and model you want, checks the official docs, writes the setup and runs a check until it passes. It never asks for your API key in the chat. When it needs the key, it asks you to copy it, then runs `pbpaste | Howler config set api-key --stdin`, which sends the key straight into the Keychain.

You can run the same commands yourself. They live in the app binary:

```bash
H=/Applications/Howler.app/Contents/MacOS/Howler
$H config schema                                    # every field, with examples
$H config set preset=deepseek 'body={"thinking":{"type":"disabled"}}'
pbpaste | $H config set api-key --stdin             # or --env NAME, --file PATH
$H check                                            # --verbose shows the request, key masked
$H config show
```

| Field | Meaning |
| --- | --- |
| `format` | `chat-completions` (OpenAI and compatible, including local Ollama / LM Studio), `anthropic-messages`, `gemini-generate-content` |
| `base-url` | API base without the endpoint path; `https://` only, except `http://localhost` |
| `model` | Model name as the service spells it |
| `body` | JSON merged into every request, e.g. to turn thinking off or cap the output |
| `headers` | Extra HTTP headers. Never the key. |
| `preset` | `openai`, `anthropic`, `gemini`, `xai`, `deepseek` or `openrouter`. Fills the three fields above. |

Changes take effect in the running app at once. Every request goes straight to the service you configured, never through a relay.

## Use

| | |
| --- | --- |
| **⌥Space** | Open the letter. Press again to burn it. The shortcut can be changed in Settings. |
| **↩** / **⌥↩** | Send / new line |
| **⇧⌘C** | Copy the latest answer (or click ❧ Copy) |
| **+ Attach** | Paste from the clipboard, or capture a screen region |
| **⌘V** | Short text goes into the question. Long text or a picture is sealed as an attachment. |
| **Esc** / click outside | Burn the letter, and the conversation with it |

Follow-up questions stay on the same sheet, separated by a fleuron. ⏹ stops a reply and keeps what is already written. Attachments travel only with your next question, so leave out passwords and other secrets. Screen capture asks for Screen & System Audio Recording permission the first time.

## Privacy

- No chat history, ever. Messages live in memory and burn with the letter.
- Stored: the model setup, its last check and your shortcut (UserDefaults), plus the API key (Keychain).
- The clipboard and the screen are read only when you paste or capture.
- No logs, no telemetry. Network requests use an ephemeral `URLSession`.
- The command line never prints the key.

## Build from source

Requires Xcode 15.3+ (Swift 5.10+) and macOS 14+. No third-party dependencies.

```bash
make test   # unit tests: config, requests, streaming, attachments, hotkeys, quill pacing
make app    # universal build → build/Howler.app and build/Howler.zip (ad-hoc signed)
make dmg    # the same app in build/Howler.dmg, beside an Applications link
make run    # build and open
make icon   # re-render Resources/AppIcon.icns from Sources/Howler/AppIconArt.swift
```

Debug builds include a demo mode that needs no key and no network:

```bash
swift build
HOWLER_DEMO=1 .build/debug/Howler          # also: long, multi, burn, image, setup, settings
HOWLER_DEMO_DARK=1 HOWLER_DEMO=1 .build/debug/Howler
```

To rename the app or change its bundle ID, edit [`app.config`](app.config) and rebuild. To release, bump `VERSION` there and push a matching `v` tag. CI tests, builds and publishes the release. Manual checks are listed in [ACCEPTANCE.md](ACCEPTANCE.md).

<details>
<summary>Upgrading from Napkin or QuickAsk</summary>

The project was renamed QuickAsk → Napkin → Howler, and so was the GitHub repo. Update old clones with `git remote set-url origin git@github.com:HiAriesZhou/Howler.git`. The bundle ID `com.hiarieszhou.howler` shares nothing with `com.hiarieszhou.napkin` or `io.github.hiarieszhou.quickask`, so set up the model again. Delete the old app, because both would compete for ⌥Space. You can remove the old Keychain items in Keychain Access by searching for the old bundle IDs.
</details>

---

<p align="center">
  <sub>The icon and seals are drawn in code with the letter's own paper, wax and fire. Provider marks are monochrome letters and SF Symbols; no trademarked logos are bundled.<br>
  MIT License · © 2026 AriesZhou</sub>
</p>
