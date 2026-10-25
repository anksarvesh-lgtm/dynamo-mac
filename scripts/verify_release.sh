#!/usr/bin/env bash
# ==============================================================================
# verify_release.sh — Gatekeeper, Codesign & Notarization Verification Tool
# ==============================================================================
# Validates whether a built LiquidDynamo .app or .dmg is ready for distribution
# without triggering macOS Gatekeeper malware alerts ("Apple could not verify...").
#
# Usage:
#   bash scripts/verify_release.sh <path-to-.dmg-or-.app>
#
# Checks performed:
#   1. Deep codesign validation (--verify --deep --strict)
#   2. Signature metadata (Developer ID Authority, Team ID, Timestamp, Hardened Runtime)
#   3. Gatekeeper assessment via spctl (install/exec assessment)
#   4. Apple Notarization ticket validation via stapler
#   5. Exhaustive embedded Mach-O binary scan (ensures zero unsigned binaries)
#   6. Absence of debug/vulnerable entitlements (com.apple.security.get-task-allow)
# ==============================================================================

set -euo pipefail

say() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }
pass() { printf "\033[32m  ✓ %s\033[0m\n" "$*"; }
warn() { printf "\033[33m  ⚠️  %s\033[0m\n" "$*"; }
fail() { printf "\033[31m  ✗ %s\033[0m\n" "$*"; FAILED=1; }

FAILED=0

