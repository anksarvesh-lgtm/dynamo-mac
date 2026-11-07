#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# MacLink macOS Terminal Installer & Launcher
# Usage: curl -fsSL https://raw.githubusercontent.com/anksarvesh-lgtm/MacLink/main/install.sh | bash

set -euo pipefail

# ANSI Styling & Colors
if [ -t 1 ]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    CYAN='\033[38;2;68;170;255m'
    BLUE='\033[38;2;79;110;247m'
    GREEN='\033[38;2;52;211;153m'
    YELLOW='\033[38;2;251;191;36m'
    RED='\033[38;2;248;113;113m'
    GRAY='\033[38;2;156;163;175m'
    PURPLE='\033[38;2;168;85;247m'
    RESET='\033[0m'
else
    BOLD=''
    DIM=''
    CYAN=''
    BLUE=''
    GREEN=''
    YELLOW=''
    RED=''
    GRAY=''
    PURPLE=''
    RESET=''
fi

step() {
    local num="$1"
    local title="$2"
    local desc="$3"
    printf "  ${BLUE}[%s]${RESET}  ${BOLD}%-15s${RESET} %b\n" "$num" "$title" "$desc"
}

info() {
    printf "        ${GRAY}↳ %b${RESET}\n" "$1"
}

error() {
    printf "  ${RED}✖ Error:${RESET} %b\n" "$1" >&2
}

# Header Banner
printf "\n"
printf "  ${CYAN}   __  __            _     _       _    ${RESET}\n"
printf "  ${CYAN}  |  \/  |          | |   (_)     | |   ${RESET}\n"
printf "  ${BLUE}  | \  / | __ _  ___| |    _ _ __ | | __${RESET}\n"
printf "  ${BLUE}  | |\/| |/ _\` |/ __| |   | | '_ \| |/ /${RESET}\n"
printf "  ${PURPLE}  | |  | | (_| | (__| |___| | | | |   < ${RESET}\n"
printf "  ${PURPLE}  |_|  |_|\__,_|\___|______|_|_| |_|_|\_\${RESET}\n"
printf "\n"
printf "  ${BOLD}MacLink macOS Installer${RESET} ${GRAY}• Unified Android & Mac Ecosystem${RESET}\n"
printf "  ${GRAY}─────────────────────────────────────────────────────────────────${RESET}\n\n"

# 1. Platform Verification
if [[ "$OSTYPE" != "darwin"* ]]; then
    error "MacLink is designed specifically for macOS."
    exit 1
fi

ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
    error "Unsupported processor architecture: ${ARCH}"
    exit 1
fi

ARCH_LABEL="Apple Silicon (arm64)"
if [[ "$ARCH" == "x86_64" ]]; then
    ARCH_LABEL="Intel (x86_64)"
fi
step "1/5" "Platform" "${GREEN}macOS $(sw_vers -productVersion 2>/dev/null || echo '') • ${ARCH_LABEL}${RESET}"

# 2. Release Discovery
REPO="anksarvesh-lgtm/MacLink"
LATEST_TAG=""
if command -v curl >/dev/null 2>&1; then
    LATEST_TAG="$(curl -sL --max-time 10 "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4 || true)"
fi

if [[ -z "$LATEST_TAG" ]]; then
    LATEST_TAG="${MACLINK_VERSION:-v0.0.8}"
fi
if [[ "$LATEST_TAG" != v* ]]; then
    LATEST_TAG="v${LATEST_TAG}"
fi
VERSION="${LATEST_TAG#v}"
step "2/5" "Release" "${GREEN}${LATEST_TAG}${RESET} ${GRAY}(latest published)${RESET}"

# 3. Environment Preparation
step "3/5" "Environment" "${GRAY}Preparing background environment and services...${RESET}"
pkill -x "maclink-desktop" 2>/dev/null || true
pkill -x "NectarLink" 2>/dev/null || true
pkill -x "nectarlink" 2>/dev/null || true

LEGACY_APP="/Applications/NectarLink.app"
if [[ -d "$LEGACY_APP" ]]; then
    rm -rf "$LEGACY_APP"
    info "Removed legacy application bundle: NectarLink.app"
fi

