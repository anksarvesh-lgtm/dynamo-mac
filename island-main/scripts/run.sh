#!/usr/bin/env bash
# Build a debug Island.app and launch it.
set -euo pipefail
source "$(dirname "$0")/env.sh"
"$ROOT/scripts/build.sh" debug "$(uname -m)"
APP=$("$ROOT/scripts/bundle.sh" "$BUILD_DIR/debug-$(uname -m)/Island" "$BUILD_DIR" "0.0.0-dev")
pkill -x Island 2>/dev/null || true
for _ in $(seq 1 50); do pgrep -x Island >/dev/null || break; sleep 0.1; done
open "$APP" --args "$@"
