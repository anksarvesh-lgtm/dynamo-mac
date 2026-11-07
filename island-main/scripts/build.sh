#!/usr/bin/env bash
# Builds IslandCore (static library), the Island executable, and the test runner using swiftc directly.
# Usage: scripts/build.sh [debug|release] [arm64|x86_64] [--tests]
set -euo pipefail
source "$(dirname "$0")/env.sh"
CONFIG="${1:-debug}"; ARCH="${2:-$(uname -m)}"; WITH_TESTS="${3:-}"
OUT="$BUILD_DIR/$CONFIG-$ARCH"; mkdir -p "$OUT"
TARGET="$ARCH-apple-macos$MIN_MACOS"

if [[ "$CONFIG" == "release" ]]; then OPT=(-O -whole-module-optimization); else OPT=(-Onone -g -enable-testing -DDEBUG); fi
COMMON=(-target "$TARGET" -sdk "$SDKROOT" -swift-version 5 "${OPT[@]}")

CORE_SRC=$(find "$ROOT/Sources/IslandCore" -name '*.swift' | sort)
APP_SRC=$(find "$ROOT/Sources/Island" -name '*.swift' | sort)

echo "▸ IslandCore ($CONFIG, $ARCH)"
swiftc "${COMMON[@]}" -parse-as-library -module-name IslandCore -emit-module -emit-module-path "$OUT/IslandCore.swiftmodule" \
  -emit-library -static -o "$OUT/libIslandCore.a" $CORE_SRC

echo "▸ Island"
swiftc "${COMMON[@]}" -module-name Island -I "$OUT" -L "$OUT" -lIslandCore \
  -framework AppKit -framework SwiftUI -framework IOKit -framework CoreAudio -framework CoreMediaIO \
  -framework EventKit -framework ServiceManagement -framework Carbon -framework Network \
  -o "$OUT/Island" $APP_SRC

if [[ "$WITH_TESTS" == "--tests" ]]; then
  echo "▸ IslandCoreTests"
  TEST_SRC=$(find "$ROOT/Tests/IslandCoreTests" -name '*.swift' | sort)
  swiftc "${COMMON[@]}" -module-name IslandCoreTests -I "$OUT" -L "$OUT" -lIslandCore -o "$OUT/IslandCoreTests" $TEST_SRC
fi
echo "✓ $OUT"
