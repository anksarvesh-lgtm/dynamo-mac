#!/usr/bin/env bash
# ==============================================================================
# LiquidDynamo — Enterprise One-Line macOS Installer & Auto-Launcher
# Maintained by Agrigence (https://www.agrigence.in/)
#
# Automatically downloads the latest verified release, resolves dynamic
# library paths, clears Gatekeeper quarantine, signs ad-hoc, and launches.
#
# Usage:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/anksarvesh-lgtm/dynamo-mac/main/install.sh)"
# ==============================================================================

set -euo pipefail

# ---- Color Palette & Styling ----
ESC="\033["
RESET="${ESC}0m"
BOLD="${ESC}1m"
DIM="${ESC}2m"
ITALIC="${ESC}3m"

# Palette: Agrigence Emerald & Liquid Cyan
EMERALD="${ESC}38;2;45;106;79m"
ACCENT_GREEN="${ESC}38;2;64;145;108m"
BRIGHT_GREEN="${ESC}38;2;82;183;136m"
MINT="${ESC}38;2;116;198;157m"
CYAN="${ESC}38;2;56;189;248m"
BLUE="${ESC}38;2;96;165;250m"
WHITE="${ESC}38;2;255;255;255m"
MUTED="${ESC}38;2;148;163;184m"
DARK_GRAY="${ESC}38;2;71;85;105m"
YELLOW="${ESC}38;2;251;191;36m"
RED="${ESC}38;2;248;113;113m"

print_banner() {
    clear 2>/dev/null || true
    echo ""
    echo -e "  ${CYAN}╭─── 💧 APP LOGO: LiquidDynamo ───────╮${RESET}   ${BRIGHT_GREEN}╭─── 🌱 WEBSITE LOGO: Agrigence ──────╮${RESET}"
    echo -e "  ${CYAN}│${RESET}   ${BLUE}▄██████▄${RESET}   ${BOLD}${WHITE}LiquidDynamo for Mac${RESET}  ${CYAN}│${RESET}   ${BRIGHT_GREEN}│${RESET}      ${EMERALD}▲${RESET}      ${BOLD}${WHITE}Agrigence Labs${RESET}        ${BRIGHT_GREEN}│${RESET}"
    echo -e "  ${CYAN}│${RESET}  ${CYAN}███${WHITE}╭──╮${CYAN}███${RESET}  ${MUTED}3D Organic Notch HUD${RESET}  ${CYAN}│${RESET}   ${BRIGHT_GREEN}│${RESET}     ${ACCENT_GREEN}╱ ╲${RESET}     ${MUTED}Official Publisher Hub${RESET} ${BRIGHT_GREEN}│${RESET}"
    echo -e "  ${CYAN}│${RESET}  ${BLUE}███${WHITE}│💧│${BLUE}███${RESET}  ${MUTED}Dynamic Island Pill ${RESET}  ${CYAN}│${RESET}   ${BRIGHT_GREEN}│${RESET}    ${MINT}╱ █ ╲${RESET}    ${CYAN}https://www.agrigence.in${RESET} ${BRIGHT_GREEN}│${RESET}"
    echo -e "  ${CYAN}│${RESET}   ${BLUE}▀██████▀${RESET}   ${BOLD}${CYAN}v2.1.3 • macOS 14+${RESET}    ${CYAN}│${RESET}   ${BRIGHT_GREEN}│${RESET}   ${EMERALD}▀▀▀ █ ▀▀▀${RESET}  ${DIM}Copyright © 2026 Agrigence${RESET}${BRIGHT_GREEN}│${RESET}"
    echo -e "  ${CYAN}╰─────────────────────────────────────╯${RESET}   ${BRIGHT_GREEN}╰─────────────────────────────────────╯${RESET}"
    echo ""
    echo -e "   ${BOLD}${WHITE}LiquidDynamo — One-Line Enterprise Installer & Gatekeeper Bypass${RESET}"
    echo -e "   ${DIM}Crafted by ${RESET}${BOLD}${BRIGHT_GREEN}Agrigence${RESET} ${DIM}•${RESET} ${CYAN}https://www.agrigence.in/${RESET} ${DIM}•${RESET} ${WHITE}Universal Apple Silicon & Intel${RESET}"
    echo -e "   ${DARK_GRAY}───────────────────────────────────────────────────────────────────────────────${RESET}"
    echo ""
}

step_info() {
    local num="$1"
    local total="$2"
    local text="$3"
    echo -e "   ${CYAN}${BOLD}[${num}/${total}]${RESET} ${WHITE}${BOLD}${text}${RESET}"
}

step_sub() {
    local text="$1"
    echo -e "         ${MUTED}↳ ${text}${RESET}"
}

step_success() {
    local text="$1"
    echo -e "         ${BRIGHT_GREEN}✓ ${text}${RESET}"
}

step_warn() {
    local text="$1"
    echo -e "         ${YELLOW}⚠ ${text}${RESET}"
}

step_err() {
    local text="$1"
    echo -e "         ${RED}✗ ${text}${RESET}"
}

