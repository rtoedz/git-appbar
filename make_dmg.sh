#!/bin/bash
# Build a distributable DMG installer for Git AppBar.
# Requires the .app bundle to exist first:  ./make_app.sh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="GitAppBar"
DISPLAY_NAME="Git AppBar"
APP="${APP_NAME}.app"
VERSION=$(defaults read "$(pwd)/${APP}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0")
OUT_DIR=".build-dmg"
TMP_DMG="${OUT_DIR}/${APP_NAME}-tmp.dmg"
FINAL_DMG="${OUT_DIR}/${APP_NAME}-${VERSION}.dmg"
VOLUME="${DISPLAY_NAME} ${VERSION}"

mkdir -p "$OUT_DIR"

if [ ! -d "$APP" ]; then
    echo "❌ ${APP} not found — run ./make_app.sh first"
    exit 1
fi

if [ ! -f Resources/dmg-background.png ]; then
    echo "▶ Generating DMG background…"
    swift scripts/generate_dmg_background.swift > /dev/null
fi

echo "▶ Staging DMG contents…"
STAGING=$(mktemp -d)
MOUNT="/Volumes/${VOLUME}"
trap "hdiutil detach \"$MOUNT\" 2>/dev/null; rm -rf \"$STAGING\" \"$TMP_DMG\" 2>/dev/null; true" EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
mkdir -p "$STAGING/.background"
cp Resources/dmg-background.png "$STAGING/.background/dmg-background.png"

echo "▶ Creating writable DMG…"
hdiutil create \
    -volname "$VOLUME" \
    -srcfolder "$STAGING" \
    -ov -format UDRW \
    "$TMP_DMG" > /dev/null

echo "▶ Mounting to set Finder layout…"
# Detach any stale mount of the same volume from a previous run.
hdiutil detach "$MOUNT" 2>/dev/null || true
# Mount under /Volumes (not a custom mountpoint) so Finder manages the window
# metadata and actually persists the .DS_Store layout.
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG" | egrep '^/dev/' | head -1 | awk '{print $1}')

# Finder resolves a hidden ".background:" HFS path unreliably (error -10006),
# so the background is referenced by its mounted POSIX path as an alias instead.
if ! osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${VOLUME}"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 800, 540}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 12
        set background picture of viewOptions to (POSIX file "${MOUNT}/.background/dmg-background.png" as alias)
        set position of item "${APP_NAME}.app" of container window to {160, 200}
        set position of item "Applications" of container window to {440, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
then
    echo "⚠️  Finder layout step failed — DMG may open without the custom background."
fi

# Set volume icon from the app's icns (best-effort)
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${MOUNT}/.VolumeIcon.icns"
    SetFile -a C "$MOUNT" 2>/dev/null || true
fi

# Ensure the Finder layout (.DS_Store) is flushed to the image before detaching.
sync
sleep 2
[ -f "${MOUNT}/.DS_Store" ] || echo "⚠️  .DS_Store not written — layout may not persist."

hdiutil detach "$DEVICE" > /dev/null

echo "▶ Compressing to final DMG…"
rm -f "$FINAL_DMG"
hdiutil convert "$TMP_DMG" -format UDZO -o "$FINAL_DMG" > /dev/null
rm -f "$TMP_DMG"

# Give the .dmg file itself the app icon in Finder (separate from the volume icon).
if [ -f Resources/AppIcon.icns ]; then
    swift scripts/set_file_icon.swift Resources/AppIcon.icns "$FINAL_DMG" > /dev/null 2>&1 || true
fi

echo "✅ ${FINAL_DMG} ready"
echo "   Install: open ${FINAL_DMG}, then drag ${DISPLAY_NAME} → Applications"
shasum -a 256 "$FINAL_DMG"
