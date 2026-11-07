#!/usr/bin/env bash
# Builds, signs, notarizes, and packages an ILoveNotch release, then drafts it on GitHub:
#
#   scripts/release.sh 0.3.0            # a release
#   scripts/release.sh 0.3.0-beta.1     # a beta, drafted as a GitHub pre-release
#
# It needs a clean main, and:
# - release.env (see release.env.example): the App Store Connect API key for notarization;
# - a Developer ID Application signing identity: a certificate in the keychain, or the Account
#   Holder's Apple ID in Xcode › Settings › Accounts for cloud signing;
# - Sparkle's EdDSA key in the login keychain, made once with `.build/sparkle/bin/generate_keys`;
# - gh, signed in.
#
# The release is drafted, not published. Publish it on GitHub, then commit the appcast.xml this
# writes so installed copies find the update. docs/releasing.md walks through it.
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:?usage: scripts/release.sh <version, for example 0.3.0 or 0.3.0-beta.1>}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || { echo "Not a version: $version" >&2; exit 1; }
[[ -f release.env ]] || { echo "Missing release.env: copy release.env.example and fill it in" >&2; exit 1; }
# shellcheck source=/dev/null
source release.env
if [[ $(git rev-parse --abbrev-ref HEAD) != main || -n $(git status --porcelain) ]]; then
    echo "Release from a clean main" >&2
    exit 1
fi

tag="v$version"
marketing=${version%%-*}            # CFBundleShortVersionString can't carry a pre-release suffix
build=$(git rev-list --count HEAD)  # grows with every commit, so Sparkle orders builds correctly
out="build/release/$tag"
auth=(--key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
sparkle=.build/sparkle/bin
rm -rf "$out"
mkdir -p "$out"

# The version's section of CHANGELOG.md is its release notes, in the update prompt and on the GitHub
# release (a beta gets a section of its own). The app must already carry the version, in project.yml.
notes="$out/notes.md"
scripts/release-notes.sh "$version" >"$notes"
grep -Eq "^ +MARKETING_VERSION: $marketing( |$)" project.yml || {
    echo "Set MARKETING_VERSION in project.yml to $marketing first" >&2
    exit 1
}

echo "== Checking $tag"
make lint test

echo "== Archiving $tag (build $build)"
make project
xcodebuild -project OpenNotch.xcodeproj -scheme OpenNotch -configuration Release \
    -archivePath "$out/OpenNotch.xcarchive" archive -quiet \
    MARKETING_VERSION="$marketing" CURRENT_PROJECT_VERSION="$build" \
    OPENNOTCH_COMMIT="$(git rev-parse --short HEAD)" OPENNOTCH_SOURCE=

echo "== Signing with Developer ID"
cat >"$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>automatic</string>
    <key>teamID</key><string>$TEAM_ID</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$out/OpenNotch.xcarchive" -exportPath "$out/export" \
    -exportOptionsPlist "$out/ExportOptions.plist" -allowProvisioningUpdates -quiet
app="$out/export/ILoveNotch.app"
codesign --verify --deep --strict "$app"
# The Authority lines only print at -vv. Captured rather than piped to grep -q: under pipefail, grep's
# early exit can kill codesign with SIGPIPE and fail a correctly signed export.
[[ $(codesign -dvv "$app" 2>&1) == *"Authority=Developer ID Application"* ]] || {
    echo "The export isn't signed with Developer ID" >&2
    exit 1
}

echo "== Notarizing the app"
ditto -c -k --keepParent "$app" "$out/ILoveNotch.zip"
xcrun notarytool submit "$out/ILoveNotch.zip" "${auth[@]}" --wait
xcrun stapler staple "$app"
spctl --assess --type execute --verbose "$app"  # Gatekeeper's verdict: "Notarized Developer ID"

echo "== Packaging the DMG"
dmg="$out/ILoveNotch-$version.dmg"
mkdir -p "$out/dmg"
ditto "$app" "$out/dmg/ILoveNotch.app"
ln -s /Applications "$out/dmg/Applications"
hdiutil create -volname "ILoveNotch $version" -srcfolder "$out/dmg" -fs HFS+ -format UDZO -ov "$dmg" -quiet
identity=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
if [[ -n $identity ]]; then
    codesign --sign "$identity" --timestamp "$dmg"
    xcrun notarytool submit "$dmg" "${auth[@]}" --wait
    xcrun stapler staple "$dmg"
else
    echo "No local Developer ID identity (cloud signing): the DMG stays unsigned; the app inside is notarized."
fi

echo "== Updating the appcast"
if [[ ! -x $sparkle/generate_appcast ]]; then
    mkdir -p .build/sparkle
    gh release download 2.10.0 -R sparkle-project/Sparkle -p 'Sparkle-2.10.0.tar.xz' -D .build/sparkle --clobber
    tar -xf .build/sparkle/Sparkle-2.10.0.tar.xz -C .build/sparkle
fi
mkdir -p "$out/updates"
cp "$dmg" "$out/updates/"
[[ -f appcast.xml ]] && cp appcast.xml "$out/updates/"  # keeps the earlier releases' entries
cp "$notes" "$out/updates/ILoveNotch-$version.md"      # embedded in the update prompt
"$sparkle/generate_appcast" --embed-release-notes \
    --download-url-prefix "https://github.com/niyamvora/ILoveNotch/releases/download/$tag/" "$out/updates"
cp "$out/updates/appcast.xml" appcast.xml

echo "== Drafting the GitHub release"
# Also as ILoveNotch.dmg, so https://github.com/niyamvora/ILoveNotch/releases/latest/download/ILoveNotch.dmg
# always downloads the newest release.
cp "$dmg" "$out/ILoveNotch.dmg"
(cd "$out" && shasum -a 256 "ILoveNotch-$version.dmg" ILoveNotch.dmg >SHA256SUMS)
# The release page gets how to install after the notes, for anyone who lands there; the update prompt
# doesn't need it. One line per paragraph: GitHub shows a line break as one.
cat "$notes" - >"$out/release-page.md" <<INSTALL

### Install

Download **ILoveNotch-$version.dmg** below, open it, and drag ILoveNotch into Applications. It updates itself from then on; if you already have it, choose **Check for Updates…** from its menu bar item. Or with Homebrew: \`brew install --cask niyamvora/tap/ilovenotch\`.

Needs macOS 14.6 or later. Signed and notarized by Apple. \`SHA256SUMS\` has the checksums.
INSTALL
# The notes go above the generated list of pull requests. The tag goes on the commit just built, even
# if main moves before the draft is published.
flags=(--draft --title "ILoveNotch $version" --notes-file "$out/release-page.md" --generate-notes
    --target "$(git rev-parse HEAD)")
[[ $version == *-* ]] && flags+=(--prerelease)
gh release create "$tag" "$dmg" "$out/ILoveNotch.dmg" "$out/SHA256SUMS" "${flags[@]}"

cat <<DONE

Drafted $tag with the notarized DMG and its checksum. Next:
  1. Check the draft on GitHub and publish it.
  2. Ship the appcast so installed copies find the update: commit it on dev,
       git switch dev && git add appcast.xml && git commit -m "chore(release): appcast for $tag" && git push
     then open dev's pull request into main and, once it's green, make ship.
  3. Bump the Homebrew cask to $version with the DMG's checksum from SHA256SUMS.
DONE
