# Changelog — LiquidDynamo

All notable changes, bug fixes, and feature enhancements in LiquidDynamo are documented in this file.

---

## [1.9.6] — 2026-10-23

### FileDroid & OpenMTP Android Storage Bridge (Option B)
- **Protocol Abstraction (`AndroidTransferBackend`)**: Introduced clean backend protocol decoupling with `AdbBackend` and `MtpBackend` implementations, enabling high-performance ADB file operations alongside native MTP fallback without proprietary drivers.
- **Finder External SSD Volume Emulation**: Connected Android devices mount automatically into macOS Finder as virtual external drives with standard storage folder hierarchies (`DCIM`, `Download`, `Documents`, `Music`, `Movies`).
- **Real-Time Device Telemetry**: Live readout of device manufacturer, market name, Android OS version, battery percentage, charging state, battery temperature, and internal/SD storage capacity meters.
- **Robust Transfer Engine**: Process-based streaming transfers with single-quote shell escaping for spaces and non-ASCII paths, transfer progress drawer, retry on disconnect, and customizable file conflict resolution (`Replace`, `Keep Both`, `Skip`).
- **Dedicated Settings Pane**: Added `SettingsFileDroidView` in Settings with ADB auto-detect, custom path browse, Finder auto-mount toggles, and concurrency limit steppers.

### Plexo Turbo Downloader & Multi-Network Booster
- **Parallel Chunk Acceleration**: Multi-threaded byte-range downloader partitioning large files into chunks handled by an asynchronous worker pool.
- **Multi-Network Interface Bonding**: Concurrent multi-interface streaming combining Wi-Fi, Gigabit Ethernet, and USB-C cellular hotspots.
- **Single-Stream Resilient Fallback**: Automatic detection of servers lacking byte-range support (`supportsRange == false`) with streaming direct-to-disk downloads.
- **BitTorrent & Magnet Link Engine**: Built-in BEP 0003 Bencode decoder and magnet URI parser.
- **Bandwidth Throttling & Slow Mode**: Global speed limiter and one-click "Slow Mode" toggle.
- **Dedicated Settings Pane**: Added `SettingsPlexoView` featuring interface toggles, chunk size picker, parallel connection steppers, and clipboard auto-detect toggle.

### Interactive Collapsed Notch Wings & Live Readout Expansion
- **Collapsed Detail Expansion**: Clicking or hovering wing icons in the collapsed notch state reveals detailed telemetry readouts (e.g. `45%`, `52°C`, `↓14.2M ↑2.1M`).
- **Intelligent Auto-Collapse Timer**: Automatically collapses revealed details after 3 seconds, or immediately upon outside click or island expansion.
- **Consolidated Hit-Testing Geometry**: Single-source `NotchSafeAreaEngine.shared.collapsedWingHitRects(for:)` with +8pt padding matching drawn layout.
- **Native Event Passthrough**: Window hit testing strictly returns true inside the notch and wing capsules, passing all other events through to underlying apps and macOS menu bar.

---

## [1.9.5] — 2026-10-23

### Hover-to-Click Detail Card Pinning & Window Stability
- **Instant Pinned State Promotion**: Clicking any status button (Connected Device, Clipboard, Dropper, Storage Cleaner, Color Dropper, Plexo, FileDroid) while the island is in hover preview state immediately cancels the hover retraction timer (`cancelHoverCollapse()`), promotes `isPinnedOpen = true`, and activates pinned mode in `LiquidViewModel`.
- **AppKit Tracking Area Boundary Guard**: Guarded `onHoverExited()` with `guard !self.isPinnedOpen && self.activeOrganicItem == .none else { return }`, preventing tracking area rebuilds during window resize animations from triggering premature collapse.
- **Hierarchical Click-Outside Dismissal**: Refined `clickOutsideMonitor` in `LiquidDynamoApp` so clicking outside while a detail view is active dismisses only the active card back to the island home (`activeOrganicItem = .none`) rather than abruptly collapsing the entire island window.
- **Unified Card Geometry**: Standardized expanded card width to `max(openNotchSize.width, 740)` across all views, ensuring seamless visual transitions and eliminating width jumping.

---

## [1.9.4] — 2026-10-23

