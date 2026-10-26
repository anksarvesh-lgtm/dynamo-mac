# LiquidDynamo — Rename Map: FileDroid & Kalam Bridge → Phone Bridge & MTPBridge

This document defines the complete inventory and translation mapping for renaming the "FileDroid / Kalam Bridge" feature to "Phone Bridge" and "MTPBridge" across LiquidDynamo.

---

## 1. Configured Target Identifiers

| Variable | Configured Value | Description |
|---|---|---|
| `NEW_PRODUCT_NAME` | `"Phone Bridge"` | User-facing product name displayed in UI, menu bar, alerts, settings, and documentation. |
| `NEW_TYPE_PREFIX` | `"PhoneBridge"` | Prefix for Swift types, classes, structs, enums, and filenames replacing `FileDroid`. |
| `NEW_DEFAULTS_PREFIX` | `"phonebridge"` | Prefix for `Defaults.Keys` and `UserDefaults` string keys replacing `filedroid`. |
| `NEW_MTP_BRIDGE` | `"MTPBridge"` | Swift class name replacing `KalamBridge` for the in-process MTP engine wrapper. |

---

## 2. Directory & File Move Plan (`git mv`)

All files are moved preserving Git commit history via `git mv`:

| Old Path | New Path | Category | Persisted? |
|---|---|---|---|
| `liquiddinamo/Features/FileDroid/` | `liquiddinamo/Features/PhoneBridge/` | Directory | No |
| `liquiddinamo/Features/FileDroid/FileDroidEngine.swift` | `liquiddinamo/Features/PhoneBridge/PhoneBridgeEngine.swift` | File (Swift Source) | No |
| `liquiddinamo/Features/FileDroid/FileDroidModels.swift` | `liquiddinamo/Features/PhoneBridge/PhoneBridgeModels.swift` | File (Swift Source) | No |
| `liquiddinamo/Features/FileDroid/FileDroidView.swift` | `liquiddinamo/Features/PhoneBridge/PhoneBridgeView.swift` | File (Swift Source) | No |
| `liquiddinamo/Features/FileDroid/FileDroidWindowController.swift` | `liquiddinamo/Features/PhoneBridge/PhoneBridgeWindowController.swift` | File (Swift Source) | No |
| `liquiddinamo/Features/FileDroid/KalamBridge.swift` | `liquiddinamo/Features/PhoneBridge/MTPBridge.swift` | File (Swift Source) | No |
| `liquiddinamo/Features/FileDroid/SettingsFileDroidView.swift` | `liquiddinamo/Features/PhoneBridge/SettingsPhoneBridgeView.swift` | File (Swift Source) | No |
| `liquiddinamo/Features/FileDroid/AndroidTransferBackend.swift` | `liquiddinamo/Features/PhoneBridge/AndroidTransferBackend.swift` | File (Swift Source) | No |
| `scripts/test_filedroid_engine.swift` | `scripts/test_phonebridge_engine.swift` | File (Test Script) | No |
| `scripts/test_kalam_bridge.swift` | `scripts/test_mtp_bridge.swift` | File (Test Script) | No |
| `scripts/test_kalam_mtp_backend.swift` | `scripts/test_mtp_backend.swift` | File (Test Script) | No |
| `scripts/test_kalam_bridge_milestone4.swift` | `scripts/test_mtp_bridge_milestone4.swift` | File (Test Script) | No |

---

## 3. Swift Symbols & Identifiers

