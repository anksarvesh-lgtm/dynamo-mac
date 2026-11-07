#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# MacLink unified release build script
# Builds Android release APK and macOS desktop MacLink.app / DMG.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

TARGET="${1:-all}"
VERSION="$(awk -F'"' '/^\[workspace.package\]/{f=1} f && /^version = /{print $2; exit}' Cargo.toml)"
ARCH="$(uname -m)"
OUT_DIR="${REPO_ROOT}/dist"
mkdir -p "$OUT_DIR"

echo "=========================================================="
echo " MacLink Release Build (v${VERSION})"
echo " Target: ${TARGET} | Arch: ${ARCH}"
echo " Repo:   ${REPO_ROOT}"
echo "=========================================================="

# ---------------------------------------------------------------------------
# Setup toolchain environment
# ---------------------------------------------------------------------------
export PATH="${HOME}/.cargo/bin:${PATH}"

# Android SDK & NDK
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
    if [[ -d "${ANDROID_HOME}/ndk" ]]; then
        LATEST_NDK="$(ls -1 "${ANDROID_HOME}/ndk" 2>/dev/null | sort -V | tail -n 1 || echo "")"
        if [[ -n "$LATEST_NDK" ]]; then
            export ANDROID_NDK_HOME="${ANDROID_HOME}/ndk/${LATEST_NDK}"
        fi
    fi
fi

# Java Home
if [[ -z "${JAVA_HOME:-}" ]]; then
    for jvm in "${HOME}/.local/jdk21/Contents/Home" "/Library/Java/JavaVirtualMachines"/*/Contents/Home; do
        if [[ -x "${jvm}/bin/java" ]]; then
            export JAVA_HOME="${jvm}"
            break
        fi
    done
fi

# Qt 6
if [[ -z "${QT_ROOT_DIR:-}" ]]; then
    for candidate in "${HOME}/Qt"/6.*/macos /Users/*/Qt/6.*/macos /opt/homebrew/opt/qt6 /usr/local/opt/qt6; do
        if [[ -x "${candidate}/bin/macdeployqt" ]]; then
            export QT_ROOT_DIR="${candidate}"
            break
        fi
    done
fi

if [[ -n "${QT_ROOT_DIR:-}" && -x "${QT_ROOT_DIR}/bin/qmake" ]]; then
    export QMAKE="${QT_ROOT_DIR}/bin/qmake"
fi

# ---------------------------------------------------------------------------
# Android Build
# ---------------------------------------------------------------------------
build_android() {
    echo ""
    echo "[step 1/3] Building Android release APK..."
    command -v cargo-ndk >/dev/null || { echo "cargo-ndk is required: cargo install cargo-ndk" >&2; exit 1; }
    [[ -n "${JAVA_HOME:-}" ]] || { echo "JAVA_HOME must be set" >&2; exit 1; }
    [[ -n "${ANDROID_HOME:-}" ]] || { echo "ANDROID_HOME must be set" >&2; exit 1; }
    [[ -n "${ANDROID_NDK_HOME:-}" ]] || { echo "ANDROID_NDK_HOME must be set" >&2; exit 1; }

    echo "    Using Java:    $JAVA_HOME"
    echo "    Using Android: $ANDROID_HOME"
    echo "    Using NDK:     $ANDROID_NDK_HOME"

    (
        cd "${REPO_ROOT}/android"
        ./gradlew assembleRelease --no-daemon -Pmaclink.abis=arm64-v8a,x86_64
    )

    APK_SOURCE="${REPO_ROOT}/android/app/build/outputs/apk/release/app-release.apk"
    if [[ ! -f "$APK_SOURCE" ]]; then
        APK_SOURCE="${REPO_ROOT}/android/app/build/outputs/apk/release/app-release-unsigned.apk"
    fi

    APK_TARGET="${OUT_DIR}/MacLink-${VERSION}-android.apk"
    cp -f "$APK_SOURCE" "$APK_TARGET"
    echo "    Built: ${APK_TARGET} ($(du -h "$APK_TARGET" | awk '{print $1}'))"
}

# ---------------------------------------------------------------------------
# macOS Desktop Build
# ---------------------------------------------------------------------------
build_mac() {
    echo ""
    echo "[step 2/3] Building macOS desktop release binary & packaging..."
    [[ -n "${QT_ROOT_DIR:-}" ]] || { echo "QT_ROOT_DIR must be set or Qt 6 installed" >&2; exit 1; }
    echo "    Using Qt:      $QT_ROOT_DIR"

    echo "    Compiling maclink-desktop binary..."
    cargo build --release --bin maclink-desktop

    echo "    Packaging MacLink.app & MacLink-${VERSION}-macos-${ARCH}.dmg..."
    ./desktop/packaging/macos/build-app.sh
}

# ---------------------------------------------------------------------------
# Execution
# ---------------------------------------------------------------------------
case "$TARGET" in
    android)
        build_android
        ;;
    mac)
        build_mac
        ;;
    all)
        build_android
        build_mac
        ;;
    *)
        echo "Usage: $0 [android|mac|all]" >&2
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Checksums & Distribution
# ---------------------------------------------------------------------------
echo ""
echo "[step 3/3] Generating SHA-256 release checksums..."
(
    cd "$OUT_DIR"
    rm -f SHA256SUMS.txt
    # Hash release files (exclude MacLink.app folder)
    FILES=()
    for f in MacLink-${VERSION}-android.apk MacLink-${VERSION}-macos-${ARCH}.dmg MacLink-${VERSION}-macos-${ARCH}.zip; do
        if [[ -f "$f" ]]; then
            FILES+=("$f")
        fi
    done
    if [[ ${#FILES[@]} -gt 0 ]]; then
        shasum -a 256 "${FILES[@]}" > SHA256SUMS.txt
        cat SHA256SUMS.txt
    fi
)

# Sync with workspace root dist if running from subfolder
if [[ -d "${REPO_ROOT}/../dist" ]]; then
    echo "    Mirroring to ${REPO_ROOT}/../dist..."
    cp -Rf "${OUT_DIR}/"* "${REPO_ROOT}/../dist/"
fi

echo ""
echo "=========================================================="
echo " Build complete!"
ls -lh "$OUT_DIR"
echo "=========================================================="

