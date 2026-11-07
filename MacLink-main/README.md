<div align="center">

<img src="assets/brand/icon-512.png" alt="MacLink Icon" width="128" height="128">

# MacLink

**Your Android phone and your Mac, working seamlessly as one.**

Notifications, messages, phone calls, bidirectional clipboard, gigabit file transfers, photo library access, and low-latency hardware-accelerated screen mirroring between Android and macOS.

*Local-first • Zero-Cloud • End-to-End Encrypted via QUIC & TLS 1.3 • Apple Liquid Glass Edition*

---

[![Latest Release](https://img.shields.io/github/v/release/anksarvesh-lgtm/MacLink?style=flat-square&color=F49D04&label=Release)](https://github.com/anksarvesh-lgtm/MacLink/releases)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS%20(Apple%20Silicon%20%26%20Intel)-black.svg?style=flat-square&logo=apple)](desktop/packaging/macos/build-app.sh)
[![Platform: Android](https://img.shields.io/badge/Platform-Android%20(API%2026%2B)-3DDC84.svg?style=flat-square&logo=android&logoColor=white)](android/)
[![Package ID: in.maclink.srv](https://img.shields.io/badge/Package%20ID-in.maclink.srv-CB7501.svg?style=flat-square)](core/maclink-core/src/session.rs)
[![Rust: 1.80+](https://img.shields.io/badge/Rust-1.80+-orange.svg?style=flat-square&logo=rust)](rust-toolchain.toml)
[![Qt: 6.8+](https://img.shields.io/badge/Qt-6.8+-41CD52.svg?style=flat-square&logo=qt)](desktop/app/)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/License-GPL--3.0--or--later-blue.svg?style=flat-square)](LICENSES/GPL-3.0-or-later.txt)

</div>

---

## 📸 Visual Showcase

<div align="center">

### Desktop Interface (macOS · Amber Liquid Glass)
<img src="assets/screenshots/desktop-home.png" alt="MacLink Desktop Home Screen" width="950" style="border-radius: 12px; box-shadow: 0 16px 36px rgba(0,0,0,0.5);">

<br/><br/>

### Mobile Interface (Android · Liquid Glass Edition)
<img src="assets/screenshots/android-liquid-glass.jpg" alt="MacLink Android Mobile Screen" width="420" style="border-radius: 16px; box-shadow: 0 16px 36px rgba(0,0,0,0.5);">

</div>

---

## ✨ Key Capabilities

- **Apple Liquid Glass Aesthetic**: Crafted with physical optical properties—Snell refraction, chromatic dispersion along borders, dual-axis warm specular highlights, and natural spring motion in deep amber/warm charcoal surfaces.
- **Strict Package Verification Gate**: Handshakes enforce cryptographically verified package identities (`in.maclink.srv`). Mismatched or spoofed clients are rejected before session creation.
- **Live Notification Mirroring**: Push notifications from Android directly to macOS with interactive inline quick-replies, dismiss-sync, and one-tap OTP verification code clipboard copying.
- **Unified SMS & Messaging**: Read and compose SMS, RCS, and chat threads directly in a fluid desktop interface with photo attachment support.
- **Phone Calls & Dialer**: Receive caller ID alerts, accept or reject incoming phone calls from your Mac, dial contacts directly, and route phone audio.
- **End-to-End Encrypted Clipboard Sync**: Bidirectional real-time clipboard sharing for text and images with automatic sensitive credential filtering (passwords, auth tokens).
- **Gigabit Drag-and-Drop File Transfers**: Transfer folders and multi-gigabyte files over local Wi-Fi or USB with BLAKE3 integrity verification and automatic transfer resume.
- **Phone Screen Mirroring & PC Control**: Hardware-accelerated 60 FPS H.264 display streaming with sub-frame input latency, keyboard navigation, and touch simulation.
- **Audio Routing & Media Handoff**: Control music playback across Spotify, YouTube Music, and local media; toggle playback, adjust volume, or route audio output.
- **Zero-Dependency FTP File Server & macOS Finder Mount**: Powered by embedded MinimalFTP on Android and one-ftpserver compatibility. Mount your Android phone storage directly in macOS Finder (`Go › Connect to Server › ftp://...`) as a native volume, or browse and transfer files with FileZilla, Cyberduck, or terminal clients over Wi-Fi.
- **Device Management & Power Controls**: Ring phone to find it, trigger DND, flashlight, battery health monitoring, lock PC, and trigger sleep mode remotely.

---

## 🏛️ System Architecture

MacLink utilizes a memory-safe, shared Rust core powering both native frontends via zero-overhead foreign function interfaces (FFI).

```mermaid
flowchart TD
    subgraph Android["Android Application (Kotlin + Jetpack Compose)"]
        UI_A["Compose UI + AGSL Liquid Glass Shaders"]
        SVC_A["Android System Services (NotificationListener, MediaSession, Telecom)"]
        UNI_A["UniFFI JNI Bridge"]
        UI_A --> UNI_A
        SVC_A --> UNI_A
    end

    subgraph Core["Shared Cross-Platform Core (Rust)"]
        direction TB
        CORE_A["maclink-core (Android Runtime)"]
        PROTO["maclink-protocol (CBOR Serialization, Enums, Caps)"]
        CRYPTO["Cryptography (Ed25519, TLS 1.3, BLAKE3, SAS)"]
        TRANS["Transport Engine (iroh QUIC + Multiplexed Streams)"]
        CORE_M["maclink-core (macOS Runtime)"]
        
        CORE_A --- PROTO
        CORE_A --- CRYPTO
        CORE_A --- TRANS
        
        CORE_M --- PROTO
        CORE_M --- CRYPTO
        CORE_M --- TRANS
    end

    subgraph macOS["macOS Desktop Application (Qt 6 + C++ + Rust)"]
        UNI_M["cxx-qt C++ / Rust Bridge"]
        QML_M["Qt Quick QML + Amber Liquid Glass Shaders"]
        NATIVE_M["macOS Native Frameworks (UserNotifications, IOKit, AVFoundation)"]
        UNI_M --> QML_M
        NATIVE_M --> UNI_M
    end

    UNI_A <===>|"FFI Bindings"| CORE_A
    UNI_M <===>|"cxx-qt Bridge"| CORE_M

    CORE_A <===>|"Encrypted Peer-to-Peer QUIC Tunnel\nLocal Wi-Fi 5GHz/6GHz or USB Cable"| CORE_M
```

---

## 🔐 Cryptographic Handshake & Protocol Flow

Every connection guarantees zero external server interaction, mutual authentication, and cryptographic channel binding.

```mermaid
sequenceDiagram
    autonumber
    participant Phone as Android (in.maclink.srv)
    participant CoreP as Phone Rust Core
    participant CoreM as Mac Rust Core
    participant Mac as macOS (MacLink.app)

    Note over Phone,Mac: Discovery & Transport Handshake
    CoreP->>CoreM: mDNS / LAN Broadcast (Ed25519 Peer ID)
    CoreM->>CoreP: QUIC Connection Request (ALPN: maclink/0)
    CoreP-->>CoreM: TLS 1.3 Handshake (Ed25519 Ephemeral Keys)

    Note over Phone,Mac: Package Verification & Security Gate
    CoreM->>CoreP: HandshakeInit(package: "in.maclink.srv", nonce, protocol: 0)
    CoreP->>CoreM: HandshakeResp(package: "in.maclink.srv", signature, caps)
    
    alt Package Mismatch or Invalid Signature
        CoreM-->>CoreP: Terminate Session (Reject Connection)
    else Package Verified
        CoreM->>Mac: Display SAS / Compare QR Fingerprint
        CoreP->>Phone: Display SAS / Verify Fingerprint
        Note over Phone,Mac: Out-of-Band SAS Verification (Visual Match)
    end

    Note over Phone,Mac: Active Multiplexed Streams
    CoreP->>CoreM: Stream 1: Device State & Battery (CBOR)
    CoreP->>CoreM: Stream 2: Push Notifications & Live OTP
    CoreM->>CoreP: Stream 3: Encrypted Clipboard Sync
    CoreP->>CoreM: Stream 4: H.264 Video Mirroring (60 FPS)
    CoreM->>CoreP: Stream 5: High-Speed File Chunks (BLAKE3 Hashed)
```

---

## 🎨 Liquid Glass Design System (Amber Edition)

MacLink features a warm, physical glass design tokens system crafted to match modern macOS window aesthetics:

```mermaid
flowchart LR
    WP["Desktop / Wallpaper Surface"] --> BLUR["Volumetric Gaussian Blur (28px - 48px)"]
    BLUR --> TINT["Translucent Amber Tint (#221A0F @ 78%)"]
    TINT --> BORDER["Subtle Specular Border (#FFFFFF @ 12%)"]
    BORDER --> GLOW["Warm Inner Radiance (#F49D04 @ 15%)"]
    GLOW --> CONTENT["High-Contrast Typography (#F3F0E8 / #FFFFFF)"]
```

### Color Palette

| Token | Hex Value | Role |
| :--- | :--- | :--- |
| **Deep Background** | `#1A1008` | Canvas foundation, dark contrast floor |
| **Glass Background** | `#221A0F` | Translucent frosted glass card body |
| **Dark Amber** | `#603606` | Ambient gradient accent, subtle glow base |
| **Burnt Orange** | `#894F03` | Active card borders, energetic illumination |
| **Brown Surface** | `#6D4510` | Elevated glass controls and buttons |
| **Primary Accent** | `#F49D04` | Focus rings, status indicators, badges |
| **Highlight Yellow** | `#FFB52E` | Specular reflection, star ratings, active states |
| **Text Primary** | `#F3F0E8` | High-contrast readable typography (100% white-gold) |
| **Text Secondary** | `#B5A18B` | Labels, captions, timestamps, secondary data |
| **Text Muted** | `#897360` | Inactive hints, disabled states, subtle borders |

---

## ⚡ Capability Matrix

| Feature | Protocol Capability | macOS Support | Android Support | Encryption |
| :--- | :--- | :---: | :---: | :---: |
| **Device Battery & Health** | `device.battery` | Receive & Display | Broadcast & Charge ETA | TLS 1.3 |
| **Notification Mirroring** | `notify.mirror` | Inline Action & View | Capture & Remote Dismiss | TLS 1.3 |
| **SMS / RCS Messaging** | `sms.read`, `sms.send` | Full Desktop Chat | Carrier Transport Gateway | TLS 1.3 |
| **Phone Calls & Audio** | `call.state`, `call.control` | Caller ID & Remote Dial | Telephony Manager | TLS 1.3 |
| **Encrypted Clipboard** | `clip.write`, `clip.share` | Bidirectional Sync | Bidirectional Sync | TLS 1.3 |
| **High-Speed File Transfer** | `files.transfer` | Drag-and-Drop Hub | SAF File System | BLAKE3 + TLS |
| **60 FPS Screen Mirror** | `mirror.capture`, `mirror.view` | Hardware Decode Window | MediaProjection H.264 | TLS 1.3 |
| **Remote Touch & Type** | `mirror.input` | Trackpad & Keyboard | Accessibility Dispatcher | TLS 1.3 |
| **Zero-Config FTP Server** | `files.ftp`, `storage.read` | macOS Finder Mount | Embedded MinimalFTP | TLS / WPA3 |
| **Remote System Toggles** | `toggles.*` (DND/Torch/BT/Wi-Fi)| Controls Palette | Device Settings Provider | TLS 1.3 |

---

## ⚡ One-Line Install & Launch (macOS)

Install MacLink and launch it immediately from your terminal with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/anksarvesh-lgtm/MacLink/main/install.sh | bash
```

**What this one-liner does automatically:**
1. 🔍 Detects your macOS architecture (Apple Silicon `arm64` / Intel `x86_64`).
2. 📦 Downloads and verifies the latest release (`v0.0.6`) from GitHub.
3. 🚀 Installs `MacLink.app` to `/Applications/MacLink.app` and removes Gatekeeper quarantine.
4. ⚙️ Installs the `maclink` CLI helper to `~/.local/bin/maclink` (and `/usr/local/bin` if permitted).
5. ✨ Opens MacLink immediately!

### 💻 Terminal CLI Usage
Once installed, open or control MacLink anytime directly from your terminal:

```bash
maclink            # Launch or bring MacLink to front
maclink --ui-check # Run headless UI verification
maclink --version  # Print version
maclink --help     # Display CLI options
```

---

## 🛠️ Building & Installing

### Requirements
- **macOS**: Sonoma 14.0+ or Sequoia 15.0+ (Apple Silicon or Intel)
- **Rust**: 1.80+ (`rustup toolchain install stable`)
- **Qt SDK**: Qt 6.8+ (Homebrew or official installer)
- **Android SDK**: API 34+, NDK `30.0.16248370`, JDK 21

### 1. Prebuilt Binaries

Download ready-to-run releases from the [Releases Page](https://github.com/anksarvesh-lgtm/MacLink/releases):
- **macOS**: `MacLink-0.0.6-macos-arm64.dmg` or `.zip`
- **Android**: `MacLink-0.0.6-android.apk`
- **Verification**: `SHA256SUMS.txt`

### 2. Build macOS App from Source

```bash
# Clone the repository
git clone https://github.com/anksarvesh-lgtm/MacLink.git
cd MacLink/nectarlink

# Build release binaries
QT_ROOT_DIR=~/Qt/6.8.2/macos cargo build --release --bin maclink-desktop

# Package MacLink.app bundle and DMG
./desktop/packaging/macos/build-app.sh
```

The resulting `MacLink.app` and `MacLink-0.0.5.dmg` will be placed in `dist/`.

### 3. Build Android App from Source

```bash
cd android

# Install Rust Android toolchain
rustup target add aarch64-linux-android
cargo install cargo-ndk

# Compile APK
./gradlew assembleDebug -Pmaclink.abis=arm64-v8a
```

Compiled APK will be located at:
`android/app/build/outputs/apk/debug/app-debug.apk`.

### 4. Run Test Suite

```bash
cargo test -p maclink-protocol -p maclink-core -p maclink-cli
```

---

## 🔒 Security & Privacy Guarantees

1. **Zero Cloud Infrastructure**: MacLink operates 100% peer-to-peer. There are no registration accounts, no analytics tracking, no remote relay servers, and no telemetry sent anywhere.
2. **Ed25519 Identity Keys**: All devices generate cryptographic keys stored in the Apple Keychain or Android EncryptedSharedPreferences.
3. **Short Authentication String (SAS)**: Man-in-the-middle attacks are prevented by visual SAS matching or cryptographic QR verification during initial pairing.
4. **Credential Isolation**: Clipboards containing sensitive data (passwords, 2FA codes, hidden clipboard flags) are strictly sanitized according to user preferences.

---

## 📂 Repository Structure

```text
MacLink/
├── android/                    # Android application (Kotlin, Jetpack Compose, AGSL)
│   ├── app/src/main/kotlin/   # UI pages, services, notification listeners
│   └── app/src/main/res/      # Drawables, layouts, vector assets
├── assets/                     # Brand icons, typography, and screenshots
│   ├── brand/                 # SVG, PNG, and ICNS logo assets
│   └── screenshots/           # High-resolution desktop and mobile graphics
├── core/
│   ├── maclink-core/          # QUIC engine, session state, storage, crypto
│   ├── maclink-protocol/      # Type-safe protocol messages, CBOR contracts
│   └── maclink-cli/           # Headless command-line daemon & tools
├── desktop/
│   ├── app/                   # macOS Desktop client (Qt 6, C++, Rust cxx-qt)
│   │   ├── qml/               # Liquid Glass pages, components, and animations
│   │   └── src/               # Native bridge, menu bar, system lifecycle
│   └── packaging/macos/       # DMG generation, Info.plist, codesign scripts
└── dist/                      # Distribution artifacts (DMG, ZIP, APK, checksums)
```

---

## 📜 License

- **Applications & Desktop Client**: [GPL-3.0-or-later](LICENSES/GPL-3.0-or-later.txt)
- **Core Engine & Protocol**: [MPL-2.0](LICENSES/MPL-2.0.txt)
- **Typography & Fonts**: [SIL Open Font License 1.1](assets/fonts/OFL-SpaceMono.txt)
