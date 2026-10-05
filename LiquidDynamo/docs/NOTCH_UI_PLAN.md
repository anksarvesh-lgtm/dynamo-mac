# Boring Notch Dashboard UI & Architecture Plan

This document details the architectural plan to expand Boring Notch into a modular, high-performance system dashboard while preserving its core aesthetics, spring physics, and upstream mergeability.

---

## 1. System Overview & Design Goals

The expanded notch will serve as an extensible command center featuring:
1. **Connected Bluetooth Devices**: Paired and connected devices, device type glyphs, live battery levels, and connect/disconnect controls.
2. **CPU & System Stats**: Real-time overall CPU %, per-core load breakdown, memory pressure/allocation, and a historical sparkline graph.
3. **Volume & Audio Output Control**: Master volume slider, mute toggle, and an output device selector (e.g., MacBook Speakers, AirPods, External DAC).
4. **Multi-Display Brightness**: Independent sliders for all connected displays (built-in screen and external monitors).
5. **Preserved Core Modules**: Now Playing, Boring Shelf, and Calendar remain fully functional and uncompromised.
6. **Tactile "3D" Icon Dock**: A floating dock at the top of the expanded notch for switching between dashboard tabs with responsive spring animations and visual depth.

---

## 2. Notch States & Layout Behavior

### A. Collapsed State
* **Physical Dimension Matching**: Matches hardware notch dimensions on MacBook Pro/Air screens, or menu bar height / user preference on displays without a notch (via `getClosedNotchSize()`).
* **Live Info Wings (Optional Left/Right Slots)**:
  * Left & right "wings" flanking the hardware notch cutout can display live glanceable info.
  * **Supported Wings**:
    * **Left Options**: Music Album Art (existing), CPU % gauge, Bluetooth device count / primary device status, Battery status.
    * **Right Options**: Audio Spectrum visualizer (existing), Minimal Face (existing), RAM usage %, Volume/Mute status, Battery icon.
  * **Settings Controls**: User-selectable dropdowns in Settings (`closedNotchLeftWing`, `closedNotchRightWing`).
  * **Event Priority**: Urgent system events (volume/brightness HUD sneak peeks, power alerts) temporarily override the wings using existing sneak peek transitions.
  * **Zero Idle Overhead**: If CPU or Bluetooth wings are disabled, their respective background polling services remain completely stopped (`stop()`).

### B. Expanded State
* **Dimensions**: Built inside `openNotchSize` (`640 x 190` pt standard, dynamically adaptative if user configures a taller dashboard).
* **Vertical Structure**:
  1. **Top Section**:
     * Centered notch cutout mask (to seamlessly hug the physical camera hardware).
     * Flanked by the **Tactile 3D Icon Dock** on the left/center and quick utilities (webcam toggle, settings gear, battery) on the right.
  2. **Content Area**:
     * Transitioned view container hosting the active tab content below the dock.
     * Smooth asymmetric fade + scale transition when switching tabs (`.smooth(duration: 0.3)`).

---

## 3. Tab Structure & Dashboard Modules

The expanded notch will support 6 dedicated tabs:

