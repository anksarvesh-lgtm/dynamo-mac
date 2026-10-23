# Master Plan: Liquid Island Engine (v2.0)

## Executive Summary
The **Liquid Island Engine** replaces the rigid capsule and hybrid clip containers with an organic, liquid-like 3D signed-distance field (SDF) shape that emerges smoothly from the MacBook physical notch, expands outside the notch, presents rich dynamic content, and seamlessly collapses like a water droplet back into the hardware bezel.

---

## 1. Acceptance Rules & Architectural Invariants

| Invariant | Specification | Guarantee Mechanism |
| :--- | :--- | :--- |
| **Rule 1: Notch is a Hole** | Nothing is ever drawn inside `notchRect` except the pure black shape fill (`#000000`). No text, icons, sliders, images, or 3D models. | Layout engine enforces strictly that all interactive/rendered subviews live in `leftSlot`, `rightSlot`, or `belowArea` (`y >= notchRect.maxY`). `NotchSafetyRegistry` asserts no content frame intersects `notchRect`. |
| **Rule 2: Slot Segregation** | Top band content (height = notch height) exists exclusively in `leftSlot` (x < notchRect.minX) or `rightSlot` (x > notchRect.maxX). | `NotchGeometry` calculates exact wing boundaries. Top band views are framed and clipped to safe wing widths. |
| **Rule 3: Auto-Sizing** | The shape resizes to content dynamically and without visual jumps as content grows, shrinks, or updates. | SwiftUI `PreferenceKey` measurement pipeline reads intrinsic content size; spring physics drive continuous lobe bounding dimensions. |
| **Rule 4: Autonomous Dwell** | Automatic activities appear, dwell briefly, and collapse. Hover intent pauses the timer. | `IslandMotion.shared` dwell scheduler tracks `(2.5s + 0.04s * charCount)` clamped to 8.0s; hover enters pause state; new activity extends dwell. |
| **Rule 5: Zero-Cost Idle** | At idle, no Metal shaders execute, CADisplayLink is suspended, and the window ignores mouse events. | Engine transitions to `.idle`, deallocating shader layer, pausing rendering loop, and toggling `window.ignoresMouseEvents = true`. CPU use is near 0.0%. |
| **Rule 6: Velocity Handoff** | Mid-animation interruptions seamlessly retain physical velocity. | Interactive springs (`IslandMotion.shared`) use spring state velocity continuity rather than restarting from zero. |

---

## 2. Renderer Architecture (Metal SDF + Fallback)

### 2.1 Lobe System
The liquid shape is represented as a union of up to 8 geometric lobes:
1. **Lobe 0 (Root)**: Anchored directly along the notch's bottom lip. Bulges downward during anticipation/swell.
2. **Lobe 1 (Body)**: The primary content container capsule centered in `belowArea`.
3. **Lobe 2 (Wing Left)**: Top band extension to the left of the notch for HUD icons, indicators, or system stats.
4. **Lobe 3 (Wing Right)**: Top band extension to the right of the notch for meters, battery indicators, or status text.
5. **Lobe 4 (Droplet)**: The falling/rising bead that forms the gooey neck between the root and the body.
6. **Lobe 5 (Satellite 1)**: Secondary detached/merging bubble for concurrent activities.
7. **Lobe 6 (Satellite 2)**: Additional accessory bubble.
8. **Lobe 7 (Auxiliary)**: Reserved for transient splashes or particles.

### 2.2 Signed-Distance Field & Smooth Minimum (`smin`)
Each lobe computes the 2D signed distance to a rounded box / capsule:
$$\text{sdRoundedBox}(p, b, r) = \| \max(|p| - b + r, 0) \| + \min(\max(|p|_x - b_x + r, |p|_y - b_y + r), 0) - r$$

Lobes are merged using polynomial smooth minimum with smoothing radius $k$:
$$\text{smin}(d_1, d_2, k) = \min(d_1, d_2) - \frac{\max(k - |d_1 - d_2|, 0)^2}{4k}$$
- **During Swell & Birth**: $k$ expands up to $28.0\text{--}36.0\text{ pt}$ creating a viscous, organic neck.
- **During Settled Bloom**: $k$ tightens to $8.0\text{--}12.0\text{ pt}$ for crisp, clean definition.
- **During Collapse**: $k$ re-expands as the droplet is drawn back into the notch.

### 2.3 3D Lighting & Shading Model
- **Normal Vector**: Calculated via 2D finite-difference gradient of the distance field:
  $$\vec{n}_{xy} = \nabla d = \left(\frac{d(p + \epsilon_x) - d(p - \epsilon_x)}{2\epsilon}, \frac{d(p + \epsilon_y) - d(p - \epsilon_y)}{2\epsilon}\right), \quad n_z = \sqrt{\max(0, 1 - \|\vec{n}_{xy}\|^2)}$$
