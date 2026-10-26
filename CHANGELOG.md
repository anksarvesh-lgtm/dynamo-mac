# Changelog — LiquidDynamo

All notable changes, bug fixes, and feature enhancements in LiquidDynamo are documented in this file.

## [2.1.0] — 2026-10-26

### Phone Bridge Android Storage Synchronization & USB Detection Fixes
- **Multi-Tiered Android Storage Query**: Added unprivileged `dumpsys diskstats` parser providing 100% reliable internal storage metrics across Android 4 through Android 15 without requiring root access.
- **Global Mount Point Parser**: Added resilient global `df -k` partition parser matching `/data`, `/storage/emulated`, and `/sdcard` mounts directly from kernel `/proc/mounts`, bypassing scoped storage and path permission blocks on Android 11–15.
- **Toybox Stat Syntax Fix**: Fixed single-quote argument passing to `stat -f -c "%a %b %s"` in `AdbBackend`, resolving toybox format error.
- **MTP Session Stability**: Removed premature `dispose()` invocations during storage query and device discovery in `MtpBackend`, preserving active MTP connections and directory navigation.
- **Expanded Android Device Classification**: Added 20+ additional OEM and model identifiers (Samsung Galaxy SM-, Xiaomi, Redmi, Poco, OnePlus, Oppo, Vivo, Realme, Motorola, Nothing Phone, Honor, Sony Xperia, Huawei, Infinix, Tecno, Asus ROG, MTP) in `DeviceMonitor` to eliminate false negatives.
- **Automatic Sync & UI Reactivity**: Enforced automatic storage sync on device connection and explicit `@MainActor` object invalidation in `PhoneBridgeEngine` ensuring instant UI re-renders in dynamic notch HUD and Finder mount info.

## [2.0.9] — 2026-10-26

### Minimal macOS Settings UI & Contextual Notch Aesthetics
- **Streamlined Settings Presentation**: Cleaned up the settings interface with refined spacing, typography, and controls while maintaining the premium dark Liquid Glass aesthetic.
- **Removed Irrelevant Decorative Notch Graphics**: Removed decorative notch illustrations, fake preview cards, and notch background canvases from non-notch settings pages (`GeneralSettingsView`, `SettingsPrivacyView`). Live notch previews are retained strictly in `LookSettingsView` (Notch & Wings).
- **Compact Island Notification Capsules**: Enforced small, content-aware capsule presentation anchored to the notch for all temporary notifications (volume, media, devices, network, charging, and system status), eliminating oversized 460pt banners.

### Phone Bridge Android Storage Synchronization
- **Multi-Mount & Stat Fallback Probing**: Replaced brittle single-line `df -k` execution with multi-mount probing (`/storage/emulated/0`, `/sdcard`, `/storage/self/primary`, `/data`) using POSIX `stat -f -c '%a %b %s'` block geometry and resilient multi-line token extraction.
- **Dynamic On-Demand Storage Sync**: Added `syncStorage(forced:)` with interactive UI sync buttons in both `PhoneBridgeView` and `SettingsPhoneBridgeView`, updating storage metrics automatically on device connection, periodic polling, and file transfer completion.

### NetMerge Multi-Network Link Bonding Engine (Standalone & Powerload)
- **Universal Mach-O Engine**: Bundled pre-compiled universal binary (`arm64` & `x86_64`) of the NetMerge connection bonding engine directly into application Resources with full inside-out runtime code-signing.
- **Standalone Bonding Module**: Added dedicated NetMerge service controller (`NetMergeEngine.swift`) managing the local zero-admin SOCKS5 bonding proxy on port 10888, real-time log and throughput stream parsing, and system-wide virtual TUN mode.
- **Dynamic Notch HUD & Settings UI**: Added `NetMergeTelemetryWing` displaying live bonded bandwidth in the dynamic notch, plus a dedicated `SettingsNetMergeView` with live throughput hero, adapter weights, and one-click terminal export commands.
- **Powerload Engine Integration**: Integrated Powerload chunk downloading with NetMerge's SOCKS5 proxy (`performNetMergeSocksChunk`), dynamically balancing file chunks across all active network adapters (Wi-Fi, Ethernet, USB tether, hotspot) with capacity-weighted worker allocation.

### Agrigence Branding & Restricted-Use Proprietary Licensing
- **Publisher & Copyright Attribution**: Fully established Agrigence as developer, publisher, and copyright holder across application metadata, About views, and documentation.
- **Restricted-Use License**: Replaced permissive open-source license with a proprietary restricted-use license permitting intended personal macOS utility use while prohibiting unauthorized modification, adaptation, and redistribution of modified copies.
- **Comprehensive Third-Party Acknowledgements**: Fully updated `NOTICE.md` and in-app `LicenseView` preserving notices for all incorporated open-source libraries.