| Old Symbol | New Symbol | Category | File Location | Persisted? |
|---|---|---|---|---|
| `FileDroidEngine` | `PhoneBridgeEngine` | Class | `PhoneBridgeEngine.swift` | No |
| `FileDroidFormatting` | `PhoneBridgeFormatting` | Enum / Namespace | `PhoneBridgeModels.swift` | No |
| `FileDroidConnectionType` | `PhoneBridgeConnectionType` | Enum | `PhoneBridgeModels.swift` | Yes (in `filedroidBackendType`) |
| `FileDroidDeviceStatus` | `PhoneBridgeDeviceStatus` | Enum | `PhoneBridgeModels.swift` | No |
| `FileDroidTransferDirection` | `PhoneBridgeTransferDirection` | Enum | `PhoneBridgeModels.swift` | No |
| `FileDroidTransferStatus` | `PhoneBridgeTransferStatus` | Enum | `PhoneBridgeModels.swift` | No |
| `FileDroidTransferItem` | `PhoneBridgeTransferItem` | Struct | `PhoneBridgeModels.swift` | No |
| `FileDroidView` | `PhoneBridgeView` | Struct (SwiftUI View) | `PhoneBridgeView.swift` | No |
| `FileDroidWindowController` | `PhoneBridgeWindowController` | Class (NSWindowController) | `PhoneBridgeWindowController.swift` | No |
| `FileDroidStandaloneWindowView` | `PhoneBridgeStandaloneWindowView` | Struct (SwiftUI View) | `PhoneBridgeWindowController.swift` | No |
| `SettingsFileDroidView` | `SettingsPhoneBridgeView` | Struct (SwiftUI View) | `SettingsPhoneBridgeView.swift` | No |
| `NotchViews.filedroid` | `NotchViews.phoneBridge` | Enum Case | `liquiddinamo/enums/generic.swift:39` | No |
| `OrganicNotchExpandedItem.filedroid` | `OrganicNotchExpandedItem.phoneBridge` | Enum Case | `LiquidOrganicNotchView.swift:27` | No |
| `filedroidEngine` | `phoneBridgeEngine` | Property | `LiquidOrganicNotchView.swift:44` | No |
| `filedroidStatusButton` | `phoneBridgeStatusButton` | Property | `LiquidOrganicNotchView.swift:806` | No |
| `fdDev` | `pbDev` | Local Variable | `LiquidOrganicNotchView.swift:1112` | No |
| `KalamBridge` | `MTPBridge` | Class | `MTPBridge.swift` | No |
| `KalamCallbackFn` | `MTPCallbackFn` | Typealias | `MTPBridge.swift` | No |
| `KalamResponse` | `MTPResponse` | Struct (Codable Envelope) | `MTPBridge.swift` | No |
| `KalamEmptyData` | `MTPEmptyData` | Struct (Codable Payload) | `MTPBridge.swift` | No |
| `KalamDeviceInfoData` | `MTPDeviceInfoData` | Struct (Codable Payload) | `MTPBridge.swift` | No |
| `KalamMtpDeviceInfo` | `MTPMtpDeviceInfo` | Struct (Codable Payload) | `MTPBridge.swift` | No |
| `KalamUsbDeviceInfo` | `MTPUsbDeviceInfo` | Struct (Codable Payload) | `MTPBridge.swift` | No |
| `KalamStorageItem` | `MTPStorageItem` | Struct (Codable Payload) | `MTPBridge.swift` | No |
| `KalamStorageDetail` | `MTPStorageDetail` | Struct (Codable Payload) | `MTPBridge.swift` | No |
| `KalamWalkItem` | `MTPWalkItem` | Struct (Codable Payload) | `MTPBridge.swift` | No |
| `KalamProgressPayload` | `MTPProgressPayload` | Struct (Codable Payload) | `MTPBridge.swift` | No |
| `KalamError` | `MTPError` | Enum (Error) | `MTPBridge.swift` | No |
| `KalamRequestQueue` | `MTPRequestQueue` | Class (Request Queue) | `MTPBridge.swift` | No |

---

## 4. Persisted Keys & Defaults Migration

All 9 `Defaults.Keys` and 1 raw `UserDefaults` key are renamed to use the `phonebridge` prefix.
A one-time migration runs in `AppDelegate.applicationDidFinishLaunching` guarded by `migratedPhoneBridgeKeys_v1`.
Old keys are retained in `UserDefaults` to support graceful downgrades.

| Old Key | New Key | Type | Default Value | Migration Strategy |
|---|---|---|---|---|
| `filedroidAdbPath` | `phonebridgeAdbPath` | `String` | `""` | Copy if old exists and new is unset. |
| `filedroidAutoDetectAdb` | `phonebridgeAutoDetectAdb` | `Bool` | `true` | Copy if old exists and new is unset. |
| `filedroidAutoMountOnConnect` | `phonebridgeAutoMountOnConnect` | `Bool` | `true` | Copy if old exists and new is unset. |
| `filedroidAutoRevealInFinder` | `phonebridgeAutoRevealInFinder` | `Bool` | `false` | Copy if old exists and new is unset. |
| `filedroidDefaultMacFolder` | `phonebridgeDefaultMacFolder` | `String` | `~/Downloads/Android` | Copy if old exists and new is unset (Folder path strictly preserved). |
| `filedroidTransferConcurrency` | `phonebridgeTransferConcurrency` | `Int` | `2` | Copy if old exists and new is unset. |
| `filedroidShowHiddenFiles` | `phonebridgeShowHiddenFiles` | `Bool` | `false` | Copy if old exists and new is unset. |
| `filedroidNotifications` | `phonebridgeNotifications` | `Bool` | `true` | Copy if old exists and new is unset. |
| `filedroidBackendType` | `phonebridgeBackendType` | `String` | `"adb"` | Copy if old exists and new is unset. |
| `"filedroid_custom_adb_path"` | `"phonebridge_custom_adb_path"` | Raw `String` | `nil` | Copy in raw `UserDefaults` if old exists and new is unset. |
| Settings Tab ID: `"FileDroid"` | Settings Tab ID: `"PhoneBridge"` | Navigation ID | `"NotchWings"` | Handled in `SettingsView` switch and `SettingsNavigationState`. |

