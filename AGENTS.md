# AGENTS.md

Howler is a macOS 14+ menu bar app (Swift 5.10, SwiftPM). `HowlerCore` holds the testable logic; `Howler` is the app. README.md describes the product; this file only holds what an agent needs to work here.

## Scope and public content

- Agree on the task's scope and authorization before changing files. Permission to edit does not grant permission to commit, push, publish, install or change system settings.
- Preserve existing changes. Work on a task branch; changes to the protected default branch go through a pull request.
- This is a public, MIT-licensed repository. Keep documentation about the project, not the maintainer's machine or private workflow. Do not commit personal paths, private account or certificate details, credentials, user content, raw session logs or agent memory. Use synthetic fixtures and neutral placeholders; review screenshots before committing them.
- Preserve required license notices and intentional public author attribution, including the website's avatar, homepage and social links. These are distinct from private credentials and user data.
- Keep durable rules here and product usage in the two READMEs. Keep one-off handoffs, audit reports and task progress local. Preserve any existing `CLAUDE.md`; do not silently replace another tool's instructions.

## Engineering boundaries

- Keep protocol, request and parsing logic in `HowlerCore`, with focused tests. Keep AppKit, SwiftUI, Keychain and other macOS integrations in `Howler`.
- Conversations stay in memory and are cleared when the letter closes. Stop cancelled streams from writing into a later conversation. Screen capture uses a temporary file: keep its cleanup and describe that exception accurately.
- API keys belong in Keychain, never command arguments, logs, fixtures or documentation. Read the clipboard and screen only after a user action; use an ephemeral session for chat requests.
- Preserve input-method composition, selection-aware copy, Reduce Motion, and legacy configuration/shortcut migration. Add manual checks when behavior changes.
- The Settings footer shows either the current version or one Update button. A click authorizes only the offered update, including restart; cancellation, failure or session end clears that consent. Keep download validation and installation in Sparkle, with its progress and error UI. Informational and major-upgrade offers retain Sparkle's standard confirmation.

## Commands

- `make test`: unit tests (`swift test`).
- `make app`: universal app in `build/stage.noindex/Howler.app` and `build/Howler.zip`. Set `SIGN_IDENTITY` for a Developer ID build; otherwise it is ad-hoc signed.
- `make dmg`: builds the app and wraps it in `build/Howler.dmg`.
- Debug demo: `swift build && HOWLER_DEMO=settings .build/debug/Howler`. The variants are listed at the top of `Sources/Howler/DemoMode.swift`. `HOWLER_DEMO_SNAPSHOT=out.png` saves the Settings window as a PNG without screen-recording permission.

## Versions

- `app.config` holds `VERSION` and `BUILD_NUMBER`. Bump both in their own commit (`chore: bump version to X.Y.Z`).
- Stay on 0.1.x and bump only the patch number.
- `BUILD_NUMBER` goes up by one every release. Sparkle compares it to decide whether an update is newer.

## Releasing

1. Merge the pull request. Use rebase and merge when it has several commits.
2. Push an annotated tag `vX.Y.Z` on the merge commit. It must match `VERSION`.
3. CI tests, builds, signs and notarizes. It then creates the GitHub Release with `Howler.zip`, `Howler.dmg` and `appcast.xml` in one step.

Don't create the GitHub Release yourself before CI finishes. It would become "latest" without `appcast.xml`, and installed copies would get a 404 from `SUFeedURL` until CI catches up. The secrets CI needs, and the Sparkle update key, are described in `docs/release-signing.md`. Keys never go into the repo or a chat.

## Checks before a pull request

- `make test`, then a signed `make app`. For user-visible changes, try the installed app.
- Use the same Developer ID identity for installed-app checks so updates retain Keychain and privacy grants. Obtain the identity from the local signing environment; do not record its personal details here. Installing or replacing the app must be within the task's authorization.
- Manual checks are listed in `ACCEPTANCE.md`. Add a line there for new behavior.
- Record the tested version, environment and result without user data. Distinguish source inspection, fixture tests, CI results, real-service checks and human acceptance. An unchecked item is not a pass.
- Review the diff and public content before a pull request. Documentation-only changes need link, consistency and privacy checks; they do not require rebuilding or reinstalling the app.
