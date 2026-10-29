#!/usr/bin/env bash
# Writes build/appcast.xml: the Sparkle feed for the release in app.config, pointing at that
# release's zip and carrying its EdDSA signature. CI attaches it to every release, so
# SUFeedURL (…/releases/latest/download/appcast.xml) always names the newest version.
# Usage: SPARKLE_ED_PRIVATE_KEY=… SIGN_UPDATE=path/to/sign_update scripts/appcast.sh [notes.md]
#   notes.md: the release's Markdown notes; "* " lines become the list shown in the update window.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=../app.config
source ./app.config

: "${SPARKLE_ED_PRIVATE_KEY:?is not set}"
: "${SIGN_UPDATE:?is not set (path to the sign_update tool from Sparkle)}"
NOTES="${1:-}"
ZIP="build/$APP_NAME.zip"
OUT="build/appcast.xml"
[[ -f "$ZIP" ]] || { echo "error: no $ZIP (build and notarize first)" >&2; exit 1; }

REPO_URL="${SPARKLE_FEED_URL%/releases/*}"
ZIP_URL="$REPO_URL/releases/download/v$VERSION/$APP_NAME.zip"
# → sparkle:edSignature="…" length="…"
SIGNATURE="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$ZIP")"
[[ "$SIGNATURE" == *'sparkle:edSignature="'* ]] || { echo "error: sign_update gave no signature" >&2; exit 1; }

escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
# GitHub's generated notes read "* Title by @someone in https://…/pull/N"; keep the titles.
ITEMS=""
if [[ -n "$NOTES" && -f "$NOTES" ]]; then
    ITEMS="$(grep -E '^[*-] ' "$NOTES" | grep -v 'made their first contribution' | sed -E -e 's/^[*-] //' -e 's/ by @[^ ]+ in https:[^ ]+$//' | escape | sed -E 's|.*|      <li>&</li>|' || true)"
fi
RELEASE_URL="$REPO_URL/releases/tag/v$VERSION"
DESCRIPTION="<h3>$APP_NAME $VERSION</h3>"
[[ -n "$ITEMS" ]] && DESCRIPTION+=$'\n'"    <ul>"$'\n'"$ITEMS"$'\n'"    </ul>"
DESCRIPTION+=$'\n'"    <p><a href=\"$RELEASE_URL\">Release notes on GitHub</a></p>"

cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$APP_NAME</title>
    <link>$REPO_URL</link>
    <item>
      <title>$APP_NAME $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_MACOS</sparkle:minimumSystemVersion>
      <description><![CDATA[
    $DESCRIPTION
      ]]></description>
      <enclosure url="$ZIP_URL" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
XML
xmllint --noout "$OUT"
echo "Built $OUT ($APP_NAME $VERSION, build $BUILD_NUMBER)"
