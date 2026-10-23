# LiquidDynamo — Engineering & Contribution Rules

This document outlines the core engineering guidelines, design constraints, and rules of engagement for developing, maintaining, and contributing to **LiquidDynamo**.

---

## 1. Architectural Principles

1. **Native macOS Synergy**:
   - LiquidDynamo is built natively for macOS using **SwiftUI**, **AppKit**, **CoreAudio**, **Metal**, and **SceneKit**.
   - Do NOT introduce bulky cross-platform frameworks, Electron layers, or unnecessary third-party dependencies.

2. **Preserve Established Visual Identity**:
   - Liquid Glass shaders, fluid morphing shapes, organic spring physics (`IslandMotion.shared`), and dark OLED blending are core hallmarks of the application.
   - Never replace the fluid glass/droplet aesthetic with generic, blocky rectangular views or flat UI templates.

3. **Multi-Display & Hardware Notch Support**:
   - Always rely on `NotchSafeAreaEngine.shared` to read physical screen safe areas, auxiliary top areas, and hardware cutout bounds.
   - On notched MacBooks (MacBook Pro / MacBook Air M2+), the closed notch sits flush with the physical cutout.
   - On external displays and non-notched Macs, the UI floats gracefully as a Dynamic Island pill.

4. **100% Privacy & Zero Telemetry**:
   - LiquidDynamo executes 100% locally.
   - Never introduce analytics trackers, telemetry reporters, or network phone-home calls.
   - Bluetooth discovery and CoreAudio device inspection must remain strictly local to user-paired devices.

---

## 2. Interaction & Gesture Rules

1. **Two-Finger Trackpad Gestures**:
   - **Vertical Slide (Up / Down)**: Controls System Audio Volume.
     - Sliding two fingers **UP** increases volume.
     - Sliding two fingers **DOWN** decreases volume.
     - Account for macOS natural scrolling (`event.isDirectionInvertedFromDevice`).
   - **Horizontal Slide (Left / Right)**: Controls Display Brightness.
     - Sliding two fingers **RIGHT** increases brightness.
     - Sliding two fingers **LEFT** decreases brightness.
   - Keep gesture thresholds responsive (threshold ≤ 4.0 points).

2. **Notch Expansion & Pinning**:
   - Clicking the closed hardware notch cutout must explicitly expand and pin the island (`island.setExpanded(pin: true)`).
   - Once expanded, clicking inside interactive dashboard components (Clipboard History, Device Showcase, Color Dropper, Sliders, Tabs) must **never** close the island.
   - Clicks strictly outside the island frame (`clickOutsideMonitor`) or pressing the `Esc` key cleanly close the island.

---

## 3. Concurrency & State Management

1. **MainActor Thread Isolation**:
   - All UI state changes, `@Published` property updates in ViewModels (`LiquidViewModel`, `IslandController`, `VolumeManager`, `BrightnessManager`), and HUD postings must be executed on `@MainActor` / main thread.
   - For audio/brightness mutations, synchronously update manager states (`rawVolume`, `isMuted`, `rawBrightness`) on the main thread so that immediate UI calls (`postVolumeHUD`) reflect the new state without async race conditions.

2. **Deterministic Hardware Controls**:
   - Do not use toggle functions where an absolute state is required (e.g., when increasing volume, explicitly call `setMuteInternal(false)` rather than toggling mute).
   - Always provide reliable fallback mechanisms (e.g., CoreAudio scalar property write with AppleScript fallback `set volume output volume ...`).

---

## 4. Code Quality & Formatting

1. **Swift Version Support**:
   - Code must build cleanly with Swift 5.9+ / Swift 6 on Xcode 15+ targeting macOS 14.0 (Sonoma) or newer.
   - Respect `@Sendable` boundaries and actor isolation.

2. **Resource Management**:
   - Clean up event monitors (`removeMonitor`), Combine subscriptions (`cancellables.removeAll()`), and background polling timers on deinit or window closing.
   - Prevent memory leaks and excessive CPU usage; the app must maintain ~0.0% CPU usage while idle in the notch.

---

## 5. Build, Test & Packaging Procedure

1. **Compilation**:
   ```bash
   bash scripts/compile_release.sh
   ```
2. **Local Deployment & Testing**:
   ```bash
   bash scripts/deploy_and_package.sh
   ```
3. **Distribution DMG**:
   - Production releases are packaged into a standalone DMG with custom volume background and `/Applications` symlink via `build_dmg.sh`.
