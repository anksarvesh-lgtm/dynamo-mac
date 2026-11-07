#!/usr/bin/env bash
# Builds and runs the IslandCore test suite, then the app's headless self-test.
set -euo pipefail
source "$(dirname "$0")/env.sh"
"$ROOT/scripts/build.sh" debug "$(uname -m)" --tests
OUT="$BUILD_DIR/debug-$(uname -m)"
"$OUT/IslandCoreTests" "$@"
if [[ "${SKIP_SELF_TEST:-0}" != "1" ]]; then "$OUT/Island" --self-test; fi
