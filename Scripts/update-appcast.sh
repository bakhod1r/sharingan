#!/usr/bin/env bash
#
# update-appcast.sh <dmg> <version> <build> <download-url> <notes-file>
#
# Signs the DMG with the Sparkle EdDSA key (SPARKLE_ED_PRIVATE_KEY env,
# base64 of the exported key file — or falls back to the local keychain)
# and inserts a new <item> at the top of site/appcast.xml. Idempotent per
# version: an existing item with the same sparkle:version is replaced.
set -euo pipefail
DMG="$1"; VERSION="$2"; BUILD="$3"; URL="$4"; NOTES_FILE="$5"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST="$ROOT/site/appcast.xml"

# -path exclusion: Sparkle also ships a legacy DSA sign_update under
# old_dsa_scripts/, which would silently produce the wrong signature.
SIGN_BIN="$(find "$ROOT/.build" -type f -name sign_update -path "*artifacts*" ! -path "*old_dsa*" | head -1)"
[[ -n "$SIGN_BIN" ]] || { echo "sign_update not found (run swift build first)"; exit 1; }

if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  KEY_FILE="$(mktemp)"; printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$KEY_FILE"
  SIG_LINE="$("$SIGN_BIN" --ed-key-file "$KEY_FILE" "$DMG")"
  rm -f "$KEY_FILE"
else
  SIG_LINE="$("$SIGN_BIN" "$DMG")"   # local keychain
fi
# sign_update prints: sparkle:edSignature="…" length="…"
ED_SIG="$(sed -nE 's/.*edSignature="([^"]+)".*/\1/p' <<<"$SIG_LINE")"
LENGTH="$(sed -nE 's/.*length="([^"]+)".*/\1/p' <<<"$SIG_LINE")"
PUB_DATE="$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")"

ITEM_FILE="$(mktemp)"
{
  echo "    <item>"
  echo "      <title>Sharingan $VERSION</title>"
  echo "      <pubDate>$PUB_DATE</pubDate>"
  echo "      <sparkle:version>$BUILD</sparkle:version>"
  echo "      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>"
  echo "      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>"
  echo "      <description><![CDATA["
  cat "$NOTES_FILE"
  echo "      ]]></description>"
  echo "      <enclosure url=\"$URL\" length=\"$LENGTH\" type=\"application/octet-stream\" sparkle:edSignature=\"$ED_SIG\"/>"
  echo "    </item>"
} > "$ITEM_FILE"

python3 - "$APPCAST" "$ITEM_FILE" "$BUILD" <<'PY'
import re, sys
appcast, item_file, build = sys.argv[1], sys.argv[2], sys.argv[3]
xml = open(appcast).read()
item = open(item_file).read()
# Replace an existing item with the same sparkle:version (idempotent re-runs).
xml = re.sub(r'    <item>(?:(?!</item>).)*?<sparkle:version>%s</sparkle:version>.*?</item>\n' % re.escape(build),
             '', xml, flags=re.S)
xml = xml.replace('<language>en</language>', '<language>en</language>\n' + item.rstrip(), 1)
open(appcast, 'w').write(xml)
PY
echo "✓ appcast updated: $VERSION (build $BUILD, $LENGTH bytes)"
