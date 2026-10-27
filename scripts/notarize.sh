#!/usr/bin/env bash
# Notarizes a Developer ID–signed build with Apple's notary service and staples the ticket,
# so Gatekeeper opens the download without warnings, even offline.
#
# Usage: scripts/notarize.sh app   # after bundle.sh: notarize the app, staple it, rebuild the zip
#        scripts/notarize.sh dmg   # after dmg.sh (from the stapled app): notarize and staple the DMG
#
# Credentials (an App Store Connect API key), from the environment:
#   NOTARY_KEY_PATH   path to the AuthKey_XXXXXXXXXX.p8 file
#   NOTARY_KEY_ID     the key's ID
#   NOTARY_ISSUER_ID  the issuer ID shown above the keys in App Store Connect
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=../app.config
source ./app.config

TARGET="${1:-}"
OUT="$ROOT/build"
APP="$OUT/stage.noindex/$APP_NAME.app"
ZIP="$OUT/$APP_NAME.zip"
DMG="$OUT/$APP_NAME.dmg"

for var in NOTARY_KEY_PATH NOTARY_KEY_ID NOTARY_ISSUER_ID; do
    [[ -n "${!var:-}" ]] || { echo "error: $var is not set" >&2; exit 1; }
done
[[ -f "$NOTARY_KEY_PATH" ]] || { echo "error: no key file at $NOTARY_KEY_PATH" >&2; exit 1; }

# Submits a file, waits for the verdict, and prints Apple's log if it is not accepted.
submit() {
    local file="$1" result="$OUT/notary-result.json"
    echo "==> notarytool submit $(basename "$file")"
    xcrun notarytool submit "$file" \
        --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
        --wait --timeout 30m --output-format json > "$result"
    local status id
    status="$(plutil -extract status raw -o - "$result")"
    id="$(plutil -extract id raw -o - "$result")"
    echo "Notarization $id: $status"
    if [[ "$status" != "Accepted" ]]; then
        xcrun notarytool log "$id" \
            --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" >&2 || true
        exit 1
    fi
}

case "$TARGET" in
app)
    [[ -d "$APP" ]] || { echo "error: no app at $APP (run scripts/bundle.sh first)" >&2; exit 1; }
    SUBMISSION="$OUT/$APP_NAME-notarize.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMISSION"
    submit "$SUBMISSION"
    rm -f "$SUBMISSION"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
    echo "==> zip (stapled app)"
    rm -f "$ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    ;;
dmg)
    [[ -f "$DMG" ]] || { echo "error: no disk image at $DMG (run scripts/dmg.sh first)" >&2; exit 1; }
    submit "$DMG"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
    ;;
*)
    echo "usage: scripts/notarize.sh app|dmg" >&2
    exit 1
    ;;
esac
echo "Notarized and stapled: $TARGET"
