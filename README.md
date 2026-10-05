# LiquidDynamo — Dynamic Notch Enhancement for macOS

<p align="center">
  <b>A sleek, fluid, and dynamic notch enhancement experience for macOS</b><br>
  Developed by <b>Agrigence</b>
</p>

<p align="center">
  <a href="https://github.com/anksarvesh-lgtm/Liquiddynamo/releases"><img src="https://img.shields.io/github/v/release/anksarvesh-lgtm/Liquiddynamo?style=flat-square&color=indigo" alt="Latest Release" /></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?style=flat-square" alt="Platform macOS 14+" />
  <img src="https://img.shields.io/badge/arch-Apple%20Silicon%20%7C%20Intel-informational?style=flat-square" alt="Architecture" />
  <a href="LiquidDynamo/LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-green?style=flat-square" alt="License GPL-3.0" /></a>
</p>

---

## ⚡ Overview

**LiquidDynamo** transforms your MacBook’s physical camera notch into an interactive, dynamic command center. Designed with fluid animations and precision engineering, it seamlessly expands into a feature-rich hub for media playback, 3D device interaction, calendar schedules, system controls, and file management—or floats as an elegant dynamic island on non-notched external displays.

This workspace also provides the **Interactive Web Showcase & Documentation Suite**, allowing developers to test the dynamic island physics, explore the Metal signed-distance field (SDF) shaders, and inspect the codebase directly in the browser.

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
  - Eliminates clunky default macOS HUD squares with smooth, sub-16ms response.
- 📂 **Liquid Shelf & AirDrop**
  - Quick-drop staging shelf right at the top of your display for dragging files, text, and images.
  - Integrated one-click AirDrop sharing to send files instantly to nearby devices.
- 📅 **Calendar & Schedule at a Glance**
  - Hover or click to preview upcoming appointments, meetings, and system Reminders.
  - Direct 1-click meeting join for Google Meet, Zoom, Microsoft Teams, and Webex.
- 🔋 **Intelligent Power Monitoring**
  - Real-time battery status and charging wattage for MagSafe 3 and USB-C adapters.
  - Low-battery warning triggers at 15% and 5% thresholds.
- 🎛️ **Adaptive Display Mode**
  - Automatically matches the physical geometry of notched MacBook displays with pitch-black OLED blending.
  - Effortlessly transforms into a floating pill island on external monitors and non-notched Macs.
- ⚡ **Ultra-Efficient Architecture**
  - Built with native SwiftUI, AppKit, Metal, and SceneKit.
  - Near-zero (0.0%) CPU utilization during idle states with full support for macOS Reduce Motion and Low Power Mode.

---

## 💻 System Requirements

- **Operating System**: macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia)
- **Architecture**: Apple Silicon (M1/M2/M3/M4) and Intel-based Macs
- **Hardware**: Compatible with all Mac displays (notched MacBooks, external 4K/5K displays, Studio Display, iMac, Mac mini, Mac Studio, and Mac Pro)

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

```bash
# 1. Clone repository
git clone https://github.com/anksarvesh-lgtm/Liquiddynamo.git
cd Liquiddynamo

# 2. Open project in Xcode
open LiquidDynamo.xcodeproj

# 3. Build & Package DMG
bash build_dmg.sh
```

---

## 🌐 Web Documentation & Live Simulator

This repository contains a full interactive web documentation portal built with React, TypeScript, and Tailwind CSS.

### Running the Web Showcase Locally:

```bash
npm install
npm run dev
```

The interactive simulator allows testing all 5 island states (`Idle`, `Compact`, `Minimal`, `Expanded`, `Alert Pop`) and includes:
- Live AirPods 3D Space and Listening Mode selector
- Now Playing player with frequency bars
- Top-of-screen Liquid Shelf with file staging and AirDrop simulation
- Interactive Metal SDF smooth-minimum ($k$) physics lab
- Full codebase architecture browser

---

## 🔒 Privacy & Security

LiquidDynamo is designed with a strict privacy-first architecture:
- **100% Local Execution**: All computations, media tracking, and device management occur entirely on your local machine.
- **Zero Telemetry**: No analytics, telemetry trackers, or external network requests.
- **Isolated Scanning**: Bluetooth scanning only interacts with your own connected devices and never captures, stores, or logs third-party hardware nearby.

---

## 📜 License & Acknowledgments

LiquidDynamo is open-source software licensed under the **GNU General Public License v3.0 (GPL-3.0)**. See the [LICENSE](LiquidDynamo/LICENSE) file for complete details.

### Upstream Attribution
LiquidDynamo is based on the open-source project [Boring Notch](https://github.com/TheBoredTeam/boring.notch) by TheBoredTeam. Modifications, custom Metal Signed-Distance Field (SDF) shaders, AirPods 3D space architecture, and custom DMG packaging pipeline are Copyright © 2026 Agrigence.
