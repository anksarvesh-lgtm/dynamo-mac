#!/usr/bin/env bash
# Builds a universal (arm64 + x86_64) release Island.app into dist/.
# Usage: scripts/build-release.sh [version]
set -euo pipefail
source "$(dirname "$0")/env.sh"
VERSION="${1:-$(git -C "$ROOT" describe --tags --always 2>/dev/null | sed 's/^v//' || echo 0.0.0)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
DIST="$ROOT/dist"
rm -rf "$DIST" && mkdir -p "$DIST"

for arch in arm64 x86_64; do
  "$ROOT/scripts/build.sh" release "$arch"
done
lipo -create "$BUILD_DIR/release-arm64/Island" "$BUILD_DIR/release-x86_64/Island" -output "$DIST/Island-universal"
lipo -info "$DIST/Island-universal"

"$ROOT/scripts/bundle.sh" "$DIST/Island-universal" "$DIST" "$VERSION" "$BUILD_NUMBER"
rm "$DIST/Island-universal"
codesign --verify --deep --strict "$DIST/Island.app" && echo "✓ signature (ad-hoc) valid"
echo "✓ $DIST/Island.app ($VERSION, build $BUILD_NUMBER)"
