#!/usr/bin/env bash
# ==============================================================================
# build_dmg.sh — Professional Signing, Notarization, and Packaging Pipeline
# ==============================================================================
# Builds LiquidDynamo, signs inside-out with Developer ID and Hardened Runtime,
# submits for Apple Notarization, staples tickets to both .app and DMG, and
# packages the final distributable disk image on your Desktop.
#
# Usage:
#   Local test build (ad-hoc):
#     bash build_dmg.sh
#
#   Official release build (Developer ID + Notarization):
#     SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#     NOTARY_PROFILE="LIQUIDDYNAMO_NOTARY" \
#     RELEASE=1 bash build_dmg.sh
#
# Optional environment variables:
#   RELEASE           Set to 1 or true for release distribution mode (or pass --release)
#   SIGN_IDENTITY     e.g. "Developer ID Application: Your Name (TEAMID)". Default: "-"
#   NOTARY_PROFILE    Keychain profile name created via `xcrun notarytool store-credentials`
#   DEVELOPMENT_TEAM  Apple Team ID (auto-detected from SIGN_IDENTITY if not provided)
#   SCHEME            Xcode scheme (default: LiquidDynamo)
#   OUTPUT_DIR        Where the DMG goes (default: ~/Desktop)
#   INSTALL_APP       Set to true to copy to /Applications (local test mode ONLY)
# ==============================================================================

set -euo pipefail

APP_NAME="LiquidDynamo"
CONFIG="Release"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/Desktop}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUILD_DIR="$(pwd)/build"

say() { printf "\n\033[1m==> %s\033[0m\n" "$*"; }
warn() { printf "\033[33mWARNING: %s\033[0m\n" "$*"; }
die() { printf "\033[31mERROR: %s\033[0m\n" "$*" >&2; exit 1; }

command -v hdiutil >/dev/null || die "hdiutil not found (this script must run on macOS)"

# ---- Parse Release Mode ----
IS_RELEASE=false
for arg in "$@"; do
  if [ "$arg" = "--release" ] || [ "$arg" = "-r" ]; then
    IS_RELEASE=true
  fi
done
if [ "${RELEASE:-0}" = "1" ] || [ "${RELEASE:-}" = "true" ]; then
  IS_RELEASE=true
fi

# ---- Extract Version and Build Number from Project ----
VERSION=""
BUILD_NUMBER=""
if [ -f "LiquidDynamo.xcodeproj/project.pbxproj" ]; then
  VERSION="$(grep -m1 'MARKETING_VERSION' LiquidDynamo.xcodeproj/project.pbxproj | awk -F'=' '{print $2}' | tr -d ' ;\"' || true)"
  BUILD_NUMBER="$(grep -m1 'CURRENT_PROJECT_VERSION' LiquidDynamo.xcodeproj/project.pbxproj | awk -F'=' '{print $2}' | tr -d ' ;\"' || true)"
fi
if [ -z "$VERSION" ] && [ -f "liquiddinamo/Info.plist" ]; then
  VERSION="$(plutil -p liquiddinamo/Info.plist 2>/dev/null | grep CFBundleShortVersionString | awk '{print $NF}' | tr -d '\"' || true)"
fi
if [ -z "$BUILD_NUMBER" ] && [ -f "liquiddinamo/Info.plist" ]; then
  BUILD_NUMBER="$(plutil -p liquiddinamo/Info.plist 2>/dev/null | grep CFBundleVersion | awk '{print $NF}' | tr -d '\"' || true)"
fi
VERSION="${VERSION:-2.0.5}"
BUILD_NUMBER="${BUILD_NUMBER:-18}"
DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.dmg"

