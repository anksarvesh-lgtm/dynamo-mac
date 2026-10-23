# LiquidDynamo 1.9.4 Codebase Map

This document provides a comprehensive overview of the **LiquidDynamo 1.9.4** codebase architecture, window and geometry management, motion engine, storage cleaner integration (Purge engine parity), configurable wing telemetry, color & clipboard tools, and UI layout.

---

## 1. Project & Build Configuration

* **Xcode Project**: `LiquidDynamo.xcodeproj`
* **Root Application Source**: `liquiddinamo/`
* **Targets**:
  * `LiquidDynamo` (Main macOS native application)
* **Build Tooling**:
  * Clean compilation with Swift 5.9+ / Swift 6 on macOS 14.0+ (Sonoma, Sequoia).
  * Build script: `scripts/compile_release.sh`
  * Packaging script: `scripts/deploy_and_package.sh`

---

## 2. Core Architecture & Component Map

### A. Window & Notch Geometry Engine
* **Physical Cutout & Safe Area**:
  * [NotchSafeAreaEngine.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/sizing/NotchSafeAreaEngine.swift): Central source of truth for all display bounds, hardware cutout dimensions (`rawNotchWidth`, `rawNotchHeight`), menu bar thickness, and notch exclusion zones. Never hardcode screen or notch sizes.
* **Window Management**:
  * [LiquidDynamoApp.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/LiquidDynamoApp.swift): `AppDelegate` manages screen parameter changes, display reconnection, event monitors, and hosts `ContentView` in an `NSHostingView`.
  * [BoringNotchWindow.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/components/Notch/BoringNotchWindow.swift): Borderless, non-activating floating HUD panel (`level = .mainMenu + 3`).
* **Dimensions & Sizing**:
  * [sizing/matters.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/sizing/matters.swift): Defines `openNotchSize`, closed notch dimension calculation (`getClosedNotchSize`), corner radius insets, and screen frame detection.

### B. Motion Engine & Dynamic Island Routing
* **State & Organic Springs**:
  * [IslandController.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Motion/IslandController.swift): Singleton `@MainActor class IslandController` managing `.closed`, `.compact`, `.expanded`, and `.alertPop` states, target dimensions, minimum height clamping floors, hover tracking, and active organic dropdown selection (`activeOrganicItem`).
  * [IslandMotion.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Motion/IslandMotion.swift): Liquid-glass spring physics and timings.
  * [DynamicIslandHub.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Motion/DynamicIslandHub.swift): Central dispatcher for hardware HUDs, audio/brightness events, battery/power announcements, track changes, and clipboard copy alerts.
* **Liquid Alert & HUD Capsule**:
  * [IslandAlertView.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Motion/IslandAlertView.swift): Contains `LiquidAlertCapsuleContainer<Content: View>`, providing a 3D obsidian capsule with dynamic width derived via `IslandController.alertCapsuleSize(for:)`.

### C. Dashboard & Organic Notch
* [LiquidOrganicNotchView.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Dashboard/LiquidOrganicNotchView.swift):
  * **Notch Exclusion Zone**: Wraps around physical camera cutout.
  * **Primary Hover Row**: Connected devices, Clipboard status, Dropper shelf status, Storage Purge button, and Color Dropper button.
  * **System Telemetry**: CPU temperature and RAM usage.
  * **Interactive Detail Cards**:
    * Device detail card (with 3D SceneKit rendering and battery status)
    * Clipboard history card
    * File dropper shelf card
    * Purge storage cleaner card
    * Color dropper swatch card

### D. Storage Cleaner (Purge Integration)
* **Allowlist & Safety Policy**:
  * [StorageSafetyPolicy.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Storage/StorageSafetyPolicy.swift): Strict allowlists, exact path component matching (`url.pathComponents`) replacing unsafe substrings, two-layer defense-in-depth (`evaluate(url) == .allow`), protected cache folder names, bundle ID patterns, JetBrains local history protection, and Ruby gems protection.
* **Models & Engine**:
  * [StorageCleanupModels.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Storage/StorageCleanupModels.swift): Data models for `SafetyTier` (`safeToClean`, `checkFirst`), categories (`.caches`, `.developer`, `.largeFiles`, `.appUninstaller`, `.logs`, `.downloads`, `.trash`), and duplicate detection.
  * [StorageCleanupManager.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/managers/StorageCleanupManager.swift): Background scanning, Full Disk Access checking, CryptoKit 3-stage duplicate file detector, managed library skips (Photos, Music, TV, iMovie), VM bundle management, local AI model stores (`.ollama`, `.lmstudio`, `.cache/huggingface`), running-app protection, and trash-only deletion via `FileManager.default.trashItem`.
