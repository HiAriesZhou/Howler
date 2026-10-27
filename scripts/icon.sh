#!/usr/bin/env bash
# Renders the app icon from source (Sources/Howler/AppIconArt.swift) into
# Resources/AppIcon.icns, and the README's icon into docs/images/icon.png.
# Run after changing the icon art; both outputs are committed, so builds and CI never need it.
# Usage: scripts/icon.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> swift build (debug: the renderer is a debug-only demo variant)"
swift build --product Howler
BIN="$(swift build --show-bin-path)/Howler"

echo "==> render"
HOWLER_DEMO=appicon HOWLER_DEMO_OUT="$WORK" "$BIN"
[[ -d "$WORK/AppIcon.iconset" ]] || { echo "error: renderer wrote no iconset" >&2; exit 1; }

echo "==> iconutil"
mkdir -p Resources docs/images
iconutil -c icns "$WORK/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$WORK/icon.png" docs/images/icon.png
echo "Wrote Resources/AppIcon.icns and docs/images/icon.png"
