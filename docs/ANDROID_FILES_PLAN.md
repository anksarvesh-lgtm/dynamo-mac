# In-App Android File Manager Implementation Plan

## 1. Executive Summary & Problem Scope

LiquidDynamo surfaces connected hardware in the Dynamic Notch Island. When an Android device is connected via USB, the device detail card in the open island displays the device name (e.g. "motorola edge 50"), an "Android" badge, and subtitle "MTP Media Bridge". Previously, the action button opened either Finder or an external folder view.

The goal of this task is to:
1. Replace the button on the **Android device card only** with **"Open in app"** (`folder.badge.gearshape` / `externaldrive.connected.to.line.below`). Storage cards (SSDs, USB flash drives, local volumes) retain their native "Open in Finder" button.
2. Build a native, high-performance, in-app Android File Manager under `liquiddinamo/Features/AndroidFiles/` powered by ADB over USB (`adb -s <serial>`), featuring a liquid-glass UI, lazy file browser, breadcrumbs, search, grid/list view, Quick Look, drag-and-drop transfers, and thumbnail caching.
3. Wire the button to open or focus the dedicated `AndroidFileManagerWindow` for that device serial without collapsing or unpinning the notch island.

---

## 2. Phase 1 Discoveries

### 2.1 Android Card & "Open in Finder" / "Open Device Folders" Button
- **File & Line**: `liquiddinamo/Features/Dashboard/LiquidOrganicNotchView.swift:882-944` (`deviceDetailCard`), specifically lines `1064-1123` (`androidInfoRow`).
- **Rendering**:
  - `deviceDetailCard` checks `device.kind == .androidPhone` and routes to `androidInfoRow(device:)`.
  - Subtitle is derived from `pbDev?.androidVersion ?? device.connectionType.rawValue`, which resolves to `"MTP Media Bridge"` when connected via MTPBridge (`liquiddinamo/Features/PhoneBridge/AndroidTransferBackend.swift:433`).
  - The button currently renders inside `androidInfoRow`:
    ```swift
    Button {
        PhoneBridgeWindowController.shared.showWindow()
    } label: {
        HStack(spacing: 4) {
            Image(systemName: "folder.fill")
            Text("Open Device Folders")
        }
    }
    ```
    While for storage devices (`.ssdDrive`, `.usbStick`), `storageInfoRow(device:)` (line 1152) renders `Text("Open in Finder")`.
