#!/usr/bin/env bash
#
# make-app.sh — build Sharingan and assemble a distributable Sharingan.app bundle.
#
# The bundle is what makes LSUIElement (no Dock icon) and launch-at-login
# (SMAppService) work. Run from anywhere:
#
#   Scripts/make-app.sh          # release build → ./dist/Sharingan.app
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

# SwiftPM product and shipped bundle are both branded `Sharingan`.
PRODUCT_NAME="Sharingan"
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
# Only this package's bundles ("Sharingan_<target>.bundle"): the bin dir can
# still hold stale "Blink_*.bundle" artifacts from before the rename, and the
# app resolves its bundles by the new name only (ResourceBundle.swift) — the
# old ones would just ship as dead weight.
for b in "$BINDIR/${PRODUCT_NAME}_"*.bundle; do
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

# WidgetKit extension (.appex). Deliberately OUTSIDE Package.swift: the appex
# is hand-assembled like the rest of the bundle, so its sources are compiled
# straight to a binary here — the widget UI plus the two snapshot files it
# shares with SharinganCore (one module, no imports between them).
echo "▸ Building widget extension…"
WIDGET="SharinganWidget"
APPEX="$APP/Contents/PlugIns/$WIDGET.appex"
mkdir -p "$APPEX/Contents/MacOS"
# Entry point MUST be _NSExtensionMain (what Xcode links appex targets
# with): the extension runtime has to own the process from the first
# instruction — check in with launchd, publish the XPC listener — before any
# widget code runs. Entering through @main's `main` instead leaves chronod's
# connection dangling: the process logs as far as "Extension Type:" and then
# exit(0)s, chronod records "query failed", and the widget never reaches the
# gallery. @main stays for swiftc to emit the WidgetBundle metadata that
# WidgetKit's host locates at runtime.
xcrun swiftc -O -parse-as-library -module-name "$WIDGET" \
  -target "$(uname -m)-apple-macos14.0" \
  -Xlinker -e -Xlinker _NSExtensionMain \
  "$ROOT/Sources/SharinganWidget"/*.swift \
  "$ROOT/Sources/SharinganCore/Models/WidgetSnapshot.swift" \
  "$ROOT/Sources/SharinganCore/Services/WidgetSnapshotStore.swift" \
  -o "$APPEX/Contents/MacOS/$WIDGET"
cp "$ROOT/Resources/Widget-Info.plist" "$APPEX/Contents/Info.plist"
# Version stamps stay in lockstep with the app's.
if [[ -n "${BUILD_NUM:-}" ]]; then
  plutil -replace CFBundleVersion -string "$BUILD_NUM" "$APPEX/Contents/Info.plist"
fi
APP_VER="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
plutil -replace CFBundleShortVersionString -string "$APP_VER" "$APPEX/Contents/Info.plist"
echo "  ✓ $WIDGET.appex"

# Strip any quarantine flag (e.g. if a resource came in via download/AirDrop)
# so macOS 15/26 Gatekeeper doesn't block the ad-hoc bundle with a
# "Sharingan can't be opened" dialog.
xattr -cr "$APP" 2>/dev/null || true

# Sign inside-out: the appex first, WITH its entitlements (sandbox + app
# group — chronod won't load an unsandboxed widget, and the app group is how
# it reads the snapshot the app writes). Then the outer app with its own
# entitlements and WITHOUT --deep: a --deep re-sign would strip the appex's
# entitlements again.
codesign --force --sign - \
  --entitlements "$ROOT/Resources/Widget.entitlements" \
  "$APPEX" 2>/dev/null && echo "  ✓ appex ad-hoc signed" || echo "  ! appex codesign skipped"
codesign --force --sign - \
  --entitlements "$ROOT/Resources/App.entitlements" \
  "$APP" 2>/dev/null && echo "  ✓ ad-hoc signed" || echo "  ! codesign skipped"

# Fail loudly if the seal isn't strict-valid: this is exactly what Gatekeeper
# checks on another Mac, so a failure here means "won't open there".
if codesign --verify --deep --strict "$APP" 2>/dev/null; then
  echo "  ✓ signature strict-valid"
else
  echo "  ✗ signature NOT strict-valid — the app will be rejected on other Macs" >&2
  exit 1
fi

# Finder registers the bundle the moment `mkdir` creates it — half-built and
# icon-less (a generic grid icon if the dist window is open) — and keys its
# icon cache off the bundle root's mtime, which nothing above ever bumps
# (only Contents/* changes after that first mkdir). Bump it and re-register
# so the finished bundle's real icon wins.
touch "$APP"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true

echo "✅ Done → $APP"
echo "   Install:  Scripts/install.sh   (build + install to /Applications)"
