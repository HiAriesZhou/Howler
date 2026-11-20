# Agent guide

Read this guide when building, testing, running a demo, or preparing a pull request. Product, privacy and release constraints remain in the root AGENTS.md.

## Commands

- `make check`: choose checks from the branch diff and local edits (`BASE=<ref>` overrides `origin/main`). Node.js 20+ is required for this command and CI scope checks.
- `make test` / `make test-core`: fast core tests; excludes the app, AppKit and Sparkle, using `.build/core-tests`.
- `make test-app`: app and interaction tests on macOS, excluding release-tool fixtures.
- `make test-tooling`: release/signing/Homebrew fixture tests, without UI interaction tests or real publication.
- `make test-all`: all tests (`swift test`); use for full validation or release preparation.
- `make test-ci`: change-classifier regression tests; no native build.
- `make app`: universal app in `build/stage.noindex/Howler.app` and `build/Howler.zip`. Set `SIGN_IDENTITY` for a Developer ID build; otherwise it is ad-hoc signed.
- `make dev`: build for this Mac and launch `build/dev/stage.noindex/Howler Dev.app`. It uses its own preferences and Keychain service. Updates and the `howler://` link are disabled. The Settings footer shows the short commit, with `-dirty` for uncommitted changes. The Dev menu opens letters without taking the release app's default shortcuts.
- `make dmg`: builds the app and wraps it in `build/Howler.dmg`.
- Debug demo: `swift build && HOWLER_DEMO=settings .build/debug/Howler`. The variants are listed at the top of `Sources/Howler/DemoMode.swift`. `HOWLER_DEMO_SNAPSHOT=out.png` saves the Settings window as a PNG without screen-recording permission.

## Checks before a pull request

- Choose verification by the changed behavior; do not run Swift tests, signed builds or installation for documentation, website copy/metadata, OG images or other non-behavioral assets. Check their content, links, image properties or browser output as appropriate.
- Core logic: `make test-core`; compile the app when changing core source contracts. Native interaction/state: `make test-app`, plus targeted installed-app checks when relevant. Mixed core/app changes: `make test-all`.
- Pure icon-rendering Swift changes need a compile check, not interaction tests. A mixed SwiftUI file may contain event/state behavior: treat it as an interaction change unless that behavior is demonstrably unaffected.
- Build, dependency, bundle identity or release tooling changes need the relevant fixture tests and packaging checks. Signed universal builds and full release checks remain required before a release; do not sign and create a DMG for every PR.
- Use the same Developer ID identity for installed-app checks so updates retain Keychain and privacy grants. Obtain the identity from the local signing environment; do not record its personal details here. Installing or replacing the app must be within the task's authorization.
- Manual checks are listed in `ACCEPTANCE.md`. Add a line there for new behavior.
- Record the tested version, environment and result without user data. Distinguish source inspection, fixture tests, CI results, real-service checks and human acceptance. An unchecked item is not a pass.
- Review the diff and public content before a pull request. Documentation-only changes need link, consistency and privacy checks; they do not require rebuilding or reinstalling the app.

## CI scope

The shared classifier is `scripts/ci-scope.mjs`; `make check` uses it locally, including uncommitted and untracked files. CI compares the full PR merge-base/head or main before/after diff, including both paths of a rename.

| Change | Automatic native verification |
| --- | --- |
| Documentation, website/OG assets and metadata, issue templates, committed icon bitmap | None; validate the changed content or website as appropriate |
| Core tests | Core suite only |
| Core source | Core suite and app compilation |
| App state/interaction or app tests | App suite without unrelated release fixtures; mixed core/app changes run all tests once |
| `AppIconArt.swift` only | App compilation, no interaction tests |
| CI selector or Makefile | Selector fixtures; Makefile/workflow edits also run release-tool fixtures |
| Release/bundle scripts or `app.config` | Tool fixtures; bundle checks when the packaging path changes; DMG only when its script changes |
| Package manifest/dependency changes | Full tests and bundle check |
| Version tag or manual workflow run | Full tests, universal packaging and DMG; tags require signing, notarization and atomic release publication |

Unknown paths or unavailable/incomplete CI diffs request full checks. Ordinary app code changes do not import signing credentials, build a universal archive or make a DMG. The required `build` status remains present even when native jobs are skipped, and it rejects a failed/cancelled required job. This avoids a pending required check on content-only PRs without relaxing branch protection. Main pushes use the same scope selection instead of always rebuilding.

`swift test` / `make test-all` remain available explicitly; no existing test is removed or failure ignored. A full result and a selected suite result must be reported separately. Do not classify a mixed interaction file as cosmetic just because the intended change is visual.
