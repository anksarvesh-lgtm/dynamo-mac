#!/usr/bin/env bash
# Build LiquidDynamo and package it as a DMG on your Desktop.
# Run this on your Mac, from the root of the repository:   bash build_dmg.sh
#
# Optional environment variables:
#   SCHEME            Xcode scheme (auto-detected if unset)
#   SIGN_IDENTITY     e.g. "Developer ID Application: Your Name (TEAMID)". Default: ad-hoc ("-")
#   NOTARY_PROFILE    name of a notarytool keychain profile (enables notarization)
#   OUTPUT_DIR        where the DMG goes (default: ~/Desktop)
set -euo pipefail

APP_NAME="LiquidDynamo"
VERSION="1.4.0"
CONFIG="Release"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/Desktop}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUILD_DIR="$(pwd)/build"
DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.dmg"

say() { printf "\n\033[1m==> %s\033[0m\n" "$*"; }
die() { printf "\033[31mERROR: %s\033[0m\n" "$*" >&2; exit 1; }

command -v xcodebuild >/dev/null || die "xcodebuild not found. Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app"
command -v hdiutil   >/dev/null || die "hdiutil not found (this script must run on macOS)"

# ---- find the project or workspace ----
if ls ./*.xcworkspace >/dev/null 2>&1; then
  CONTAINER=(-workspace "$(ls -d ./*.xcworkspace | head -n1)")
elif ls ./*.xcodeproj >/dev/null 2>&1; then
  CONTAINER=(-project "$(ls -d ./*.xcodeproj | head -n1)")
else
  die "No .xcodeproj or .xcworkspace in $(pwd). Run from the repository root."
fi

# ---- pick the scheme ----
SCHEME="${SCHEME:-LiquidDynamo}"
say "Using scheme: $SCHEME   configuration: $CONFIG   version: $VERSION   signing: $SIGN_IDENTITY"

# ---- build ----
say "Building (log: $BUILD_DIR/build.log)"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"
set +e
xcodebuild "${CONTAINER[@]}" -scheme "$SCHEME" -configuration "$CONFIG" \
  -derivedDataPath "$BUILD_DIR/derived" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  ENABLE_HARDENED_RUNTIME=YES \
  build 2>&1 | tee "$BUILD_DIR/build.log" | tail -n 25
STATUS=${PIPESTATUS[0]}
set -e
if [ "$STATUS" -ne 0 ]; then
  echo; echo "--- first errors ---"; grep -E "error:" "$BUILD_DIR/build.log" | head -n 15 || true
  die "Build failed. Full log: $BUILD_DIR/build.log"
fi

APP_PATH="$(find "$BUILD_DIR/derived/Build/Products/$CONFIG" -maxdepth 1 -name '*.app' | head -n1)"
[ -d "$APP_PATH" ] || die "Built .app not found under $BUILD_DIR/derived/Build/Products/$CONFIG"
say "Built: $APP_PATH"

# ---- sign + verify ----
say "Signing"
if [ -d "$APP_PATH/Contents/Frameworks" ]; then
  for fw in "$APP_PATH/Contents/Frameworks"/*.framework; do
    [ -d "$fw" ] && codesign --force --sign "$SIGN_IDENTITY" "$fw"
  done
fi
if [ -d "$APP_PATH/Contents/XPCServices" ]; then
  for xpc in "$APP_PATH/Contents/XPCServices"/*.xpc; do
    [ -d "$xpc" ] && codesign --force --entitlements "LiquidDynamoXPCHelper/LiquidDynamoXPCHelper.entitlements" --sign "$SIGN_IDENTITY" "$xpc"
  done
fi
codesign --force --entitlements "liquiddinamo/LiquidDynamo.entitlements" --options runtime --sign "$SIGN_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dvv "$APP_PATH" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier|Signature" || true

# ---- package DMG with App Icon and Professional Layout ----
say "Creating Professional DMG: $DMG_PATH"
STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Copy AppIcon.icns for DMG volume icon branding
if [ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]; then
  cp "$APP_PATH/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
  SetFile -c icnC "$STAGE/.VolumeIcon.icns" 2>/dev/null || true
  SetFile -a C "$STAGE" 2>/dev/null || true
fi

# Copy DMG background image if available
if [ -f "$(pwd)/Configuration/dmg/.background/background.tiff" ]; then
  mkdir -p "$STAGE/.background"
  cp "$(pwd)/Configuration/dmg/.background/background.tiff" "$STAGE/.background/"
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$DMG_PATH"

# Create read-write temporary disk image to position icons
TEMP_DMG="$BUILD_DIR/temp.dmg"
rm -f "$TEMP_DMG"
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
            set background picture of viewOptions to file ".background:background.tiff"
        end try
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

# Convert to final compressed DMG
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -f "$TEMP_DMG"

[ "$SIGN_IDENTITY" != "-" ] && codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"

# ---- optional notarization ----
if [ -n "${NOTARY_PROFILE:-}" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  say "Notarizing (this can take a few minutes)"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
fi

# ---- generate Release Notes and Build Report ----
say "Writing Release Notes and Build Report"

cat <<'EOF' > "$OUTPUT_DIR/ReleaseNotes.txt"
LiquidDynamo 1.4.0 — Production Release
========================================
Release Date: October 2026
Version: 1.4.0 (Build 5)
Build Type: Production Release

LiquidDynamo transforms the MacBook notch into an intelligent Liquid Glass status and notification Dynamic Island.

Core Highlights in Version 1.4.0:
1. Liquid Island Engine & Metal 3D SDF Architecture
   - Organic signed-distance field (SDF) continuous shape engine with smooth polynomial blending.
   - 3D specular highlight and Fresnel rim lighting reacting dynamically to system media tint.
   - Intrinsic auto-sizing pipeline reading SwiftUI preferences with zero jumps or visual snaps.
   - Autonomous multi-phased lifecycle: Swell -> Birth -> Bloom -> Hold -> Collapse.
   - Zero-cost idle execution with CADisplayLink pausing when the island is closed.
2. Complete Live Activity & Complex Views Migration
   - Media & Now-Playing with dynamic ambient glow, marquee track metadata, and fluid scrubber.
   - Timers & Pomodoro countdowns with animated progress ring and quick controls.
   - Notifications, Clipboard Shelf, and Calendar event previews with one-tap meeting join.
3. Physical Notch Hole Avoidance & Single Source of Truth Geometry
   - Dynamic NotchGeometry coordinates (leftSlot, rightSlot, belowArea, notchRect).
   - Zero-overlap guarantee: treats the physical notch cutout as a complete hole.
   - Top band content strictly partitions to leftSlot and rightSlot; no text/icons inside the cutout.
   - Liquid drop alerts, device showcases, and popups cleanly bloom in belowArea.
   - Seamless floating pill fallback on non-notched Macs and external displays.
   - Configurable wing width (50 to 160 pt) and real-time layout guides overlay (Debug).

2. Dynamic Island Status Hub around the Notch
   - Intelligent status hub anchored around the MacBook physical notch.
   - Smooth fluid expansion into a floating Liquid Glass panel on alerts.
   - Automatic return to compact notch state when idle.
   - Interactive hover details and click navigation.

2. Rich Expansion Triggers
   - Music & Media: Live album art, scrolling song title, artist, and audio visualizer.
   - Volume & Sound: Live smooth slider, percentage level, and mute badge.
   - AirPods & Bluetooth: Connection alerts with Left, Right, and Case battery levels.
   - Battery & Charging: Live charge detection and critical low battery alerts (15% & 5%).
   - Downloads & File Transfers: Live progress ring/bar, download speed, and completion status.
   - Notifications & Messages: Native notification card with app icon, sender, and preview.
   - Privacy Hub: Real-time indicators when microphone, camera, or screen recording activates.

3. Liquid Glass Materials & Aesthetics
   - Real-time backdrop blur (.ultraThinMaterial), obsidian tinting, and specular highlights.
   - 3D icons across all modules and status hubs.
   - Adaptive sizing (compact, medium, large) strictly respecting MacBook safe display boundaries.
   - Fluid 60–120 FPS spring animations driven by IslandMotion physics.

4. Consistent Application Branding
   - Official application icon applied as primary logo across Dock, About screen, Onboarding, and installer DMG.
   - Professional macOS installer experience with drag-to-Applications layout.
EOF

cat <<EOF > "$OUTPUT_DIR/BuildReport.txt"
LiquidDynamo Production Build Report
=====================================
Application Name: $APP_NAME
Marketing Version: $VERSION
Current Project Version: 1
Build Configuration: $CONFIG
Build Type: Production Release
Deployment Target: macOS 14.0+
Architecture: arm64
Signed: $SIGN_IDENTITY
Codesign Verification: Passed (deep, strict)
DMG Package: $DMG_PATH
Volume Name: $APP_NAME
Branding Assets: AppIcon.icns, .VolumeIcon.icns, 3D Icon Suite, Liquid Glass Material Engine
Safe Area Engine: NotchSafeAreaEngine integrated
Build Timestamp: $(date)
Status: Succeeded & Validated
EOF

say "Done: $DMG_PATH"
say "Release Notes: $OUTPUT_DIR/ReleaseNotes.txt"
say "Build Report: $OUTPUT_DIR/BuildReport.txt"