## [2.0.8] — 2026-10-26

### Background Auto-Download & Install & Instant Boot Checks
- **Automated Background Updates**: Configured `GitHubUpdateChecker` to automatically download and stage updates in the background when pushed (`Defaults[.autoDownloadAndInstallUpdates]`), performing verified atomic in-place replacement and relaunch with zero user intervention required.
- **Immediate Boot & Wake Verification**: Integrated immediate update checks on every boot and launch (0.5s post-startup) and subscribed to `NSWorkspace.didWakeNotification` to check for updates whenever the Mac wakes or unlocks.
- **Background Periodic Scheduler**: Added automatic periodic background polling (every 30 minutes) ensuring updates pushed to GitHub are detected and installed swiftly while running in the background.
- **High-Speed Streaming Pipeline**: Replaced byte-by-byte async sequence loop with native `URLSessionDownloadTask` and `HighSpeedDownloadDelegate`, saturating gigabit network connections directly to APFS storage at line-rate speeds (completing 22.6MB downloads in under 1 second on fast networks).
- **Settings Toggle**: Added dedicated "Automatically download and install updates in background" toggle in Settings > Software Updates.

## [2.0.7] — 2026-10-26

### 3D Smoked-Glass Capsule Refinements & Content Contrast
- **Water Effect Removal**: Removed water-filling simulation, pouring streams, surface waves, ripples, and splashes across all capsules.
- **Enhanced Dark Smoked-Glass Base**: Upgraded capsule backgrounds to a solid, high-opacity (92-97%) dark charcoal/obsidian glass with subtle 3D curved gloss reflections, ensuring crystal-clear text contrast on any wallpaper.
- **Rendering Optimization**: Eliminated 60fps Canvas simulation loops and particle allocations, dramatically decreasing CPU and GPU utilization.

### Scopa Storage Optimizer Parity
- **Full Parity Renaming**: Cleanly rebranded the storage optimizer from Purge to **Scopa** across UI menus, dock views, notch dropdowns, models, and safety allowlist engine.

### Dual Logo Terminal Installer
- **Agrigence & LiquidDynamo Branding**: Enhanced the one-line terminal installer (`install.sh`) with dual ANSI truecolor badges featuring the **LiquidDynamo app logo** (3D notch droplet) and the **Agrigence website logo** (pen nib & sprout emblem with hyperlink).
- **Auto-Launch Hardening**: Implemented direct dyld binding repairs and Gatekeeper clearance to guarantee immediate startup on macOS Sonoma and Sequoia.

## [2.0.6] — 2026-10-26

### Live 3D Half-Filled Water Capsule Notification
- **Procedural 3D Liquid Simulation (`LiquidWaterCapsuleView.swift`)**:
  - Implemented real-time procedural 50% water volume inside a transparent Liquid Glass capsule.
  - Continuous downward pouring stream with laminar-to-turbulent wave sway, animated stream core, and moving droplet beadlets.
  - Luminous specular air-liquid meniscus line with diffuse ambient glow and subsurface caustics.
  - Dynamic surface waves with radial impact crown flare, micro-splashes, and expanding concentric elliptical ripples with perspective compression.
  - Contained strictly within the capsule's rounded geometry with zero overflow or boundary oscillation.
  - Clean lifecycle integration across `IslandAlertView`, `DeviceShowcasePopupView`, `BluetoothBatteryAlertPopupView`, and `WatcherPillView`.
- **Global Fix for Clipped Notification Capsules**:
  - Resolved capsule clipping across all notification and event types.
  - Ensured dynamic content-aware width expansion so left and right rounded edges remain fully visible.

### Phone Bridge & MTPBridge Architecture
- **Renamed FileDroid / Kalam Bridge to Phone Bridge and MTPBridge (settings keys migrated automatically)**:
  - Renamed user-facing feature name to **Phone Bridge** across UI surfaces, Dynamic Island expanded views, Settings sidebar (`PhoneBridge`), and documentation.
  - Renamed Swift types to `PhoneBridgeEngine`, `PhoneBridgeModels`, `PhoneBridgeView`, `PhoneBridgeWindowController`, `SettingsPhoneBridgeView`, and `MTPBridge`.
  - Preserved backward-compatible typealiases (`FileDroidEngine`, `FileDroidView`, `FileDroidWindowController`, `SettingsFileDroidView`, `KalamBridge`, etc.).
  - Migrated persisted `Defaults` keys from `filedroid*` to `phonebridge*` with automatic one-time startup migration preserving existing settings and downgrade compatibility.
  - Upstream project names, licenses, and bundled binary dynamic libraries (`kalam.dylib`, `libusb.dylib`) remain strictly preserved.

