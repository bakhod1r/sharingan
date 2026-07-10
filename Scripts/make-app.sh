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

# The SwiftPM product is still `Blink` (module rename would churn the whole
# tree); the shipped bundle and executable are branded `Sharingan`.
PRODUCT_NAME="Blink"
APP_NAME="Sharingan"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

# Safe empty-array expansion for bash 3.2 (macOS default) under `set -u`.
build() { swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} "$@"; }

BINDIR="$(build --show-bin-path)"

label="$CONFIG"; [[ "${1:-}" == "--universal" ]] && label="$label, universal"
echo "▸ Building ($label)…"
build --product "$PRODUCT_NAME"

echo "▸ Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Executable (built as $PRODUCT_NAME, shipped under the brand name)
cp "$BINDIR/$PRODUCT_NAME" "$APP/Contents/MacOS/$APP_NAME"

# Info.plist — stamp CFBundleVersion with the commit count so every build is
# distinguishable ("which build is on the other Mac" was undiagnosable at a
# constant 1).
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if BUILD_NUM="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null)"; then
  plutil -replace CFBundleVersion -string "$BUILD_NUM" "$APP/Contents/Info.plist"
fi

# SwiftPM resource bundles (sounds, animations, icons) live in Contents/Resources,
# where codesign can seal them cleanly. They are resolved at runtime via
# Bundle.main.resourceURL (see Sources/*/ResourceBundle.swift) rather than the
# SwiftPM-generated Bundle.module — whose search path expects the bundle at the
# .app ROOT. Putting anything at the root ("unsealed contents present in the
# bundle root") breaks codesign, so a copy that arrives quarantined on another
# Mac is rejected by Gatekeeper and won't open. Keeping everything under
# Contents/ keeps the signature valid on every Mac.
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

# Ad-hoc codesign so SMAppService / LaunchServices accept the bundle. Nothing
# lives at the bundle root (Contents/ only), so the seal is valid and survives
# Gatekeeper's strict re-verification of a quarantined copy on another Mac.
codesign --force --deep --sign - "$APP" 2>/dev/null && echo "  ✓ ad-hoc signed" || echo "  ! codesign skipped"

# Fail loudly if the seal isn't strict-valid: this is exactly what Gatekeeper
# checks on another Mac, so a failure here means "won't open there".
if codesign --verify --deep --strict "$APP" 2>/dev/null; then
  echo "  ✓ signature strict-valid"
else
  echo "  ✗ signature NOT strict-valid — the app will be rejected on other Macs" >&2
  exit 1
fi

echo "✅ Done → $APP"
echo "   Install:  Scripts/install.sh   (build + install to /Applications)"