- **Key Light**: Positioned at top-left: $\vec{L} = \text{normalize}(-0.55, -0.75, 1.25)$.
- **Tight Specular**: Sharp glossy highlight on glass crest: $(\vec{N} \cdot \vec{H})^{32.0} \times 0.65$.
- **Broad Specular**: Subtle sheen across liquid curvature: $(\vec{N} \cdot \vec{H})^{5.0} \times 0.25$.
- **Fresnel Rim**: Refraction edge glow along boundary: $(1.0 - n_z)^3 \times \text{tintColor}$.
- **Base Fill**: Pure optical black (`#000000`) that perfectly merges into the hardware notch cutout, fading with anti-aliasing: $\text{smoothstep}(0.5, -0.5, d)$.

### 2.4 Fallback Renderers
- **macOS 14–25 Fallback**: SwiftUI `Canvas` with Gaussian blur (`radius: 8.0`) + `alphaThreshold(min: 0.5)` gooey metaball technique.
- **Reduce Transparency**: Opaque obsidian solid fill (`Color(white: 0.08)`) with crisp contrast border.
- **Reduce Motion**: Instant cross-fade and scale (0.95 → 1.0) bypassing fluid neck physics.

---

## 3. Auto-Sizing & Measurement Pipeline

```
+-------------------------------------------------------------------+
| Content View (Live Activity Template / HUD / Notification Card)   |
|   .background(GeometryReader -> ContentSizePreferenceKey)         |
+---------------------------------+---------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
| LiquidIslandEngine Sizing Coordinator                             |
|   1. targetBodyWidth  = clamp(contentSize.width + 24, minW, maxW) |
|   2. targetBodyHeight = clamp(contentSize.height + 16, minH, maxH)|
|   3. targetCenter     = (notchRect.midX, notchRect.maxY + 8 + H/2)|
+---------------------------------+---------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
| Lobe State Interpolator (Continuous Springs in IslandMotion)      |
|   - Smoothly morphs Body Lobe without jumps or visual snapping    |
|   - Content opacity reveals after size >= 60%                     |
+-------------------------------------------------------------------+
```

---

## 4. Lifecycle & Physics Timing

| Phase | Duration | Description | Spring / Curve |
| :--- | :--- | :--- | :--- |
| **1. Swell** | $\sim 0.12\text{ s}$ | Root lobe bulges 4 to 6 pt down into `belowArea`. | `.easeIn(duration: 0.12)` |
| **2. Birth & Fall** | $\sim 0.24\text{ s}$ | Droplet lobe snaps neck, stretches vertically ($1.25\times$), travels to target center. | `.easeOut(duration: 0.24)` |
| **3. Bloom** | $\sim 0.40\text{ s}$ | Droplet morphs into body lobe. Organic 4% decaying wobble (aspect ratio & radius). | Response: `0.45`, Damping: `0.72` |
| **4. Reveal** | $\sim 0.15\text{ s}$ | Content fades in and scales smoothly once body reaches $\ge 60\%$ target size. | `.easeOut(duration: 0.15)` |
| **5. Hold** | $2.5\text{--}8.0\text{ s}$ | Steady presentation. Dwell timer: $2.5\text{ s} + 0.04\text{ s} \times \text{chars}$. Hover pauses timer. | Linear countdown |
| **6. Collapse** | $\sim 0.35\text{ s}$ | Content fades out in 0.15s. Body shrinks into droplet. **Absorb**: Droplet rises and merges into root. **Evaporate**: Droplet shrinks to zero with fading highlight. | Response: `0.36`, Damping: `0.86` |
| **7. Idle** | Indefinite | Shader layer detached, CADisplayLink halted, `ignoresMouseEvents = true`. | Idle state |

---

## 5. Live Activity Hub Migration Plan

1. **Volume & Display Brightness HUD**: Migrated to WingL (icon) + WingR (percentage) in compact mode; body droplet bloom for draggable sliders.
2. **Alerts & AirPods**: Migrated to below-notch body bloom with 3D model / device badge.
3. **Notification Cards**: Migrated to below-notch body bloom with interactive quick actions.
4. **Ongoing Activities & Downloads**: Primary item in body or wings; secondary concurrent activity appears as satellite lobe.
5. **Expanded Dashboard**: Full downward bloom into multi-tab liquid glass surface.

---

## 6. Standalone Debug Window Architecture
A dedicated inspection controller (`LiquidEngineDebugWindowController`) allows tuning all parameters in real-time:
- Lobe positions, radii, and dimensions (Root, Body, Wings, Droplet, Satellites).
- Smoothing parameter $k$ ($0.0 \dots 40.0$).
- 3D lighting parameters (Key Light X/Y/Z, Specular Exponent, Specular Intensity, Fresnel Rim, Inner Shadow).
- Tint selection (Emerald `#10B981`, Cyan `#06B6D4`, Orange `#F59E0B`, Red `#EF4444`, Purple `#8B5CF6`).
- Interactive Phase Trigger Buttons (Swell, Birth, Bloom, Hold, Collapse Absorb, Collapse Evaporate).
- Slow-Motion Multiplier ($0.1\times \dots 2.0\times$) and Layout Guides toggles.

---

## 7. Migration Progress Tracker