### Milestone 1: Powerload Multi-Interface Network Engine
- **Documented Network.framework Binding (`PowerloadHTTPClient.swift`)**:
  - Replaced private, undocumented KVC key `kCFStreamPropertyBoundInterfaceIdentifier` / `_socketStreamProperties` with official Network.framework `NWConnection` binding using `NWParameters.requiredInterface` matched against active `NWInterface` instances.
  - Added robust HTTP/1.1 Range streaming client supporting TLS, redirection resolution, and graceful fallback to `/usr/bin/curl --interface <bsd>` when socket-level binding is required.
- **Authoritative Interface Eligibility & Gateway Health (`PowerloadNetworkManager.swift`)**:
  - Replaced loose `hasIP || isLinkActive` check with strict qualification: requires `IFF_UP`, `IFF_RUNNING`, non-link-local IPv4 (excluding `169.254/16`) or global IPv6, and an active default router gateway verified via SCDynamicStore (`State:/Network/Service/<id>/IPv4 Router`).
  - Added bound probe against the target download host before marking an interface usable.
  - Excluded all virtual, loopback, and bridge interfaces (`vmnet*`, `utun*`, `bridge*`, `docker`, `awdl*`, `llw*`, `anpi*`).
  - Removed "fallback to all enabled interfaces" behavior to prevent stalling on inactive NICs.
  - Track granular health state per adapter: `usable`, `degraded`, or `unusable(reason:)` with visible reasons ("No default gateway", "Link-local address only", "Target host probe failed", "Interface link down").
- **Throughput-Weighted Scheduling & Circuit Breaker (`PowerloadDownloadEngine.swift`)**:
  - Replaced rigid round-robin scheduling with a work-stealing pool weighted by measured throughput (EWMA per interface).
  - Added circuit breaker: after 3 consecutive failed chunk downloads, an interface is marked degraded with exponential backoff (30s–60s) and excluded from chunk scheduling until a health probe succeeds.
  - Implemented exception-safe `FileHandle` validation, pausing downloads with visible alerts if target files cannot be opened or seeked rather than silently dropping data.
- **Range Correctness & Single-Stream Fallback**:
  - Strictly accept HTTP 206 with matching `Content-Range: bytes start-end/total`.
  - Servers returning HTTP 200 to Range requests are detected as non-range-supporting; chunked multi-stream plan is immediately converted to a safe single-stream download from byte 0, completely preventing file corruption from overwriting chunks.
  - Validate received chunk size against requested range and re-queue failed chunks without data loss.
- **SCNetworkInterface Classification & Metered Connections**:
  - Authoritative classification using `SCNetworkInterfaceGetInterfaceType` (IEEE 802.11, Ethernet, Bluetooth, Bridge, etc.) and hardware port mapping.
  - Added user toggle `powerloadUseMeteredConnections` (default ON) with explicit documentation that Wi-Fi personal hotspots share the physical Wi-Fi radio and cannot be aggregated.

### Milestone 2: Secure Application Updater
- **Cryptographic Code Signature & Gatekeeper Verification (`GitHubUpdateChecker.swift`)**:
  - Staged updates are cryptographically audited before replacement: requires `/usr/bin/codesign --verify --deep --strict`, Developer ID Application signing authority, exact Team Identifier match against the running binary via `SecCodeCopySelf`, and Gatekeeper validation via `/usr/sbin/spctl --assess --type execute`.
  - Replaced unversioned fallback repository `dynamomac` and mutable `releases/download/app/...` URLs with version-pinned release assets from official GitHub repositories over HTTPS.
  - Removed `-noverify` flag from `hdiutil attach`, ensuring disk images are fully checksum-verified prior to mounting.
  - Removed quarantine stripping (`xattr -dr com.apple.quarantine` completely eliminated).
- **SemVer 2.0.0 Specification Parser**:
  - Implemented compliant Semantic Versioning parser with pre-release precedence, correctly sorting `"2.8-rc.1" < "2.8"`, `"1.10.0" > "1.9.0"`, and `"2.0.5" == "2.0.5"`.
- **Atomic Staging & Automated Rollback**:
  - Staged installation operates beside the active bundle within the same volume: creates `.backup` of `Bundle.main.bundleURL`, moves new app into place atomically, and automatically restores `.backup` if installation or verification fails.
  - Added user opt-in toggle `Defaults[.autoCheckUpdates]` (default ON) in Settings > General / Privacy with transparent endpoint disclosure.

