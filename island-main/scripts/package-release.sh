#!/usr/bin/env bash
# Packages dist/Island.app into dist/Island.zip and dist/Island.dmg, plus SHA-256 checksums.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
[[ -d "$DIST/Island.app" ]] || { echo "Run scripts/build-release.sh first" >&2; exit 1; }
cd "$DIST"
rm -f Island.zip Island.dmg SHA256SUMS.txt

# ditto preserves the bundle structure, symlinks and code signature.
ditto -c -k --sequesterRsrc --keepParent Island.app Island.zip

STAGE="$(mktemp -d)"
cp -R Island.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Island" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ Island.dmg >/dev/null
rm -rf "$STAGE"

shasum -a 256 Island.zip Island.dmg > SHA256SUMS.txt
cat SHA256SUMS.txt
