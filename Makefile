.PHONY: build check test test-core test-app test-tooling test-all test-ci app zip dmg icon run clean
TOOLING_TESTS = HowlerAppTests\.(HomebrewTests|ReleaseSigningTests|ReleaseNotesTests|CaptureLinkBundleTests)

build:
	swift build

test: test-core

test-core:
	./scripts/test-core.sh

test-app:
	swift test --filter HowlerAppTests --skip '$(TOOLING_TESTS)'

test-tooling:
	swift test --filter '$(TOOLING_TESTS)'

test-all:
	swift test

test-ci:
	node --test scripts/ci-scope.test.mjs

# Choose checks from the diff, including local edits. Override BASE for another review base.
check:
	node scripts/ci-scope.mjs --check --base $(or $(BASE),origin/main)

# Assembles build/stage.noindex/<APP_NAME>.app and build/<APP_NAME>.zip (universal binary, ad-hoc signed).
app zip:
	./scripts/bundle.sh

# Wraps the app into build/<APP_NAME>.dmg (with an Applications link).
dmg: app
	./scripts/dmg.sh

# Re-renders Resources/AppIcon.icns and docs/images/icon.png from Sources/Howler/AppIconArt.swift.
icon:
	./scripts/icon.sh

run: app
	. ./app.config && open "build/stage.noindex/$$APP_NAME.app"

clean:
	rm -rf .build build
