# Changelog

All notable changes to MacLink are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.0.9] - 2026-11-04

### Added & Fixed - Seamless Auto-Updates, Bluetooth Calling & Zero-Permission Mirroring

#### Seamless Auto-Update & In-Place Replacement
- **Zero-Loop Update Engine:** Resolved update detection loops where installed apps showed older versions. Android versionCode bumped to 9 with genuine v0.0.9 signed artifact.
- **In-Place macOS Replacement:** In-app updater extracts `.app` directly, clears Gatekeeper quarantine with `xattr -cr`, atomically replaces `/Applications/MacLink.app`, and auto-relaunches seamlessly.
- **Dynamic Bundle Versioning:** Desktop UI dynamically reads installed bundle version from `Info.plist`, ensuring consistency with release artifacts.
- **Developer-Grade Installer:** Interactive one-line terminal installer with ASCII branding, progressive step indicators, and instant `maclink` CLI launcher.

#### Bluetooth Calling & Hands-Free Profile (HFP 1.7)
- **Native Objective-C++ Engine:** Integrated Bluetooth HFP 1.7 SDP service publishing and Synchronous Connection-Oriented (SCO) audio routing directly with `IOBluetooth`.
- **Bidirectional Audio Routing:** Answer, decline, and route incoming cellular audio between Android phone and Mac microphone/speakers.
- **Call Privacy & Security:** Automated sanitization of caller numbers in memory, zero call audio persistence on disk.

#### Zero-Permission App Mirroring & Multi-Touch Input
- **Hardware Bluetooth HID Input:** Injects native trackpad and touchscreen events into Android without requiring accessibility or USB developer debugging permissions.
- **Multi-Touch Trackpad Support:** Smooth 1-4 finger gestures with local haptic feedback.

## [0.0.4] - 2026-11-02

### Added & Changed - Amber Liquid Glass Mobile Experience & Desktop Polish

#### Android UI & Amber Liquid Glass Edition
- **Complete Visual Redesign:** Implemented the full Apple-inspired Amber Liquid Glass interface with centralized amber tokens, warm translucent glass surfaces, specular rims, and dark obsidian backdrops.
- **LinkDesk Top Bar:** Integrated a frosted glass app identity container with crown shortcut, help walk-through, and QR pairing buttons.
- **Illuminated Device Card:** Realistic 3D angled MacBook illustration with golden illuminated wallpaper and reflective chassis alongside connection latency indicators and hardware badge chips.
- **Quick Action & Bento Controls:** Radiant amber quick action tiles (`Control PC`, `Deck`, `Desk Clock`), transfer action cards (`Send Files`, `Send Folder`, `Send Clipboard`, `Browse Files`), and circular system power buttons (`Record`, `Ring PC`, `Lock PC`, `Sleep`).
- **Amber Light Wave Ribbon:** Flowing ambient amber sine-wave ribbon with glowing golden Apple emblem.
- **Enhanced Auxiliary Cards:** Liquid glass styling for permissions setup, preview-chipped clipboard history, and 12-bar equalizer waveform timeline.
- **Tri-Tab Liquid Floating Dock:** 3-tab floating glass dock (`Home`, `Settings`, `Guide`) featuring active radiant amber gradient pill and golden glow highlights.

#### macOS Desktop & Cross-Platform
- **Shelf Auto-Hide:** Proactive auto-hide behavior when the mouse cursor departs the Shelf activation zone.
- **Unified Release Packaging:** Automated multi-architecture release distribution with SHA-256 checksums.

## [0.0.1] - 2026-11-01

### Added - Initial Beta Release

#### Connectivity & Resilience
- **Persistent Local Auto-Connect:** Mac and Android automatically connect on application startup and whenever both devices are present on the same local Wi-Fi network.
- **Unbreakable Keep-Alive:** Multi-try heartbeat resilience with 15-second fault tolerance prevents premature disconnects during Android radio power-saving modes.
- **Android Background Reliability:** High-performance `WifiLock` and partial wake lock ensure background reachability without connection interruptions.
- **Fast LAN Discovery:** mDNS and UDP discovery broadcast peer LAN addresses directly into connection endpoints for sub-second handshake resolution.
- **Strict Local Privacy:** Pure local LAN and USB P2P communication; cellular stay-connected disabled to safeguard mobile data and maintain zero cloud dependency.
- **Alphanumeric Pairing:** Short alphanumeric SAS pairing verification codes for simple and unambiguous authentication.

#### Desktop & Android Experience
- **Liquid Glass & System Theme Adaptation:** Modern translucent UI that organically inherits native macOS and system wallpaper themes.
- **Smart Connect App Play:** Run and control Android apps inside independent desktop windows with keyboard and mouse input.
- **Screen & Display Mirroring:** Low-latency H.264/H.265 display streaming with interactive touch, scroll, and gesture support.
- **Bidirectional Clipboard Sync:** Seamless real-time clipboard sharing for text and copied images with automatic exclusion of password manager secrets.
- **High-Speed File & Folder Sharing:** Direct encrypted peer-to-peer transfers with folder preservation, pause/resume, and offline send queuing.
- **Notification Mirroring:** Live synchronized phone notifications on your desktop with inline action execution and monochrome status icons.
- **Calls & SMS:** View incoming calls, dial phone contacts, and read and reply to text messages from your Mac.
- **Phone as Speaker & Microphone:** Stream Mac audio directly to your phone speakers or use your Android phone as a wireless desktop microphone.
- **Automatic GitHub Updates:** Built-in update check on application startup with automated platform-specific artifact delivery (.dmg, .pkg, .apk, .exe, .AppImage).
