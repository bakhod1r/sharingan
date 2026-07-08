#!/usr/bin/env bash
#
# install.sh — build Blink from source and install it to /Applications so it
# opens cleanly on ANY Mac, including a second machine you git-pulled onto.
#
#   Scripts/install.sh              # build + install + launch
#   Scripts/install.sh --universal  # universal binary (needs Xcode)
#
# Why this exists: the app is ad-hoc signed (no paid Apple Developer ID), and
# on macOS 15/26 Gatekeeper shows "Blink can't be opened" for an ad-hoc app
# that carries a quarantine flag — which is exactly what happens when you copy
# the built .app between Macs (AirDrop/iCloud/USB). Building from source on each
# Mac and stripping quarantine avoids that entirely. This script does both.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Blink"
SRC="$ROOT/dist/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

# 1) Build the bundle (forwards --universal / --debug).
"$ROOT/Scripts/make-app.sh" "${1:-}"

# 2) Replace any previous install.
echo "▸ Installing to $DEST …"
if [[ -d "$DEST" ]]; then
  # Quit a running copy so the replace doesn't hit a busy binary.
  pkill -f "$DEST/Contents/MacOS/$APP_NAME" 2>/dev/null || true
  sleep 1
  rm -rf "$DEST"
fi
cp -R "$SRC" "$DEST"

# 3) Clear quarantine + re-sign the installed copy so Gatekeeper lets it launch
#    from Finder (double-click), not just from Terminal.
xattr -cr "$DEST" 2>/dev/null || true
codesign --force --deep --sign - "$DEST" 2>/dev/null || true

# 4) Launch it.
open "$DEST"

echo "✅ Installed and launched → $DEST"
echo "   The stopwatch icon should now be in your menu bar."