```
┌────────────────────────────────────────────────────────────────────────┐
│  [🏠 Home] [📊 Stats] [🎧 BT] [🖥️ Sound] [📁 Shelf] [📅 Cal]   [📷 ⚙️ 🔋] │  <-- Top Dock
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│                       ACTIVE TAB CONTENT AREA                          │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### Tab 1: Home (Media & Quick Controls)
* **Left**: Existing `MusicPlayerView` (Album art, song title, artist, seek slider, and slot playback controls).
* **Center / Right**:
  * Quick volume and brightness mini-sliders.
  * Mini stat pills: CPU %, Memory %, active Bluetooth device chip.
  * Preserves existing optional `CalendarView` or `CameraPreviewView` toggles.

### Tab 2: Stats (CPU & Memory Deep-Dive)
* **Overall CPU Usage**: Bold percentage readout + smooth animated circular gauge or bar.
* **Per-Core Activity**: Compact grid or bar cluster showing real-time load per logical/efficiency/performance core.
* **Memory Breakdown**: Memory gauge showing Used vs. Wired vs. Compressed vs. Free memory.
* **Short History Graph**: Interactive Canvas-based sparkline graph showing CPU load trends over the past 30–60 seconds.

### Tab 3: Bluetooth Devices
* **Device List**: Paired and actively connected Bluetooth accessories.
* **Row Items**:
  * Type Icon (SF Symbols: `airpodspro`, `headphones`, `keyboard`, `magicmouse`, `gamecontroller`, `speaker.wave.2`).
  * Device Name with connection badge (green active dot).
  * Battery percentage indicator with battery level glyph (if reported by accessory).
* **Actions**: Context menu or click-to-toggle popover allowing "Connect" / "Disconnect".

### Tab 4: Display & Sound
* **Sound Section**:
  * Output Device Picker: Dropdown/picker listing all CoreAudio output devices with active checkmark.
  * Master volume slider with dynamic volume glyph (`speaker.wave.3`, `speaker.wave.1`, `speaker.slash`).
  * Mute toggle button.
* **Display Brightness Section**:
  * Multi-display list: Detects all connected monitors (`NSScreen.screens` / `CGDirectDisplayID`).
  * Individual brightness slider for each screen:
    * Built-in display (via `DisplayServices` / `XPCHelperClient`).
    * External displays (via `DisplayServices` or DDC/CI software emulation).
  * Labeled clearly with the monitor’s friendly localized name (e.g., "Built-in Liquid Retina XDR", "Studio Display", "Dell 4K").

### Tab 5: Shelf
* Reuses existing [ShelfView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Shelf/Views/ShelfView.swift) without modifications.

### Tab 6: Calendar
* Reuses existing [BoringCalendar.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Calendar/BoringCalendar.swift) without modifications.

---

## 4. Service Layer Architecture (Lazy Polling & Lifecycle Control)

To ensure zero impact on battery life and system performance, **nothing will poll while the notch is closed or while a tab is inactive**.

### Common Service Protocol
```swift
@MainActor
protocol DashboardService: AnyObject {
    var isRunning: Bool { get }
    func start()
    func stop()
}
```

### Module Services:

#### 1. `SystemStatsService` (`Services/SystemStatsService.swift`)
* **CPU Metric Engine**:
  * Queries Mach kernel host statistics:
    * `host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, ...)` for per-core ticks.
    * Computes delta against previous tick (`user`, `system`, `idle`, `nice`).
  * Overall CPU load derived from cumulative ticks.
* **Memory Metric Engine**:
  * Calls `host_statistics64(mach_host_self(), HOST_VM_INFO64, ...)` to calculate:
    * Active, Inactive, Wired, Compressed memory relative to total physical RAM (`ProcessInfo.processInfo.physicalMemory`).
* **Historical Buffer**:
  * Ring buffer maintaining the last 30 readings (`[Double]`) updated every interval.
* **Lifecycle**:
  * Polling interval: 1.0s (or 1.5s in low power mode).
  * Driven by a background `Task` with `Task.sleep` or `DispatchSourceTimer`.
  * `start()`: Initializes tick snapshot and starts timer.
  * `stop()`: Cancels background task immediately and cleans up Mach memory allocations (`vm_deallocate`).

#### 2. `BluetoothService` (`Services/BluetoothService.swift`)
* **Device Enumeration**:
  * Uses `IOBluetooth` framework (`IOBluetoothDevice.pairedDevices()`).
  * Filters for connected devices (`device.isConnected()`).
  * Maps device Major/Minor device classes to appropriate SF Symbols.
* **Battery Level Retrieval**:
  * Reads battery levels from `IORegistry` (`AppleDeviceManagementHIDEventService` / `BatteryPercent` properties) for Apple & Beats accessories.
* **Event Notifications**:
  * Registers for connect/disconnect notifications using `IOBluetoothDevice.register(forConnectNotifications:selector:)`.
* **Lifecycle**:
  * Active polling is NOT used; it relies on IOKit/Bluetooth notifications.
  * Full list refresh only triggers on `start()` (when opening the Bluetooth tab or expanding the notch with BT wing enabled) and upon connect/disconnect callbacks.

#### 3. `AudioDeviceService` (`Services/AudioDeviceService.swift`)
* **CoreAudio HAL Integration**:
  * Queries `kAudioHardwarePropertyDevices` to list available audio hardware.
  * Filters for devices with output channels (`kAudioDevicePropertyScopeOutput`).
  * Retrieves localized device name (`kAudioObjectPropertyName` / `kAudioDevicePropertyDeviceNameCFString`).
  * Queries `kAudioHardwarePropertyDefaultOutputDevice` to identify the current default.
* **Switching & Volume**:
  * Sets default output device via `AudioObjectSetPropertyData`.
  * Interfaces with existing [VolumeManager.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/managers/VolumeManager.swift) for volume reading and adjustment.
* **Lifecycle**:
  * Listens to CoreAudio hardware property changes (`AudioObjectAddPropertyListenerBlock`).
  * Only active when the Display & Sound tab or Home tab is visible.

#### 4. `MultiDisplayBrightnessService` (`Services/MultiDisplayBrightnessService.swift`)
* **Display Enumeration**:
  * Iterates `NSScreen.screens` and extracts `displayID` (`NSScreenNumber`).
  * Categorizes displays into **Built-in** vs. **External**.
* **Brightness Adjustment**:
  * **Built-in**: Delegates to existing `XPCHelperClient.shared.setScreenBrightness(_:)` or `DisplayServicesSetBrightness`.
  * **External Apple Displays**: Uses `DisplayServicesSetBrightness` (supported on Apple Studio Display, Pro Display XDR, LG UltraFine).
  * **Standard External Displays**: Provides gamma/software overlay fallback where DDC is not available.
* **Display Configuration Changes**:
  * Listens to `NSApplication.didChangeScreenParametersNotification` to dynamically update display sliders when monitors are plugged/unplugged.

#### 5. `DashboardCoordinator` (`Services/DashboardCoordinator.swift`)
* Central supervisor coordinating lifecycle:
  * Observes `BoringViewModel.shared.notchState` and `BoringViewCoordinator.shared.currentView`.
  * Automatically calls `start()` on services needed for the active view or enabled collapsed wings.
  * Automatically calls `stop()` on all services when the notch collapses (unless a collapsed wing requires ongoing updates, e.g., CPU wing polling at reduced 2.0s rate).

---

## 5. Existing Code Reuse & File Impact

### Existing Code Reused
* **[VolumeManager.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/managers/VolumeManager.swift)**: Retain existing volume ramping, mute logic, and HUD sneak peek triggering.
* **[BrightnessManager.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/managers/BrightnessManager.swift)**: Reused for primary display brightness synchronization.
* **[BatteryStatusViewModel.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/models/BatteryStatusViewModel.swift)**: Reused for battery charging state, wattages, and popovers.
* **[BoringHeader.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Notch/BoringHeader.swift)**: Header layout structure, notch cutout mask, and utility capsule buttons.
* **[TabSelectionView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Tabs/TabSelectionView.swift)**: Base pattern for tab navigation and capsule transitions.
* **[ShelfView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Shelf/Views/ShelfView.swift) & [BoringCalendar.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Calendar/BoringCalendar.swift)**: Fully preserved without internal modifications.

### New Files to Create (Zero Risk to Upstream Merges)
```
boringNotch/
├── services/
│   ├── DashboardService.swift                // Common protocol & lifecycle
│   ├── SystemStatsService.swift              // CPU & RAM Mach engine
│   ├── BluetoothService.swift                // IOBluetooth & battery reader
│   ├── AudioDeviceService.swift              // CoreAudio output device selector
│   ├── MultiDisplayBrightnessService.swift   // Multi-monitor brightness controller
│   └── DashboardCoordinator.swift            // Lifecycle orchestrator
└── components/
    └── Dashboard/
        ├── Dock/
        │   ├── DashboardDockView.swift       // 3D tactile icon dock
        │   └── DockItemView.swift            // Tactile 3D button with glow/depth
        ├── Tabs/
        │   ├── DashboardHomeView.swift       // Home tab (media + quick sliders)
        │   ├── StatsView.swift               // CPU, cores, RAM & sparkline graph
        │   ├── BluetoothDevicesView.swift    // Bluetooth device cards & actions
        │   └── DisplaySoundView.swift        // Multi-display & audio output picker
        └── Common/
            ├── SparklineGraph.swift          // Canvas-based real-time line chart
            ├── MiniStatPill.swift            // Glanceable stat badge
            └── CircularGaugeView.swift       // Animated circular progress gauge