# ---- Derive Team ID if possible ----
if [ -z "${DEVELOPMENT_TEAM:-}" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  DEVELOPMENT_TEAM="$(echo "$SIGN_IDENTITY" | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p' || true)"
fi

# ---- Check Build Tools ----
HAS_XCODE=false
if command -v xcodebuild >/dev/null 2>&1; then
  if xcodebuild -version >/dev/null 2>&1; then
    HAS_XCODE=true
  fi
fi

# ---- Enforcement & Fail-Fast ----
if [ "$IS_RELEASE" = "true" ]; then
  say "Running in RELEASE DISTRIBUTION mode (version: $VERSION, build: $BUILD_NUMBER)"
  if [ "$SIGN_IDENTITY" = "-" ] || [ -z "$SIGN_IDENTITY" ]; then
    echo ""
    printf "\033[31m=================================================================\n"
    printf "❌ RELEASE REFUSED: Developer ID certificate is missing!\n"
    printf "=================================================================\n"
    printf "A release build for direct distribution CANNOT use ad-hoc signing ('-').\n"
    printf "It will trigger macOS Gatekeeper malware alerts on every user's Mac.\n\n"
    printf "Please provide your Apple Developer ID:\n"
    printf "  SIGN_IDENTITY=\"Developer ID Application: Your Name (TEAMID)\" \\\n"
    printf "  NOTARY_PROFILE=\"LIQUIDDYNAMO_NOTARY\" \\\n"
    printf "  RELEASE=1 bash build_dmg.sh\n"
    printf "=================================================================\033[0m\n\n"
    die "Refusing to create an ad-hoc release build."
  fi

  if [ "$HAS_XCODE" = false ]; then
    echo ""
    printf "\033[31m=================================================================\n"
    printf "❌ RELEASE REFUSED: xcodebuild is not available!\n"
    printf "=================================================================\n"
    printf "Official release builds require a clean, reproducible Xcode build.\n"
    printf "The non-Xcode fallback and /Applications template are strictly forbidden\n"
    printf "in release mode to prevent shipping corrupted or untracked artifacts.\n"
    printf "=================================================================\033[0m\n\n"
    die "Refusing to create a release build without xcodebuild."
  fi

  # In release mode, NEVER overwrite /Applications or remove quarantine on local machine
  INSTALL_APP="false"
else
  say "Running in LOCAL TEST mode (version: $VERSION, build: $BUILD_NUMBER)"
  INSTALL_APP="${INSTALL_APP:-true}"
  if [ "$SIGN_IDENTITY" = "-" ]; then
    printf "\n\033[33m=================================================================\n"
    printf "⚠️  WARNING: AD-HOC SIGNED BUILD (NOT FOR DISTRIBUTION)\n"
    printf "This build uses ad-hoc signing ('-'). It will fail Gatekeeper\n"
    printf "on any other Mac (\"Apple could not verify it is free of malware\").\n"
    printf "For a public release, use: RELEASE=1 SIGN_IDENTITY=\"Developer ID Application: ...\" bash build_dmg.sh\n"
    printf "=================================================================\033[0m\n\n"
  fi
fi

# ---- Build / Stage Application ----
say "Building $APP_NAME (version: $VERSION, build: $BUILD_NUMBER, signing identity: $SIGN_IDENTITY)"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

if [ "$HAS_XCODE" = true ]; then
  if ls ./*.xcworkspace >/dev/null 2>&1; then
    CONTAINER=(-workspace "$(ls -d ./*.xcworkspace | head -n1)")
  elif ls ./*.xcodeproj >/dev/null 2>&1; then
    CONTAINER=(-project "$(ls -d ./*.xcodeproj | head -n1)")
  else
    die "No .xcodeproj or .xcworkspace found in $(pwd)."
  fi

  SCHEME="${SCHEME:-LiquidDynamo}"
  say "Building with xcodebuild (log: $BUILD_DIR/build.log)..."
  set +e
  xcodebuild "${CONTAINER[@]}" -scheme "$SCHEME" -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR/derived" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build 2>&1 | tee "$BUILD_DIR/build.log" | tail -n 25
  STATUS=${PIPESTATUS[0]}
  set -e
  if [ "$STATUS" -ne 0 ]; then
    echo; echo "--- first errors ---"; grep -E "(error:|fatal:|Undefined symbols|ld:)" "$BUILD_DIR/build.log" | head -n 50 || true
    echo; echo "--- last 100 log lines ---"; tail -n 100 "$BUILD_DIR/build.log" || true
    die "Build failed. Full log: $BUILD_DIR/build.log"
  fi

  APP_PATH="$(find "$BUILD_DIR/derived/Build/Products/$CONFIG" -maxdepth 1 -name '*.app' | head -n1)"
  [ -d "$APP_PATH" ] || die "Built .app not found under $BUILD_DIR/derived/Build/Products/$CONFIG"

  # Ensure required dynamic libraries in Frameworks are staged and verified
  mkdir -p "$APP_PATH/Contents/Frameworks"
  if [ -d "$(pwd)/Frameworks" ]; then
    if [ "$IS_RELEASE" = "true" ]; then
      say "Staging and validating Frameworks dynamic libraries for release..."
      cp -f "$(pwd)/Frameworks/"*.dylib "$APP_PATH/Contents/Frameworks/"
      [ -f "$APP_PATH/Contents/Frameworks/kalam.dylib" ] || die "Required kalam.dylib missing from staged Frameworks!"
      [ -f "$APP_PATH/Contents/Frameworks/libusb.dylib" ] || die "Required libusb.dylib missing from staged Frameworks!"
    else
      cp -f "$(pwd)/Frameworks/"*.dylib "$APP_PATH/Contents/Frameworks/" 2>/dev/null || true
    fi

    # Fix dyld install names and references so binary loads without relative path errors
    if [ -f "$APP_PATH/Contents/Frameworks/kalam.dylib" ]; then
      install_name_tool -id @rpath/kalam.dylib "$APP_PATH/Contents/Frameworks/kalam.dylib" 2>/dev/null || true
      install_name_tool -change kalam.dylib @rpath/kalam.dylib "$APP_PATH/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    fi
    if [ -f "$APP_PATH/Contents/Frameworks/libusb.dylib" ]; then
      install_name_tool -change @loader_path/libusb.dylib @rpath/libusb.dylib "$APP_PATH/Contents/MacOS/$APP_NAME" 2>/dev/null || true
      # Provide fallback symlink in Contents/MacOS for direct dyld loader_path resolution
      ln -sf ../Frameworks/libusb.dylib "$APP_PATH/Contents/MacOS/libusb.dylib" 2>/dev/null || true
      ln -sf ../Frameworks/kalam.dylib "$APP_PATH/Contents/MacOS/kalam.dylib" 2>/dev/null || true
    fi
  elif [ "$IS_RELEASE" = "true" ]; then
    die "Required Frameworks directory not found in project root for release."
  fi
else
  # Non-Xcode fallback: strictly local test builds only
  if [ "$IS_RELEASE" = "true" ]; then
    die "Non-Xcode fallback is strictly forbidden in release mode."
  fi

  printf "\n\033[33m=================================================================\n"
  printf "⚠️  LOCAL TEST FALLBACK: BUILDING WITHOUT XCODEBUILD\n"
  printf "xcodebuild is not available. Using local swiftc compilation and template.\n"
  printf "THIS BUILD IS FOR LOCAL TESTING ONLY AND CANNOT BE RELEASED.\n"
  printf "=================================================================\033[0m\n\n"

  # Isolate build artifacts in unique temporary directory with mktemp -d
  FALLBACK_BUILD_TMP="$(mktemp -d "${TMPDIR:-/tmp}/spm_deps.XXXXXX")"
  export SPM_DEPS_DIR="$FALLBACK_BUILD_TMP"
  trap 'rm -rf "$FALLBACK_BUILD_TMP"' EXIT

  say "Compiling fresh binary with swiftc via scripts/compile_dynamo.sh..."
  bash "$(pwd)/scripts/compile_dynamo.sh"
  APP_PATH="$BUILD_DIR/$APP_NAME.app"
  rm -rf "$APP_PATH"
  
  if [ -d "/Applications/$APP_NAME.app" ]; then
    cp -R "/Applications/$APP_NAME.app" "$APP_PATH"
  elif [ -d "$(pwd)/build/$APP_NAME.app" ]; then
    cp -R "$(pwd)/build/$APP_NAME.app" "$APP_PATH"
  else
    die "Base app bundle template not found."
  fi
  
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
  plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
  
  # Install fresh compiled binary
  cp "$SPM_DEPS_DIR/LiquidDynamo_test" "$APP_PATH/Contents/MacOS/$APP_NAME"
  chmod +x "$APP_PATH/Contents/MacOS/$APP_NAME"
  
  # Install dependency dylibs and frameworks
  mkdir -p "$APP_PATH/Contents/Frameworks"
  if [ -d "$SPM_DEPS_DIR/bundle_frameworks" ]; then
    cp -f "$SPM_DEPS_DIR/bundle_frameworks/"* "$APP_PATH/Contents/Frameworks/" 2>/dev/null || true
  fi
  rm -rf "$APP_PATH/Contents/Frameworks/Sparkle.framework" "$APP_PATH/Contents/Frameworks/Lottie.framework"
  if [ -d "$SPM_DEPS_DIR/frameworks_flat/Sparkle.framework" ]; then
    cp -R "$SPM_DEPS_DIR/frameworks_flat/Sparkle.framework" "$APP_PATH/Contents/Frameworks/"
  fi
  if [ -d "$SPM_DEPS_DIR/frameworks_flat/Lottie.framework" ]; then
    cp -R "$SPM_DEPS_DIR/frameworks_flat/Lottie.framework" "$APP_PATH/Contents/Frameworks/"
  fi
  if [ -d "$(pwd)/Frameworks" ]; then
    cp -f "$(pwd)/Frameworks/"*.dylib "$APP_PATH/Contents/Frameworks/" 2>/dev/null || true
  fi
fi

say "Staged Application: $APP_PATH"

# ==============================================================================
# INSIDE-OUT CODE SIGNING
# ==============================================================================
# Apple Notarization requires every embedded Mach-O binary (dylibs, helper
# executables, XPCs, frameworks) to be signed with Developer ID, Hardened
# Runtime (--options runtime), and a Secure Timestamp (--timestamp).
# Signing MUST be done inside-out so outer SHA-1/SHA-256 code seals remain valid.
# ==============================================================================
say "Signing Application Bundle inside-out..."

SIGN_FLAGS=(--force)
if [ "$SIGN_IDENTITY" != "-" ]; then
  SIGN_FLAGS+=(--timestamp)
fi

# 1. Sign standalone Mach-O executables in Resources (e.g. MediaRemoteAdapterTestClient)
if [ -d "$APP_PATH/Contents/Resources" ]; then
  find "$APP_PATH/Contents/Resources" -type f ! -name ".*" | while read -r res_file; do
    if file -b "$res_file" | grep -q "Mach-O"; then
      say "  Signing standalone binary in Resources: $(basename "$res_file")"
      codesign "${SIGN_FLAGS[@]}" --options runtime --sign "$SIGN_IDENTITY" "$res_file"
    fi
  done
fi

# 2. Sign all individual dylibs in Frameworks
if [ -d "$APP_PATH/Contents/Frameworks" ]; then
  find "$APP_PATH/Contents/Frameworks" -maxdepth 1 -type f -name "*.dylib" | while read -r dylib; do
    say "  Signing dynamic library: $(basename "$dylib")"
    codesign "${SIGN_FLAGS[@]}" --options runtime --sign "$SIGN_IDENTITY" "$dylib"
  done
fi

# 3. Sign nested XPC services inside frameworks (e.g. Sparkle Downloader & Installer)
find "$APP_PATH/Contents/Frameworks" -type d -name "*.xpc" 2>/dev/null | sort -r | while read -r nested_xpc; do
  say "  Signing nested framework XPC: $(basename "$nested_xpc")"
  codesign "${SIGN_FLAGS[@]}" --options runtime --sign "$SIGN_IDENTITY" "$nested_xpc"
done

# 4. Sign nested helper applications inside frameworks (e.g. Sparkle Updater.app)
find "$APP_PATH/Contents/Frameworks" -type d -name "*.app" 2>/dev/null | sort -r | while read -r nested_app; do
  say "  Signing nested framework helper app: $(basename "$nested_app")"
  codesign "${SIGN_FLAGS[@]}" --options runtime --sign "$SIGN_IDENTITY" "$nested_app"
done

# 5. Sign standalone helper executables in frameworks (e.g. Sparkle Autoupdate)
find "$APP_PATH/Contents/Frameworks" -type f -name "Autoupdate" 2>/dev/null | while read -r autoupdate; do
  say "  Signing framework helper tool: $(basename "$autoupdate")"
  codesign "${SIGN_FLAGS[@]}" --options runtime --sign "$SIGN_IDENTITY" "$autoupdate"
done

# 6. Sign framework bundles deepest first
find "$APP_PATH/Contents/Frameworks" -maxdepth 1 -type d -name "*.framework" | sort -r | while read -r fw; do
  say "  Signing framework bundle: $(basename "$fw")"
  codesign "${SIGN_FLAGS[@]}" --options runtime --sign "$SIGN_IDENTITY" "$fw"
done

# 7. Sign top-level XPCServices with helper entitlements
if [ -d "$APP_PATH/Contents/XPCServices" ]; then
  for xpc in "$APP_PATH/Contents/XPCServices"/*.xpc; do
    if [ -d "$xpc" ]; then
      say "  Signing XPC service: $(basename "$xpc") with LiquidDynamoXPCHelper.entitlements"
      codesign "${SIGN_FLAGS[@]}" --options runtime \
        --entitlements "LiquidDynamoXPCHelper/LiquidDynamoXPCHelper.entitlements" \
        --sign "$SIGN_IDENTITY" "$xpc"
    fi
  done
fi

# 8. Finally, sign the main application bundle with primary entitlements
say "  Signing main application bundle with LiquidDynamo.entitlements..."
codesign "${SIGN_FLAGS[@]}" --options runtime \
  --entitlements "liquiddinamo/LiquidDynamo.entitlements" \
  --sign "$SIGN_IDENTITY" "$APP_PATH"

# ---- Deep Verification ----
say "Verifying application code signature..."
codesign --verify --strict --verbose=2 "$APP_PATH"
codesign -dvv "$APP_PATH" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier|Signature|flags|Timestamp" || true

# ==============================================================================
# STAGE 1: NOTARIZE AND STAPLE THE .APP BUNDLE
# ==============================================================================
# The .app bundle MUST be notarized and stapled before DMG packaging so that
# users who drag the app out of the DMG have a valid staple ticket locally,
# allowing offline launch without Gatekeeper network lookups.
# ==============================================================================
if [ -n "${NOTARY_PROFILE:-}" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  say "Stage 1: Submitting $APP_NAME.app to Apple Notary Service..."
  APP_ZIP="$BUILD_DIR/$APP_NAME.zip"
  rm -f "$APP_ZIP"
  ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"

  NOTARY_LOG="$BUILD_DIR/notary_app_submit.log"
  set +e
  xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee "$NOTARY_LOG"
  NOTARY_STATUS=${PIPESTATUS[0]}
  set -e

  SUBMISSION_ID="$(grep -E "id: " "$NOTARY_LOG" | head -n1 | awk '{print $2}' || true)"

  if [ "$NOTARY_STATUS" -ne 0 ] || grep -qi "status: Invalid" "$NOTARY_LOG"; then
    echo ""
    printf "\033[31m=================================================================\n"
    printf "❌ NOTARIZATION REJECTED FOR APPLICATION BUNDLE\n"
    printf "=================================================================\033[0m\n"
    if [ -n "$SUBMISSION_ID" ]; then
      say "Fetching Apple Notary error log for submission: $SUBMISSION_ID"
      xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" || true
    fi
    die "Application notarization failed. Review issues above."
  fi

  say "Stage 1 Notarization Accepted! Stapling ticket to $APP_NAME.app..."
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  rm -f "$APP_ZIP"
fi

# ---- Local Install (local test builds only) ----
if [ "${INSTALL_APP:-false}" = "true" ] && [ "$IS_RELEASE" = "false" ]; then
  say "Installing local test build to /Applications/$APP_NAME.app..."
  pkill -9 -f "/Applications/$APP_NAME.app" 2>/dev/null || true
  sleep 1
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_PATH" "/Applications/$APP_NAME.app"
  xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null || true
fi

# ==============================================================================
# STAGE 2: BUILD, SIGN, AND NOTARIZE THE DMG
# ==============================================================================
say "Packaging Professional DMG: $DMG_PATH"
STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Copy AppIcon.icns for volume icon
if [ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]; then
  cp "$APP_PATH/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
  SetFile -c icnC "$STAGE/.VolumeIcon.icns" 2>/dev/null || true
  SetFile -a C "$STAGE" 2>/dev/null || true
fi

# Copy background picture if available
if [ -f "$(pwd)/Configuration/dmg/.background/background.tiff" ]; then
  mkdir -p "$STAGE/.background"
  cp "$(pwd)/Configuration/dmg/.background/background.tiff" "$STAGE/.background/"
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$DMG_PATH"

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
rm -rf "$STAGE"

# Sign the DMG
if [ "$SIGN_IDENTITY" != "-" ]; then
  say "Signing final DMG container..."
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

# Notarize and staple the DMG
if [ -n "${NOTARY_PROFILE:-}" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  say "Stage 2: Submitting final DMG to Apple Notary Service..."
  DMG_NOTARY_LOG="$BUILD_DIR/notary_dmg_submit.log"
  set +e
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee "$DMG_NOTARY_LOG"
  DMG_NOTARY_STATUS=${PIPESTATUS[0]}
  set -e

  DMG_SUBMISSION_ID="$(grep -E "id: " "$DMG_NOTARY_LOG" | head -n1 | awk '{print $2}' || true)"

  if [ "$DMG_NOTARY_STATUS" -ne 0 ] || grep -qi "status: Invalid" "$DMG_NOTARY_LOG"; then
    echo ""
    printf "\033[31m=================================================================\n"
    printf "❌ NOTARIZATION REJECTED FOR DMG CONTAINER\n"
    printf "=================================================================\033[0m\n"
    if [ -n "$DMG_SUBMISSION_ID" ]; then
      say "Fetching Apple Notary error log for DMG submission: $DMG_SUBMISSION_ID"
      xcrun notarytool log "$DMG_SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" || true
    fi
    die "DMG notarization failed. Review issues above."
  fi

  say "Stage 2 Notarization Accepted! Stapling ticket to DMG..."
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

# ==============================================================================
# SUMMARY & VERIFICATION
# ==============================================================================
say "Build & Packaging Complete!"
echo "  Artifact: $DMG_PATH"
echo "  Size:     $(du -sh "$DMG_PATH" | awk '{print $1}')"
echo "  Version:  $VERSION"
echo ""
echo "To verify this release artifact against Gatekeeper, run:"
echo "  bash scripts/verify_release.sh \"$DMG_PATH\""
