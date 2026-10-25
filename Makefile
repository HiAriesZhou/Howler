.PHONY: build test app zip run clean

build:
	swift build

test:
	swift test

# Assembles build/<APP_NAME>.app and build/<APP_NAME>.zip (universal binary, ad-hoc signed).
app zip:
	./scripts/bundle.sh

run: app
	. ./app.config && open "build/$$APP_NAME.app"

clean:
	rm -rf .build build
