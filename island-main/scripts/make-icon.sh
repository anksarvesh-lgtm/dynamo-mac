#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
TMP="$(mktemp -d)"
swiftc -sdk "$SDKROOT" "$ROOT/scripts/make-icon.swift" -o "$TMP/make-icon"
"$TMP/make-icon" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
echo "Resources/AppIcon.icns"
