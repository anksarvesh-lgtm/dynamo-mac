#!/usr/bin/env bash
set -e

DIR="$(pwd)"
APP_NAME="LiquidDynamo"
VERSION="1.9.8"
APP_PATH="$DIR/build/LiquidDynamo.app"
OUTPUT_DIR="$HOME/Desktop"
DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.dmg"

echo "==> 1. Codesigning $APP_PATH..."
codesign --force --deep --sign - --entitlements "$DIR/liquiddinamo/LiquidDynamo.entitlements" "$APP_PATH"

echo "==> 2. Terminating old LiquidDynamo instances..."
killall LiquidDynamo 2>/dev/null || true
sleep 1

echo "==> 3. Installing to /Applications/$APP_NAME.app..."
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_PATH" "/Applications/$APP_NAME.app"
xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null || true

echo "==> 4. Packaging professional DMG: $DMG_PATH..."
STAGE="$DIR/build/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

if [ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]; then
  cp "$APP_PATH/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
  SetFile -c icnC "$STAGE/.VolumeIcon.icns" 2>/dev/null || true
  SetFile -a C "$STAGE" 2>/dev/null || true
fi

TEMP_DMG="$DIR/build/temp.dmg"
rm -f "$TEMP_DMG" "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$TEMP_DMG" >/dev/null

MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG" 2>/dev/null || true)
MOUNT_DIR=$(echo "$MOUNT_OUTPUT" | grep "/Volumes/" | awk -F'\t' '{print $NF}')

if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
  if [ -f "$MOUNT_DIR/.VolumeIcon.icns" ]; then
    SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
  fi

  osascript <<APPLESCRIPT >/dev/null 2>&1 || true
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 200, 1060, 600}
        set viewOptions to the icon view options of container window
        set icon size of viewOptions to 128
        try
            set position of item "$APP_NAME.app" of container window to {160, 200}
        end try
        try
            set position of item "Applications" of container window to {500, 200}
        end try
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT

  sync
  hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
fi

hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -f "$TEMP_DMG"
rm -rf "$STAGE"

echo "==> 5. Launching updated /Applications/LiquidDynamo.app..."
open "/Applications/LiquidDynamo.app"

echo "==> Done! App installed and DMG ready at $DMG_PATH."
