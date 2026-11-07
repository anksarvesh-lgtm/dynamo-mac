#!/usr/bin/env bash
# Shared toolchain detection. Picks an SDK that the installed swiftc can actually compile against
# (handles partially-updated Command Line Tools where the default SDK is newer than the compiler).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/.build/island}"
MIN_MACOS="14.0"

pick_sdk() {
  if [[ -n "${SDKROOT:-}" ]]; then echo "$SDKROOT"; return; fi
  local probe; probe="$(mktemp -d)"
  echo 'import AppKit; print(0)' > "$probe/p.swift"
  local candidates=("$(xcrun --show-sdk-path 2>/dev/null || true)")
  local sdkdir; sdkdir="$(dirname "${candidates[0]}")"
  for s in $(ls -d "$sdkdir"/MacOSX*.*.sdk 2>/dev/null | sort -rV); do candidates+=("$s"); done
  for s in "${candidates[@]}"; do
    [[ -d "$s" ]] || continue
    if SDKROOT="$s" swiftc -typecheck "$probe/p.swift" >/dev/null 2>&1; then rm -rf "$probe"; echo "$s"; return; fi
  done
  rm -rf "$probe"; echo "No compatible macOS SDK found" >&2; exit 1
}

export SDKROOT="$(pick_sdk)"
