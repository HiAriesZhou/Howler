.PHONY: build test app zip dmg icon run clean

build:
	swift build

test:
	swift test

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