### Milestone 3: Resilient Clipboard History Service
- **Definitive Change Count Consumption & Lazy Promise Retries (`ClipboardHistoryService.swift`)**:
  - `lastChangeCount` is now consumed strictly upon terminal decisions (permanent skips or successful ingestion).
  - Transient conditions (lazy pasteboard promises where data is not yet generated) trigger non-blocking retries for up to 2.0 seconds without dropping entries.
- **Clipboard-Local Screen Recording Debouncer with Hysteresis**:
  - Built a dedicated clipboard screen-capture detector with 1.5s on / 1.0s off hysteresis, filtering transient screenshot overlays (`screencapture`) to prevent dropped copies during user screenshots.
  - Wired to user setting `Defaults[.clipboardShieldDuringScreenRecording]` (default ON) with Settings toggle, leaving `HardwareSensorMonitor` and the Dynamic Island indicator untouched.
- **DispatchSourceTimer & Background Persistence**:
  - Replaced main-thread `Timer.scheduledTimer` with background `DispatchSourceTimer` on a utility queue, holding `ProcessInfo.beginActivity` token to prevent App Nap stalls during window drags and modal menus.
  - Added automatic wake re-arming via `NSWorkspace.didWakeNotification`.
  - Offloaded thumbnail decompression/compression to background tasks and debounced disk JSON encoding.
- **SHA-256 Image Deduplication & Text Preservation**:
  - Deduplicate images using SHA-256 hash of original raw bytes stored as an optional Codable field (`imageHash`), eliminating thumbnail `prefix(256)` collision bugs.
  - Reordered type priority to inspect text before image representations, preserving rich text from spreadsheets and browsers that also place preview bitmaps on the pasteboard.
  - Added explicit "Retry Access" action in `LiquidClipboardRegionView` for macOS 15.4+ pasteboard access behaviors.

### Milestone 4: FileDroid & KalamBridge Thread Safety
- **Serial AsyncStream Queue (`KalamBridge.swift`)**:
  - Replaced problematic `NSLock` cross-thread locking/unlocking with a thread-safe serial `AsyncStream` FIFO operation queue.
  - Eliminated global static handler collisions (`activeDoneHandler`, `activeProgressHandler`) by binding responses to isolated operation tokens.
  - Added per-operation 15-second timeout and automatic bridge recovery with `KalamError.timeout`.
- **Strict Codable Response Envelope**:
  - Replaced loose substring checks with typed `KalamResponse<T>` JSON decoding, treating non-empty error fields or malformed JSON strictly as failures.
- **Secure Dylib Resolution & Intel Compatibility**:
  - Removed all hardcoded developer paths (`/Users/sarvesh/...`), CWD search paths, and `/Applications`. Restricted dynamic library loading to `Bundle.main.privateFrameworksURL` and `@rpath`.
  - Added runtime architecture detection (`isSupportedArchitecture`): displays clear user guidance ("Native MTP bridge is unavailable on Intel Macs") rather than failing silently on x86_64 systems.
  - Added comprehensive third-party license notices to `THIRD_PARTY_LICENSES` for libusb (LGPL-2.1 with dynamic linking and user relinking notices), OpenMTP, and Kalam.

### Milestone 5: ADBClient Concurrency & Process Safety
- **Bounded Concurrent Pipe Streaming (`ADBClient.swift`)**:
  - Concurrently streams `standardOutput` and `standardError` via `readabilityHandler` into thread-safe `ConcurrentDataBuffer` (10 MB bounded capacity), eliminating child process deadlocks on output exceeding macOS 64 KB pipe buffer.
- **Typed Error Hierarchy & Task Cancellation**:
  - Implemented typed `ADBError` enum (`.timeout`, `.cancelled`, `.commandFailed`, `.transferFailed`).
  - Process timeouts now throw typed `ADBError.timeout` rather than returning exit code 15 with truncated output.
  - Added `withTaskCancellationHandler` and `ProcessHolder` so cooperative Swift Task cancellations promptly terminate the underlying ADB process.
- **Exception-Safe Timers & Atomic File Replacement**:
  - Made `progressTimer` in `pullFile` and `pushFile` lifecycle exception-safe: created and resumed only when `finalBytes > 0 && onProgress != nil`, eliminating libdispatch inactive source release crashes.
  - Implemented atomic file placement in `pullFile` using `FileManager.default.replaceItemAt`, guaranteeing that existing destination files are never deleted prior to complete download success.