---

## 5. Runtime Identifiers, Activity IDs, and Logs

| Old Identifier / Log | New Identifier / Log | Category | Location |
|---|---|---|---|
| `"filedroid_transfer"` | `"phonebridge_transfer"` | Island Activity ID | `PhoneBridgeEngine.swift:683, 692` |
| `[FileDroid]` | `[PhoneBridge]` | Log Prefix | `PhoneBridgeEngine.swift:323`, etc. |
| `[KalamBridge]` | `[MTPBridge]` | Log Prefix | `MTPBridge.swift:280, 296, 306, 310` |
| Finder Mount Volume Info: `"FileDroid & OpenMTP"` | `"Phone Bridge"` | Header in `Device Info & Storage Specs.txt` | `PhoneBridgeEngine.swift:264` |
| `FileDroid will automatically sync...` | `Phone Bridge will automatically sync...` | Instruction Text | `PhoneBridgeEngine.swift:280` |
| Window title: `"Android Storage Bridge"` | `"Phone Bridge"` | Window Title | `PhoneBridgeWindowController.swift:33` |

---

## 6. User-Facing Strings & UI Surfaces

| File / Component | Old Text / Identifier | New Text / Identifier |
|---|---|---|
| `SettingsControlCenterSidebar.swift:56` | `SettingsSidebarItem(id: "FileDroid", title: "FileDroid (ADB)", ...)` | `SettingsSidebarItem(id: "PhoneBridge", title: "Phone Bridge", ...)` |
| `SettingsView.swift:79` | `case "FileDroid": SettingsFileDroidView()` | `case "PhoneBridge", "FileDroid": SettingsPhoneBridgeView()` |
| `PhoneBridgeView.swift:130` | `Text("FileDroid & OpenMTP")` | `Text("Phone Bridge")` |
| `PhoneBridgeView.swift:803` | `alert.messageText = "FileDroid & OpenMTP Finder Mount"` | `alert.messageText = "Phone Bridge Finder Mount"` |
| `PhoneBridgeView.swift:804` | `"When any Android device connects, FileDroid..."` | `"When any phone connects, Phone Bridge..."` |
| `SettingsPhoneBridgeView.swift:50` | `Text("FileDroid & OpenMTP")` | `Text("Phone Bridge")` |
| `LiquidOrganicNotchView.swift:835` | `Text("FileDroid")` | `Text("Phone Bridge")` |
| `LiquidOrganicNotchView.swift:849` | `.help("FileDroid — \(dev) mounted in Finder")` | `.help("Phone Bridge — \(dev) mounted in Finder")` |

---

## 7. Upstream Attributions & Preserved Artifacts (DO NOT RENAME)

Per explicit requirements, third-party projects and binary artifacts retain their original names and copyrights:
- Bundled dynamic libraries: `Frameworks/kalam.dylib` and `Frameworks/libusb.dylib` (names, install names, C exported symbol names `Initialize`, `FetchDeviceInfo`, `Walk`, `UploadFiles`, `DownloadFiles`, `Dispose` remain unchanged).
- Upstream project credits: OpenMTP (Ganesh Rathinavel, MIT License) and libusb (LGPL-2.1) in `README.md`, `NOTICE.md`, and `THIRD_PARTY_LICENSES`.
- Codable wire model JSON keys: `Manufacturer`, `Model`, `SerialNumber`, `IdVendor`, `IdProduct`, `Sid`, `StorageType`, `FreeSpaceInBytes`, `errorType`, `error`, `data` match `kalam.dylib` JSON output.
- Android File Manager (`liquiddinamo/Features/AndroidFiles/*`, `ADBClient.swift`, `AndroidFileManagerView.swift`) remains a distinct separate feature and is not renamed.
