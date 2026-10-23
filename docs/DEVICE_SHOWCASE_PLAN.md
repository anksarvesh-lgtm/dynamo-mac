# Boring Notch 3D Device Showcase Architecture Plan

This document details the design, caching hierarchy, rendering pipeline, privacy constraints, and file changes for the **3D Device Showcase** feature in Boring Notch.

---

## 1. Feature Overview & Design Philosophy

When an external device connects to the Mac:
1. **Bluetooth accessories**: Earphones, over-ear headphones, portable speakers, keyboards, mice, game controllers.
2. **External Storage**: USB flash drives, portable SSDs, external hard drives, SD cards.
3. **USB Peripherals**: Audio interfaces/DACs, webcams, microphones, hardware dongles.

The collapsed notch expands into a sleek, animated pill displaying an **interactive spinning 3D model** of the device alongside its friendly name, device-type badge, and live battery or storage capacity. The notification dismisses automatically after 3.5 seconds unless hovered, or expands into the full dashboard upon click.

```
       Hardware Connection Detected (Bluetooth / DiskArbitration / IOKit)
                                       │
                                       ▼
                   ┌───────────────────────────────────────┐
                   │       DeviceIdentityResolver          │
                   │  - Normalizes Hardware Identifiers    │
                   │  - Generates Stable Device Cache Key  │
                   └───────────────────────────────────────┘
                                       │
                                       ▼
                   ┌───────────────────────────────────────┐
                   │       3-Tier Model Pipeline           │
                   ├───────────────────────────────────────┤
                   │ Tier 1: Exact Device Model Cache      │ -> [Instant USDZ]
                   │ Tier 2: Category Procedural Stand-in  │ -> [Bundled USDZ]
                   │ Tier 3: Opt-In Cloud Image-to-3D      │ -> [User Triggered]
                   └───────────────────────────────────────┘
                                       │
                                       ▼
                   ┌───────────────────────────────────────┐
                   │    SceneKitDeviceView (Protocoled)    │
                   │  - Transparent 60fps turntable spin   │
                   │  - Zero idle rendering when collapsed │
                   └───────────────────────────────────────┘
```

---

## 2. The 3-Tier Model Pipeline

| Tier | Source | Latency | Network | Accuracy | Fallback / Trigger |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Tier 1** | Local Disk Cache (`~/Library/Application Support/...`) | **< 2 ms** | None (Offline) | Exact Product Match | Falls back to Tier 2 if cache miss |
| **Tier 2** | Pre-bundled Generic 3D Assets | **0 ms** | None (Offline) | Category Archetype | Default baseline for all recognized devices |
| **Tier 3** | Cloud AI Image-to-3D Generation | **15–45 s** (background) | HTTPS API | High-fidelity photorealistic 3D | Strictly manual, user-triggered via Device Library |

### Tier 1: Cached Exact Model
- If a 3D model was previously downloaded, generated, or manually assigned to this `deviceKey`, it is loaded directly from the local filesystem (`model.usdz`).
- Load time is sub-frame, allowing the notch animation to render smoothly without pop-in.

### Tier 2: Category Stand-in Archetypes
When no exact model exists in the cache, the system selects an immediate category stand-in from 9 bundled USDZ archetypes:
1. `earbuds.usdz`: In-ear wireless earphones (AirPods / Galaxy Buds archetype).
2. `headphones.usdz`: Over-ear premium headphones with headband and earcups.
3. `speaker.usdz`: Cylindrical/pill Bluetooth speaker with acoustic mesh texture.
4. `ssd_drive.usdz`: Sleek rectangular external drive with USB-C port indicator.
5. `usb_stick.usdz`: Classic thumb drive with metal connector.
6. `mouse.usdz`: Ergonomic computer mouse with subtle scroll-wheel detail.
7. `keyboard.usdz`: Low-profile mechanical/chiclet keyboard.
8. `phone.usdz`: Modern glass-slab smartphone.
9. `generic_device.usdz`: Minimal geometric hardware badge for unclassified devices.

