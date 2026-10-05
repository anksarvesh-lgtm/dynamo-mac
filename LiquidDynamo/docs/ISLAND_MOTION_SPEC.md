# LiquidDynamo Dynamic Island Motion Specification

> **Document**: `docs/ISLAND_MOTION_SPEC.md`  
> **Status**: Specification Proposal — Awaiting Approval  
> **Target**: Apple Dynamic Island Physics & State Machine  
> **Date**: October 4, 2026  

---

## 1. Design Philosophy & Motion Principles

The iPhone Dynamic Island feels alive because it never behaves like a static, rectangular window. It behaves like an **elastic, fluid physical silicone element** integrated directly into the hardware cutout.

### Core Tenets
1. **Never Cut, Always Morph**: The black container must smoothly deform from one shape to the next. It never pops or snaps into place.
2. **Staggered Content Choreography**: Content inside the island must not scale with the container. Old content leaves first with a quick blur-out; the container moves; new content enters with an elastic blur-in.
3. **No Uncoordinated Timers**: Hover sequencing, auto-dismiss, and state switches are unified under a single state machine, eliminating timer collisions.
4. **Continuous Curvature**: All rounded corners use Apple continuous curvature (squircles), scaling proportionally with the container height.

---

## 2. The 5 Island States

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. IDLE                                                                     │
│    [     Hardware Notch (Invisible / Zero Content)     ]                   │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ 2. COMPACT                                                                  │
│    ( Left Wing ) ─── [ Hardware Notch ] ─── ( Right Wing )                  │
│    Artwork / Icon                           Waveform / Status               │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ 3. MINIMAL (Multi-Activity)                                                │
│    ( Compact Pill ) ─── [ Hardware Notch ]           ( Detached Bubble )    │
│    Primary Activity                                  Secondary Activity     │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ 4. EXPANDED                                                                 │
│    ┌───────────────────────────────────────────────────────────────────┐    │
│    │                    Full Interactive Dashboard                     │    │
│    │  [Dock / Controls]        [Main Card]          [HUD / Battery]    │    │
│    │  Width: ~640 pt, Height: ~190 pt                                  │    │
│    └───────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ 5. ALERT POP                                                                │
│    ┌───────────────────────────────────────────────────────────────────┐    │
│    │ ⚡ AirPods Connected / Low Battery / Charger Plugged In           │    │
│    │ Height: ~44 pt, Width: ~380–420 pt (Overshoot Spring, 3–4s Dwell) │    │
│    └───────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Detailed State Descriptions
1. **Idle**:
   - Exactly matches the hardware notch bounds (`closedNotchSize.width` × `effectiveClosedNotchHeight`, typically ~185 × 32 pt).
   - Completely invisible and inert. Zero extra padding, zero shadows, zero active CPU.
2. **Compact**:
   - The notch stretches horizontally at native notch height (32 pt), revealing symmetric or asymmetric "wings".
   - *Left Wing*: Leading indicator (album artwork, app icon, download progress ring).
   - *Right Wing*: Trailing indicator (audio visualizer bars, download speed, battery level, live stats).
3. **Minimal (Multi-Activity)**:
   - Engaged when two or more distinct background activities are active simultaneously (e.g., Music playing + Timer countdown, or Call active + Low battery warning).
   - The primary activity occupies the compact notch container.
   - The secondary activity detaches as a small circular/pill bubble (e.g., 28 × 28 pt) separated by a 6–8 pt gap on the trailing edge.
4. **Expanded**:
   - The full interactive dashboard.
   - Grows downward and outward to ~640 × 190 pt.
   - Houses full controls: music scrubber, calendar events, battery indicators, shelf drop zone, and tab views.
5. **Alert Pop**:
   - Transient, high-priority announcement (device connection, battery warning, charging chime, HUD volume/brightness feedback).
   - Springs out aggressively with momentum and overshoot, holds for a configured dwell duration (3.0–4.0 s), then retracts back to the resting state (`Idle`, `Compact`, or `Minimal`).

---

## 3. Legal Transitions & Choreography Matrix