- **What "MTP Media Bridge" is**:
  - An in-process C-FFI wrapper (`MTPBridge.swift`) linking against `kalam.dylib` (derived from OpenMTP's libmtp engine). It interfaces directly with USB endpoints using MTP protocol without ADB daemon, setting `androidVersion: "MTP Media Bridge"`.
  - It does NOT mount a virtual FUSE filesystem in Finder; it only provides raw byte read/write calls across MTP endpoints.

### 2.2 Android Device Detection & ADB Resolution
- **Detection Architecture**:
  - `liquiddinamo/Features/DeviceShowcase/DeviceMonitor.swift`: Uses IOKit USB matching (`kIOUSBDeviceClassName`). Matches against vendor IDs for Android manufacturers (e.g., `0x22B8` Motorola, `0x18D1` Google, `0x04E8` Samsung, `0x2717` Xiaomi, `0x2A70` Nothing) or product string containing "android", "pixel", "galaxy", "motorola", etc. Classifies the device as `DeviceKind.androidPhone`.
  - `PhoneBridgeEngine.swift` listens to `DeviceMonitor.shared.$activeDevices` and scans via `AndroidTransferBackend` (both MTP and ADB).
- **Existing ADB Client**:
  - `AdbBackend` in `liquiddinamo/Features/PhoneBridge/AndroidTransferBackend.swift` provides synchronous/asynchronous `Process` execution.
- **ADB Binary Resolution**:
  - Candidate paths:
    1. Custom path set in Settings (`Defaults[.phonebridgeAdbPath]` / `Defaults[.androidFilesAdbPath]`).
    2. Local user binary: `~/.local/bin/adb` (verified present on this machine).
    3. Standard Android SDK: `~/Library/Android/sdk/platform-tools/adb`.
    4. Homebrew paths: `/opt/homebrew/bin/adb`, `/usr/local/bin/adb`.
    5. Environment: `$ANDROID_HOME/platform-tools/adb`, `$ANDROID_SDK_ROOT/platform-tools/adb`.
    6. Login shell check: `/bin/zsh -l -c 'which adb'`.
- **ADB Server Lifecycle**:
  - Started locally via `adb start-server` on `localhost:5037`.
  - Under D4, LiquidDynamo never kills an existing user server; only stops what it started, and only if "Stop adb on quit" is enabled (default false).

### 2.3 Plexo & "motorola edge 50" Chips
- **Plexo Chip**:
  - Rendered in Group 3 (`androidRow`) in `LiquidOrganicNotchView.swift` via `plexoStatusButton`.
  - Fed by `PlexoDownloadEngine.shared` and `PlexoNetworkManager.shared`.
- **"motorola edge 50" Chip**:
  - Rendered in Group 3 via `phoneBridgeStatusButton` (fed by `PhoneBridgeEngine.shared.selectedDevice`), or `androidDevicesFromMonitor` in `androidRow` rendering `deviceIconButton(device: device)` with phone icon and green connection badge.
  - Sourced from `DeviceMonitor.shared.activeDevices` and `PhoneBridgeEngine.shared.selectedDevice`.

### 2.4 App Sandbox & Entitlements
- **Entitlements file**: `liquiddinamo/LiquidDynamo.entitlements`.
- `com.apple.security.app-sandbox` is `false`: LiquidDynamo is **non-sandboxed**.
- Spawning child processes via `Foundation.Process` (such as `/opt/homebrew/bin/adb`, `~/.local/bin/adb`, or a bundled adb binary) and writing files to `~/Downloads` or temporary caches in `NSTemporaryDirectory()` is fully permitted without sandbox restrictions or security-scoped bookmark hurdles.
- Hardened runtime: requires valid ad-hoc or Developer ID code signing.

### 2.5 Reusable Architectural Components
1. **Window Management**: `SettingsWindowController.swift` and `PhoneBridgeWindowController.swift` provide the canonical AppKit `NSWindowController` + `NSHostingView` pattern with `.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView`, transparent titlebar, and smooth window positioning.
2. **Design System**: `LiquidGlassSystem.swift` provides `.liquidGlassCard()`, `.liquidGlassCapsule()`, `LiquidGlassSurface`, and vibrant frosted glass backdrops.
3. **Quick Look & File Icons**: `NSWorkspace.shared.icon(forFileType:)`, QuickLook preview panel (`QLPreviewPanel`).

---

## 3. Decisions (D1 – D4)

- **D1. Presentation**:
  A dedicated resizable `NSWindow` (SwiftUI `AndroidFileManagerView`) titled `"<device name> Files"` managed by `AndroidFileManagerWindowManager.shared`. Opening or focusing this window does NOT collapse, unpin, or resize the island overlay.
- **D2. Transport**:
  ADB over USB (`adb -s <serial> ...`). ADB provides robust scoped storage support, streaming stdout/stderr, reliable file pulls/pushes with byte counts, and shell execution. Device identity from `DeviceMonitor` / `PhoneBridge` (serial number / model) is reused.
- **D3. adb Resolution Order**:
  1. Bundled adb (if packaged)
  2. Setting override (`Defaults[.androidFilesAdbPath]`)
  3. `~/.local/bin/adb`
  4. `/opt/homebrew/bin/adb`
  5. `/usr/local/bin/adb`
  6. `~/Library/Android/sdk/platform-tools/adb`
  7. `$ANDROID_HOME/platform-tools/adb`
  Zero network downloads at runtime.
- **D4. Server Lifecycle**:
  Local daemon on `localhost:5037`. Do not kill pre-existing user adb servers. Only terminate adb on quit if `Defaults[.stopAdbOnQuit]` is explicitly enabled (default false).

---

## 4. Implementation Milestones

### Milestone 1: ADB Client Engine (`Features/AndroidFiles/ADBClient.swift`)
- `protocol ADBClient` & `LiveADBClient`:
  - `Process` execution with `Task` cancellation, timeouts, non-blocking async streams.
  - Connection states: `noAdb`, `noDevice`, `unauthorized`, `offline`, `multipleDevices`, `ready(device: AndroidDeviceInfo)`, `error(String)`.
  - Shell safety: strictly escape single quotes via `'\''` or argument arrays; never format strings directly into raw shell commands.
  - File parser: parse `ls -lA` outputs with date, type, file size, permissions, symlinks (`/sdcard` -> `/storage/emulated/0`), and hidden file filtering.
  - Transfer operations: `adb pull`, `adb push` with progress callbacks, cancel support, conflict handling.
  - Android 11+ restricted path detection (`/Android/data`, `/Android/obb`).
- `FakeADBClient` for unit testing with mocked fixtures.

### Milestone 2: File Manager UI & Window (`Features/AndroidFiles/AndroidFileManager*.swift`)
- `AndroidFileManagerWindowController`: Manages single window per device serial.
- `AndroidFileManagerView`:
  - Toolbar: Back, Forward, Up, Breadcrumbs, Refresh, View Mode (List/Grid), Sort, Filter/Search, Hidden Files toggle, New Folder, Upload, Download.
  - Sidebar: Quick locations (Internal storage, DCIM, Pictures, Download, Documents, Movies, Music, WhatsApp).
  - Main Pane: LazyVStack / LazyVGrid supporting 10,000+ items smoothly.
  - Thumbnails: LRU-cached small image thumbnail generator.
  - Keyboard shortcuts: Space (Quick Look), Return (Open), Cmd+Delete (Delete), Cmd+N (New Folder), Cmd+F (Search), Cmd+R (Refresh).
  - Transfer Panel: Floating progress bar and transfer queue manager.

### Milestone 3: Wiring & Settings Integration
- Update `androidInfoRow` in `LiquidOrganicNotchView.swift`:
  Replace button with "Open in app" (`folder.badge.gearshape`).
- Clicking button calls `AndroidFileManagerWindowManager.shared.openWindow(for: device)`.
- Add Settings controls under `SettingsDevicesView.swift` or dedicated Android Files section.
- Add Defaults keys in `models/Constants.swift`.

### Milestone 4: Hardening & Testing
- Unit tests for shell escaping, `ls` parsing, state transitions.
- Reconnection & unplug handling.
- Verify memory and CPU footprint (idle ~0%).