### Milestone 6: Release Script Reproducibility
- **Reproducible Release Guard (`build_dmg.sh`)**:
  - When invoked with `RELEASE=1` or `--release`, strictly requires clean `xcodebuild` compilation and Developer ID Application signing identity; completely refuses non-Xcode fallback and `/Applications` template copying.
  - Replaced hardcoded `CFBundleVersion 17` with dynamic project version extraction (`CURRENT_PROJECT_VERSION 18`).
  - Staged framework dynamic libraries (`kalam.dylib`, `libusb.dylib`) fail fast if missing, removing unsafe `|| true`.
- **Isolated Build Directories**:
  - Replaced shared `/tmp/spm_deps` in `scripts/compile_dynamo.sh` and `scripts/setup_spm_deps.sh` with isolated `mktemp -d` temporary directories with automatic cleanup traps.

### Milestone 7: Outbound Network Disclosure & Privacy Opt-Ins
- **Unified Privacy Disclosure Card (`SettingsPrivacyView.swift`)**:
  - Added "Network Access & Endpoints" disclosure card in Settings > Privacy listing all outbound network hosts, data transmitted, and user control toggles:
    - Update Checks (`api.github.com` / `github.com`): default ON with toggle.
    - Public IP Lookup (`api64.ipify.org`): default OFF with toggle; guarded in `PublicIPService.swift`.
    - 3D Cloud Model Generation (`api.meshy.ai`): default OFF with toggle; guarded in `MeshyImageTo3DProvider.swift` with mandatory `NSAlert` modal confirmation dialog before image upload and API key stored strictly in macOS Keychain.
    - Synced Lyrics (`lrclib.net`): default OFF with toggle per existing settings.
    - Powerload Downloads: transparently documented as contacting user-provided URLs only.
- **Bundled Offline Waveform Animation**:
  - Bundled `default_wave_visualizer.json` in application resources for 100% offline rendering, removing network dependency on `assets9.lottiefiles.com`.
- **Documentation Updates**:
  - Updated `README.md` and `RULES.md` to accurately document network transparency, privacy opt-ins, and zero telemetry.

---

## [2.0.5] — 2026-10-25

### Apple Developer ID Signing, Hardened Runtime, & Apple Notarization Pipeline
- **Inside-Out Code Signing (`build_dmg.sh`)**:
  - Replaced ad-hoc `--deep` signing with deterministic inside-out signing order without `--deep`.
  - Discovers and signs all embedded Mach-O binaries (including `MediaRemoteAdapterTestClient` in Resources and all framework dylibs) with `--force --options runtime --timestamp`.
  - Signs nested Sparkle helper components (`Downloader.xpc`, `Installer.xpc`, `Updater.app`, `Autoupdate`), framework bundles, `LiquidDynamoXPCHelper.xpc` with its entitlements, and finally `LiquidDynamo.app` with its hardened runtime entitlements.
- **Two-Stage Apple Notarization & Offline Stapling**:
  - Implemented two-stage notarization: Stage 1 zips and submits `LiquidDynamo.app`, and staples the notarization ticket directly to `.app`. Stage 2 packages the stapled app into the custom DMG, signs the DMG with secure timestamp, submits the DMG to notary service, and staples the DMG.
  - Ensures users who drag `LiquidDynamo.app` to `/Applications` can open it without Gatekeeper network requests, including completely offline Macs.
  - Automatic error diagnostic retrieval (`xcrun notarytool log <id>`) whenever notarization status returns `Invalid`.
- **Release Fail-Fast Guard**:
  - `build_dmg.sh` refuses to proceed if `RELEASE=1` or `--release` is passed and `SIGN_IDENTITY` is `"-"` or unset, preventing accidental distribution of ad-hoc binaries.
  - Dynamic version extraction from Xcode project / Info.plist.
- **Automated Verification Script (`scripts/verify_release.sh`)**:
  - Added full verification suite inspecting deep code signature, Developer ID Application authority, Team ID, Hardened Runtime flags (`0x10000(runtime)`), secure Apple timestamps, Gatekeeper assessment (`spctl -a -vvv` -> `source=Notarized Developer ID`), stapler validation (`xcrun stapler validate`), exhaustive scan of all embedded Mach-Os, and absence of `com.apple.security.get-task-allow`.
- **Ad-Hoc Packaging Guard (`scripts/deploy_and_package.sh`)**:
  - Added loud red warning guard requiring explicit `ALLOW_ADHOC=1` to run, preventing use of deprecated ad-hoc `--deep` packaging for distribution.