| From State | To State | Trigger Event | Motion Spring / Curve | Content Choreography |
| :--- | :--- | :--- | :--- | :--- |
| **Idle** | **Compact** | Background activity starts (e.g., music plays, download begins, wings enabled) | `expandSpring`<br>(0.45, 0.75) | Container widens horizontally; compact content enters via `contentIn`. |
| **Compact** | **Idle** | Activity ceases (e.g., music pauses, playback terminates) | `collapseSpring`<br>(0.36, 0.86) | Compact content blurs out (`contentOut`); wings pull inward to notch bounds. |
| **Compact** | **Compact** | Track change or info mode toggle | Shape: `collapseSpring`<br>Swap: `compactSwap` (0.30s) | Old wing content blurs (10pt) and scales (0.95), crossfading simultaneously into new content. |
| **Compact** | **Minimal** | Second concurrent activity begins | `alertPopSpring`<br>(0.40, 0.65) | Primary container adjusts; secondary bubble fluidly separates and slides to trailing side. |
| **Minimal** | **Compact** | Secondary activity finishes | `collapseSpring`<br>(0.36, 0.86) | Detached bubble slides leftward and dissolves into the main notch body. |
| **Any** | **Expanded** | Click, downward swipe gesture, or hover `>= 0.10s` | `expandSpring`<br>(0.45, 0.75) | 1. Current content exits immediately (`contentOut`, 0.15s).<br>2. Container expands.<br>3. Dashboard content fades in after 0.09s (`contentIn`, 0.28s). |
| **Expanded** | **Previous** (`Idle`/`Compact`/`Minimal`) | Click outside, upward swipe, Esc key, or cursor leaves `>= 0.25s` | `collapseSpring`<br>(0.36, 0.86) | 1. Dashboard fades/scales down (`contentOut`).<br>2. Container collapses.<br>3. Resting state content enters (`contentIn`). |
| **Idle / Compact** | **Alert Pop** | Peripheral connected, battery alert, or volume/brightness adjustment | `alertPopSpring`<br>(0.40, 0.65) | Container pops open with energetic overshoot; alert badge & title animate in with `contentIn`. |
| **Alert Pop** | **Resting** (`Idle`/`Compact`/`Minimal`) | Dwell timer expires (3.0–4.0s) or user dismisses | `collapseSpring`<br>(0.36, 0.86) | Alert content fades out; container snaps back into resting geometry. |

---

## 4. Phase-Staggered Content Pipeline

A major cause of animation jank in the existing app is that content and container bounds animate at the exact same moment with conflicting curves. The Dynamic Island model solves this with a **three-phase pipeline**:

```
Timeline: 0.00s ────── 0.09s ────────────── 0.15s ─────────────────── 0.37s ───►
Container:  [━━━━━━━━━━━━━━━━━━ Expanding with Spring (0.45s) ━━━━━━━━━━━━━━━]
Old Content:[ Exit (0.15s) ] (Opacity 1->0, Blur 0->10, Scale 1->0.95)
New Content:             [ Delay: 0.09s ━━► Enter (0.28s) ━━━━━━━━━━━━━━━━━━━]
                                    (Opacity 0->1, Blur 10->0, Scale 0.95->1.0)
```

1. **Phase 1: Content Exit (`contentOut`)**:
   - Duration: **0.15 s**
   - Curve: `.easeOut`
   - Transforms: Opacity $1.0 \to 0.0$, Blur radius $0 \to 10 \text{ pt}$, Scale $1.0 \to 0.95$.
2. **Phase 2: Container Deformation**:
   - Initiated simultaneously at $t = 0$.
   - Expansion uses `expandSpring` (response: 0.45, damping: 0.75).
   - Collapse uses `collapseSpring` (response: 0.36, damping: 0.86).
3. **Phase 3: Content Entry (`contentIn`)**:
   - Starts with a **0.09 s stagger delay** after container starts moving.
   - Duration: **0.28 s**
   - Transforms: Blur radius $10 \to 0 \text{ pt}$, Scale $0.95 \to 1.0$, Opacity $0.0 \to 1.0$.

---

## 5. Geometry & Dynamic Corner Radius Model

The notch container must maintain continuous squircle aesthetics regardless of size:
- **Top Corners (Hardware Notch Ears)**:
  - Fixed hardware ear radius: **6 pt** (closed) to **19 pt** (opened, blends into top bezel).
- **Bottom Corners (Dynamic Scaling)**:
  - Corner radius scales continuously with container height $h$:
    $$r_{\text{bottom}}(h) = \text{clamp}\left(h \times 0.44, \, 14\text{ pt}, \, 28\text{ pt}\right)$$
  - *Compact ($h = 32\text{ pt}$)*: $r_{\text{bottom}} = 14.0\text{ pt}$
  - *Alert Pop ($h = 44\text{ pt}$)*: $r_{\text{bottom}} = 19.3\text{ pt}$
  - *Expanded ($h = 190\text{ pt}$)*: $r_{\text{bottom}} = 28.0\text{ pt}$
- **Detached Bubble**:
  - Rendered as a continuous capsule with $r = h / 2 = 14\text{ pt}$.

---

