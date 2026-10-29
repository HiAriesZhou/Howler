# AGENTS.md

Howler is a macOS 14+ menu bar app (Swift 5.10, SwiftPM). `HowlerCore` holds the testable logic; `Howler` is the app. README.md describes the product; this file only holds what an agent needs to work here.

## Commands

- `make test`: unit tests (`swift test`).
- `make app`: universal app in `build/stage.noindex/Howler.app` and `build/Howler.zip`. Set `SIGN_IDENTITY` for a Developer ID build; otherwise it is ad-hoc signed.
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
- Manual checks are listed in `ACCEPTANCE.md`. Add a line there for new behavior.