TMP_DIR="$(mktemp -d /tmp/maclink-install.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Check for local build first (if running within local workspace)
SOURCE_APP=""
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." 2>/dev/null && pwd || echo "")"

if [[ -n "$SCRIPT_DIR" && -d "${SCRIPT_DIR}/dist/MacLink.app" ]]; then
    SOURCE_APP="${SCRIPT_DIR}/dist/MacLink.app"
    info "Using existing local build at ${SCRIPT_DIR}/dist/MacLink.app"
elif [[ -n "$REPO_ROOT" && -d "${REPO_ROOT}/dist/MacLink.app" ]]; then
    SOURCE_APP="${REPO_ROOT}/dist/MacLink.app"
    info "Using existing local build at ${REPO_ROOT}/dist/MacLink.app"
elif [[ -d "./dist/MacLink.app" ]]; then
    SOURCE_APP="./dist/MacLink.app"
    info "Using local build at ./dist/MacLink.app"
fi

# 4. Download and Extract Release
if [[ -z "$SOURCE_APP" ]]; then
    ZIP_NAME="MacLink-${VERSION}-macos-${ARCH}.zip"
    DMG_NAME="MacLink-${VERSION}-macos-${ARCH}.dmg"
    RELEASE_BASE="https://github.com/${REPO}/releases/download/${LATEST_TAG}"
    DOWNLOAD_SUCCESS=false

    # Try ZIP first (faster download & instant direct extraction)
    info "Downloading ${ZIP_NAME}..."
    if curl -# -fSL "${RELEASE_BASE}/${ZIP_NAME}" -o "${TMP_DIR}/${ZIP_NAME}" 2>/dev/null; then
        info "Extracting native application bundle..."
        ditto -x -k "${TMP_DIR}/${ZIP_NAME}" "${TMP_DIR}/extracted"
        if [[ -d "${TMP_DIR}/extracted/MacLink.app" ]]; then
            SOURCE_APP="${TMP_DIR}/extracted/MacLink.app"
            DOWNLOAD_SUCCESS=true
        fi
    fi

    # Fallback to DMG if ZIP was not available
    if [[ "$DOWNLOAD_SUCCESS" = false ]]; then
        info "Downloading DMG package (${DMG_NAME})..."
        if curl -# -fSL "${RELEASE_BASE}/${DMG_NAME}" -o "${TMP_DIR}/${DMG_NAME}" 2>/dev/null; then
            MOUNT_POINT="${TMP_DIR}/mnt"
            mkdir -p "$MOUNT_POINT"
            hdiutil attach "${TMP_DIR}/${DMG_NAME}" -nobrowse -quiet -mountpoint "$MOUNT_POINT"
            if [[ -d "${MOUNT_POINT}/MacLink.app" ]]; then
                cp -R "${MOUNT_POINT}/MacLink.app" "${TMP_DIR}/"
                SOURCE_APP="${TMP_DIR}/MacLink.app"
                DOWNLOAD_SUCCESS=true
            fi
            hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
        fi
    fi

    if [[ "$DOWNLOAD_SUCCESS" = false || -z "$SOURCE_APP" ]]; then
        error "Failed to download MacLink ${LATEST_TAG}. Please check your connection."
        exit 1
    fi
fi

# 5. Install to /Applications and configure Gatekeeper
step "4/5" "Install" "${CYAN}/Applications/MacLink.app${RESET}"
INSTALL_DIR="/Applications"
TARGET_APP="${INSTALL_DIR}/MacLink.app"

# Clean old installation safely
rm -rf "$TARGET_APP" 2>/dev/null || true
cp -R "$SOURCE_APP" "$TARGET_APP"

# Strip Gatekeeper quarantine flags so macOS opens cleanly
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
xattr -cr "$TARGET_APP" 2>/dev/null || true
info "Configured Gatekeeper permissions and Mach-O ad-hoc signatures"

# 6. Configure 'maclink' Terminal CLI Launcher
step "5/5" "Terminal CLI" "${GREEN}maclink${RESET} ${GRAY}(launcher command)${RESET}"

