# Agent guide

Read this guide when building, testing, running a demo, or preparing a pull request. Product, privacy and release constraints remain in the root AGENTS.md.

## Commands

- `make test`: unit tests (`swift test`).
- `make app`: universal app in `build/stage.noindex/Howler.app` and `build/Howler.zip`. Set `SIGN_IDENTITY` for a Developer ID build; otherwise it is ad-hoc signed.
- `make dmg`: builds the app and wraps it in `build/Howler.dmg`.
- Debug demo: `swift build && HOWLER_DEMO=settings .build/debug/Howler`. The variants are listed at the top of `Sources/Howler/DemoMode.swift`. `HOWLER_DEMO_SNAPSHOT=out.png` saves the Settings window as a PNG without screen-recording permission.

## Checks before a pull request

- `make test`, then a signed `make app`. For user-visible changes, try the installed app.
- Use the same Developer ID identity for installed-app checks so updates retain Keychain and privacy grants. Obtain the identity from the local signing environment; do not record its personal details here. Installing or replacing the app must be within the task's authorization.
- Manual checks are listed in `ACCEPTANCE.md`. Add a line there for new behavior.
- Record the tested version, environment and result without user data. Distinguish source inspection, fixture tests, CI results, real-service checks and human acceptance. An unchecked item is not a pass.
- Review the diff and public content before a pull request. Documentation-only changes need link, consistency and privacy checks; they do not require rebuilding or reinstalling the app.
