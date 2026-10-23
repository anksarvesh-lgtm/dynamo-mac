# LiquidDynamo Motion & State Audit

> **Document**: `docs/MOTION_AUDIT.md`  
> **Status**: Complete — Awaiting Approval  
> **Target**: Dynamic Island Behavior & Physics Model  
> **Date**: October 4, 2026  

---

## 1. Executive Summary

This audit evaluates all interaction state management, windowing behavior, container shape resizing, animation curves, and timing mechanisms in the current codebase.

### Primary Finding
The current codebase exhibits noticeable animation "jank" and abrupt visual transitions due to:
1. **Binary State Architecture**: The system only understands `.open` and `.closed` states in `BoringViewModel`, treating all intermediate presentations (battery banners, Bluetooth connection banners, 3D showcase popups, collapsed live info wings, and HUD overlays) as ad-hoc visual overrides layered on top of the closed notch.
2. **Scattered Magic-Number Sizing**: Container width is computed in [ContentView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/ContentView.swift) via a 14-branch `computedChinWidth` property with hardcoded pixel increments (`+240`, `410`, `640`, `+200`, `360`, `+50`, `+70`, `+16`).
3. **Competing Asynchronous Timers**: Hover, auto-dismiss, debounce, and peek timers use uncoordinated `Task.sleep` and `DispatchQueue` calls. Rapid mouse movement or rapid successive events cause tasks to race and cancel inconsistently.
4. **Lack of Staggered Content Choreography**: Content inside the notch scales and fades simultaneously with the container border, causing text and controls to clip through the black bezel while the container is in mid-expansion.

---

## 2. Where Interaction State Lives

Interaction and display state is currently fragmented across multiple singletons and view-local `@State` properties:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Current State Dispersion                        │
└────────────────────────────────────────────────────────────────────────┘
       │
       ├─► BoringViewModel.shared
       │     ├─ notchState: .open | .closed
       │     ├─ notchSize & closedNotchSize (CGSize)
       │     ├─ effectiveClosedNotchHeight (CGFloat)
       │     ├─ chinHeight (CGFloat)
       │     ├─ hideOnClosed (Bool)
       │     ├─ isBatteryPopoverActive (Bool)
       │     └─ dropZoneTargeting / dragDetectorTargeting (Bool)
       │
       ├─► BoringViewCoordinator.shared
       │     ├─ currentView: NotchViews (.home, .stats, .bluetooth, etc.)
       │     ├─ sneakPeek: (HUD: volume, brightness, backlight, mic)
       │     │    └─ auto-hide via sneakPeekTask (Task.sleep)
       │     ├─ expandingView: (battery banner, bluetooth banner, download)
       │     │    └─ auto-hide via expandingViewTask (Task.sleep)
       │     └─ helloAnimationRunning (Bool)
       │
       ├─► DeviceShowcaseCoordinator.shared
       │     ├─ isShowing: Bool
       │     ├─ currentDevice: DeviceIdentity?
       │     └─ dismissTask: Task.sleep(4.0s / 2.5s)
       │
       ├─► BluetoothBatteryAlertManager.shared
       │     ├─ isShowingAlertPopup: Bool
       │     ├─ hasActiveLowBatteryDot: Bool
       │     └─ dismissTask: Task.sleep(5.0s)
       │
       └─► ContentView (@State local to window view)
             ├─ isHovering: Bool
             ├─ hoverTask: Task.sleep(0.3s open / 0.1s close)
             ├─ gestureProgress: CGFloat
             ├─ haptics: Bool
             └─ anyDropDebounceTask: Task.sleep(0.5s)
