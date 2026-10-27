#!/usr/bin/env bash
# Wraps the app into build/<APP_NAME>.dmg: the app beside a link to /Applications, so
# installing is a single drag. Run scripts/bundle.sh first (`make dmg` does both).
# Usage: scripts/dmg.sh                    # packs build/stage.noindex/<APP_NAME>.app
#        scripts/dmg.sh path/to/App.app    # packs a given bundle, e.g. one CI built
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=../app.config
source ./app.config

APP="${1:-$ROOT/build/stage.noindex/$APP_NAME.app}"
[[ -d "$APP" ]] || { echo "error: no app bundle at $APP (run scripts/bundle.sh first)" >&2; exit 1; }

OUT="$ROOT/build"
DMG="$OUT/$APP_NAME.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$OUT"

echo "==> stage"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
codesign --verify --strict "$STAGE/$APP_NAME.app"

echo "==> hdiutil create"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ \
    -format UDZO -imagekey zlib-level=9 -ov "$DMG"
hdiutil verify "$DMG"
echo "Built $DMG"