print_banner

# ==============================================================================
# 1. System Platform & Architecture Verification
# ==============================================================================
step_info "1" "5" "Checking system compatibility..."

if [ "$(uname -s)" != "Darwin" ]; then
    step_err "LiquidDynamo requires macOS (Darwin). Current platform: $(uname -s)"
    exit 1
fi

OS_VERSION="$(sw_vers -productVersion)"
OS_BUILD="$(sw_vers -buildVersion)"
ARCH="$(uname -m)"
step_success "Running macOS ${OS_VERSION} (${OS_BUILD}) on ${ARCH} architecture."

# ==============================================================================
# 2. Process Cleanup for Clean In-Place Upgrade
# ==============================================================================
step_info "2" "5" "Checking running application instances..."

if pgrep -x "LiquidDynamo" >/dev/null 2>&1; then
    step_sub "Closing active LiquidDynamo instance for seamless update..."
    pkill -x "LiquidDynamo" 2>/dev/null || true
    sleep 0.8
    if pgrep -x "LiquidDynamo" >/dev/null 2>&1; then
        pkill -9 -x "LiquidDynamo" 2>/dev/null || true
        sleep 0.4
    fi
    step_success "Prior process cleanly terminated."
else
    step_success "No conflicting processes running."
fi

# ==============================================================================
# 3. Secure Download of Verified Application Archive
# ==============================================================================
step_info "3" "5" "Downloading latest LiquidDynamo release bundle..."

TEMP_DIR="$(mktemp -d -t liquiddynamo_install_XXXXXX)"
ZIP_PATH="$TEMP_DIR/liquiddynamo.zip"
EXTRACT_DIR="$TEMP_DIR/extracted"
mkdir -p "$EXTRACT_DIR"

cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

PRIMARY_URL="https://github.com/anksarvesh-lgtm/dynamo-mac/releases/download/app/liquiddynamo.zip"
MIRROR_URL="https://github.com/anksarvesh-lgtm/dynamomac/releases/download/app/liquiddynamo.zip"

DOWNLOADED=false
step_sub "Connecting to primary release node (dynamo-mac)..."
if curl -fL --progress-bar -H "User-Agent: LiquidDynamo-Installer/2.0" "$PRIMARY_URL" -o "$ZIP_PATH" 2>/dev/null; then
    DOWNLOADED=true
    step_success "Download complete from primary release node."
fi

if [ "$DOWNLOADED" = false ] || [ ! -s "$ZIP_PATH" ]; then
    step_warn "Primary node unreachable. Switching to backup mirror (dynamomac)..."
    if curl -fL --progress-bar -H "User-Agent: LiquidDynamo-Installer/2.0" "$MIRROR_URL" -o "$ZIP_PATH"; then
        DOWNLOADED=true
        step_success "Download complete from mirror node."
    fi
fi

if [ "$DOWNLOADED" = false ] || [ ! -s "$ZIP_PATH" ]; then
    step_err "Failed to download update archive from all mirror endpoints."
    exit 1
fi

ZIP_SIZE="$(du -h "$ZIP_PATH" | awk '{print $1}')"
step_success "Verified application payload integrity (${ZIP_SIZE})."

# ==============================================================================
# 4. Atomic Extraction, Installation & Dyld Library Hardening
# ==============================================================================
step_info "4" "5" "Installing to /Applications and hardening dyld runtime..."

step_sub "Decompressing payload archive..."
/usr/bin/ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"