- **Documentation & Install Guide Overhaul**:
  - Rewrote `docs/DISTRIBUTION_GUIDE.md` with complete prerequisites, Keychain setup, release commands, verification instructions, and a detailed troubleshooting matrix for `notarytool` error codes.
  - Updated `README.md` install instructions to guide users through standard drag-to-Applications installation without quarantine stripping, noting normal macOS privacy permission prompts.


### Permanent Multi-Display Island & Ambient Wing Indicators
- **Permanent "Show on all displays" Enforcement (Change A)**:
  - "Show on all displays" is now permanently ON for all users, including existing installs with a stored `false`.
  - Removed all 4 configuration UI surfaces: menu bar toggle, Settings System Features toggle & dependent pickers, Behavior Settings toggle & pickers, and Onboarding checkbox.
  - Added leak-free `Defaults.observe(.showOnAllDisplays)` guard in `AppDelegate` to immediately restore `true` upon any external modification.
- **Island Capsule Streamlining (Change B)**:
  - Removed the CPU-temp + RAM status capsule (`systemMetricsBar`) from the open Dynamic Island in `LiquidOrganicNotchView.swift`.
  - Island height now adapts naturally via content-height measurement without empty spacing or leftover vertical gaps.
  - Eliminated redundant local `SystemStatsService` observer from `LiquidOrganicNotchView`.
- **Ambient Wing Bottom Indicators (Change C)**:
  - **LEFT Wing CPU-Temperature Glow (`CPUTempGlowEdge`)**: Edge-aligned 2pt rounded line with soft bloom and gradient fade. Features smooth interpolated gradient (<=45°C cyan/teal, 45-60°C green, 60-72°C yellow, 72-82°C orange, >=82°C red), fallback to macOS `ProcessInfo.ThermalState` when temperature sensors are unavailable, and slow urgency breathing at >=85°C (respecting `accessibilityReduceMotion`).
  - **RIGHT Wing RAM Status Bar (`RAMBottomBar`)**: 2.5pt progress bar with 12% white track, filled from the hardware notch outward with subtle glow, dynamically colored by RAM percentage & memory pressure severity (<60% cyan/green, 60-80% yellow, 80-90% orange, >=90% red) and clamped to [0.0, 1.0].
  - **Telemetry Lifecycle Management**: `SystemStatsService` starts whenever any wing with an indicator is visible and cleanly terminates when wings or side readouts are disabled (`.none`), keeping idle CPU at ~0%.
  - Fully clipped to `LeftNotchDropShape`, `RightNotchDropShape`, and `Capsule` silhouettes without altering wing geometry or touch targets.

---

## [2.0.4] — 2026-10-25

### Live Dynamic Wing Auto-Arrangement & Multi-Display Architecture
- **Real-Time Content-Based Wing Sizing**: Dynamic notch wings automatically arrange their size in real-time according to their live intrinsic content (CPU %, RAM details, Network upload/download speeds, live track titles, system battery, volume, and ambient weather).
- **Organic Fluid Spring Animations**: All wing dimension changes are orchestrated through `IslandMotion.shared.expandSpring` for seamless, non-jittery morphing during telemetry fluctuations and detail card expansions.
- **Bi-Directional Shrink & Expand**: Removed rigid `compactPillWidth` window clamping. Wings now naturally shrink down to compact icon-only footprints (265 pt) and expand dynamically for verbose metric readouts (303 pt+) without clipping.
- **Perfect Multi-Display Symmetry**: On external and non-notched monitors, the central Dynamic Island pill remains locked in the true center while left and right wings independently auto-size within symmetrical slots.
- **Eliminated Initialization Deadlock**: Decoupled `getClosedNotchSize` from the `IslandController.shared` singleton, preventing recursive `dispatch_once` locks on startup.

---

## [2.0.3] — 2026-10-25

### Continuous Background Persistence & Stability Fixes
- **Zero-Termination Background Operation**: Configured `NSSupportsAutomaticTermination = false`, `NSSupportsSuddenTermination = false`, and `NSAppSleepDisabled = true` across `Info.plist` and `project.pbxproj`.
- **Latency-Critical Background Assertion**: Added persistent `ProcessInfo.processInfo.beginActivity` assertion and explicit `disableAutomaticTermination` / `disableSuddenTermination` in `AppDelegate` so macOS WindowServer and App Nap never terminate or freeze LiquidDynamo in the background.
- **Fixed MTP libusb POSIX Key Exhaustion (SIGABRT Crash)**: Eliminated unconditional 5-second background MTP scanner loop that leaked POSIX thread keys (`pthread_key_create`). Device detection now relies on Darwin IOKit notifications via `DeviceMonitor`, completely preventing `usbi_io_init` assertion crashes after extended background runtime.
- **Synchronized Bundle Framework Dylibs**: Ensured all compiled dylibs are synchronized into the application bundle during compilation and packaging.