### Tier 3: Optional Opt-In Cloud Image-to-3D Upgrade
- **Strictly User-Initiated**: Never runs automatically in the background. Triggered only when the user clicks "Generate 3D Model" in the **Device Library** tab or settings.
- **Workflow**:
  1. Product photo is either searched automatically (using sanitized device name, e.g. "Sony WH-1000XM5 black") or supplied via user file drop.
  2. Background removal: Apple Vision framework (`VNGenerateForegroundInstanceMaskRequest` in macOS 14+) runs locally on-device to isolate the product with 0 cloud leakage.
  3. Image-to-3D Generation: Preprocessed image sent to an image-to-3D cloud provider (e.g. Meshy API, Tripo3D, or CSM) using the user's private API key.
  4. Response `.usdz` or `.glb` is downloaded, converted/sanitized via ModelIO (`MDLAsset`), poly-reduced if needed, and saved into Tier 1 cache.
  5. `meta.json` updated with `sourceTier = "ai_generated"`.

---

## 3. Device Identification & Stable Cache Keys

To guarantee persistent caching without collision or false matching across device reconnects:

### A. Bluetooth Devices
* **Key Format**: `bt_<normalized_mac>`
* **Primary Key**: Hardware MAC Address (e.g. `14:3f:a2:6b:40:91` $\rightarrow$ `bt_14-3f-a2-6b-40-91`).
* **Fallback (if MAC is randomized or hidden)**:
  `bt_vid_<vendorID>_pid_<productID>_<slugifiedName>` (e.g. `bt_vid_004c_pid_200e_airpods-pro`).

### B. External Volumes & Disks (SSDs, HDDs, Thumb Drives)
* **Key Format**: `vol_<uuid>` or `disk_<vendor>_<product>_<serialHash>`
* **Primary Key**: Filesystem Volume UUID via `DADiskRef` / `kDADiskDescriptionVolumeUUIDKey` or `NSURLVolumeUUIDStringKey`.
* **Fallback (Unformatted or Multi-partition Disks)**:
  `disk_<vendorID>_<productID>_<sha256(serialNumber).prefix(8)>`.
* **Category Discrimination**:
  - `kDADiskDescriptionDeviceProtocolKey` == `"USB"` and size < 64GB $\rightarrow$ `usb_stick`.
  - `kDADiskDescriptionDeviceProtocolKey` == `"USB"` / `"Thunderbolt"` and non-rotational $\rightarrow$ `ssd_drive`.
  - Rotational media $\rightarrow$ `ssd_drive` (styled as external HDD).

### C. USB Peripherals (Webcams, Microphones, Audio Interfaces)
* **Key Format**: `usb_<vendorID_hex>_<productID_hex>`
* **Primary Key**: IOKit USB registry properties:
  `kUSBVendorID` (16-bit) and `kUSBProductID` (16-bit)
  (e.g., Logitech C920: `usb_046d_082d`; Focusrite Scarlett 2i2: `usb_1235_8210`).

---

## 4. Cache Layout, Storage Caps & Eviction Policy

### Directory Layout
Models are saved in the user's standard application support directory:
```text
~/Library/Application Support/theboringteam.boringnotch/DeviceModels/
├── index.json                               # Master lookup index & LRU metadata
├── bt_14-3f-a2-6b-40-91/                    # Example: AirPods Pro
│   ├── model.usdz                           # 3D SceneKit / RealityKit asset
│   ├── preview.png                          # 512x512 thumbnail with alpha
│   └── meta.json                            # Model provenance & spec
├── vol_a1b2c3d4-e5f6-7890-abcd-ef0123456789/ # Example: Samsung T7 SSD
│   ├── model.usdz
│   ├── preview.png
│   └── meta.json
└── usb_046d_082d/                           # Example: Logitech Webcam
    ├── model.usdz
    ├── preview.png
    └── meta.json
```

