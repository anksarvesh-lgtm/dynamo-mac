#include "NotchIslandInfoPlist.h"

// A bare SwiftPM executable has no bundle, so we embed an Info.plist in the __TEXT,__info_plist
// section. macOS reads it from there: it gives the binary a bundle identifier and name (so
// permission prompts say "NotchIsland"), LSUIElement (no Dock icon), and the privacy usage
// descriptions TCC requires before it will even show the Calendar / Camera / Microphone prompts.
__attribute__((used, section("__TEXT,__info_plist")))
static const char notchisland_info_plist[] =
"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
"<plist version=\"1.0\"><dict>\n"
"  <key>CFBundleIdentifier</key><string>com.notchisland.app</string>\n"
"  <key>CFBundleName</key><string>NotchIsland</string>\n"
"  <key>CFBundleDisplayName</key><string>NotchIsland</string>\n"
"  <key>CFBundleExecutable</key><string>NotchIsland</string>\n"
"  <key>CFBundleVersion</key><string>2</string>\n"
"  <key>CFBundleShortVersionString</key><string>0.2</string>\n"
"  <key>CFBundlePackageType</key><string>APPL</string>\n"
"  <key>LSUIElement</key><true/>\n"
"  <key>LSMinimumSystemVersion</key><string>13.0</string>\n"
"  <key>NSHumanReadableCopyright</key><string>NotchIsland</string>\n"
"  <key>NSAppleEventsUsageDescription</key><string>NotchIsland controls Music, Spotify, VLC and your browser to show and drive Now Playing, and System Events for volume and dark mode.</string>\n"
"  <key>NSCalendarsUsageDescription</key><string>NotchIsland shows your next calendar event in the island.</string>\n"
"  <key>NSCalendarsFullAccessUsageDescription</key><string>NotchIsland shows your next calendar event and its meeting link in the island.</string>\n"
"  <key>NSCameraUsageDescription</key><string>NotchIsland can show a quick camera mirror before a meeting.</string>\n"
"  <key>NSMicrophoneUsageDescription</key><string>NotchIsland shows when the microphone is in use.</string>\n"
"  <key>NSBluetoothAlwaysUsageDescription</key><string>NotchIsland shows when AirPods and other Bluetooth devices connect.</string>\n"
"</dict></plist>\n";

const char *NotchIslandInfoPlistMarker(void) { return notchisland_info_plist; }