### Island Pinning & Alert Lifecycle (Bug A3)
- **Protected Pinned State**: `IslandController.triggerEventExpansion(payload:)` no longer unconditionally clears `isPinnedOpen` when an active organic item is selected or the island is already pinned open.
- **State Restoration**: `dismissExpandedAlert()` and `dismissAlert()` now restore to `.expanded` if pinned open or viewing a detail card, rather than collapsing back to resting state.

### Alert-on-Home Capsule Geometry & Non-Notched Screens (Bugs A5, B2)
- **Capsule Sizing on Home View**: Alerts arriving on the home view without an active item selection now smoothly size the window to the compact `capsuleSize` rather than leaving an oversized 500x207 empty container.
- **External Display Bottom Clipping**: Fixed 4 pt bottom capsule clipping on non-notched displays by calculating `yOffset` and `topNotchGap` as 0 pt on non-notched screens (`!geom.isNotched`).

### Purge Safety Engine & Scanner Parity (Bug C)
- **Exact Path Component Safety Matching**: Replaced substring checks (`path.contains(...)`) in `StorageSafetyPolicy.safetyTier` with exact path component matching against `url.pathComponents` and Purge's `SafetyTierList`.
- **Two-Layer Deletion Protection**: Added defense-in-depth ensuring that paths can never be designated `.safeToClean` unless validated by `evaluate(url) == .allow`.
- **Managed Library & VM Protection in Large Files**: Ported Purge's exclusions for Apple Photos, Photo Booth, Music, TV, and iMovie libraries, as well as virtual machine bundles (`.pvm`, `.utm`, `.vmwarevm`), preventing unintended descending into personal databases.
- **Local AI Model Repositories**: Added scan targets and allowlists for local LLM weights in `~/.ollama/models`, `~/.lmstudio/models`, and `~/.cache/huggingface/hub`.
- **Regression Audit Suite**: Expanded `scripts/test_allowlist_audit.swift` with counter-examples (`dist-notes`, `rebuild-plan`, `building-app`) to guarantee developer folder safety.

### Plexo Multi-Network Download Accelerator Integration
- **Multi-Network Interface Engine**: Native macOS discovery (`networksetup -listallhardwareports`, Darwin `getifaddrs`, and `NWPathMonitor`) detecting Wi-Fi, Ethernet, iPhone USB tethering, and cellular hotspots simultaneously.
- **Parallel Chunk Download Acceleration**: Splits HTTP/HTTPS downloads into dynamic parallel chunks routed over multiple active network adapters concurrently, with intelligent work stealing (fast adapters pull more chunks) and slow-chunk racing to prevent long-tail finishes.
- **Resumable Downloads & Sparse Files**: Saves `<filename>.plexo-meta.json` with chunk maps, allowing downloads to pause, resume, or recover gracefully across app restarts.
- **BitTorrent & Magnet Link Engine**: Native Bencode parser (BEP 0003) for `.torrent` files and magnet link decoder (`xt=urn:btih:`, `dn=`, `tr=`).
- **Bandwidth Controls & Scheduling**: Global and per-interface speed limits, one-tap "Slow Mode" for video calls/gaming, data allowance tracking, and off-peak download scheduling.
### FileDroid & OpenMTP Android Storage Bridge
- **Finder External SSD Mount Emulation**: When any Android phone connects via USB, FileDroid automatically creates an External Storage volume in macOS Finder (on Desktop and in Finder sidebar) with a custom `.VolumeIcon.icns`, giving Android devices the seamless look and feel of a native external SSD or flash drive.
- **Device Telemetry & Specs File**: Automatically writes `Device Info & Storage Specs.txt` in the root of the mounted volume, displaying live battery percentage, health, temperature, charging state, internal storage and SD card usage, and Android OS version.
- **Bidirectional Live File Sync**: Users can drag and drop photos, documents, and media directly into `Internal Storage` folders in Finder; FileDroid detects the drop and pushes the files to the device automatically via background ADB streaming.
- **Native Liquid Island UI (`FileDroidView`)**: Adds a dedicated FileDroid status button in the notch hover bar with live storage metrics and phone badge. Clicking opens the full dual-pane file browser with breadcrumb navigation, quick access shortcuts (Camera, Downloads, Pictures, Music, Documents, Movies), upload/download queue, and "Open in Finder" quick launch.
- **Settings Tab**: Added dedicated "FileDroid & OpenMTP" tab in Settings Control Center to configure ADB platform tools paths and Finder auto-mount behaviors.