### Metadata Schema (`meta.json`)
```json
{
  "deviceKey": "bt_14-3f-a2-6b-40-91",
  "deviceName": "AirPods Pro (2nd gen)",
  "category": "earbuds",
  "sourceTier": "cached",
  "provider": "meshy",
  "sourceURL": "https://api.meshy.ai/v1/models/...",
  "createdAt": "2026-10-04T12:00:00Z",
  "lastSeenAt": "2026-10-04T12:35:10Z",
  "fileSizeBytes": 2411724,
  "polygonCount": 8640,
  "meshChecksum": "sha256-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}
```

### Storage Budgets & LRU Eviction Rule
* **Global Cache Size Limit**: **150 MB** default (user adjustable in Settings: 50 MB, 150 MB, 300 MB, 500 MB).
* **Per-Model Maximum Size**: **15 MB** (rejects oversized unoptimized assets).
* **Eviction Policy**:
  1. Bundled Tier 2 models reside in `Bundle.main` and are **never** evicted.
  2. When total cache size exceeds the limit, the eviction manager deletes the oldest directory where `sourceTier == "ai_generated"` sorted by ascending `lastSeenAt`.
  3. User can explicitly "Pin" a custom model to prevent it from automatic eviction.

---

## 5. 3D Rendering Architecture (SceneKit Protocol Abstraction)

### Protocol Interface (`DeviceModelRendererProtocol`)
To ensure smooth future migration to **RealityKit** without touching UI or notification logic:

```swift
@MainActor
protocol DeviceModelRendererProtocol {
    func loadModel(from fileURL: URL) throws
    func setTurntableSpin(rpm: Float, animated: Bool)
    func pauseRendering()
    func resumeRendering()
    func resetCamera(animated: Bool)
}
```

### SceneKit Implementation (`SceneKitDeviceView`)
* **View Type**: `NSViewRepresentable` wrapping `SCNView`.
* **Zero Idle Rendering**:
  - `scnView.preferredFramesPerSecond = 60` during animation.
  - `scnView.isPlaying = false` whenever the notch collapses or is closed!
  - No continuous background CADisplayLink or timer.
* **Lighting Rig**:
  - Neutral studio lighting: Key light (45° azimuth, 60° elevation), soft fill light, subtle rim light for specular highlights on device edges.
  - Physically Based Rendering (PBR) shader environment with a neutral studio HDRI reflection map.
* **Memory & Performance Budgets**:
  - **Polygon budget**: Target 8,000–16,000 triangles; hard limit 35,000 triangles.
  - **Texture budget**: Max 1024x1024 per PBR map (BaseColor, Roughness, Metalness, Normal).
  - Single shared renderer instance in memory to avoid GPU context recreation spikes.

---

## 6. Interaction & UI Flow

### A. The Collapsed Notch Connect Popup
When a device connects:
1. Notch expands from collapsed hardware notch (`~160 pt`) to an interactive showcase capsule (`~260 pt width x 32 pt height`).
2. Left side: 28x28 embedded turntable 3D render rotating smoothly at 20 RPM.
3. Center: Device name with truncated tail + connection badge (green dot).
4. Right: Live metric (e.g. Battery percentage `85%` for Bluetooth, Free capacity `1.2 TB free` for SSD).
5. **Dismissal**:
   - Auto-collapses after 3.5 seconds with a spring animation.
   - Hovering over the popup cancels auto-dismissal.
   - Clicking opens the full dashboard directly.

```
┌────────────────────────────────────────────────────────┐
│  ( 🌀 3D )  Sony WH-1000XM5 • Connected      🔋 92%    │  <-- Collapsed Popup
└────────────────────────────────────────────────────────┘
```

### B. Interactive Turntable & Click-to-Spin
* **In Expanded Notch & Device Library**:
  - Drag gesture rotates the model along the azimuth and elevation with inertia.
  - Single click gives a playful, satisfying spring spin (360° over 0.6s) with `NSHapticFeedbackManager` tap.
  - Double click resets camera angle to default beauty hero perspective.

