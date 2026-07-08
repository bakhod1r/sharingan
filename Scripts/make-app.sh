#!/usr/bin/env bash
#
# make-app.sh — build Blink and assemble a distributable Blink.app bundle.
#
# The bundle is what makes LSUIElement (no Dock icon) and launch-at-login
# (SMAppService) work. Run from anywhere:
#
#   Scripts/make-app.sh          # release build → ./dist/Blink.app
#   Scripts/make-app.sh --debug  # debug build instead
#
set -euo pipefail

CONFIG="release"
[[ "${1:-}" == "--debug" ]] && CONFIG="debug"
[[ "${1:-}" == "--universal" ]] && CONFIG="release"

# Release builds stay host-arch (no Xcode/xcbuild required). If you have
# Xcode installed and want a universal binary, pass --universal.
ARCH_FLAGS=()
[[ "${1:-}" == "--universal" ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Blink"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

# Safe empty-array expansion for bash 3.2 (macOS default) under `set -u`.
build() { swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} "$@"; }

BINDIR="$(build --show-bin-path)"

label="$CONFIG"; [[ "${1:-}" == "--universal" ]] && label="$label, universal"
echo "▸ Building ($label)…"
build --product "$APP_NAME"

echo "▸ Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Executable
cp "$BINDIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# Info.plist
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# SwiftPM resource bundles (Bundle.module lookups: sounds, animations, icons)
for b in "$BINDIR"/*.bundle; do
  [[ -e "$b" ]] && cp -R "$b" "$APP/Contents/Resources/"
done

# App icon: build AppIcon.icns from the .appiconset PNGs
ICONSET_SRC="$ROOT/Resources/AppIcon.appiconset"
if [[ -f "$ICONSET_SRC/icon_1024.png" ]]; then
  TMP_ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$TMP_ICONSET"
  master="$ICONSET_SRC/icon_1024.png"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size"       "$master" --out "$TMP_ICONSET/icon_${size}x${size}.png"    >/dev/null
    sips -z $((size*2)) $((size*2)) "$master" --out "$TMP_ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  cp "$master" "$TMP_ICONSET/icon_512x512@2x.png"
  iconutil -c icns "$TMP_ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$(dirname "$TMP_ICONSET")"
  echo "  ✓ AppIcon.icns"
fi

# Strip any quarantine flag (e.g. if a resource came in via download/AirDrop)
# so macOS 15/26 Gatekeeper doesn't block the ad-hoc bundle with a
# "Blink can't be opened" dialog.
xattr -cr "$APP" 2>/dev/null || true

# Ad-hoc codesign so SMAppService / LaunchServices accept the bundle locally.
codesign --force --deep --sign - "$APP" 2>/dev/null && echo "  ✓ ad-hoc signed" || echo "  ! codesign skipped"

echo "✅ Done → $APP"
echo "   Install:  Scripts/install.sh   (build + install to /Applications)"
