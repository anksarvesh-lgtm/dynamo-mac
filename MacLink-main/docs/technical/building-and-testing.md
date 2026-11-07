# Building and Testing

This document covers the pinned toolchain versions, environment variables, build commands, and test suites required to build and verify MacLink on Windows and Android.

## Pinned Toolchains

| Component | Required Version | Configuration File / Default Path |
|---|---|---|
| **Rust Toolchain** | `stable` (pinned in [`rust-toolchain.toml`](../../rust-toolchain.toml)) | [`rust-toolchain.toml`](../../rust-toolchain.toml) |
| **Rust Targets** | `x86_64-pc-windows-msvc`, `aarch64-pc-windows-msvc`, `aarch64-linux-android`, `x86_64-linux-android` | Installed via `rustup target add` |
| **MSVC Build Tools** | Visual Studio 2022 Build Tools (C++, `x64` and `ARM64/ARM64EC`) | Windows 11 SDK |
| **Qt 6** | `Qt 6.12` (`msvc2022_64` and `msvc2022_arm64`, QtQuick, QtQuickControls2, QtShaderTools, QtMultimedia) | `C:\Qt\6.12.0\msvc2022_64` / `msvc2022_arm64` |
| **JDK** | JDK `17` or newer (`21` supported) | `JAVA_HOME` |
| **Android SDK** | Platform `37` (`compileSdk = 37`, `targetSdk = 37`, `minSdk = 26` / Android 8.0) | `%LOCALAPPDATA%\Android\Sdk` |
| **Android NDK** | `30.0.16248370` (or side-by-side NDK configured in `android/app/build.gradle.kts`) | `%LOCALAPPDATA%\Android\Sdk\ndk` |
| **`cargo-ndk`** | `>= 3.5` | Used by Gradle (`buildRustAndroid`) to cross-compile `libmaclink_ffi.so` |
| **NSIS** | NSIS `3.x` (`makensis.exe`) | Used by `scripts/package.ps1` (`desktop/installer/maclink.nsi`) to build the Windows setup installer |

## Environment Variables

When building the Windows desktop client (`maclink-desktop`) or running workspace-wide `cargo` commands that compile `desktop/app`, ensure Qt's `bin` folder is on `PATH` or point `QMAKE` to its `qmake.exe`:

```powershell
$env:QMAKE = "C:\Qt\6.12.0\msvc2022_64\bin\qmake.exe"
$env:PATH  = "C:\Qt\6.12.0\msvc2022_64\bin;$env:PATH"
```

When building the Android native library or APK:

```powershell
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
```

Note: [`scripts/check.ps1`](../../scripts/check.ps1) and [`scripts/package.ps1`](../../scripts/package.ps1) automatically locate the installed Qt and Android SDK paths on Windows if the environment variables are not already set.

## Building Individual Components

### 1. Core Rust Crates and Headless CLI

The core crates (`maclink-protocol`, `maclink-core`, `maclink-ffi`, `maclink-cli`) do not depend on Qt and can be built on any machine with the Rust toolchain:

```powershell
cargo build -p maclink-protocol -p maclink-core -p maclink-ffi -p maclink-cli
```

To run the headless CLI (`cli/`):

```powershell
cargo run -p maclink-cli -- --help
```

### 2. Windows Desktop Application (`maclink-desktop`)

```powershell
# Debug build
cargo build -p maclink-desktop

# Release build (LTO = thin, codegen-units = 1, opt-level = 3)
cargo build --release -p maclink-desktop
```

The compiled executable is placed at `target/release/maclink-desktop.exe`.

### 3. Windows Virtual Camera DLL (`maclink-vcam`)

```powershell
cargo build --release -p maclink-vcam
```

Produces `target/release/maclink_vcam.dll`. To register the COM virtual camera for testing with video conferencing apps, run in an elevated PowerShell prompt:

```powershell
regsvr32.exe target\release\maclink_vcam.dll
```