```

### Critical Flaws in Current State Architecture
- **State Collisions**: If music is playing (`MusicLiveActivity`), a USB device is plugged in (`DeviceShowcaseCoordinator`), and the user adjusts volume (`InlineHUD`), three separate subsystems compete to render within the same collapsed notch height, resulting in layout flickering.
- **Hover Race Conditions**: In `ContentView.swift`, moving the mouse out of the notch schedules a close task with `Task.sleep(for: .milliseconds(100))`. If the cursor re-enters at 95 ms, the task cancellation often races with `MainActor.run`, causing the notch to close while the cursor is hovering directly over it.

---

## 3. Window, Shape, and Container Layout Mechanisms

### A. NSWindow Frame Management
* **Window Class**: [BoringNotchWindow.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Notch/BoringNotchWindow.swift) and [BoringNotchSkyLightWindow.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Notch/BoringNotchSkyLightWindow.swift) (`NSPanel`).
* **Frame Sizing**:
  * Set once at creation in [boringNotchApp.swift:235](file:///Users/sarvesh/Documents/boring.notch/boringNotch/boringNotchApp.swift#L235):
    ```swift
    let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
    // windowSize = CGSize(width: 640, height: 190 + 20)
    ```
  * Positioned at the top center of the screen via `window.setFrameOrigin(...)`.
* **Window Frame Animation**:
  * **The NSWindow frame itself is NOT continuously animated.**
  * The window remains a static `640 x 210` transparent canvas at the top of the screen.
  * *Advantage*: Zero macOS WindowServer frame resizing latency or black flash artifacts.
  * *Constraint*: The visual notch is completely drawn inside this canvas. Any secondary "detached bubble" (for minimal multi-activity) must fit inside the 640 pt canvas, or secondary detached auxiliary panels must be spawned.

### B. Geometry & Shape Clipping
* **Shape Implementation**: [NotchShape.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Notch/NotchShape.swift).
* Uses quadratic Bezier curves (`addQuadCurve`) to render the top ears and bottom corners.
* Conforms to `AnimatablePair<CGFloat, CGFloat>` for `(topCornerRadius, bottomCornerRadius)`.
* **Current Radii Insets**:
  * Closed: Top = 6 pt, Bottom = 14 pt
  * Opened: Top = 19 pt, Bottom = 24 pt
* **Limitation**: The shape assumes standard macOS notch geometry (outward top ears, straight bottom chin). It does not dynamically adjust into a pill/capsule shape for floating non-notch displays or detached bubbles.

### C. Container Sizing Pipeline
* **Width**: Computed by `computedChinWidth` in `ContentView.swift:65-106`. Dynamically adjusts width by checking:
  1. `showcaseCoordinator.isShowing`: `max(closedNotchSize.width + 240, 410)`
  2. `coordinator.expandingView.type == .battery`: `640`
  3. `coordinator.expandingView.type == .bluetooth`: `max(closedNotchSize.width + 200, 360)`
  4. `musicLiveActivity`: `closedNotchSize.width + 2 * (height - 12) + 20`
  5. `showNotHumanFace`: `closedNotchSize.width + 2 * (height - 12) + 20`
  6. Collapsed Wings (CPU +50, BT +50, Network +70, Low Battery Dot +16)
* **Height**: Controlled by:
  ```swift
  .frame(height: vm.notchState == .open ? vm.notchSize.height : nil)
  ```
  When closed, height collapses to `effectiveClosedNotchHeight` (~32 pt on notched screens, 32 pt or menu bar height on external displays).

---

## 4. Current Animation Curves & Durations Inventory

Animations across the codebase are currently fragmented with widely divergent springs and curves:

| Location | Trigger / Purpose | Animation Curve & Parameters | Assessment |
| :--- | :--- | :--- | :--- |
| `ContentView.swift:45` | Movement / Resizing spring | `interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)` | Decent interactive tracking, but overridden in subviews. |
| `ContentView.swift:148` | Notch Open (Expansion) | `spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)` | Slightly sluggish response; lacks initial snap. |
| `ContentView.swift:149` | Notch Close (Collapse) | `spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)` | Critically damped (1.0). Feels heavy and slow to dismiss. |
| `ContentView.swift:464` | Tab Navigation Swap | `.smooth(duration: 0.3)` | Ease-in-out curve; lacks physical spring feel. |
| `ContentView.swift:468` | Dashboard View Transition | `.scale(0.8).combined(with: .opacity)` with `.smooth(0.35)` | Fades too slowly; elements pop into place awkwardly. |
| `ContentView.swift:249` | Drag Gesture Pull | `.smooth` (tied to `gestureProgress`) | Linear smoothing; lacks elastic resistance. |
| `BoringViewCoordinator:221` | SneakPeek HUD Appear | `.smooth` | Flat duration; lacks punchy alert physics. |
| `DeviceShowcase:64` | 3D Showcase Presentation | `spring(response: 0.42, dampingFraction: 0.8)` | Custom curve isolated from main notch spring. |
| `DeviceShowcase:75` | 3D Showcase Dismissal | `spring(response: 0.38, dampingFraction: 0.82)` | Disconnected from main notch collapse curve. |
| `BluetoothBatteryAlert:438` | Low Battery Alert Appear | `spring(response: 0.42, dampingFraction: 0.8)` | Duplicated curve definition. |
| `BluetoothBatteryAlert:450` | Low Battery Alert Dismiss | `spring(response: 0.38, dampingFraction: 0.82)` | Duplicated curve definition. |
| `NotchHomeView.swift:461` | Camera Preview Unfold | `interactiveSpring(response: 0.32, dampingFraction: 0.76)` | Independent local spring. |
| `NotchHomeView.swift:575` | Volume/Brightness Slider Drag | `spring(response: 0.35, dampingFraction: 0.7)` | Good slider spring, but uncoordinated with notch body. |
| `drop.swift:21` | Legacy Central Animation | `spring(.bouncy(duration: 0.4))` | Unused legacy placeholder. |

---

## 5. Delays, Timers & Asynchronous Sequencing (Root Causes of Jank)

Below is an exhaustive inventory of hardcoded delays and timers in the active codebase:

### A. Hover Sequencing
* **Hover Open Delay** ([ContentView.swift:642](file:///Users/sarvesh/Documents/boring.notch/boringNotch/ContentView.swift#L642)):
  * `Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))`
  * Defaults to `0.30 s`. Feels sluggish and unresponsive compared to iOS Dynamic Island.
* **Hover Close Grace Delay** ([ContentView.swift:655](file:///Users/sarvesh/Documents/boring.notch/boringNotch/ContentView.swift#L655)):
  * `Task.sleep(for: .milliseconds(100))`
  * `100 ms` is far too short. Normal mouse tracking often leaves the hover rect for 120–180 ms when moving toward a corner or button, triggering an unintended collapse.

### B. Auto-Dismiss Timers
* **HUD SneakPeek Auto-Hide** ([BoringViewCoordinator.swift:242](file:///Users/sarvesh/Documents/boring.notch/boringNotch/BoringViewCoordinator.swift#L242)):
  * `Task.sleep(for: .seconds(duration))` with hardcoded `1.5 s`.
* **Notification Banner Auto-Hide** ([BoringViewCoordinator.swift:288](file:///Users/sarvesh/Documents/boring.notch/boringNotch/BoringViewCoordinator.swift#L288)):
  * `Task.sleep(for: .seconds(expandingView.type == .download ? 2 : 3))`.
* **3D Device Showcase Dismissal** ([DeviceShowcaseCoordinator.swift:100](file:///Users/sarvesh/Documents/boring.notch/boringNotch/Features/DeviceShowcase/DeviceShowcaseCoordinator.swift#L100)):
  * `Task.sleep(for: .seconds(4.0))` on presentation; `2.5 s` on unhover.
* **Bluetooth Battery Alert Dismissal** ([BluetoothBatteryAlertManager.swift:478](file:///Users/sarvesh/Documents/boring.notch/boringNotch/Features/Bluetooth/BluetoothBatteryAlertManager.swift#L478)):
  * `Task.sleep(nanoseconds: 5_000_000_000)` (`5.0 s`).
* **Webcam Authorization Timeout** ([BoringViewModel.swift:171](file:///Users/sarvesh/Documents/boring.notch/boringNotch/models/BoringViewModel.swift#L171)):
  * `DispatchQueue.main.asyncAfter(deadline: .now() + 2)` (`2.0 s`).

---

## 6. Summary of Architectural Deficits to Resolve

1. **Replace Binary State with Island State Machine**:
   Transition from `.open` / `.closed` to 5 distinct, well-defined physical states: `idle`, `compact`, `minimal`, `expanded`, and `alertPop`.
2. **Eliminate Magic Sizing Logic**:
   Replace manual pixel arithmetic in `computedChinWidth` with state-driven layout contracts defined by each state.
3. **Establish Unified Spring Curves**:
   All container morphs must use centrally defined springs (`expand`, `collapse`, `alertPop`), tuned for elastic iOS physics.
4. **Implement Staggered Content Choreography**:
   Content must exit *before* the container changes size, and enter *after* the container has nearly reached its destination, preventing text overlap and edge clipping.
5. **Decouple Timers from View Logic**:
   Standardize dwell and grace intervals into a single timing configuration.
