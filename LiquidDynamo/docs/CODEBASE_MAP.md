# Boring Notch Codebase Map

This document provides an overview of the Boring Notch codebase architecture, window and UI management, settings persistence, media handling, and guidelines for adding new widgets or tabs with minimal upstream merge conflicts.

---

## 1. Project & Scheme Information

* **Xcode Project**: `boringNotch.xcodeproj`
* **Targets**:
  * `boringNotch` (Main macOS application)
  * `BoringNotchXPCHelper` (Helper XPC Service for privileged/system actions like media key interception)
* **Primary Build Scheme**: `boringNotch`

### Build Status (Debug Configuration)
Running `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build` returns:
```text
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
```
* **Reason**: Full Xcode is not installed (or `xcode-select` is pointed to the standalone Apple Command Line Tools directory at `/Library/Developer/CommandLineTools` rather than an `Xcode.app` bundle).

---

## 2. Core Architecture & Component Map

### A. Notch Window & Shape Creation
* **Window Definition**:
  * [BoringNotchWindow.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Notch/BoringNotchWindow.swift): Custom `NSPanel` subclass configured as a floating, borderless, non-activating HUD panel (`level = .mainMenu + 3`, `canBecomeKey = false`, `canBecomeMain = false`).
  * [BoringNotchSkyLightWindow.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Notch/BoringNotchSkyLightWindow.swift): Subclass of `BoringNotchWindow` that interfaces with the private `SkyLight` framework (`SkyLightOperator`) to show the notch over fullscreen apps and the lock screen.
* **Window Lifecycle & Multi-Display Setup**:
  * [boringNotchApp.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/boringNotchApp.swift): `AppDelegate` manages display configurations, screen lock/unlock notifications, window positioning (`positionWindow`), and hosts `ContentView` in `NSHostingView`.
* **Notch Shape Geometry**:
  * [NotchShape.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Notch/NotchShape.swift): Custom SwiftUI `Shape` with animatable top and bottom corner radii producing the physical notch curve cutout.
  * [BottomRoundedRectangle.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/BottomRoundedRectangle.swift): Auxiliary shape used for rounded bottom elements.
* **Dimensions & Sizing**:
  * [sizing/matters.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/sizing/matters.swift): Defines `openNotchSize` (`CGSize(width: 640, height: 190)`), `windowSize`, closed notch dimension calculation (`getClosedNotchSize`), corner radius insets, and screen frame detection.

### B. Hover Expand/Collapse & Animations
* **State Management**:
  * [BoringViewModel.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/models/BoringViewModel.swift): Holds published `@Published var notchState: NotchState` (`.open` vs `.closed`), coordinates open/close state transitions (`open()`, `close()`), drop targeting flags, and notch dimensions.
  * [BoringViewCoordinator.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/BoringViewCoordinator.swift): Singleton `@MainActor class BoringViewCoordinator` managing active tab (`currentView: NotchViews`), sneak peek popups, and HUD activity.
* **Hover & Gesture Interactions**:
  * [ContentView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/ContentView.swift):
    * `.onHover { hovering in handleHover(hovering) }`: Debounces hover with `Defaults[.minimumHoverDuration]` before triggering `doOpen()`.
    * `.panGesture(direction: .down)` & `.panGesture(direction: .up)`: Handles swipe-down to open and swipe-up to close notch.
    * Spring Animations: Uses interactive springs (`Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)` and `Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)`).

### C. Settings Storage
* **Defaults / Persistence Framework**:
  * Uses the `Defaults` package (`Defaults.Keys`) with strongly typed keys.
  * [Constants.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/models/Constants.swift): Contains `extension Defaults.Keys` defining all user preferences (e.g., hover delays, haptics, appearances, gestures, HUD toggles, music slot layout).
  * [BoringViewCoordinator.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/BoringViewCoordinator.swift): Uses `@AppStorage` for UI state flags (`alwaysShowTabs`, `openLastTabByDefault`, `firstLaunch`, `preferred_screen_uuid`).
* **Settings UI**:
  * [SettingsView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Settings/SettingsView.swift) & [SettingsWindowController.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Settings/SettingsWindowController.swift): Native settings window tabs for General, Behavior, Appearance, Media, Shelf, HUD, etc.

