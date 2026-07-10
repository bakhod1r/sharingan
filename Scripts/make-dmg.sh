#!/usr/bin/env bash
#
# make-dmg.sh — build Sharingan.app and wrap it in a distributable disk image.
#
#   Scripts/make-dmg.sh          # → dist/Sharingan.dmg (release)
#   Scripts/make-dmg.sh --debug
#
# The .dmg contains Sharingan.app plus an /Applications symlink for drag-install.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Sharingan"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"
VOL_NAME="Sharingan"

# 1) Build the app bundle (forwards --debug).
"$ROOT/Scripts/make-app.sh" "${1:-}"

# 2) Stage a clean folder with the app + an Applications shortcut.
STAGE="$(mktemp -d)/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 3) Build the compressed image.
echo "▸ Creating $DMG …"
rm -f "$DMG"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

rm -rf "$(dirname "$STAGE")"

SIZE="$(du -h "$DMG" | cut -f1)"
echo "✅ Done → $DMG ($SIZE)"
echo "   Open it, then drag $APP_NAME.app onto Applications."
