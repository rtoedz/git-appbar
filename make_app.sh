#!/bin/bash
# Build a release binary and wrap it in a proper GitAppBar.app bundle.
# A real bundle is required for LSUIElement (menu-bar-only), Launch at Login
# and notifications.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="GitAppBar"
APP="${APP_NAME}.app"

echo "▶ Building release (universal: arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64
BUILD_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "▶ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP" 2>/dev/null || \
    echo "  (codesign skipped — ad-hoc signing unavailable)"

echo "✅ Built $APP"
echo "   Launch with:  open $APP"