### 4. Design Tokens and Third-Party Notices (`cargo xtask`)

[`tools/xtask`](../../tools/xtask/src/main.rs) generates platform design-system files from [`docs/design/tokens.json`](../../docs/design/tokens.json) and compiles the third-party license attribution bundle:

```powershell
# Regenerate desktop/app/src/bridge/theme_tokens.rs and android/.../DesignTokens.kt
cargo xtask tokens

# Verify generated token files are up to date without modifying disk
cargo xtask tokens --check

# Generate THIRD-PARTY-NOTICES.txt from Cargo.lock and Android dependencies
cargo xtask notices
```

### 5. Android Native Library, Kotlin Bindings, and APK

[`android/app/build.gradle.kts`](../../android/app/build.gradle.kts) registers `buildRustAndroid` and `generateUniffiBindings` tasks that automatically invoke `cargo ndk` (`arm64-v8a` and `x86_64`) and `uniffi-bindgen` before compiling Kotlin sources:

```powershell
Push-Location android
# Debug APK (builds arm64-v8a + x86_64 JNI libs and regenerates UniFFI Kotlin bindings):
.\gradlew.bat assembleDebug

# Fast single-ABI build for an attached arm64 phone:
.\gradlew.bat assembleDebug -Pabi=arm64-v8a

# Release APK:
.\gradlew.bat assembleRelease
Pop-Location
```

### 6. Full Release Packaging (`scripts/package.ps1`)

To stage the release desktop binary, `maclink_vcam.dll`, `windeployqt` Qt runtime DLLs and QML modules, `THIRD-PARTY-NOTICES.txt`, and Sparse Package manifest (`AppxManifest.xml`), and build the NSIS setup installer (`desktop/installer/maclink.nsi`):

```powershell
# Full release build + staging + NSIS installer (default x64):
powershell -ExecutionPolicy Bypass -File scripts\package.ps1

# Full release build + staging + NSIS installer for Windows 11 ARM64:
powershell -ExecutionPolicy Bypass -File scripts\package.ps1 -Arch arm64

# Stage files into target\package\MacLink\ without running makensis:
powershell -ExecutionPolicy Bypass -File scripts\package.ps1 -StageOnly
```

Artifacts are written to `target/package/`:
- `target/package/MacLink/` (staged portable directory)
- `target/package/MacLink-<version>-x64-setup.exe` or `MacLink-<version>-arm64-setup.exe` (NSIS installer when `makensis.exe` is installed)

## Running the Test Suites

### Full Pre-Commit Verification (`scripts/check.ps1`)

The canonical one-command verification script runs `cargo fmt --all -- --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`, `scripts/check-headers.ps1`, `cargo xtask tokens --check`, and `cargo deny`:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check.ps1

# Also verify Android NDK cross-compilation and Gradle assembleDebug:
powershell -ExecutionPolicy Bypass -File scripts\check.ps1 -Android -Arm64
```

### Targeted Rust Test Suites

```powershell
# Protocol framing, pairing SAS/QR proofs, and video packetization tests
cargo test -p maclink-protocol

# Core unit tests (SQLite store v7, send_queue FIFO/TTL/replacement, ADB/USB tunnel, OKLab palette, clipboard vault)
cargo test -p maclink-core --lib

# End-to-end two-device QUIC integration tests (pairing, capabilities, transfers, pause/resume)
cargo test -p maclink-core --test two_devices

# Scale benchmarks, opt-in (4 GiB transfer, 10,000 notifications, 5,000 timeline entries, encrypted clipboard history)
cargo test -p maclink-core --release --test scale_tests -- --ignored

# UniFFI binding round-trip tests
cargo test -p maclink-ffi

# Desktop notification store, localhost HTTP API auth/CORS guards, and vcam shared memory tests
cargo test -p maclink-desktop -p maclink-vcam
```

### Android Lint and Unit Tests

```powershell
Push-Location android
.\gradlew.bat compileDebugKotlin testDebugUnitTest
Pop-Location
```