## 6. Proposed `IslandMotion.swift` Implementation

Below is the complete, self-contained proposed file holding every constant, spring, transition modifier, and timing parameter to be added in Phase 2:

```swift
//
//  IslandMotion.swift
//  LiquidDynamo
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import SwiftUI

// MARK: - Island Motion Tokens & Physics Constants

public enum IslandMotion {

    // MARK: - Spring Curves
    /// Energetic expansion spring for opening into the full dashboard or expanding wings.
    public static let expandSpring = Animation.spring(
        response: 0.45,
        dampingFraction: 0.75,
        blendDuration: 0
    )

    /// Snappy, well-damped collapse spring for returning to compact or idle.
    public static let collapseSpring = Animation.spring(
        response: 0.36,
        dampingFraction: 0.86,
        blendDuration: 0
    )

    /// Punchy alert spring with visible overshoot for urgent popups and notifications.
    public static let alertPopSpring = Animation.spring(
        response: 0.40,
        dampingFraction: 0.65,
        blendDuration: 0
    )

    // MARK: - Content Timing & Durations
    /// Phase 1: Outgoing content fast exit duration.
    public static let contentOutDuration: TimeInterval = 0.15
    public static let contentOutAnimation: Animation = .easeOut(duration: contentOutDuration)

    /// Phase 3: Incoming content entry start delay and duration.
    public static let contentInDelay: TimeInterval = 0.09
    public static let contentInDuration: TimeInterval = 0.28
    public static let contentInAnimation: Animation = .easeOut(duration: contentInDuration).delay(contentInDelay)

    /// Compact mode content swap crossfade duration (blur + scale).
    public static let compactSwapDuration: TimeInterval = 0.30
    public static let compactSwapAnimation: Animation = .easeInOut(duration: compactSwapDuration)

    // MARK: - Interaction Dwell & Grace Intervals
    /// Intentional hover open delay to eliminate accidental trigger on mouse fly-bys.
    public static let hoverOpenDelay: TimeInterval = 0.10

    /// Hover close grace period so cursor can leave boundary briefly without closing.
    public static let hoverCloseGrace: TimeInterval = 0.25

    /// Default alert dwell duration before auto-retraction.
    public static let alertDwellDuration: TimeInterval = 3.50

    // MARK: - Dynamic Corner Radii
    /// Calculates the continuous bottom corner radius scaled to container height.
    public static func bottomCornerRadius(forHeight height: CGFloat) -> CGFloat {
        let scaled = height * 0.44
        return min(max(scaled, 14.0), 28.0)
    }

    /// Top corner radius for notch hardware alignment.
    public static func topCornerRadius(isExpanded: Bool) -> CGFloat {
        isExpanded ? 19.0 : 6.0
    }
}

// MARK: - Content Animation Modifiers

public struct IslandContentExitModifier: ViewModifier {
    public let isActive: Bool

    public func body(content: Content) -> some View {
        content
            .opacity(isActive ? 0.0 : 1.0)
            .blur(radius: isActive ? 10.0 : 0.0)
            .scaleEffect(isActive ? 0.95 : 1.0)
            .animation(IslandMotion.contentOutAnimation, value: isActive)
    }
}

public struct IslandContentEnterModifier: ViewModifier {
    public let isVisible: Bool

    public func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1.0 : 0.0)
            .blur(radius: isVisible ? 0.0 : 10.0)
            .scaleEffect(isVisible ? 1.0 : 0.95)
            .animation(IslandMotion.contentInAnimation, value: isVisible)
    }
}

public extension View {
    func islandContentOut(when active: Bool) -> some View {
        modifier(IslandContentExitModifier(isActive: active))
    }

    func islandContentIn(when visible: Bool) -> some View {
        modifier(IslandContentEnterModifier(isVisible: visible))
    }
}
```

---

## 7. Migration Roadmap

1. **Step 1 (Spec & Audit Approval)**: Review and approve `docs/MOTION_AUDIT.md` and `docs/ISLAND_MOTION_SPEC.md`.
2. **Step 2 (Token File Addition)**: Add `IslandMotion.swift` to `boringNotch/Animations/` with all tuned constants.
3. **Step 3 (Container Sizing Refactor)**: Replace `computedChinWidth` with clean state-driven geometry computed from the active `IslandState`.
4. **Step 4 (Hover & Timer Consolidation)**: Replace scattered `Task.sleep` routines in `ContentView` and `BoringViewCoordinator` with the unified `hoverOpenDelay` and `hoverCloseGrace`.
5. **Step 5 (Visual Verification)**: Verify silky-smooth spring response and zero content clipping across all 5 states.
