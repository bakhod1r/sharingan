#!/usr/bin/env bash
#
# make-dmg.sh — MoveEyes.app'ni yig'ib, disk-image (drag-install) qiladi.
#
#   Scripts/make-dmg.sh   # → dist/MoveEyes.dmg
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="MoveEyes"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"

"$ROOT/Scripts/make-app.sh" "${1:-}"

STAGE="$(mktemp -d)/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "▸ Creating $DMG …"
rm -f "$DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

rm -rf "$(dirname "$STAGE")"
echo "✓ $DMG tayyor"
