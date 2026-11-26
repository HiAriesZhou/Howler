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

CONFIGURATION=release
OUT="$ROOT/build"
COMMIT=""
case "${1:-}" in
    "")
        ARCHS="${ARCHS:-arm64 x86_64}"
        ;;
    --dev)
        CONFIGURATION=debug
        OUT="$OUT/dev"
        ARCHS="$(uname -m)"
        APP_NAME="$APP_NAME Dev"
        BUNDLE_ID="$BUNDLE_ID.dev"
        COMMIT="$(git rev-parse --short HEAD)"
        if [[ -n "$(git status --porcelain)" ]]; then COMMIT="$COMMIT-dirty"; fi
        ;;
    *)
        echo "Usage: $0 [--dev]" >&2
        exit 2
        ;;
esac
ARCH_FLAGS=()
for arch in $ARCHS; do ARCH_FLAGS+=(--arch "$arch"); done

echo "==> swift build -c ${CONFIGURATION} (${ARCHS})"
swift build -c "$CONFIGURATION" --product "$EXECUTABLE_PRODUCT" "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c "$CONFIGURATION" "${ARCH_FLAGS[@]}" --show-bin-path)"
BINARY="$BIN_DIR/$EXECUTABLE_PRODUCT"
[[ -x "$BINARY" ]] || { echo "error: binary not found at $BINARY" >&2; exit 1; }

APP="$OUT/stage.noindex/$APP_NAME.app"
ZIP="$OUT/$APP_NAME.zip"
if [[ -n "$COMMIT" ]]; then
    DEV_PIDS="$(osascript -l JavaScript - "$BUNDLE_ID" <<'JXA'
ObjC.import('AppKit');
function run(args) {
    const applications = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(args[0]);
    const pids = [];
    for (let index = 0; index < applications.count; index++) {
        const application = applications.objectAtIndex(index);
        pids.push(application.processIdentifier);
        application.terminate;
    }
    return pids.join(' ');
}
JXA
)"
    for pid in $DEV_PIDS; do
        for ((attempt = 0; attempt < 50; attempt++)); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then
            echo "Quit Howler Dev before rebuilding it." >&2
            exit 1
        fi
    done
fi
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

bash "$ROOT/scripts/info-plist.sh" "$APP_NAME" "$BUNDLE_ID" > "$APP/Contents/Info.plist"
if [[ -n "$COMMIT" ]]; then
    for key in SUFeedURL SUPublicEDKey SUScheduledCheckInterval SUAllowsAutomaticUpdates CFBundleURLTypes; do
        plutil -remove "$key" "$APP/Contents/Info.plist"
    done
    plutil -insert HowlerDevelopmentCommit -string "$COMMIT" "$APP/Contents/Info.plist"
fi
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

echo "Built $APP"
if [[ -n "$COMMIT" ]]; then
    open "$APP"
else
    echo "==> zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    echo "Built $ZIP"
fi