- [x] **Step 1: Metal SDF Shader Engine & Standalone Debug Window**
  - Custom `LiquidIslandShader.metal` with `sdRoundedBox` signed-distance fields, polynomial `smin`, surface gradients, dual-lobe specular lighting, and Fresnel edge refraction.
  - Swift lobe data models (`LiquidIslandLobe`, `LiquidLightingConfig`, `LiquidIslandCanvasView`).
  - Standalone debug inspector (`LiquidEngineDebugWindowController`, shortcut: `⌥⌘L`).
- [x] **Step 2: Live Activity Template, Auto-Sizing Pipeline & Simpler Views Migration**
  - Preference-key intrinsic size measurement pipeline (`ContentSizePreferenceKey`, `measureIntrinsicContentSize`).
  - Smooth spring sizing coordinator (`LiquidIslandSizingCoordinator`) morphing the SDF body lobe with zero jumps or clipping.
  - Unified `LiveActivityTemplateView` supporting `.compactWings` (Rule 1 & 2 compliant) and `.liquidDropletBloom` (phased emergence from notch into belowArea).
  - Migrated simpler views:
    - **Volume HUD**: `VolumeLiveActivityView` with dynamic wave speaker icon, fluid interactive slider, haptic step ticks, and live `VolumeManager` binding.
    - **Display Brightness HUD**: `BrightnessLiveActivityView` with dynamic sun rays icon, fluid slider, and live `BrightnessManager` binding.
    - **Battery & Power Alerts**: `BatteryLiveActivityView` with animated charging bolt, emerald/amber/crimson state tints, and low-battery/power notifications.
  - Application version bumped to **1.2.0 (Build 3)** across Xcode project configuration and packaging scripts.
- [x] **Step 3: Complex Views Migration** (Now-Playing, Timers, Notifications, Clipboard Shelf, Calendar)
  - **Media & Now-Playing**: `MediaLiveActivityView` with compact wing status (artwork & animated equalizer bars), below-notch blooming droplet with ambient glow tinting, marquee track metadata, fluid scrub bar, and media controls.
  - **Timers & Pomodoro**: `TimerLiveActivityView` with compact countdown wing, blooming circular progress ring, monospaced countdown clock, and interactive pause/resume & dismiss controls.
  - **Push & Local Notifications**: `NotificationLiveActivityView` with app icon badge, category color styling, sender & preview text, dynamic multi-action buttons, and gesture-driven swipe-up dismiss.
  - **Clipboard Shelf**: `ClipboardShelfLiveActivityView` with wing item count badge, blooming droplet card displaying clipboard snippet preview, item count, and quick paste/clear actions.
  - **Calendar & Meetings**: `CalendarLiveActivityView` with wing countdown ("in 5m"), blooming droplet date badge, event title/location, and one-tap video meeting join button.
  - All 5 complex views wired into `belowAreaPresentations` in `ContentView.swift`, fully adhering to Master Spec Invariant 1 (Nothing in notch) and Invariant 2 (Top band slots only).
  - Version bumped to **1.3.0 (Build 4)** across all project targets and release configurations.
- [x] **Step 4: Deprecate & Remove Obsolete Rigid Capsule Code**
  - **Replaced Legacy Alert Popups**: Created `GenericAlertLiveActivityView` and routed generic alerts through `LiveActivityTemplateView` (`.liquidDropletBloom`), eliminating hardcoded capsule animations and widths.
  - **Deprecated Obsolete Shapes & Views**:
    - `NotchShape.swift`: Deprecated rigid 2023 polygon path; upgraded `LiquidHeader.swift` notch cutout to standard continuous `UnevenRoundedRectangle`.
    - `BottomRoundedRectangle.swift`: Deprecated unused legacy shape.
    - `LiquidDropAlertView.swift`: Deprecated in favor of `LiveActivityTemplateView` + `GenericAlertLiveActivityView`.
    - `GooeySplitView.swift`: Deprecated CPU blur-canvas fallback in favor of Metal SDF multi-lobe signed-distance rendering.
    - `drop.swift`: Deprecated legacy placeholder `LiquidAnimations`; migrated `LiquidViewModel` and `MusicManager` directly to single source of truth `IslandMotion.shared`.
  - **Verified Build Cleanliness**: Zero compiler warnings or errors on modern macOS 14+ toolchain.
- [x] **Step 5: Final Production Verification & Release Packaging**
  - **Version Bump**: Promoted to **1.4.0 (Build 5)** across Xcode project (`LiquidDynamo.xcodeproj/project.pbxproj`), `Constants.swift`, and `build_dmg.sh`.
  - **App Icon & Logo Synchronization**:
    - Synchronized high-resolution `AppIcon.appiconset` directly into `logo.imageset` and `logo2.imageset`.
    - Added global `AppLogo()` and `AppLogoNSImage` helpers in `AppIcons.swift` referencing `NSApp.applicationIconImage`.
  - **Clean Production Build**: Validated full `Release` build via `xcodebuild` with zero compiler errors.
  - **Packaged Production Artifacts**:
    - Branded DMG generated at `/Users/sarvesh/Desktop/LiquidDynamo-1.4.0.dmg`.
    - Release notes published to `/Users/sarvesh/Desktop/ReleaseNotes.txt`.
    - Full build report published to `/Users/sarvesh/Desktop/BuildReport.txt`.


