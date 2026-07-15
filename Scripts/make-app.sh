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

# Local builds stay host-arch — fast. Anything DISTRIBUTED must be universal
# (arm64 + x86_64) or it simply won't launch on an Intel Mac; make-dmg.sh
# therefore passes --universal by default. Universal costs ~3× the build time
# and needs a full Xcode toolchain (xcodebuild), not just the CLT.
UNIVERSAL=0
ARCH_FLAGS=()
APPEX_ARCHES=("$(uname -m)")
if [[ "${1:-}" == "--universal" ]]; then
  UNIVERSAL=1
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
  APPEX_ARCHES=(arm64 x86_64)
fi

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

label="$CONFIG"; (( UNIVERSAL )) && label="$label, universal (arm64 + x86_64)"
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

# Jira OAuth app credentials, baked in from the environment (.env.release
# locally, repo secrets in CI). Atlassian's 3LO has no PKCE and demands a
# client_secret, so a shipped app has to carry one; the XOR mask below only
# keeps it out of `strings` and secret scanners — it is NOT a security
# boundary (see JiraAppCredentials.swift). Absent env = no baked credentials,
# and the app says "OAuth not configured in this build" rather than failing at
# the authorize step.
mask_secret() {  # $1 = plaintext → base64(XOR(plaintext, mask))
  MASK_INPUT="$1" python3 - <<'PY'
import base64, os
mask = b"Sharingan-Jira-v1"
raw = os.environ["MASK_INPUT"].encode()
print(base64.b64encode(bytes(b ^ mask[i % len(mask)] for i, b in enumerate(raw))).decode())
PY
}
if [[ -n "${JIRA_CLIENT_ID:-}" && -n "${JIRA_CLIENT_SECRET:-}" ]]; then
  plutil -replace SHIntegrationAppID  -string "$(mask_secret "$JIRA_CLIENT_ID")"     "$APP/Contents/Info.plist"
  plutil -replace SHIntegrationAppKey -string "$(mask_secret "$JIRA_CLIENT_SECRET")" "$APP/Contents/Info.plist"
  echo "  ✓ Jira OAuth credentials baked in"
else
  echo "  ⚠︎ JIRA_CLIENT_ID/JIRA_CLIENT_SECRET unset — Jira OAuth disabled in this build"
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

# Sparkle auto-update framework. SwiftPM links the app against the binary
# xcframework but leaves an rpath pointing into .build — useless the moment the
# bundle moves to another Mac. Embed the framework and point an
# @executable_path rpath at it. The copy comes from the artifacts xcframework
# (its macos slice is arm64+x86_64, so it stays universal) rather than a
# per-config build directory.
echo "▸ Embedding Sparkle.framework…"
SPARKLE_FW="$(find "$ROOT/.build/artifacts" -type d -name "Sparkle.framework" -path "*macos*" 2>/dev/null | head -1)"
if [[ -z "$SPARKLE_FW" ]]; then
  echo "  ✗ Sparkle.framework not found under .build — did swift build run?" >&2
  exit 1
fi
mkdir -p "$APP/Contents/Frameworks"
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" \
  "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true
