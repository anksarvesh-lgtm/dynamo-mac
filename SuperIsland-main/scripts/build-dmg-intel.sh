#!/bin/bash
# Usage: ./scripts/build-dmg-intel.sh
# Creates a local (unsigned) install-style x86_64 DMG in build-intel/ for
# development/testing.
#
# Mirror of ./scripts/build-dmg.sh (arm64) — kept as a separate self-contained
# script so each arch is easy to debug in isolation.

set -euo pipefail

APP_NAME="SuperIsland"
SCHEME="${APP_NAME}"
BUILD_DIR="build-intel"
DERIVED_DATA="${BUILD_DIR}/DerivedData"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}-x86_64.dmg"
DMG_STAGING_DIR="${BUILD_DIR}/dmg-root"

echo "==> Cleaning build directory..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "==> Generating Xcode project..."
xcodegen generate

echo "==> Building (x86_64)..."
xcodebuild build \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA}" \
  -destination "platform=macOS,arch=x86_64" \
  ARCHS="x86_64" \
  ONLY_ACTIVE_ARCH=NO

echo "==> Copying app bundle..."
BUILT_APP=$(find "${DERIVED_DATA}" -name "${APP_NAME}.app" -type d | head -1)
if [ -z "${BUILT_APP}" ]; then
  echo "ERROR: Could not find built ${APP_NAME}.app"
  exit 1
fi
cp -R "${BUILT_APP}" "${APP_PATH}"

echo "==> Bundling Node.js runtime (x86_64)..."
NODE_VERSION="20.19.0"
NODE_TMP="$(mktemp -d)"
curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-darwin-x64.tar.gz" \
  | tar -xz -C "${NODE_TMP}" --strip-components=2 "node-v${NODE_VERSION}-darwin-x64/bin/node"
cp "${NODE_TMP}/node" "${APP_PATH}/Contents/Resources/node"
chmod +x "${APP_PATH}/Contents/Resources/node"
rm -rf "${NODE_TMP}"
echo "   Bundled node v${NODE_VERSION} ($(du -sh "${APP_PATH}/Contents/Resources/node" | cut -f1))"

echo "==> Code signing for local testing..."
# An unsigned app can't register with TCC (Calendar, Location, etc. won't appear in System Settings).
# Sign with any available development or Developer ID certificate if one exists.
CERT=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -E "Apple Development|Developer ID Application" \
  | head -1 \
  | awk -F'"' '{print $2}')
if [ -n "${CERT}" ]; then
  codesign --deep --force --sign "${CERT}" \
    --entitlements "SuperIsland/SuperIsland.entitlements" \
    "${APP_PATH}"
  echo "   Signed with: ${CERT}"
else
  echo "   Warning: no signing certificate found — TCC permissions (Calendar, etc.) won't register."
fi

echo "==> Preparing DMG contents..."
mkdir -p "${DMG_STAGING_DIR}"
cp -R "${APP_PATH}" "${DMG_STAGING_DIR}/"
ln -s /Applications "${DMG_STAGING_DIR}/Applications"

echo "==> Creating DMG..."
rm -f "${DMG_PATH}"
hdiutil create -volname "${APP_NAME}" \
  -srcfolder "${DMG_STAGING_DIR}" \
  -ov -format UDZO \
  "${DMG_PATH}"

echo ""
echo "SUCCESS: ${DMG_PATH}"
echo "   Size: $(du -h "${DMG_PATH}" | cut -f1)"
echo "   Open the mounted DMG, then drag ${APP_NAME}.app into Applications."

if [ "${OPEN_DMG_ON_SUCCESS:-1}" = "1" ]; then
  echo "==> Opening DMG..."
  open "${DMG_PATH}" || true
fi
