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

# 3) Build the image. Goes through a read-write image first so the mounted
# volume can be given the Sharingan icon (.VolumeIcon.icns + the Finder
# custom-icon bit on the root) — that icon lives INSIDE the image, so it
# survives GitHub release downloads, unlike xattrs on the .dmg file.
echo "▸ Creating $DMG …"
rm -f "$DMG"
ICNS="$APP/Contents/Resources/AppIcon.icns"
RW_DIR="$(mktemp -d)"
RW_DMG="$RW_DIR/rw.dmg"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDRW \
  "$RW_DMG" >/dev/null

if [[ -f "$ICNS" ]]; then
  MOUNT_POINT="$(hdiutil attach "$RW_DMG" -nobrowse | awk 'END {print $3}')"
  if [[ -d "$MOUNT_POINT" ]]; then
    cp "$ICNS" "$MOUNT_POINT/.VolumeIcon.icns"
    SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
    hdiutil detach "$MOUNT_POINT" >/dev/null
    echo "  ✓ volume icon"
  fi
fi

hdiutil convert "$RW_DMG" -format UDZO -o "$DMG" >/dev/null
rm -rf "$RW_DIR" "$(dirname "$STAGE")"

# 4) The .dmg file's own Finder icon. Resource forks don't survive an
# internet download (the volume icon above covers that case) — this is for
# the copy sitting on a local disk.
if [[ -f "$ROOT/Resources/AppIcon.appiconset/icon_1024.png" ]] \
   && command -v Rez >/dev/null && command -v SetFile >/dev/null; then
  ICON_TMP="$(mktemp -d)"
  cp "$ROOT/Resources/AppIcon.appiconset/icon_1024.png" "$ICON_TMP/icon.png"
  sips -i "$ICON_TMP/icon.png" >/dev/null          # embed the icon resource
  DeRez -only icns "$ICON_TMP/icon.png" > "$ICON_TMP/icon.rsrc"
  Rez -append "$ICON_TMP/icon.rsrc" -o "$DMG"
  SetFile -a C "$DMG"
  rm -rf "$ICON_TMP"
  echo "  ✓ dmg file icon"
fi

SIZE="$(du -h "$DMG" | cut -f1)"
echo "✅ Done → $DMG ($SIZE)"
echo "   Open it, then drag $APP_NAME.app onto Applications."