### Touch, Hover & Gesture Interaction Fixes
- **Trackpad Click Cancellation Fix**: Raised `minimumDistance` and `threshold` in `PanGesture.swift` from 0/4 to 16/16 pt, preventing trackpad sub-pixel jitter during clicks from triggering drag gestures and cancelling button taps.
- **Hover Boundary Grace Period**: Added a 350ms grace delay to `IslandController.onHoverExited()` (instantly cancelled upon `onHoverEntered()`) so moving the mouse across the notch into the dropdown never causes unexpected shrinking or collapse.
- **Eliminated AppKit / SwiftUI Animation Collision**: Updated window frame resizing during item switching to `animated: false`, allowing SwiftUI's native spring physics to handle content layout smoothly without AppKit clipping.
---

## [1.9.3] — 2026-10-23
- **All 5 Core Bugs Resolved**:
  - **Bug 1**: Fixed premature island collapse when interacting with device cards, clipboard, dropper, or storage cleaner.
  - **Bug 2**: Unified transient alerts, audio/brightness HUDs, and live activities into native 3D liquid capsules.
  - **Bug 3**: Fully integrated Purge zero-network storage cleaner with safety allowlists, duplicate detection, and trash-only deletion.
  - **Bug 4**: Replaced 3-toggle wings with modular `WingMetric` slot system, live `NetworkSpeedProvider`, and Settings Mock Notch Preview.
  - **Bug 5**: Perfected clipboard history deduplication, file dropper shelf, and introduced new screen Color Dropper tool via `NSColorSampler`.

---

## [1.9.2] — 2026-10-23

### Bug 1: Premature Island Collapse on Item Selection
- **Fixed premature collapse**: Selecting connected devices, clipboard history, file dropper, or storage cleaner in `LiquidOrganicNotchView` no longer causes the expanded island to shrink or dismiss.
- **Pinned State Enforcement**: `IslandController.activeOrganicItem.didSet` now explicitly enforces `isPinnedOpen = true`, seeds `lastReportedMeasuredHeight` with minimum height floors, and synchronizes target dropdown dimensions.
- **Dimension Isolation**: In `IslandController.calculateDimensions(for: .expanded)`, alert sizing is strictly bypassed when an organic item is active (`activeOrganicItem != .none`).
- **Safety Floors**: Added `minimumHeight(for:)` enforcing a minimum height floor (340–420 pt) for device, clipboard, dropper, storage cleaner, and color dropper views.
- **Hover Guard**: Guarded `onHoverExited()` in `IslandController` so hover-out events never close the island while an organic dropdown is selected.
- **Card Fallback Protection**: Added `rememberedDeviceDetailCard` and `fallbackDeviceDetailCard` in `LiquidOrganicNotchView` so a disconnected device key never produces an `EmptyView()` collapse.

### Bug 2: 3D Liquid Capsule Alert & HUD Unification
- **Liquid Capsule Container**: Replaced oversized 460x(notchH+88) rectangular alert boxes with `LiquidAlertCapsuleContainer<Content: View>`.
- **Dynamic Capsule Geometry**: Capsule width is derived dynamically via `IslandController.alertCapsuleSize(for: geom)` using `IslandController.alertCapsuleDefaultWidth = 280.0` and hardware cutout dimensions from `NotchSafeAreaEngine.shared`.
- **Notch Anchoring**: On physical notched MacBooks, capsules sit flush below the hardware cutout (`yOffset = geom.notchHeight + 8`); on external and non-notched displays, they float smoothly as pills.
- **Unified Alert Views**: Migrated `IslandAlertView`, `ExpandedAlertBannerView`, and `LiveActivityTemplateView` (`liquidBloomContainer`) into the unified capsule container with organic spring animations (`IslandMotion.shared`).