* **UI**:
  * [NotchStorageCleanerView.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Storage/NotchStorageCleanerView.swift): Multi-segment visual storage bar, FDA onboarding alert, and cleanup confirmation.

### E. Configurable Notch Wings & Telemetry Slots
* **Slot System**:
  * [Constants.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/models/Constants.swift): `WingMetric` enum (13 metric cases), `migrateWingMetricsIfNeeded()`, and strongly-typed `Defaults.Keys`.
  * [NetworkSpeedProvider.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Network/NetworkSpeedProvider.swift): Darwin `getifaddrs` speed monitor with on-demand polling for ~0% idle CPU.
  * [SystemStatsService.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/SystemStats/SystemStatsService.swift): SMC temperature and memory pressure monitor.
  * [ContentView.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/ContentView.swift): `CollapsedLiveInfoWingsView` rendering left and right stream drops flanking the hardware notch.
  * [LookSettingsView.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/components/Settings/LookSettingsView.swift): Metric pickers, wing width slider, and `MockNotchWingsPreview`.

### F. Tools: Clipboard, Dropper & Color Dropper
* **Clipboard History**:
  * [ClipboardHistoryService.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Clipboard/ClipboardHistoryService.swift): Background monitor polling `NSPasteboard.general.changeCount`, filtering concealed types, deduplicating, and triggering clipboard alert capsule.
  * [LiquidClipboardRegionView.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Clipboard/Views/LiquidClipboardRegionView.swift): Organic clipboard history view with pin/delete/copy actions.
* **File Shelf / Dropper**:
  * Directory: `liquiddinamo/components/Shelf/`
  * Drag-in accepts files, URLs, text, and images. Drag-out removes reference without deleting files. QuickLook via `QuickLookService.swift` and AirDrop via `QuickShareService.swift`.
* **Color Dropper**:
  * [ColorDropperTool.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/ColorDropper/ColorDropperTool.swift): Screen magnifier sampling via AppKit `NSColorSampler`. Stores HEX, RGB, HSL, luminance, and recent colors history. Prevents island collapse during sampling.

### G. Plexo Multi-Network Download Accelerator
* **Architecture & Engines**:
  * [PlexoModels.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Plexo/PlexoModels.swift): Data types for multi-network interfaces (`PlexoInterface`), download tasks (`PlexoDownloadTask`), chunk slices, bandwidth settings, and formatters.
  * [PlexoNetworkManager.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Plexo/PlexoNetworkManager.swift): Hardware interface discovery via `networksetup` & Darwin `getifaddrs`, `NWPathMonitor` connection observer, custom color and nickname persistence, and real-time per-adapter bandwidth sampling.
  * [PlexoDownloadEngine.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Plexo/PlexoDownloadEngine.swift): Multi-connection parallel chunk downloader, work stealing, slow chunk racing, sparse file writes, pause/resume, and metadata serialization.
  * [PlexoTorrentEngine.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Plexo/PlexoTorrentEngine.swift): BEP 0003 Bencode parser, magnet link decoder, and torrent metainfo extractor.
  * [PlexoBandwidthManager.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Plexo/PlexoBandwidthManager.swift): Global rate limits, Slow Mode, and off-peak download scheduling.
* **UI**:
  * [PlexoView.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Plexo/PlexoView.swift): 560x482 liquid-glass multi-network dashboard with segmented chunk progress, per-adapter speed strips, and download management.
  * [PlexoNetworkCardView.swift](file:///Users/sarvesh/Desktop/LiquidDynamo-1.9.2/liquiddinamo/Features/Plexo/PlexoNetworkCardView.swift): Embedded status card inside `NetworkTabView`.

---

## 3. UI Navigation & Window Hierarchy

1. **Root**: `ContentView.swift`
   - Handles gesture recognizers, closed notch wings, and expands into `LiquidOrganicNotchView`.
2. **Dashboard Coordinator**: `LiquidViewCoordinator.swift`
   - Routes between `.home`, `.shelf`, `.stats`, and `.settings`.
3. **Settings**: `SettingsView.swift` & `SettingsWindowController.swift`
   - Form-based native macOS tabs: General, Appearance/Look, Wings & Slots, Shelf, Storage, and Permissions.
