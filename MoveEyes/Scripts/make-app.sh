#!/usr/bin/env bash
#
# make-app.sh — MoveEyes'ni build qilib, tarqatiladigan MoveEyes.app yig'adi.
#
#   Scripts/make-app.sh          # release build → ./dist/MoveEyes.app
#   Scripts/make-app.sh --debug  # debug build
#
set -euo pipefail

CONFIG="release"
[[ "${1:-}" == "--debug" ]] && CONFIG="debug"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="MoveEyes"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

BINDIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG" --product "$APP_NAME"

echo "▸ Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINDIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Codesigning (ad-hoc)…"
codesign --force --deep -s - "$APP"

echo "✓ $APP tayyor"
