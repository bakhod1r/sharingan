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
    echo "  ✓ volume icon"

    # Branded install window: the app renders its own background (ghost iris,
    # arrow, caption), and Finder is scripted to lay the window out around it —
    # icon view, 560×400, app at (140,195), Applications at (420,195). The
    # .DS_Store Finder writes persists into the compressed image. Best-effort:
    # if Finder scripting is unavailable (no Automation permission), the DMG
    # still builds, just unstyled.
    mkdir -p "$MOUNT_POINT/.background"
    if "$APP/Contents/MacOS/$APP_NAME" --render-dmg-background \
         "$MOUNT_POINT/.background/bg.png" 2>/dev/null \
       && [[ -s "$MOUNT_POINT/.background/bg.png" ]]; then
      if osascript >/dev/null <<OSA
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 760, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 100
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:bg.png"
    set position of item "$APP_NAME.app" of container window to {140, 195}
    set position of item "Applications" of container window to {420, 195}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
      then
        echo "  ✓ install window styled"
      else
        echo "  ⚠ Finder styling skipped (no Automation permission?)"
      fi
    fi

    hdiutil detach "$MOUNT_POINT" >/dev/null
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