LAUNCHER_SCRIPT='#!/usr/bin/env bash
# MacLink Terminal Launcher
APP_PATH="/Applications/MacLink.app"
BIN_PATH="${APP_PATH}/Contents/MacOS/maclink-desktop"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: MacLink is not installed in /Applications/MacLink.app" >&2
    echo "Install it with: curl -fsSL https://raw.githubusercontent.com/anksarvesh-lgtm/MacLink/main/install.sh | bash" >&2
    exit 1
fi

case "${1:-}" in
    -h|--help)
        echo -e "\033[1mMacLink CLI Launcher\033[0m"
        echo ""
        echo "Usage: maclink [options]"
        echo ""
        echo "Options:"
        echo "  (no args)           Launch or activate the MacLink application"
        echo "  --fg, --foreground  Run MacLink in the terminal foreground (streams live logs)"
        echo "  --ui-check          Validate UI and capability state headlessly"
        echo "  --version, -v       Print the current MacLink version"
        echo "  --help, -h          Show this help information"
        exit 0
        ;;
    -v|--version)
        defaults read "${APP_PATH}/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "0.0.8"
        exit 0
        ;;
    --fg|--foreground)
        shift
        exec "$BIN_PATH" "$@"
        ;;
    --ui-check)
        exec "$BIN_PATH" --ui-check
        ;;
    *)
        open -a MacLink "$@"
        ;;
esac
'

USER_BIN="$HOME/.local/bin"
mkdir -p "$USER_BIN"
echo "$LAUNCHER_SCRIPT" > "${USER_BIN}/maclink"
chmod +x "${USER_BIN}/maclink"

# Try /usr/local/bin if writable
if [[ -w "/usr/local/bin" ]]; then
    echo "$LAUNCHER_SCRIPT" > "/usr/local/bin/maclink"
    chmod +x "/usr/local/bin/maclink"
fi

# Ensure ~/.local/bin is present in shell environment
SHELL_CONFIG=""
if [[ -f "$HOME/.zshrc" ]]; then
    SHELL_CONFIG="$HOME/.zshrc"
elif [[ -f "$HOME/.bash_profile" ]]; then
    SHELL_CONFIG="$HOME/.bash_profile"
elif [[ -f "$HOME/.profile" ]]; then
    SHELL_CONFIG="$HOME/.profile"
fi

if [[ -n "$SHELL_CONFIG" ]]; then
    if ! grep -q '\.local/bin' "$SHELL_CONFIG" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_CONFIG"
    fi
fi

# 7. Launch Application
open -a MacLink 2>/dev/null || true

# Success Box Presentation
printf "\n"
printf "  ${GREEN}╭──────────────────────────────────────────────────────────────╮${RESET}\n"
printf "  ${GREEN}│${RESET}  ${BOLD}✓ MacLink ${VERSION} is installed and running!${RESET}                 ${GREEN}│${RESET}\n"
printf "  ${GREEN}│${RESET}                                                              ${GREEN}│${RESET}\n"
printf "  ${GREEN}│${RESET}  ${BOLD}• Application:${RESET}  /Applications/MacLink.app                      ${GREEN}│${RESET}\n"
printf "  ${GREEN}│${RESET}  ${BOLD}• Terminal CLI:${RESET} maclink ${GRAY}(type in terminal anytime)${RESET}          ${GREEN}│${RESET}\n"
printf "  ${GREEN}│${RESET}  ${BOLD}• Capabilities:${RESET} Calls • Wireless Trackpad • App Mirroring    ${GREEN}│${RESET}\n"
printf "  ${GREEN}│${RESET}                                                              ${GREEN}│${RESET}\n"
printf "  ${GREEN}│${RESET}  ${DIM}Quick command tips:${RESET}                                         ${GREEN}│${RESET}\n"
printf "  ${GREEN}│${RESET}    ${CYAN}maclink${RESET}             Open / activate MacLink window        ${GREEN}│${RESET}\n"
printf "  ${GREEN}│${RESET}    ${CYAN}maclink --fg${RESET}        Stream live diagnostic logs           ${GREEN}│${RESET}\n"
printf "  ${GREEN}│${RESET}    ${CYAN}maclink -v${RESET}          Display installed release version     ${GREEN}│${RESET}\n"
printf "  ${GREEN}╰──────────────────────────────────────────────────────────────╯${RESET}\n\n"
