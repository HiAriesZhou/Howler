#!/usr/bin/env bash
# Builds a release binary with SwiftPM and assembles build/<APP_NAME>.app + build/<APP_NAME>.zip.
# App identity comes from app.config (the one place to rename the app).
# Usage: scripts/bundle.sh            # universal (arm64 + x86_64)
#        ARCHS=arm64 scripts/bundle.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=../app.config
source ./app.config

ARCHS="${ARCHS:-arm64 x86_64}"
ARCH_FLAGS=()
for arch in $ARCHS; do ARCH_FLAGS+=(--arch "$arch"); done

echo "==> swift build -c release (${ARCHS})"
swift build -c release --product "$EXECUTABLE_PRODUCT" "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"
BINARY="$BIN_DIR/$EXECUTABLE_PRODUCT"
[[ -x "$BINARY" ]] || { echo "error: binary not found at $BINARY" >&2; exit 1; }

OUT="$ROOT/build"
APP="$OUT/$APP_NAME.app"
ZIP="$OUT/$APP_NAME.zip"
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist"

echo "==> ad-hoc codesign"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"
lipo -info "$APP/Contents/MacOS/$APP_NAME"
# shellcheck disable=SC2086 # ARCHS is a space-separated list
lipo "$APP/Contents/MacOS/$APP_NAME" -verify_arch $ARCHS \
    || { echo "error: binary does not contain every architecture in: $ARCHS" >&2; exit 1; }

echo "==> zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "Built $APP"
echo "Built $ZIP"
