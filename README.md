<h1 align="center">
  <br>
  LiquidDynamo
  <br>
</h1>

<p align="center">
  <b>A sleek, fluid, and dynamic notch enhancement experience for macOS</b><br>
  Developed by <b>Agrigence</b>
</p>

<p align="center">
  <a href="https://github.com/anksarvesh-lgtm/Liquiddynamo/releases"><img src="https://img.shields.io/github/v/release/anksarvesh-lgtm/Liquiddynamo?style=flat-square&color=blue" alt="Latest Release" /></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?style=flat-square" alt="Platform macOS 14+" />
  <img src="https://img.shields.io/badge/arch-Apple%20Silicon%20%7C%20Intel-informational?style=flat-square" alt="Architecture" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-green?style=flat-square" alt="License GPL-3.0" /></a>
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/2d5f69c1-6e7b-4bc2-a6f1-bb9e27cf88a8" alt="LiquidDynamo Demo" />
</p>

---

**LiquidDynamo** transforms your MacBook’s hardware notch into an interactive, dynamic command center. Designed with fluid animations and precision engineering, it seamlessly expands into a feature-rich hub for media playback, 3D device interaction, calendar schedules, system controls, and file management—or floats as an elegant dynamic island on non-notched displays.

---

## ✨ Features

- 🎵 **Interactive Media Hub**
  - Live Now Playing controls with integrated artwork and dynamic visualizer waveforms.
  - Quick transport controls (play, pause, skip, scrub) with responsive hover springs.

- 🎧 **AirPods 3D Space Experience**
  - Zero-gravity 3D rendered AirPods models set against an interactive cosmic starfield.
  - Orbit battery arcs displaying exact charge levels with dynamic color alerts.
  - Noise control switching (Noise Cancellation, Transparency, Adaptive, and Off).
  - Head-tracking mirror mode utilizing `CMHeadphoneMotionManager`.

- 🖥️ **System HUD Replacements**
  - Seamless notch-integrated overlays for Volume, Display Brightness, and Keyboard Backlight.
  - Eliminates clunky default macOS HUD squares with smooth, stutter-free animations.

- 📂 **Liquid Shelf & AirDrop**
  - Quick-drop staging shelf right at the top of your display for dragging files, text, and images.
  - Integrated one-click AirDrop sharing to send files instantly to nearby devices.

- 📅 **Calendar & Schedule at a Glance**
  - Hover or click to preview upcoming appointments, meetings, and system Reminders.

- 🔋 **Intelligent Power Monitoring**
  - Real-time battery status and charging indicators for your Mac and connected Bluetooth accessories.
  - Low-battery warning triggers at 15% and 5% thresholds.

- 🎛️ **Adaptive Display Mode**
  - Automatically matches the physical geometry of notched MacBook displays with pitch-black OLED blending.
  - Effortlessly transforms into a floating pill island on external monitors and non-notched Macs.

- 👆 **Two-Finger Trackpad Gestures**
  - **Slide Up / Down**: Smoothly step system Volume up or down with live notch HUD feedback.
  - **Slide Left / Right**: Instantly adjust Display Brightness.
  - **Notch Click**: Expands and pins the dynamic island open with zero bouncing.
  - **Click Outside / Escape**: Dismisses the expanded dashboard cleanly.