### C. Dedicated "Device Library" Tab
A new tab or sub-panel in Dashboard:
* Grid/list of all previously connected and paired devices.
* Displays live 3D preview thumbnail for each item.
* Action buttons:
  - "Inspect in 3D" (full turntable viewer).
  - "Generate 3D Model" (opens manual AI generation flow).
  - "Use Generic Stand-in" (resets override).
  - "Clear Cache" button displaying total MB used.

---

## 7. Privacy, Security & Cost Controls

1. **Strictly Local by Default**:
   - All connection detection, IOKit queries, and Tier 2 rendering run 100% on-device and offline.
   - Zero network requests are made when a device connects.
2. **Opt-In Cloud Generation**:
   - Cloud generation requires the user to explicitly open Device Library and click "Generate 3D Model".
   - The user must explicitly consent in an authorization dialog detailing the exact data sent (product image only; no serial numbers or user IDs).
3. **Keychain Security**:
   - Cloud API Keys (e.g. Meshy API key) are stored exclusively in macOS **Keychain Services** (`kSecClassGenericPassword` with service identifier `theboringteam.boringnotch.apikeys`).
   - Keys are never persisted in `UserDefaults`, `Defaults`, or plain text files.
4. **Monthly Generation Quotas**:
   - Hard quota counter in secure storage (e.g. max 10 generations/month) to prevent accidental billing or API drain.

---

## 8. Files to Touch & Upstream Merge Strategy

To ensure zero merge conflicts with upstream Boring Notch:

### New Files to Create (Inside `boringNotch/Features/DeviceShowcase/`):
1. `DeviceShowcaseTypes.swift`: Data models (`DeviceShowcaseItem`, `DeviceCategory`, `ModelSourceTier`, `DeviceMetadata`).
2. `DeviceIdentityResolver.swift`: Deterministic key generation for Bluetooth, Volumes, and USB.
3. `DiskArbitrationObserver.swift`: Monitors external storage mounting via `DASession` and `NSWorkspace`.
4. `DeviceModelCacheManager.swift`: Manages `~/Library/Application Support/...` files, LRU eviction, and `meta.json`.
5. `DeviceModelRendererProtocol.swift`: Renderer protocol for SceneKit / RealityKit decoupling.
6. `SceneKitDeviceView.swift`: High-performance, zero-idle `NSViewRepresentable` SceneKit turntable renderer.
7. `DeviceShowcasePopupView.swift`: Collapsed notch interactive connect popup.
8. `DeviceLibraryView.swift`: Management UI for browsing cached devices and triggering AI models.
9. `CloudModelGenerationService.swift`: Opt-in image-to-3D API client with Keychain credential storage.

### Existing Files to Modify (Minimally):
1. [boringNotch/enums/generic.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/enums/generic.swift):
   - Add `.deviceLibrary` to `enum NotchViews` (optional tab registration).
2. [boringNotch/models/Constants.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/models/Constants.swift):
   - Add preferences: `enableDeviceShowcase` (Bool), `deviceModelCacheLimitMB` (Int).
3. [boringNotch/BoringViewCoordinator.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/BoringViewCoordinator.swift):
   - Add method to trigger device showcase popup on hardware connect.
4. [boringNotch/ContentView.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/ContentView.swift):
   - Integrate `DeviceShowcasePopupView` into closed notch layout.
5. [boringNotch/Features/Bluetooth/BluetoothService.swift](file:///Users/sarvesh/Documents/boring.notch/boringNotch/Features/Bluetooth/BluetoothService.swift):
   - Emit device connect notification with hardware identifiers to the showcase coordinator.
6. [boringNotch.xcodeproj/project.pbxproj](file:///Users/sarvesh/Documents/boring.notch/boringNotch.xcodeproj/project.pbxproj):
   - Register new files under `Features/DeviceShowcase`.

---

## 9. Next Steps (Awaiting User Approval)
- Review this design plan.
- Upon approval, proceed to step-by-step implementation starting with the core identity resolver and cache manager, followed by the SceneKit renderer and UI components.
