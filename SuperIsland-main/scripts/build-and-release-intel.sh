#!/bin/bash
# Usage: ./scripts/build-and-release-intel.sh
# Requires: APPLE_ID, APP_SPECIFIC_PASSWORD, TEAM_ID, SIGNING_IDENTITY env vars
# or reads from .env file
#
# Produces an Intel-only (x86_64) signed + notarized DMG at
# build-intel/SuperIsland-x86_64.dmg. The arm64 release script
# (./scripts/build-and-release.sh) is the canonical Apple Silicon path
# and writes to build/. The two are intentionally kept as separate
# self-contained scripts so each is easy to debug in isolation.

set -euo pipefail

# --- Configuration (from env or .env file) ---
source .env 2>/dev/null || true
APP_NAME="SuperIsland"
SCHEME="${APP_NAME}"
BUILD_DIR="build-intel"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}-x86_64.dmg"
DMG_STAGING_DIR="${BUILD_DIR}/dmg-root"
ENTITLEMENTS="SuperIsland/SuperIsland.entitlements"

# Required env vars
: "${APPLE_ID:?Set APPLE_ID in .env}"
: "${APP_SPECIFIC_PASSWORD:?Set APP_SPECIFIC_PASSWORD in .env}"
: "${TEAM_ID:?Set TEAM_ID in .env}"
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY in .env (e.g., 'Developer ID Application: Your Name (TEAMID)')}"

echo "==> Cleaning..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "==> Generating Xcode project..."
xcodegen generate

echo "==> Archiving (x86_64)..."
# Force x86_64 only so the archive runs on Intel Macs and the resulting
# binary is half the size of a universal build. The project.yml default
# is ARCHS_STANDARD which would yield a universal app.
xcodebuild archive \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  -destination "generic/platform=macOS" \
  ARCHS="x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  SKIP_INSTALL=NO \
  SWIFT_VERIFY_EMITTED_MODULE_INTERFACE=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  ENABLE_HARDENED_RUNTIME=YES

echo "==> Extracting app from archive..."
APP_IN_ARCHIVE="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
if [ ! -d "${APP_IN_ARCHIVE}" ]; then
  echo "ERROR: ${APP_IN_ARCHIVE} not found after archive"
  exit 1
fi
rm -rf "${APP_PATH}"
cp -R "${APP_IN_ARCHIVE}" "${APP_PATH}"

echo "==> Bundling Node.js runtime (x86_64)..."
NODE_VERSION="20.19.0"
NODE_TMP="$(mktemp -d)"
curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-darwin-x64.tar.gz" \
  | tar -xz -C "${NODE_TMP}" --strip-components=2 "node-v${NODE_VERSION}-darwin-x64/bin/node"
cp "${NODE_TMP}/node" "${APP_PATH}/Contents/Resources/node"
chmod +x "${APP_PATH}/Contents/Resources/node"
rm -rf "${NODE_TMP}"
echo "   Bundled node v${NODE_VERSION} ($(du -sh "${APP_PATH}/Contents/Resources/node" | cut -f1))"

echo "==> Re-signing app (required after injecting node binary)..."
NODE_ENTITLEMENTS="SuperIsland/node.entitlements"
codesign --sign "${SIGNING_IDENTITY}" --force --options runtime \
  --entitlements "${NODE_ENTITLEMENTS}" \
  "${APP_PATH}/Contents/Resources/node"
codesign --sign "${SIGNING_IDENTITY}" --force --deep --options runtime \
  --entitlements "${ENTITLEMENTS}" \
  "${APP_PATH}"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

echo "==> Preparing DMG contents..."
mkdir -p "${DMG_STAGING_DIR}"
cp -R "${APP_PATH}" "${DMG_STAGING_DIR}/"
ln -s /Applications "${DMG_STAGING_DIR}/Applications"

echo "==> Creating DMG..."
hdiutil create -volname "${APP_NAME}" \
  -srcfolder "${DMG_STAGING_DIR}" \
  -ov -format UDZO \
  "${DMG_PATH}"

echo "==> Signing DMG..."
codesign --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"

echo "==> Notarizing..."
xcrun notarytool submit "${DMG_PATH}" \
  --apple-id "${APPLE_ID}" \
  --password "${APP_SPECIFIC_PASSWORD}" \
  --team-id "${TEAM_ID}" \
  --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "${DMG_PATH}"

echo "==> Verifying notarization..."
xcrun stapler validate "${DMG_PATH}"
spctl --assess --type open --context context:primary-signature --verbose "${DMG_PATH}"

echo ""
echo "SUCCESS: ${DMG_PATH} is signed, notarized, and ready to ship!"
echo "   Size: $(du -h "${DMG_PATH}" | cut -f1) -- ${DMG_PATH}"