- 🧹 **Intelligent Storage Cleaner & Purge**
  - Integrated zero-network storage cleaner based on [Purge](https://github.com/jithin-sabu/purge-app) with multi-tiered safety allowlists.
  - Safely reclaims gigabytes across caches, logs, developer artifacts (Xcode DerivedData, Gradle, SPM), and application uninstall leftovers.
  - Multi-segment storage visualization bar and trash-only safety guarantees.

- 🪽 **Configurable Notch Wings & Telemetry Slots**
  - Modular slot system flanking the hardware notch cutout (`WingMetric`).
  - Choose live metrics for each wing: CPU usage, CPU temperature, RAM usage, network speed (up/down/combined via `getifaddrs`), battery, volume, brightness, or clock.
  - Setting a slot to "None" collapses that wing cleanly without awkward gaps.
  - Includes a live Mock Notch Preview in Settings.

- 🎨 **Color Dropper & Clipboard Intelligence**
  - Built-in screen color sampler powered by AppKit's `NSColorSampler` with loupe magnifier.
  - Interactive color swatch card with instant copy for HEX, RGB, and HSL formats.
  - Privacy-first clipboard history with automatic screening of password managers and concealed/transient types.
  - Transient 3D liquid capsule alerts for copied items and system events.

- ⚡ **Ultra-Efficient Architecture**
  - Built with native SwiftUI, AppKit, Metal, and SceneKit.
  - Near-zero CPU utilization during idle states with full support for macOS Reduce Motion and Low Power Mode.

---

> [!NOTE]
> For architecture conventions, coding standards, and contribution rules, please refer to [RULES.md](RULES.md).

---

## 💻 System Requirements

- **Operating System**: macOS 14.0 (Sonoma) or later
- **Architecture**: Apple Silicon (M1/M2/M3/M4) and Intel-based Macs
- **Hardware**: Compatible with all Mac displays (notched MacBooks, external monitors, iMac, Mac mini, Mac Studio, and Mac Pro)

---

## 🚀 Installation

### Download from GitHub Releases

1. Download the latest `LiquidDynamo.dmg` from [GitHub Releases](https://github.com/anksarvesh-lgtm/Liquiddynamo/releases).
2. Open the downloaded `.dmg` and drag **LiquidDynamo** to your `/Applications` folder.

> [!IMPORTANT]
> Because LiquidDynamo is an independent open-source release, macOS Gatekeeper may display a prompt on first launch.
> You can bypass this in seconds using Terminal:
>
> ```bash
> xattr -dr com.apple.quarantine "/Applications/LiquidDynamo.app"
> ```
>
> Alternatively, open **System Settings** > **Privacy & Security**, scroll down to the security section, and click **Open Anyway**.

---

## 🛠️ Building from Source

### Prerequisites

- macOS 14.0 or later
- Xcode 15 or later with Command Line Tools installed

### Steps

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/anksarvesh-lgtm/Liquiddynamo.git
   cd Liquiddynamo
   ```

2. **Open in Xcode**:
   ```bash
   open LiquidDynamo.xcodeproj
   ```

3. **Build & Run**:
   - Select the `LiquidDynamo` scheme.
   - Press `Cmd + R` to build and launch the application.

4. **Command-Line Build & Packaging**:
   - You can compile the release binary or package a distributable `.app` / `.dmg` via the included scripts:
   ```bash
   # Compile standalone release binary
   bash scripts/compile_release.sh

   # Package application bundle and verify entitlements
   bash scripts/deploy_and_package.sh

   # Build distributable macOS disk image (.dmg)
   bash build_dmg.sh
   ```

---

## 🔒 Privacy & Security

LiquidDynamo is designed from the ground up with a strict privacy-first architecture:

- **100% Local Execution**: All computations, media tracking, and device management occur entirely on your local machine.
- **Zero Telemetry**: No analytics, telemetry trackers, or external network requests.
- **Isolated Scanning**: Bluetooth scanning only interacts with your own connected devices and never captures, stores, or logs third-party hardware nearby.
- **Vulnerability Reporting**: If you discover any security concerns, please refer to our [Security Policy](SECURITY.md).

---

## 📜 License & Acknowledgments

LiquidDynamo is open-source software licensed under the **GNU General Public License v3.0 (GPL-3.0)**. See the [LICENSE](LICENSE) file for complete details.

### Upstream Attribution
LiquidDynamo is based on the open-source project [Boring Notch](https://github.com/TheBoredTeam/boring.notch) by TheBoredTeam. Modifications, enhancements, and custom integrations are Copyright © 2026 Agrigence. Storage cleaning and safety architecture is ported from [Purge](https://github.com/jithin-sabu/purge-app) by Jithin Sabu (MIT License).

For full licensing notices and third-party dependency disclosures, please see [NOTICE.md](NOTICE.md) and [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).
