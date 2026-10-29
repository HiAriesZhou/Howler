#!/usr/bin/env bash
# Builds a release binary with SwiftPM and assembles build/stage.noindex/<APP_NAME>.app + build/<APP_NAME>.zip.
# The app is staged in a .noindex folder so Spotlight doesn't list a second copy beside /Applications.
# App identity comes from app.config (the one place to rename the app).
# Usage: scripts/bundle.sh            # universal (arm64 + x86_64), ad-hoc signed
#        ARCHS=arm64 scripts/bundle.sh
#        SIGN_IDENTITY="Developer ID Application: …" scripts/bundle.sh   # signed with hardened runtime,
#                                     # ready for scripts/notarize.sh (any identity name or SHA-1 works)
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
APP="$OUT/stage.noindex/$APP_NAME.app"
ZIP="$OUT/$APP_NAME.zip"
rm -rf "$APP" "$ZIP" "$OUT/$APP_NAME.app" # the last: where earlier versions put the app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
# Sparkle, which installs updates. Its XPC services are only for sandboxed apps; Howler
# isn't one, so they are left out (fewer pieces to sign and notarize).
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$BIN_DIR/Sparkle.framework" "$SPARKLE"
rm -rf "$SPARKLE/Versions/B/XPCServices" "$SPARKLE/XPCServices"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$APP_NAME"
# The icon is rendered from source by scripts/icon.sh and committed.
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
    <key>SUFeedURL</key>
    <string>${SPARKLE_FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUBLIC_KEY}</string>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
    <key>SUAllowsAutomaticUpdates</key>
    <false/>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    # A stable identity keeps Keychain and privacy grants across updates; notarization
    # requires the hardened runtime and a secure timestamp.
    echo "==> codesign (${SIGN_IDENTITY}, hardened runtime)"
    sign() { codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$1"; }
else
    echo "==> ad-hoc codesign"
    sign() { codesign --force --sign - --timestamp=none "$1"; }
fi
# Inside out: Sparkle's helpers, the framework, then the app.
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
sign "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -info "$APP/Contents/MacOS/$APP_NAME"
# shellcheck disable=SC2086 # ARCHS is a space-separated list
lipo "$APP/Contents/MacOS/$APP_NAME" -verify_arch $ARCHS \
    || { echo "error: binary does not contain every architecture in: $ARCHS" >&2; exit 1; }

echo "==> zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "Built $APP"
echo "Built $ZIP"