```

### Files to Touch (Small, Surgical Insertions)
1. **[boringNotch/enums/generic.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/enums/generic.swift)**:
   * Add new cases to `NotchViews`:
     ```swift
     public enum NotchViews {
         case home
         case stats
         case bluetooth
         case displaySound
         case shelf
         case calendar
     }
     ```
2. **[boringNotch/models/Constants.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/models/Constants.swift)**:
   * Add settings keys for collapsed wings, default tabs, and refresh rates:
     ```swift
     static let closedNotchLeftWing = Key<ClosedNotchWingOption>("closedNotchLeftWing", default: .media)
     static let closedNotchRightWing = Key<ClosedNotchWingOption>("closedNotchRightWing", default: .spectrum)
     static let statsHistoryLength = Key<Int>("statsHistoryLength", default: 30)
     ```
3. **[boringNotch/ContentView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/ContentView.swift)**:
   * Update `switch coordinator.currentView` to render the new dashboard tab views.
   * Add collapsed-state wing slots in `NotchLayout()`.
4. **[boringNotch/components/Tabs/TabSelectionView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Tabs/TabSelectionView.swift)**:
   * Register the new tab definitions in the tab model list.
5. **[boringNotch/components/Settings/SettingsView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Settings/SettingsView.swift)**:
   * Add toggles and preference pickers for dashboard modules and collapsed wing behaviors.

---

## 6. Permissions, Info.plist & Entitlements

> [!IMPORTANT]
> **No permissions, entitlements, or Info.plist files will be edited without explicit user approval.** Below is the exact inventory of system requirements:

1. **Bluetooth Framework (`IOBluetooth`)**:
   * **Required Property**: `NSBluetoothAlwaysUsageDescription` in `boringNotch/Info.plist`.
   * **Purpose**: Required on macOS 11+ to discover, inspect, and connect/disconnect Bluetooth peripherals.
   * **Fallback**: Without this string, system will crash upon first invocation of `IOBluetoothDevice`.
2. **CoreAudio HAL**:
   * **Entitlements**: None required.
   * **Info.plist**: None required. CoreAudio output device enumeration and volume manipulation are standard user-space APIs.
3. **Mach Kernel System Stats (`host_processor_info`, `host_statistics64`)**:
   * **Entitlements**: None required. Standard Mach kernel statistics are accessible to all user processes without sandbox restrictions.
4. **Multi-Display Brightness**:
   * **Built-in**: Already handled via existing `BoringNotchXPCHelper` and `DisplayServices`.
   * **External Displays**: Uses standard `CoreGraphics` display IDs and `DisplayServices` SPI. No sandbox permissions required in current unsigned/ad-hoc development configuration.

---

## 7. Multi-Display & Non-Notch Hardware Handling

### Non-Notch Macs (External monitors, iMacs, Mac mini, MacBook without notch)
* **Detection**: Evaluated dynamically via `screen.safeAreaInsets.top <= 0`.
* **Collapsed Representation**:
  * Retains a floating, compact pill pinned to the top-center of the screen.
  * Height adapts to `Defaults[.nonNotchHeightMode]` (defaults to menu bar height or 32pt).
  * Collapsed live info wings flank the center pill smoothly without clipping.
* **Expanded Dashboard**:
  * Displays cleanly as a top-centered floating rounded card.
  * The center notch cutout mask is automatically omitted when `safeAreaInsets.top <= 0` (via `BoringHeader.swift` line 32), leaving a continuous, clean top dock.

### Multi-Display Environments
* **Target Display Tracking**:
  * Handled via `BoringViewCoordinator.shared.selectedScreenUUID`.
  * If `Defaults[.showOnAllDisplays]` is enabled, each display receives its own window and `BoringViewModel`.
* **Hardware Adaptation**:
  * Moving the cursor or dragging to an external monitor properly re-evaluates notch geometry and display-specific brightness controls.
  * In the **Display & Sound Tab**, all connected screens are listed simultaneously with real-time brightness sliders, clearly labeling the currently focused display.

---

## 8. Step-by-Step Implementation Roadmap

Execution is split into discrete phases. Each step produces buildable, verifiable code:

* [ ] **Phase 1: Service Layer Foundation**
  * Create `DashboardService` protocol and lifecycle management.
  * Implement `SystemStatsService` (Mach host statistics, CPU overall/per-core, memory, ring buffer).
  * Implement `BluetoothService` (IOBluetooth device enumeration, connection status, battery lookup).
  * Implement `AudioDeviceService` (CoreAudio output device list and selection).
  * Implement `MultiDisplayBrightnessService` (NSScreen enumeration and per-screen brightness).
  * Implement `DashboardCoordinator` to bind `start()`/`stop()` to notch expansion and tab selection.

* [ ] **Phase 2: Tab Registration & State Integration**
  * Update `NotchViews` in [generic.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/enums/generic.swift).
  * Add configuration keys to `Constants.swift`.
  * Register new tabs in `TabSelectionView.swift`.
  * Wire view switching inside `ContentView.swift`.

* [ ] **Phase 3: Module Tab Views**
  * Build `StatsView` (CPU gauges, per-core cluster, memory bar, `SparklineGraph`).
  * Build `BluetoothDevicesView` (accessory cards, battery glyphs, connect/disconnect popups).
  * Build `DisplaySoundView` (output device picker, volume slider, multi-display brightness sliders).
  * Build `DashboardHomeView` (integrated media view + quick controls + mini stats).

* [ ] **Phase 4: Collapsed-State Live Info Wings**
  * Add configurable left/right wings to `NotchLayout()` in [ContentView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/ContentView.swift).
  * Hook up CPU % pill and Bluetooth connectivity status icon to collapsed wings.
  * Verify zero polling when wings are inactive.

* [ ] **Phase 5: Tactile 3D Icon Dock (Later Stage)**
  * Create `DashboardDockView` and `DockItemView` with modern 3D lighting, bevel highlights, subtle gradients, and spring haptics.
  * Replace the basic header tab bar with the 3D dock.

* [ ] **Phase 6: Settings & Multi-Monitor Polish**
  * Add preferences section in `SettingsView` for module toggles and wing configurations.
  * Test on non-notch external screens and multi-display setups.

---

## 9. Next Steps

Awaiting your review and approval of this plan before writing any code or initiating Phase 1.