### D. Now Playing Manager
* **Coordinator & State**:
  * [MusicManager.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/managers/MusicManager.swift): Central manager publishing track title, artist, album art, playback state, timestamps, average color, lyrics, and volume.
* **Media Controllers**:
  * Located in [boringNotch/MediaControllers/](file:///Users/sarvesh/Documents/boring.notch/boringNotch/MediaControllers/):
    * [MediaControllerProtocol.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/MediaControllers/MediaControllerProtocol.swift): Common interface for controllers.
    * [NowPlayingController.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/MediaControllers/NowPlayingController.swift): Uses system `MRMediaRemote` private framework / adapter.
    * [AppleMusicController.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/MediaControllers/AppleMusicController.swift): ScriptingBridge controller for Apple Music.
    * [SpotifyController.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/MediaControllers/SpotifyController.swift): AppleScript controller for Spotify.
    * [YouTube Music Controller](file:///Users/sarvesh/Documents/boring.notch/boringNotch/MediaControllers/YouTube%20Music%20Controller): Controller for YouTube Music desktop app.
  * [mediaremote-adapter/](file:///Users/sarvesh/Documents/boring.notch/mediaremote-adapter): C dynamic library bridging macOS MediaRemote calls.

### E. Shelf, Calendar, and HUD
* **Shelf**:
  * Directory: [boringNotch/components/Shelf/](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Shelf/)
  * ViewModels: `ShelfStateViewModel.swift`, `ShelfItemViewModel.swift`, `ShelfSelectionModel.swift`
  * Views: `ShelfView.swift`, `ShelfItemView.swift`, `FileShareView.swift`, `DragPreviewView.swift`
  * Services: `ShelfDropService.swift`, `ShelfPersistenceService.swift`, `QuickShareService.swift`, `QuickLookService.swift`, `ThumbnailService.swift`
* **Calendar**:
  * Directory: [boringNotch/components/Calendar/](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Calendar/)
  * View: `BoringCalendar.swift` (Calendar & reminders agenda view)
  * Managers & Providers: [CalendarManager.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/managers/CalendarManager.swift), [CalendarServiceProviding.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/Providers/CalendarServiceProviding.swift), [CalendarModel.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/models/CalendarModel.swift)
* **HUD & Live Activities**:
  * Directory: [boringNotch/components/Live activities/](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Live%20activities/)
  * Views:
    * `InlineHUD.swift`: Compact closed-notch HUD for volume/brightness/backlight adjustments.
    * `OpenNotchHUD.swift`: Expanded header HUD indicator shown when notch is open.
    * `SystemEventIndicatorModifier.swift`: Floating HUD pill shown below the notch when inline HUD is disabled.
    * `BoringBattery.swift`: Battery status and charging animations.
  * Managers: [VolumeManager.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/managers/VolumeManager.swift), [BrightnessManager.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/managers/BrightnessManager.swift), [BatteryActivityManager.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/managers/BatteryActivityManager.swift)

---

## 3. Main SwiftUI Views & Navigation Flow

1. **Top-Level Root**:
   * [ContentView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/ContentView.swift): Root view inside the window. Renders the notch outline (`currentNotchShape`), background, shadow, and calls `NotchLayout()`.
2. **Notch Content Layout**:
   * `NotchLayout()` in [ContentView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/ContentView.swift):
     * **When Closed**: Renders closed-notch widgets: `InlineHUD`, `MusicLiveActivity`, `BoringFaceAnimation`, or empty spacer.
     * **When Open**:
       * Top: [BoringHeader.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Notch/BoringHeader.swift) (containing `TabSelectionView` on the left, notch cutout mask in the center, and utility buttons / HUD / battery on the right).
       * Body: Switched view container:
         ```swift
         switch coordinator.currentView {
         case .home:
             NotchHomeView(albumArtNamespace: albumArtNamespace)
         case .shelf:
             ShelfView()
         }
         ```
3. **Home Tab Layout**:
   * [NotchHomeView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Notch/NotchHomeView.swift): Displays an `HStack` with:
     * `MusicPlayerView` (Album art, song details, progress slider, playback controls)
     * Optional `CalendarView` (if `Defaults[.showCalendar]` is true)
     * Optional `CameraPreviewView` (if `Defaults[.showMirror]` is active)

---

## 4. How to Register a New Tab or Widget

### Scenario 1: Adding a New Tab to the Expanded Notch
To register a new top-level tab (like Home and Shelf):
1. **Enum Case**:
   * Add a case to `public enum NotchViews` in [boringNotch/enums/generic.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/enums/generic.swift):
     ```swift
     public enum NotchViews {
         case home
         case shelf
         case myCustomTab
     }
     ```
2. **Tab Model Registration**:
   * Add the tab to `tabs` array in [boringNotch/components/Tabs/TabSelectionView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Tabs/TabSelectionView.swift):
     ```swift
     TabModel(label: "MyTab", icon: "sparkles", view: .myCustomTab)
     ```
3. **View Switching**:
   * In [ContentView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/ContentView.swift), add the case to `switch coordinator.currentView`:
     ```swift
     case .myCustomTab:
         MyCustomTabView()
     ```
4. **Implementation**:
   * Create `MyCustomTabView.swift` in a dedicated subfolder (e.g., `boringNotch/components/MyCustomTab/`).

### Scenario 2: Adding a Widget Inside `NotchHomeView`
To place a widget alongside Music and Calendar in the home tab:
1. **Settings Toggle**:
   * Add a key in [boringNotch/models/Constants.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/models/Constants.swift):
     ```swift
     static let showMyWidget = Key<Bool>("showMyWidget", default: true)
     ```
2. **Widget Placement**:
   * In `mainContent` of [boringNotch/components/Notch/NotchHomeView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Notch/NotchHomeView.swift), add conditional view injection:
     ```swift
     if Defaults[.showMyWidget] {
         MyWidgetView()
     }
     ```
3. **Settings UI**:
   * Add a toggle in [SettingsView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Settings/SettingsView.swift) to allow the user to toggle the widget.

---

## 5. File Impact Strategy for New Widgets

To honor the rule of keeping changes focused and upstream merges painless:

### Files to CREATE (New, Independent Files):
* `boringNotch/components/<NewWidget>/<NewWidget>View.swift`: Main SwiftUI view for the widget.
* `boringNotch/components/<NewWidget>/<NewWidget>ViewModel.swift` or `Manager`: Any isolated state, background polling, or event logic.

### Minimal Files to TOUCH (1–3 lines each):
* [boringNotch/enums/generic.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/enums/generic.swift): 1 line to add enum case (if adding a tab).
* [boringNotch/components/Tabs/TabSelectionView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Tabs/TabSelectionView.swift): 1 line in `tabs` array (if adding a tab).
* [boringNotch/ContentView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/ContentView.swift): 2 lines in `switch coordinator.currentView` to route to new view (if tab).
* [boringNotch/components/Notch/NotchHomeView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Notch/NotchHomeView.swift): 3 lines to insert widget into `mainContent` (if home widget).
* [boringNotch/models/Constants.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/models/Constants.swift): 1 line to declare default configuration key.
* [boringNotch/components/Settings/SettingsView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Settings/SettingsView.swift): Small block to add toggle in relevant settings section.
* [boringNotch.xcodeproj/project.pbxproj](file:///Users/sarvesh/Documents/boring.notch/boringNotch.xcodeproj/project.pbxproj): File reference added when the new file is compiled.

### Files to LEAVE ALONE:
* **Window & OS Layer**: [BoringNotchWindow.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Notch/BoringNotchWindow.swift), [BoringNotchSkyLightWindow.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Notch/BoringNotchSkyLightWindow.swift), [NotchShape.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/components/Notch/NotchShape.swift), [boringNotchApp.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/boringNotchApp.swift), [private/CGSSpace.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/private/CGSSpace.swift).
* **Existing Subsystems**: All existing shelf code (`components/Shelf/*`), calendar code (`components/Calendar/*`, `managers/CalendarManager.swift`), media playback (`MediaControllers/*`, `managers/MusicManager.swift`), and helper/adapter tools (`mediaremote-adapter/`, `BoringNotchXPCHelper/`).
* **Entitlements & Signing**: `boringNotch.entitlements`, build settings, certificates.