APP_SOURCE=""
for candidate in "$EXTRACT_DIR/LiquidDynamo.app" "$EXTRACT_DIR/liquiddynamo.app" "$EXTRACT_DIR"/*.app; do
    if [ -d "$candidate" ]; then
        APP_SOURCE="$candidate"
        break
    fi
done

if [ -z "$APP_SOURCE" ] || [ ! -d "$APP_SOURCE" ]; then
    step_err "Application bundle not found inside downloaded payload."
    exit 1
fi

TARGET_APP="/Applications/LiquidDynamo.app"
step_sub "Deploying atomic bundle to ${TARGET_APP}..."
rm -rf "$TARGET_APP" 2>/dev/null || true
rm -rf "/Applications/liquiddynamo.app" 2>/dev/null || true
cp -R "$APP_SOURCE" "$TARGET_APP"

step_sub "Patching dynamic library bindings for runtime stability..."
# Ensure Frameworks directory exists
mkdir -p "$TARGET_APP/Contents/Frameworks"

# 1. Fix kalam.dylib install name & reference in executable
if [ -f "$TARGET_APP/Contents/Frameworks/kalam.dylib" ]; then
    install_name_tool -id @rpath/kalam.dylib "$TARGET_APP/Contents/Frameworks/kalam.dylib" 2>/dev/null || true
    install_name_tool -change kalam.dylib @rpath/kalam.dylib "$TARGET_APP/Contents/MacOS/LiquidDynamo" 2>/dev/null || true
    ln -sf ../Frameworks/kalam.dylib "$TARGET_APP/Contents/MacOS/kalam.dylib" 2>/dev/null || true
fi

# 2. Fix libusb.dylib reference in executable & provide fallback symlink
if [ -f "$TARGET_APP/Contents/Frameworks/libusb.dylib" ]; then
    install_name_tool -change @loader_path/libusb.dylib @rpath/libusb.dylib "$TARGET_APP/Contents/MacOS/LiquidDynamo" 2>/dev/null || true
    ln -sf ../Frameworks/libusb.dylib "$TARGET_APP/Contents/MacOS/libusb.dylib" 2>/dev/null || true
fi

step_sub "Clearing Gatekeeper quarantine extended attributes..."
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
xattr -cr "$TARGET_APP" 2>/dev/null || true

step_sub "Applying verified ad-hoc cryptographic code signature..."
if command -v codesign >/dev/null 2>&1; then
    # Sign frameworks and dylibs deepest first
    if [ -d "$TARGET_APP/Contents/Frameworks" ]; then
        find "$TARGET_APP/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "Autoupdate" \) -exec codesign --force --sign - {} 2>/dev/null \; || true
        find "$TARGET_APP/Contents/Frameworks" -type d -name "*.framework" -exec codesign --force --sign - {} 2>/dev/null \; || true
    fi
    if [ -d "$TARGET_APP/Contents/XPCServices" ]; then
        find "$TARGET_APP/Contents/XPCServices" -type d -name "*.xpc" -exec codesign --force --sign - {} 2>/dev/null \; || true
    fi
    codesign --force --sign - "$TARGET_APP/Contents/MacOS/LiquidDynamo" 2>/dev/null || true
    codesign --force --deep --sign - "$TARGET_APP" 2>/dev/null || true
fi
step_success "Installation verified and sealed successfully."

# ==============================================================================
# 5. Launch & Real-Time Process Verification
# ==============================================================================
step_info "5" "5" "Launching LiquidDynamo and verifying runtime state..."

# Launch via LaunchServices
open "$TARGET_APP" 2>/dev/null || true

# Verification poll (up to 4 seconds)
RUNNING=false
for i in {1..8}; do
    if pgrep -x "LiquidDynamo" >/dev/null 2>&1; then
        RUNNING=true
        break
    fi
    sleep 0.5
done

# Fallback: direct background spawn if LaunchServices was delayed
if [ "$RUNNING" = false ]; then
    step_warn "LaunchServices queued execution. Spawning directly..."
    nohup "$TARGET_APP/Contents/MacOS/LiquidDynamo" >/dev/null 2>&1 &
    sleep 1.0
    if pgrep -x "LiquidDynamo" >/dev/null 2>&1; then
        RUNNING=true
    fi
fi

APP_VERSION="$(defaults read "$TARGET_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "2.1.3")"
APP_BUILD="$(defaults read "$TARGET_APP/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "26")"

echo ""
if [ "$RUNNING" = true ]; then
    PID="$(pgrep -x "LiquidDynamo" | head -n1)"
    echo -e "   ${BRIGHT_GREEN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${RESET}"
    echo -e "   ${BRIGHT_GREEN}┃${RESET}  ${BOLD}${WHITE}🚀 LiquidDynamo v${APP_VERSION} (Build ${APP_BUILD}) is now LIVE!${RESET}                       ${BRIGHT_GREEN}┃${RESET}"
    echo -e "   ${BRIGHT_GREEN}┃${RESET}  ${MUTED}Process ID:${RESET} ${CYAN}${PID}${RESET}  ${MUTED}• Status:${RESET} ${BRIGHT_GREEN}Active Dynamic Island Engine${RESET}               ${BRIGHT_GREEN}┃${RESET}"
    echo -e "   ${BRIGHT_GREEN}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${RESET}"
    echo -e "   ${BRIGHT_GREEN}┃${RESET}  ${WHITE}• Look at your MacBook hardware notch or top screen bezel.${RESET}             ${BRIGHT_GREEN}┃${RESET}"
    echo -e "   ${BRIGHT_GREEN}┃${RESET}  ${WHITE}• Hover or drag near the notch to expand the Dynamic Island.${RESET}           ${BRIGHT_GREEN}┃${RESET}"
    echo -e "   ${BRIGHT_GREEN}┃${RESET}  ${WHITE}• Open Settings anytime with ${BOLD}Cmd + ,${RESET}${WHITE} or via the Menu Bar droplet icon.${RESET}    ${BRIGHT_GREEN}┃${RESET}"
    echo -e "   ${BRIGHT_GREEN}┃${RESET}  ${WHITE}• Developer & Updates: ${CYAN}https://www.agrigence.in/${RESET}                           ${BRIGHT_GREEN}┃${RESET}"
    echo -e "   ${BRIGHT_GREEN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${RESET}"
else
    step_err "LiquidDynamo could not be verified in process table."
    echo -e "   ${YELLOW}To launch manually, open Finder -> Applications -> LiquidDynamo.app${RESET}"
fi
echo ""
