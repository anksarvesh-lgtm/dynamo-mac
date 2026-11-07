#!/usr/bin/env bash
# Builds the Mac App Store edition and uploads it to App Store Connect:
#
#   scripts/app-store.sh 0.3.0     # archive, sign for the App Store, and upload for TestFlight and review
#
# The App Store edition is the same app in the App Sandbox, without the now-playing helper, Sparkle,
# the local updater, or the volume-key tap (docs/plan/implementation-plan.md#app-store-edition).
#
# It needs a clean main, release.env (see release.env.example) with an App Store Connect team API
# key allowed to use cloud-managed distribution certificates, and, once, an app record for the
# bundle ID in App Store Connect (My Apps › + › New App): the API can't create one. Signing with
# -allowProvisioningUpdates registers the bundle ID and makes the App Store profile if needed.
# After the upload, the build appears in App Store Connect › TestFlight within minutes.
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:?usage: scripts/app-store.sh <version, for example 0.3.0>}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "App Store versions are x.y.z: $version" >&2; exit 1; }
[[ -f release.env ]] || { echo "Missing release.env: copy release.env.example and fill it in" >&2; exit 1; }
# shellcheck source=/dev/null
source release.env
if [[ $(git rev-parse --abbrev-ref HEAD) != main || -n $(git status --porcelain) ]]; then
    echo "Upload from a clean main" >&2
    exit 1
fi

build=$(git rev-list --count HEAD)
out="build/app-store/$version-$build"
auth=(-allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID")
rm -rf "$out"
mkdir -p "$out"

echo "== Checking"
make lint test

echo "== Archiving the App Store edition $version (build $build)"
make project
xcodebuild -project OpenNotch.xcodeproj -scheme "OpenNotch App Store" -configuration Release \
    -derivedDataPath .build/xcode-appstore -archivePath "$out/OpenNotch.xcarchive" archive -quiet \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build"

echo "== Signing for the App Store and uploading"
cat >"$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>upload</string>
    <key>signingStyle</key><string>automatic</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$out/OpenNotch.xcarchive" -exportPath "$out/export" \
    -exportOptionsPlist "$out/ExportOptions.plist" "${auth[@]}"

echo "Uploaded $version ($build). It shows up in App Store Connect › TestFlight once processed."
