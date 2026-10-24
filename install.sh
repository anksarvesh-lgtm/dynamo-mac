#!/usr/bin/env bash
#
# LiquidDynamo — One-Line Instant macOS Installer & Auto-Launcher
# Automatically downloads the latest release, installs to /Applications,
# clears Gatekeeper quarantine flags, and launches the app.
#
# Usage:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/anksarvesh-lgtm/dynamo-mac/main/install.sh)"
#

set -e

# Terminal formatting
BOLD="\033[1m"
BLUE="\033[38;2;45;140;255m"
CYAN="\033[38;2;60;200;255m"
GREEN="\033[38;2;50;205;120m"
YELLOW="\033[38;2;255;190;0m"
RED="\033[38;2;255;75;75m"
RESET="\033[0m"

echo ""
echo -e "${BLUE}${BOLD}┌────────────────────────────────────────────────────────┐${RESET}"
echo -e "${BLUE}${BOLD}│              💧 LiquidDynamo for macOS                 │${RESET}"
echo -e "${BLUE}${BOLD}│       One-Click Installer & Gatekeeper Bypass          │${RESET}"
echo -e "${BLUE}${BOLD}└────────────────────────────────────────────────────────┘${RESET}"
echo ""

# 1. OS check
if [ "$(uname)" != "Darwin" ]; then
    echo -e "${RED}❌ Error: LiquidDynamo is built natively for macOS only.${RESET}"
    exit 1
fi

ARCH="$(uname -m)"
echo -e "${CYAN}==>${RESET} Detected macOS ($(sw_vers -productVersion)) on ${BOLD}${ARCH}${RESET}."

# 2. Terminate existing running instance if open
if pgrep -x "LiquidDynamo" >/dev/null 2>&1; then
    echo -e "${YELLOW}==>${RESET} Closing running LiquidDynamo instance for clean upgrade..."
    pkill -x "LiquidDynamo" || true
    sleep 0.5
fi

# 3. Setup temporary download space
TEMP_DIR="$(mktemp -d -t liquiddynamo_install_XXXXXX)"
ZIP_PATH="$TEMP_DIR/liquiddynamo.zip"
EXTRACT_DIR="$TEMP_DIR/extracted"
mkdir -p "$EXTRACT_DIR"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# 4. Download latest application archive
URL_PRIMARY="https://github.com/anksarvesh-lgtm/dynamo-mac/releases/download/app/liquiddynamo.zip"
URL_FALLBACK="https://github.com/anksarvesh-lgtm/dynamomac/releases/download/app/liquiddynamo.zip"

echo -e "${CYAN}==>${RESET} Downloading latest LiquidDynamo release..."

DOWNLOAD_SUCCESS=false
if curl -fL --progress-bar -H "User-Agent: LiquidDynamo-Installer" "$URL_PRIMARY" -o "$ZIP_PATH"; then
    DOWNLOAD_SUCCESS=true
elif curl -fL --progress-bar -H "User-Agent: LiquidDynamo-Installer" "$URL_FALLBACK" -o "$ZIP_PATH"; then
    DOWNLOAD_SUCCESS=true
fi

if [ "$DOWNLOAD_SUCCESS" = false ] || [ ! -s "$ZIP_PATH" ]; then
    echo -e "${RED}❌ Download failed from release servers. Please check your internet connection.${RESET}"
    exit 1
fi

# 5. Extract application archive
echo -e "${CYAN}==>${RESET} Extracting application archive..."
/usr/bin/ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"

APP_PATH=""
for candidate in "$EXTRACT_DIR/LiquidDynamo.app" "$EXTRACT_DIR/liquiddynamo.app" "$EXTRACT_DIR"/*.app; do
    if [ -d "$candidate" ]; then
        APP_PATH="$candidate"
        break
    fi
done

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ Error: Application bundle not found in update archive.${RESET}"
    exit 1
fi

# 6. Install to /Applications
TARGET_APP="/Applications/LiquidDynamo.app"
echo -e "${CYAN}==>${RESET} Installing to ${BOLD}$TARGET_APP${RESET}..."

# Remove old installation if exists
rm -rf "$TARGET_APP" 2>/dev/null || true
rm -rf "/Applications/liquiddynamo.app" 2>/dev/null || true

cp -R "$APP_PATH" "$TARGET_APP"

# 7. Clear Gatekeeper quarantine flags and apply ad-hoc code signature
echo -e "${CYAN}==>${RESET} Clearing Gatekeeper quarantine attributes..."
# Remove quarantine attributes recursively
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
# Clear all extended attributes
xattr -cr "$TARGET_APP" 2>/dev/null || true

# Re-sign ad-hoc to guarantee launch without security prompt
if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$TARGET_APP" 2>/dev/null || true
fi

# 8. Launch the application
echo -e "${GREEN}${BOLD}✔ Installation Complete!${RESET}"
echo -e "${CYAN}==>${RESET} Launching LiquidDynamo automatically..."
open "$TARGET_APP"

echo ""
echo -e "${GREEN}${BOLD}LiquidDynamo is now running! 🚀${RESET}"
echo -e "Look at your MacBook notch or top menu bar to experience the Dynamic Island."
echo ""