---

## [2.0.2] — 2026-10-24

### Dynamic Island Streamlining & UI Separation
- **Clean Hardware Notch Interface**: Removed placeholder "Coming Soon" Water and Break Reminder cards and status buttons from `LiquidOrganicNotchView.swift` and `IslandController.swift`. The Dynamic Island now strictly contains 100% active, interactive, production tools (Clipboard History, Dropper Shelf, Storage Cleaner, Watcher, Device Showcase, and Powerload Turbo Engine).
- **Dedicated App Settings Preview for Upcoming Modules**: Preserved and organized upcoming health & focus features (Smart Hydration & Ergonomic Break Coach) inside App Settings (`SettingsModulesView` & `SettingsHydrationView`) so users can preview and configure preferences without notch clutter.
- **Dynamic Dropdown Height Stability**: Streamlined `IslandController.minimumHeight` and intrinsic target size calculations, ensuring buttery-smooth organic liquid springs without jitter.

---

## [2.0.1] — 2026-10-24

### Powerload Multi-Network Turbo & Glowing Under-Notch Download Engine
- **Powerload Rebranding & Architecture**: Rebranded and natively ported multi-network bonding engine across Wi-Fi, Gigabit Ethernet, iPhone USB tethering, Android USB hotspots (RNDIS), and Thunderbolt bridges.
- **Glowing Under-Notch Download Progress Bar**: Real-time animated glowing beam rendered directly beneath the MacBook hardware notch with continuous 1% Red to 100% Green dynamic hue transition, specular shimmer highlight sweep, and neon atmospheric bloom.
- **Dedicated Non-Wi-Fi Telemetry Cards**: Complete live status cards for active Ethernet, USB, and Thunderbolt adapters in `NetworkTabView`.

---

## [2.0.0] — 2026-10-24

### In-App GitHub Release Changelog & Real-Time Sync
- **Native GitHub Changelog Viewer**: Added dedicated "Release Changelog (GitHub)" sheet accessible directly inside Settings > About > Links & Diagnostics (`sparkles.rectangle.stack`). Fetches live release tags, release dates, and complete release notes directly from GitHub's Releases API asynchronously with a direct "View on GitHub" button.
- **Zero-File One-Line Terminal Installer**: Designed and published a pure 1-line Terminal installer requiring no cloned files, no external scripts, and no dependencies. Automatically downloads latest binaries from GitHub releases, extracts to `/Applications`, strips macOS Gatekeeper quarantine flags (`xattr -cr`), and launches LiquidDynamo immediately.
- **Multi-Candidate Download Fallback & 404 Resilience**: Enhanced in-app updater download resilience with automatic URL sanitization and secondary repository fallback, preventing download failure or 404 server errors during release asset propagation.

### In-App Android File Manager & Device Card "Open in app"
- **"Open in app" Action on Android Device Detail Card**: Replaced the previous button with "Open in app" (`folder.badge.gearshape`) on the Android device card only (`motorola edge 50`, subtitle "MTP Media Bridge", "Android" badge). Tapping opens or focuses a dedicated native liquid glass window per device serial. Clicking does not collapse or unpin the Dynamic Island.
- **Dedicated Android File Manager Window (`Features/AndroidFiles/`)**:
  - **Asynchronous ADB Client (`ADBClient.swift`)**: Process-based async/await client supporting connection states (`noAdb`, `noDevice`, `unauthorized`, `offline`, `multipleDevices`, `ready`, `error`), strict shell escaping with single-quote escaping `'\''`, toybox `ls -lA` directory parsing with symlink resolution (`/sdcard` -> `/storage/emulated/0`), disk free space (`df`), progress-tracked streaming pulls/pushes, conflict policy, and Android 11+ scoped storage protection detection for `/Android/data` and `/Android/obb`.
  - **Liquid Glass Interface (`AndroidFileManagerView.swift`)**: Native SwiftUI window with top toolbar (navigation history, path breadcrumbs, search, new folder, upload, list/grid toggle, sort picker, hidden files toggle, refresh), quick locations sidebar (`Internal Storage`, `DCIM`, `Pictures`, `Download`, `Documents`, `Movies`, `Music`, `WhatsApp Media`), device capacity bar, lazy list/grid rows, and status bar.
  - **LRU Thumbnail Cache (`AndroidThumbnailCache.swift`)**: Size-capped disk and memory thumbnail generator (default 200 MB) for images and videos with lazy background extraction.
  - **Transfer Manager**: Real-time drawer showing active downloads/uploads with throughput speeds (`MB/s`), progress bars, cancellation, and "Reveal in Finder" for finished pulls on macOS.