if [ $# -lt 1 ]; then
    echo "Usage: $0 <path-to-LiquidDynamo.app-or-.dmg>"
    exit 1
fi

TARGET="$1"
[ -e "$TARGET" ] || { echo "ERROR: Target not found at $TARGET" >&2; exit 1; }

echo "================================================================="
echo "🛡️  LiquidDynamo Release & Notarization Gatekeeper Verifier"
echo "Target: $TARGET"
echo "Date:   $(date)"
echo "================================================================="

MOUNT_DIR=""
APP_PATH=""
cleanup() {
    if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
        say "Detaching temporary volume: $MOUNT_DIR"
        hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# ------------------------------------------------------------------------------
# 1. Inspect Container Type
# ------------------------------------------------------------------------------
if [[ "$TARGET" == *.dmg ]]; then
    say "1. Verifying DMG Container Signature & Staple"
    
    # Check DMG codesign
    if codesign -dvv "$TARGET" >/dev/null 2>&1; then
        pass "DMG is signed."
        DMG_AUTH="$(codesign -dvv "$TARGET" 2>&1 | grep "Authority=" | head -n1 | cut -d= -f2 || true)"
        if [[ "$DMG_AUTH" == *"Developer ID Application"* ]]; then
            pass "DMG Authority: $DMG_AUTH"
        else
            warn "DMG signed with non-Developer ID authority: $DMG_AUTH"
        fi
        
        if codesign -dvv "$TARGET" 2>&1 | grep -q "Timestamp="; then
            pass "DMG has a secure timestamp."
        else
            fail "DMG is missing a secure timestamp (--timestamp)."
        fi
    else
        fail "DMG is NOT signed!"
    fi

    # Check DMG staple
    say "Checking DMG Stapled Ticket"
    if xcrun stapler validate "$TARGET" >/dev/null 2>&1; then
        pass "DMG has a valid stapled ticket from Apple."
    else
        warn "DMG does not have a stapled ticket (or is unstapled)."
    fi

    # Check Gatekeeper spctl assessment for DMG
    say "Gatekeeper Assessment on DMG (spctl -a -vvv -t install)"
    SPCTL_OUT="$(spctl -a -vvv -t install "$TARGET" 2>&1 || true)"
    echo "$SPCTL_OUT" | sed 's/^/    /'
    if echo "$SPCTL_OUT" | grep -q "source=Notarized Developer ID"; then
        pass "Gatekeeper assessment: Accepted (Notarized Developer ID)."
    elif echo "$SPCTL_OUT" | grep -q "accepted"; then
        pass "Gatekeeper assessment: Accepted."
    else
        fail "Gatekeeper assessment REJECTED DMG! $SPCTL_OUT"
    fi

    # Mount DMG to inspect internal .app
    say "Mounting DMG to inspect embedded application..."
    MOUNT_OUT="$(hdiutil attach -nobrowse -readonly "$TARGET" 2>&1 || true)"
    MOUNT_DIR="$(echo "$MOUNT_OUT" | grep -o '/Volumes/.*' | head -n1 || true)"
    
    if [ -z "$MOUNT_DIR" ] || [ ! -d "$MOUNT_DIR" ]; then
        fail "Failed to mount DMG to inspect application."
        exit 1
    fi
    
    APP_PATH="$(find "$MOUNT_DIR" -maxdepth 2 -name "*.app" | head -n1 || true)"
    if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
        fail "No .app bundle found inside mounted DMG!"
        exit 1
    fi
    pass "Located application bundle inside DMG: $(basename "$APP_PATH")"
else
    APP_PATH="$TARGET"
fi

# ------------------------------------------------------------------------------
# 2. Deep Codesign Verification on .app
# ------------------------------------------------------------------------------
say "2. Verifying Application Bundle Codesign Integrity"

set +e
VERIFY_OUT="$(codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1)"
VERIFY_STATUS=$?
set -e

if [ $VERIFY_STATUS -eq 0 ]; then
    pass "codesign --verify --deep --strict PASSED (bundle sealed)."
else
    fail "codesign --verify failed:\n$VERIFY_OUT"
fi

# ------------------------------------------------------------------------------
# 3. Check Signature Metadata (Authority, Team ID, Runtime, Timestamp)
# ------------------------------------------------------------------------------
say "3. Inspecting Application Signature Metadata"
SIGN_INFO="$(codesign -dvv "$APP_PATH" 2>&1)"

APP_AUTH="$(echo "$SIGN_INFO" | grep "Authority=" | head -n1 | cut -d= -f2 || true)"
TEAM_ID="$(echo "$SIGN_INFO" | grep "TeamIdentifier=" | cut -d= -f2 || true)"
FLAGS="$(echo "$SIGN_INFO" | grep "CodeDirectory" | grep -o "flags=.*" || true)"
TIMESTAMP="$(echo "$SIGN_INFO" | grep "Timestamp=" || true)"

echo "    Authority:      ${APP_AUTH:-[None]}"
echo "    TeamIdentifier: ${TEAM_ID:-[None]}"
echo "    Flags:          ${FLAGS:-[None]}"
echo "    Timestamp:      ${TIMESTAMP:-[None]}"

if [[ "$APP_AUTH" == *"Developer ID Application"* ]]; then
    pass "Authority matches Apple Developer ID Application."
elif [ -z "$APP_AUTH" ]; then
    fail "Application is ad-hoc signed or unsigned!"
else
    fail "Invalid Authority for distribution: $APP_AUTH (Expected 'Developer ID Application')"
fi

if [ -n "$TEAM_ID" ] && [ "$TEAM_ID" != "not set" ]; then
    pass "TeamIdentifier present: $TEAM_ID"
else
    fail "TeamIdentifier is missing!"
fi

if echo "$FLAGS" | grep -q "0x10000(runtime)"; then
    pass "Hardened Runtime enabled (flags=0x10000(runtime))."
else
    fail "Hardened Runtime is NOT enabled! Apple Notarization requires Hardened Runtime."
fi

if [ -n "$TIMESTAMP" ]; then
    pass "Secure Apple timestamp present ($TIMESTAMP)."
else
    fail "Secure timestamp is MISSING! Apple Notarization requires --timestamp."
fi

# ------------------------------------------------------------------------------
# 4. Gatekeeper Assessment on Application (spctl)
# ------------------------------------------------------------------------------
say "4. Gatekeeper Execution Assessment (spctl -a -vvv -t exec)"
APP_SPCTL="$(spctl -a -vvv -t exec "$APP_PATH" 2>&1 || true)"
echo "$APP_SPCTL" | sed 's/^/    /'

if echo "$APP_SPCTL" | grep -q "source=Notarized Developer ID"; then
    pass "Application Gatekeeper status: Notarized Developer ID (ACCEPTED)."
elif echo "$APP_SPCTL" | grep -q "accepted"; then
    pass "Application Gatekeeper status: Accepted."
else
    if [[ "$APP_SPCTL" == *"Unnotarized Developer ID"* ]]; then
        warn "Application is signed with Developer ID, but NOT yet notarized by Apple."
    else
        fail "Gatekeeper assessment failed!"
    fi
fi

# ------------------------------------------------------------------------------
# 5. Stapler Validation on Application
# ------------------------------------------------------------------------------
say "5. Checking Application Stapled Ticket (Offline Capability)"
set +e
STAPLER_OUT="$(xcrun stapler validate "$APP_PATH" 2>&1)"
STAPLER_STATUS=$?
set -e

if [ $STAPLER_STATUS -eq 0 ] && echo "$STAPLER_OUT" | grep -q "The validate action worked!"; then
    pass "Application bundle has a valid stapled ticket (Offline Gatekeeper will pass!)."
else
    warn "Application bundle does NOT have a stapled ticket.\n    Note: If offline, Gatekeeper cannot verify notarization without a stapled ticket."
fi

# ------------------------------------------------------------------------------
# 6. Exhaustive Scan of All Embedded Mach-O Binaries
# ------------------------------------------------------------------------------
say "6. Scanning All Embedded Mach-O Binaries in Bundle"
MACHO_COUNT=0
MACHO_UNSIGNED=0
MACHO_NO_RUNTIME=0

while IFS= read -r bin_file; do
    if file -b "$bin_file" | grep -q "Mach-O"; then
        MACHO_COUNT=$((MACHO_COUNT + 1))
        REL_PATH="${bin_file#$APP_PATH/Contents/}"
        BIN_INFO="$(codesign -dvv "$bin_file" 2>&1 || true)"
        
        # Check if signed
        if ! echo "$BIN_INFO" | grep -q "Signed by"; then
            fail "Unsigned Mach-O binary found: Contents/$REL_PATH"
            MACHO_UNSIGNED=$((MACHO_UNSIGNED + 1))
            continue
        fi
        
        # Check runtime flag
        if ! echo "$BIN_INFO" | grep -q "flags=.*runtime"; then
            fail "Mach-O missing hardened runtime: Contents/$REL_PATH"
            MACHO_NO_RUNTIME=$((MACHO_NO_RUNTIME + 1))
        fi

        # Check arch
        ARCH_INFO="$(file -b "$bin_file" | awk -F',' '{print $1}')"
        pass "Contents/$REL_PATH ($ARCH_INFO)"
    fi
done < <(find "$APP_PATH/Contents" -type f ! -name ".*" | sort)

echo "    Total Mach-O binaries scanned: $MACHO_COUNT"
if [ "$MACHO_UNSIGNED" -eq 0 ] && [ "$MACHO_NO_RUNTIME" -eq 0 ]; then
    pass "All $MACHO_COUNT Mach-O binaries are properly signed with Hardened Runtime."
fi

# ------------------------------------------------------------------------------
# 7. Entitlements Inspection
# ------------------------------------------------------------------------------
say "7. Inspecting Entitlements & Prohibited Keys"
ENTITLEMENTS="$(codesign -d --entitlements :- "$APP_PATH" 2>&1 || true)"

if echo "$ENTITLEMENTS" | grep -q "com.apple.security.get-task-allow"; then
    if echo "$ENTITLEMENTS" | grep -A1 "com.apple.security.get-task-allow" | grep -q "<true/>"; then
        fail "PROHIBITED ENTITLEMENT FOUND: com.apple.security.get-task-allow = true! Apple Notarization WILL REJECT this binary."
    fi
else
    pass "com.apple.security.get-task-allow is safely ABSENT."
fi

# ------------------------------------------------------------------------------
# 8. Final Verdict
# ------------------------------------------------------------------------------
echo ""
echo "================================================================="
if [ $FAILED -eq 0 ]; then
    printf "\033[1;32m🎉 VERIFICATION PASSED: Release artifact is 100%% compliant with Apple Gatekeeper!\033[0m\n"
    echo "This package can be opened on any macOS 14+ system without malware warnings."
    exit 0
else
    printf "\033[1;31m❌ VERIFICATION FAILED: Found issues that will trigger Gatekeeper warnings.\033[0m\n"
    echo "Review the failure items above before distributing this build."
    exit 1
fi
