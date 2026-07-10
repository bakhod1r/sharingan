#!/usr/bin/env bash
#
# install.sh — make Blink open on THIS Mac, whatever state it arrived in.
#
#   Scripts/install.sh            # use the git-tracked prebuilt app (fast)
#   Scripts/install.sh --build    # rebuild from source first
#
# Both of your Macs are Apple Silicon, so the prebuilt arm64 bundle committed
# in dist/ runs as-is — no rebuild needed. The only thing that stops an ad-hoc
# app from launching on a second Mac (macOS 15/26) is the quarantine flag +
# Gatekeeper's Finder gate. This script removes the flag, re-seals the bundle
# with a local ad-hoc signature, installs to /Applications, and launches it via
# `open` (which bypasses the Finder double-click block for un-quarantined apps).
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Sharingan"
SRC="$ROOT/dist/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

# 1) Rebuild only if asked, or if the prebuilt bundle is missing.
if [[ "${1:-}" == "--build" || ! -d "$SRC" ]]; then
  echo "▸ Building from source…"
  "$ROOT/Scripts/make-app.sh"
else
  echo "▸ Using prebuilt dist/$APP_NAME.app (pass --build to recompile)"
fi

# 2) Replace any previous install (quit a running copy first).
echo "▸ Installing to $DEST …"
pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
# Also retire a pre-rename install, which lived at /Applications/Blink.app.
pkill -f "Blink.app/Contents/MacOS/Blink" 2>/dev/null || true
sleep 1
rm -rf "$DEST" "/Applications/Blink.app"
cp -R "$SRC" "$DEST"

# 3) The universal unlock: drop the quarantine flag (from a git-zip / AirDrop /
#    iCloud copy). The bundle keeps its original ad-hoc signature — no re-sign,
#    which would fail anyway because of the root-level Bundle.module symlinks.
xattr -cr "$DEST" 2>/dev/null || true

# 4) Launch via `open` — works even when a Finder double-click is blocked.
open "$DEST"
sleep 2

# 5) Confirm, or hand off to the one manual step macOS may still require.
if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null; then
  echo "✅ $APP_NAME is running — look for the Sharingan icon in your menu bar."
else
  cat <<EOF
⚠️  macOS is still holding the first launch. One-time unlock:
    1) Open  System Settings → Privacy & Security
    2) Scroll down — you'll see: '"$APP_NAME" was blocked'
    3) Click  Open Anyway,  then re-run:  Scripts/install.sh
  (This only happens once per Mac for an ad-hoc-signed app.)
EOF
fi