- **Settings Configuration**: Added Android File Manager section in Settings with custom ADB binary path, default download location, thumbnail cache capacity, and stop-daemon on quit toggle.

### Plexo Multi-Network Discovery & Hardware Interface Bonding
- **Comprehensive Hardware Adapter Discovery**: Enhanced `PlexoNetworkManager` using native macOS `SystemConfiguration` (`SCNetworkInterfaceCopyAll`) and BSD `getifaddrs` to discover and list all physical and virtual network interfaces (Ethernet adapters `en3`/`en4`, Wi-Fi `en0`, Thunderbolt Bridge `bridge0`, USB-C cellular tethering, and hotspot connections) instead of only listing active Wi-Fi.
- **Hardware Metadata & Status Detection**: Each network interface now displays its localized human-readable port label, hardware BSD device identifier, MAC address, IPv4 address, and subnet mask.
- **Per-Interface Socket Stream Binding**: Upgraded worker connection allocation in `PlexoDownloadEngine` to use CFNetwork's native `kCFStreamPropertyBoundInterfaceIdentifier` in `_socketStreamProperties`. Worker chunk pools dynamically distribute parallel connections across all active connected interfaces (`activeConnectedInterfaces`), executing true multi-network bonding and work-stealing across Wi-Fi and Ethernet concurrently.

---

## [1.9.9] — 2026-10-24

### Dedicated App Window for Android File Management
- **Native FileDroid Window Controller**: Clicking an Android device chip or "Open Device Folders" opens the full file manager in a dedicated native AppKit window (`FileDroidWindowController`), featuring dual-pane directory navigation, breadcrumb path traversal, quick-access shortcuts (`DCIM`, `Download`, `Documents`, `Pictures`), search, and transfer queue drawers directly in the app UI—without opening in Finder and without notch size constraints.

### Dedicated Android Downloads Directory
- **Automated Downloads Organization**: All downloads and pulls from Android devices via ADB and MTP are saved directly into a dedicated directory at `~/Downloads/Android`. The target directory is automatically created if missing, and clicking "Open Mac Downloads Folder" reveals all saved Android files directly in Finder.

### Dynamic Notch Wing Expansion
- **Content-Driven Width Measurement**: Collapsed live info wings dynamically measure their intrinsic contents using `LeftWingWidthPreferenceKey` and `RightWingWidthPreferenceKey`. When readouts contain expanded telemetry (e.g. CPU %, Network Throughput, RAM %, Battery %, or Hover/Tap details), the wing drops and `targetSize.width` organically expand with spring animation so no text or units are clipped.
- **Removed Collapsed Padding Restriction**: Eliminated extraneous horizontal padding in the resting notch container that previously pinched the wings and clipped digits on outer boundaries.
- **Synchronized Hit Rects**: `NotchSafeAreaEngine.collapsedWingHitRects` dynamically tracks the expanded wing width, ensuring hover and tap interactions register smoothly across the entire wing surface.

---

## [1.9.8] — 2026-10-24

### Home Dashboard Primary Row Multi-Line Wrapping
- **Dynamic Centered Flow Layout**: Replaced the single-line row with `CenteredFlowLayout` to wrap chips across multiple centered lines without clipping; wrapped connected devices into a continuous rounded rectangle, and removed the Color Dropper chip from the primary row.

### Combined Network Speed Wing Readout
- **Unified Total Throughput**: Combined download and upload throughput into a single rate formatted with monospaced digits and network icon in the wing readout, filtered wing pickers to `Network Speed`, and added automatic migration for legacy separate metrics on launch.

---

## [1.9.7] — 2026-10-23

### In-Place Auto-Update & Permanent Release Distribution
- **In-Place Application Replacement**: `GitHubUpdateChecker` now supports fully automated download of `LiquidDynamo.dmg`, background DMG mounting, application extraction, and detached in-place replacement of the application bundle with automatic relaunch.
- **Guaranteed Permanent Release Link**: All updates and releases are permanently published and downloaded from `https://github.com/anksarvesh-lgtm/dynamo-mac/releases/download/app/LiquidDynamo.dmg`.
- **Enhanced Software Updates UI**: `SoftwareUpdater` includes live download progress indicators, byte transfer meters, extraction state, and one-click `Auto-Update App` action.
- **Packaging Control**: `build_dmg.sh` supports `INSTALL_APP=false` to package and save DMGs to Desktop without disturbing the active running application.

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
