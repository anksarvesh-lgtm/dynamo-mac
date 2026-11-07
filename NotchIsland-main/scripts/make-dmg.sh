#!/bin/zsh
# Builds NotchIsland.app (release, Apple silicon) and wraps it in dist/NotchIsland.dmg.
# Usage: scripts/make-dmg.sh [version]   e.g. scripts/make-dmg.sh 1.1.0
#
# Signing, best available first:
#   1. A "Developer ID Application" identity in the login keychain (paid Apple Developer Program):
#      hardened runtime + timestamp, and with NOTARY_PROFILE=<notarytool keychain profile> the app and
#      the DMG are notarized and stapled, so Gatekeeper opens them without the "could not verify" dialog.
#   2. The project's self-signed "NotchIsland Developer" identity (scripts/signing-identity.sh):
#      stable across builds so permission grants survive updates; Gatekeeper still asks on first launch.
#   3. Ad-hoc, only with ALLOW_ADHOC=1: every ad-hoc build is a new app to macOS, so users lose
#      every permission grant on each update (that is what happened between 1.0.0 and 1.0.1).
#
# Resources/release-identity.sha1 holds the SHA-1 of the certificate the released builds are signed
# with. macOS stores that hash with every permission grant, so a build signed with any other
# certificate (a recreated keychain, another Mac) makes users grant everything again. The script
# refuses such a build unless NEW_IDENTITY=1, which also records the new hash.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.3.2}"
BUILD="$(date +%Y%m%d%H%M)"
APP="dist/NotchIsland.app"
ROOT="dist/dmg-root"
DMG="dist/NotchIsland.dmg"

echo "▸ swift build -c release"
swift build -c release 2>&1 | grep -E "error|warning: unre|Compiling|Build complete" || true
BIN="$(swift build -c release --show-bin-path)/NotchIsland"
[[ -x "$BIN" ]] || { echo "release binary not found at $BIN"; exit 1; }
# The MediaRemote adapter (system Now Playing feed) is a dylib loaded by /usr/bin/perl, not by the
# app; see Sources/MediaRemoteAdapter/adapter.m. SwiftPM builds it as a dynamic library product.
ADAPTER="$(dirname "$BIN")/libMediaRemoteAdapter.dylib"
[[ -f "$ADAPTER" ]] || swift build -c release --product MediaRemoteAdapter 2>&1 | grep -E "error" || true
[[ -f "$ADAPTER" ]] || { echo "adapter not found at $ADAPTER"; exit 1; }

echo "▸ assembling $APP ($VERSION, build $BUILD)"
rm -rf "$APP" "$ROOT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/NotchIsland"
cp "$ADAPTER" "$APP/Contents/Frameworks/libMediaRemoteAdapter.dylib"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ codesign"
ENTITLEMENTS="Resources/NotchIsland.entitlements"
IDENTITY_FILE="Resources/release-identity.sha1"
EXPECTED_ROOT="$(tr -d '[:space:]' < "$IDENTITY_FILE" 2>/dev/null || true)"
DEVID="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
NOTARIZE=0
if [[ -n "$DEVID" ]]; then
  codesign --force --options runtime --timestamp --sign "$DEVID" "$APP/Contents/Frameworks/libMediaRemoteAdapter.dylib"
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$DEVID" "$APP"
  echo "  signed with \"$DEVID\" (hardened runtime)"
  if [[ -n "$EXPECTED_ROOT" ]]; then
    echo "  note: releases so far were signed with certificate $EXPECTED_ROOT; the Developer ID is a new"
    echo "  identity, so users grant permissions once more after this release (the app repairs stale"
    echo "  entries on its first launch). Clear $IDENTITY_FILE once this is the released identity."
  fi
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    NOTARIZE=1
    echo "▸ notarizing $APP (profile $NOTARY_PROFILE)"
    ditto -c -k --keepParent "$APP" dist/NotchIsland-notarize.zip
    xcrun notarytool submit dist/NotchIsland-notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f dist/NotchIsland-notarize.zip
    xcrun stapler staple "$APP"
  else
    echo "  NOTARY_PROFILE not set, skipping notarization (README ▸ Notarized builds)"
  fi
elif KEYCHAIN="$(scripts/signing-identity.sh --unlock 2>/dev/null)"; then
  codesign --force --deep --sign "NotchIsland Developer" --keychain "$KEYCHAIN" "$APP"
  echo "  signed with \"NotchIsland Developer\" (stable identity, permission grants survive updates)"
  ROOT="$(codesign -dr - "$APP" 2>&1 | sed -n 's/.*certificate root = H"\([0-9a-f]*\)".*/\1/p')"
  if [[ -z "$ROOT" ]]; then
    echo "✗ could not read the certificate hash from the signature"; exit 1
  elif [[ -z "$EXPECTED_ROOT" ]]; then
    print -r -- "$ROOT" > "$IDENTITY_FILE"
    echo "  recorded certificate $ROOT in $IDENTITY_FILE"
  elif [[ "$ROOT" != "$EXPECTED_ROOT" ]]; then
    echo "✗ this build is signed with certificate $ROOT, but releases use $EXPECTED_ROOT ($IDENTITY_FILE)."
    echo "  macOS ties every permission grant to that hash: shipping this build makes every user grant"
    echo "  Accessibility, Full Disk Access, Calendar and Automation again."
    echo "  Restore ~/Library/Keychains/notchisland-signing.keychain-db from backup, or if the change is"
    echo "  deliberate run NEW_IDENTITY=1 scripts/make-dmg.sh $VERSION and say so in the release notes."
    [[ "${NEW_IDENTITY:-0}" == 1 ]] || exit 1
    print -r -- "$ROOT" > "$IDENTITY_FILE"
    echo "  NEW_IDENTITY=1: recorded $ROOT in $IDENTITY_FILE"
  else
    echo "  certificate $ROOT matches $IDENTITY_FILE"
  fi
elif [[ "${ALLOW_ADHOC:-0}" == 1 ]]; then
  codesign --force --deep --sign - "$APP"
  echo "  signed ad-hoc (ALLOW_ADHOC=1): fine for a local test, never for a release"
else
  echo "✗ no signing identity. An ad-hoc build is a different app to macOS on every compile, so every"
  echo "  permission grant is lost with each update. Run scripts/signing-identity.sh (and restore the"
  echo "  keychain it names if you had one), or ALLOW_ADHOC=1 scripts/make-dmg.sh for a throwaway build."
  exit 1
fi
codesign --verify --strict --verbose=1 "$APP"
codesign -dr - "$APP" 2>&1 | grep designated

echo "▸ building $DMG"
mkdir -p "$ROOT"
cp -R "$APP" "$ROOT/"
ln -s /Applications "$ROOT/Applications"
cp Resources/dmg-readme.txt "$ROOT/Read me first.txt"
rm -f "$DMG"
hdiutil create -volname "NotchIsland" -srcfolder "$ROOT" -ov -format UDZO -fs HFS+ -quiet "$DMG"
rm -rf "$ROOT"
if [[ "$NOTARIZE" == 1 ]]; then
  echo "▸ notarizing $DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi
echo "✓ $(du -h "$DMG" | cut -f1) $DMG"