echo "  ✓ Sparkle.framework embedded ($(lipo -archs "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"))"

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
#
# swiftc emits ONE slice per invocation, so a universal appex is built as one
# binary per arch and lipo'd together — an arm64-only appex inside a universal
# app would leave Intel Macs with a widget that can't load.
WIDGET_SRCS=(
  "$ROOT/Sources/SharinganWidget"/*.swift
  "$ROOT/Sources/SharinganCore/Models/WidgetSnapshot.swift"
  "$ROOT/Sources/SharinganCore/Services/WidgetSnapshotStore.swift"
)
SLICE_DIR="$(mktemp -d)"
SLICES=()
for arch in "${APPEX_ARCHES[@]}"; do
  xcrun swiftc -O -parse-as-library -module-name "$WIDGET" \
    -target "${arch}-apple-macos14.0" \
    -Xlinker -e -Xlinker _NSExtensionMain \
    "${WIDGET_SRCS[@]}" \
    -o "$SLICE_DIR/$WIDGET-$arch"
  SLICES+=("$SLICE_DIR/$WIDGET-$arch")
done
if (( ${#SLICES[@]} > 1 )); then
  lipo -create "${SLICES[@]}" -output "$APPEX/Contents/MacOS/$WIDGET"
else
  cp "${SLICES[0]}" "$APPEX/Contents/MacOS/$WIDGET"
fi
rm -rf "$SLICE_DIR"
echo "  ✓ appex slices: $(lipo -archs "$APPEX/Contents/MacOS/$WIDGET")"
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

# Developer ID apps carry iCloud/push entitlements only via an embedded
# provisioning profile — codesign accepts the entitlements without one, and
# then CloudKit fails at runtime with a bare "not entitled". No profile ⇒
# build an app WITHOUT the iCloud entitlements rather than a broken one.
# The profile must land in the bundle BEFORE the app's codesign call: the
# signature seals Contents/, and adding it afterwards breaks the seal.
if [[ -n "${PROVISION_PROFILE_FILE:-}" && -f "${PROVISION_PROFILE_FILE}" ]]; then
  cp "$PROVISION_PROFILE_FILE" "$APP/Contents/embedded.provisionprofile"
  ENTITLEMENTS="$ROOT/Resources/App.entitlements"
  echo "  ✓ provisioning profile embedded (iCloud enabled)"
else
  ENTITLEMENTS="$ROOT/Resources/App-NoCloud.entitlements"
  echo "  ⚠ no provisioning profile — building without iCloud entitlements"
fi

# Sign inside-out: the appex first, WITH its entitlements (sandbox + app
# group — chronod won't load an unsandboxed widget, and the app group is how
# it reads the snapshot the app writes). Then the outer app with its own
# entitlements and WITHOUT --deep: a --deep re-sign would strip the appex's
# entitlements again.
#
# SIGN_IDENTITY (e.g. "Developer ID Application: … (89LCRZKZ48)") switches to
# real signing with hardened runtime + secure timestamp — both notarization
# requirements. Failures are fatal there: a half-signed release must not ship.
# Without it, ad-hoc signing keeps local dev exactly as before.

# Sparkle ships its own nested code — two XPC services and the Autoupdate /
# Updater.app helpers that outlive the app during an install. Each is a
# separate code object and needs its own signature, innermost first, before the
# framework that contains them and long before the app that contains that.
# $@ is the identity plus whichever flags the branch below signs everything
# else with — the helpers must carry the same hardened-runtime signature as the
# app or notarization rejects the bundle.
sign_sparkle() {
  local fw="$APP/Contents/Frameworks/Sparkle.framework"
  [[ -d "$fw" ]] || return 0
  local helper
  for helper in \
    "$fw/Versions/B/XPCServices/Downloader.xpc" \
    "$fw/Versions/B/XPCServices/Installer.xpc" \
    "$fw/Versions/B/Autoupdate" \
    "$fw/Versions/B/Updater.app"; do
    if [[ -e "$helper" ]]; then
      codesign --force --sign "$@" "$helper"
    fi
  done
  codesign --force --sign "$@" "$fw"
}

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "▸ Signing with: $SIGN_IDENTITY"
  sign_sparkle "$SIGN_IDENTITY" --options runtime --timestamp
  echo "  ✓ Sparkle.framework signed"
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
    --entitlements "$ROOT/Resources/Widget.entitlements" "$APPEX"
  echo "  ✓ appex signed"
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" "$APP"
  echo "  ✓ app signed (Developer ID)"
else
  sign_sparkle - 2>/dev/null \
    && echo "  ✓ Sparkle.framework ad-hoc signed" || echo "  ! Sparkle codesign skipped"
  codesign --force --sign - \
    --entitlements "$ROOT/Resources/Widget.entitlements" \
    "$APPEX" 2>/dev/null && echo "  ✓ appex ad-hoc signed" || echo "  ! appex codesign skipped"
  codesign --force --sign - \
    --entitlements "$ENTITLEMENTS" \
    "$APP" 2>/dev/null && echo "  ✓ ad-hoc signed" || echo "  ! codesign skipped"
fi

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

# A distributed build that is missing a slice launches on nobody's Mac but the
# builder's — fail loudly rather than shipping it.
APP_ARCHES="$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
if (( UNIVERSAL )); then
  for arch in arm64 x86_64; do
    if [[ "$APP_ARCHES" != *"$arch"* ]]; then
      echo "  ✗ universal build is missing the $arch slice (got: $APP_ARCHES)" >&2
      exit 1
    fi
  done
fi
echo "  ✓ app slices: $APP_ARCHES"

echo "✅ Done → $APP"
echo "   Install:  Scripts/install.sh   (build + install to /Applications)"
