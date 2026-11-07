#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds MacLink.app for macOS from a release build of maclink-desktop:
# the bundle layout and Info.plist, the app icon, the Qt frameworks and QML
# modules (macdeployqt), an ad-hoc signature (Apple Silicon runs only signed
# code), and a zip of it in dist/.
#
#   cargo build --release --bin maclink-desktop
#   QT_ROOT_DIR=~/Qt/6.12.0/macos ./desktop/packaging/macos/build-app.sh
#
# The app isn't signed with a Developer ID or notarized, so the first time it
# opens macOS asks: Control-click it in Finder and choose Open.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$REPO_ROOT"

VERSION="$(awk -F'"' '/^\[workspace.package\]/{f=1} f && /^version = /{print $2; exit}' Cargo.toml)"
ARCH="$(uname -m)"
BIN="${BIN:-target/release/maclink-desktop}"
OUT_DIR="${OUT_DIR:-dist}"
APP="${OUT_DIR}/MacLink.app"

if [[ -z "${QT_ROOT_DIR:-}" ]]; then
    for candidate in ~/Qt/6.*/macos /Users/*/Qt/6.*/macos /opt/homebrew/opt/qt6 /usr/local/opt/qt6; do
        if [[ -x "${candidate}/bin/macdeployqt" ]]; then
            QT_ROOT_DIR="${candidate}"
            break
        fi
    done
fi

[[ -x "$BIN" ]] || { echo "build it first: cargo build --release --bin maclink-desktop" >&2; exit 1; }
MACDEPLOYQT="${QT_ROOT_DIR:+${QT_ROOT_DIR}/bin/}macdeployqt"
command -v "$MACDEPLOYQT" >/dev/null || { echo "macdeployqt not found; set QT_ROOT_DIR" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/maclink-desktop"
# Translations, next to the executable where the app looks for them.
LRELEASE="${QT_ROOT_DIR:+${QT_ROOT_DIR}/bin/}lrelease"
command -v "$LRELEASE" >/dev/null || { echo "lrelease not found; set QT_ROOT_DIR" >&2; exit 1; }
for ts in desktop/app/i18n/maclink_*.ts; do
    name="$(basename "$ts" .ts)"
    "$LRELEASE" -silent "$ts" -qm "$APP/Contents/MacOS/${name}.qm"
    cp -f "$APP/Contents/MacOS/${name}.qm" "$APP/Contents/Resources/${name}.qm"
done

# The icon: every size macOS asks for, from the 1024 px brand icon.
ICONSET="$(mktemp -d)/MacLink.iconset"
mkdir -p "$ICONSET"
SOURCE_ICON="assets/brand/icon-1024.png"
[[ -f "$SOURCE_ICON" ]] || SOURCE_ICON="assets/brand/icon-512.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE_ICON" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SOURCE_ICON" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/MacLink.icns"
cp -f "assets/brand/maclink-liquid-logo.png" "$APP/Contents/Resources/maclink-liquid-logo.png"
cp -f "assets/brand/maclink-liquid-logo.png" "$APP/Contents/MacOS/maclink-liquid-logo.png"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MacLink</string>
    <key>CFBundleDisplayName</key><string>MacLink</string>
    <key>CFBundleIdentifier</key><string>in.maclink.srv</string>
    <key>CFBundleExecutable</key><string>maclink-desktop</string>
    <key>CFBundleIconFile</key><string>MacLink</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>NSUserNotificationAlertStyle</key><string>banner</string>
    <key>NSUserActivityTypes</key>
    <array>
        <string>INSendMessageIntent</string>
    </array>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>MacLink uses Bluetooth to detect paired phones nearby.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>MacLink finds your phone and connects to it on this network.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_maclink._udp</string>
    </array>
    <key>NSMicrophoneUsageDescription</key>
    <string>MacLink uses the microphone for calls you take on this Mac.</string>
    <key>NSCameraUsageDescription</key>
    <string>MacLink uses the camera only when you start a feature that needs it.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>MacLink controls media players on this Mac when you ask it to from your phone.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>MacLink</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>maclink</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Qt frameworks, plugins and the QML modules the app imports.
"$MACDEPLOYQT" "$APP" -qmldir=desktop/app/qml -always-overwrite

# Clean any extended attributes/resource forks before signing
xattr -cr "$APP"

# Ad-hoc signature: no identity, but Apple Silicon won't run unsigned code.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

# Verify Apple Silicon Mach-O slice and signature with REA if available
if command -v rea >/dev/null 2>&1; then
    echo "Inspecting bundle binary with REA..."
    rea list-architectures "$APP/Contents/MacOS/maclink-desktop" || true
    rea inspect-signature "$APP/Contents/MacOS/maclink-desktop" || true
fi

ZIP="${OUT_DIR}/MacLink-${VERSION}-macos-${ARCH}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Built $ZIP"

DMG="${OUT_DIR}/MacLink-${VERSION}-macos-${ARCH}.dmg"
DMG_STAGING="$(mktemp -d)/dmg_staging"
mkdir -p "$DMG_STAGING"
cp -R "$APP" "$DMG_STAGING/MacLink.app"
ln -s /Applications "$DMG_STAGING/Applications"
cp assets/brand/MacLink.icns "$DMG_STAGING/.VolumeIcon.icns"
SetFile -c icnC "$DMG_STAGING/.VolumeIcon.icns" 2>/dev/null || true
SetFile -a C "$DMG_STAGING" 2>/dev/null || true
rm -f "$DMG"
hdiutil create -volname "MacLink" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DMG_STAGING"
echo "Built $DMG"
cp -f "$DMG" "${OUT_DIR}/MacLink-${VERSION}.dmg"
if [[ -d "${REPO_ROOT}/../dist" ]]; then
    cp -Rf "$APP" "${REPO_ROOT}/../dist/"
    cp -f "$DMG" "${REPO_ROOT}/../dist/"
    cp -f "$ZIP" "${REPO_ROOT}/../dist/"
    cp -f "${OUT_DIR}/MacLink-${VERSION}.dmg" "${REPO_ROOT}/../dist/"
fi