### Bug 3: Complete Storage Cleaner Integration (Purge Port)
- **Purge Engine Integration**: Fully ported and integrated the zero-network storage cleaner from [Purge](https://github.com/jithin-sabu/purge-app) by Jithin Sabu (MIT License).
- **Safety Policy & Allowlists**: Created `StorageSafetyPolicy.swift` containing comprehensive allowlists for system and application caches, developer build directories (Xcode DerivedData, Gradle, SPM, Carthage, CocoaPods), package caches, logs, and downloads, while strictly protecting JetBrains local histories, Ruby gems, and essential application bundles.
- **Non-Destructive Deletion**: Implemented trash-only deletion via `FileManager.default.trashItem`, ensuring zero unrecoverable file deletions.
- **Duplicate File Detection**: Integrated a 3-stage duplicate file detector (file size matching, partial prefix hashing, full SHA-256 CryptoKit hashing).
- **Full Disk Access Handling**: Integrated FDA permission checking via `AppPermissionManager.shared` with graceful degradation and deep-linking to macOS System Settings.
- **Allowlist Test Suite**: Ported allowlist audit test suite (`scripts/test_allowlist_audit.swift`) with 100% test pass rate.
- **Attribution & Licenses**: Added Purge MIT license to `THIRD_PARTY_LICENSES`, updated `NOTICE.md` and `README.md`.

### Bug 4: Configurable Wing Slots System
- **Modular Slot Enum**: Replaced hardcoded 3-toggle wings with `WingMetric` enum supporting 13 metrics (`none`, `cpuUsage`, `cpuTemp`, `ramUsage`, `netDown`, `netUp`, `netDownUp`, `battery`, `bluetoothBattery`, `volume`, `brightness`, `clock`, `weather`).
- **Clean Collapse**: Setting a wing metric to `.none` collapses that side cleanly without leaving empty padding or awkward spacing.
- **Live Network Telemetry**: Created `NetworkSpeedProvider.swift` reading system interface traffic from Darwin `getifaddrs` (ignoring loopback `IFF_LOOPBACK`), formatting as KB/s and MB/s, and starting/stopping dynamically to guarantee ~0% idle CPU.
- **Missing Sensor Fallback**: Updated `SystemStatsService.swift` to display em dashes (`—`) instead of "Unavailable" for missing SMC thermal sensors.
- **Migration Pipeline**: Added `migrateWingMetricsIfNeeded()` to migrate legacy boolean toggles (`showCollapsedCPUWing`, `showCollapsedNetworkWing`, `showCollapsedBluetoothWing`) on startup.
- **Settings UI & Live Mock Notch Preview**: Added "Notch Wings & Slots" section to `LookSettingsView.swift` with Left/Right Metric Pickers, Wing Width slider, fullscreen & built-in display toggles, and a live `MockNotchWingsPreview` displaying a realistic hardware cutout with flanking wing readouts.

### Bug 5: Clipboard, Dropper & New Color Dropper Tool
- **Clipboard Intelligence**:
  - Polling `NSPasteboard.general.changeCount` with automatic screening of password managers and concealed/transient types (`org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`, `com.agilebits.onepassword`).
  - Automatic deduplication and history capping at 25 entries.
  - Clicking any clipboard entry copies it back with visual "Copied!" feedback and changeCount synchronization to prevent duplicate re-ingestion.
  - Fires the Bug 2 liquid alert capsule exactly once per external copy, shielded when dashboard is open or screen recording is active.
- **File Dropper / Shelf**:
  - Drag-in accepts files, URLs, text, and images.
  - Drag-out removes references from the shelf only, never deleting the original files from disk.
  - Integrated QuickLook preview (`QLPreviewPanel`) and AirDrop sharing (`QuickShareService`).
- **Color Dropper Tool**:
  - Created `ColorDropperTool.swift` utilizing AppKit's native `NSColorSampler` with screen loupe magnifier.
  - Integrated dedicated `colorDropperStatusButton` in `LiquidOrganicNotchView`'s primary hover row.
  - Created `colorDropperDetailCard` displaying a prominent color swatch, interactive click-to-copy chips for HEX, RGB, and HSL formats, and a history row of recent colors.
  - Guaranteed that sampling colors never collapses or closes the island (`isPinnedOpen = true`).

---
