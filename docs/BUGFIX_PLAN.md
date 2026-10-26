# LiquidDynamo 2.0.5 Bugfix Plan & Audit Findings

This document establishes the audit evidence, root causes, targeted minimal changes, risks, test strategies, and regression safeguards across milestones M1–M7 for LiquidDynamo 2.0.5.

---

## 1. Audit Summary & Findings Table

| Milestone | Item | Status | Evidence Summary |
|---|---|---|---|
| **M1** | C1: Binding is not honored | **CONFIRMED** | `PowerloadDownloadEngine.swift:431` sets private undocumented KVC `config.setValue(["kCFStreamPropertyBoundInterfaceIdentifier": adapter.bsdName], forKey: "_socketStreamProperties")`. URLSession on modern macOS ignores this dictionary and routes all packets via the default route (`en0`). |
| **M1** | C2: Interface eligibility too loose | **CONFIRMED** | `PowerloadModels.swift:114` defines `isOnline = hasIP || isLinkActive` accepting link-local `fe80::` / `169.254.x.x` without gateways. `PowerloadNetworkManager.swift:230` falls back to `interfaces.filter { $0.isEnabled }` when none is online. No gateway/route/probe exists. |
| **M1** | C3: Failing workers spin | **CONFIRMED** | `PowerloadDownloadEngine.swift:405` returns failed chunks and sleeps `0.5s` in an endless loop. Dead interfaces steal chunks, block for 20s per request timeout, and collapse throughput. |
| **M1** | C4: Range handling accepts HTTP 200 | **CONFIRMED** | `PowerloadDownloadEngine.swift:440` accepts `statusCode == 206 || 200` and writes data at `rangeStart` offset in the target file. A server ignoring Range returns 200 with the full body, causing file corruption. |
| **M1** | C5: Interface classification uses guesses | **CONFIRMED** | `PowerloadNetworkManager.swift:553` checks `bsdName.hasPrefix("en") -> .ethernet`, misclassifying `en0` (Wi-Fi) and tether adapters. `speedMbps` is hardcoded (866 for Wi-Fi, 1000 for Ethernet) without SCNetworkInterface verification. |
| **M2** | Updater: validateAndRelaunch check | **CONFIRMED** | `GitHubUpdateChecker.swift:480` only checks that `Contents/MacOS` is non-empty. No `codesign --verify`, Team ID, or `spctl` assessment is performed. |
| **M2** | Updater: DMG mounted with `-noverify` | **CONFIRMED** | `GitHubUpdateChecker.swift:435` executes `hdiutil attach -noverify`. |
| **M2** | Updater: Relaunch script strips quarantine & lacks rollback | **CONFIRMED** | `GitHubUpdateChecker.swift:517-524` runs `xattr -dr com.apple.quarantine`, blindly removes both `/Applications/liquiddynamo.app` and `/Applications/LiquidDynamo.app` with `rm -rf`, and lacks rollback on failed `cp`. |
| **M2** | Updater: Mutable URLs and fallback repo | **CONFIRMED** | `GitHubUpdateChecker.swift:20-31` defines mutable URLs (`.../releases/download/app/liquiddynamo.zip`) and fallback repo `dynamomac`. |
| **M2** | Updater: Version comparison ranks "2.8-rc.1" > "2.8" | **CONFIRMED** | `GitHubUpdateChecker.swift:571` uses NSString `.compare(..., options: .numeric)`. `"2.8-rc.1".compare("2.8", options: .numeric)` yields `.orderedDescending`. |
| **M3** | H1: lastChangeCount consumed before filters | **CONFIRMED** | `ClipboardHistoryService.swift:122` sets `lastChangeCount = currentCount` before checking frontmost app, concealed types, screen recording, or reading data. Any skipped/delayed item is lost forever. |
| **M3** | H2: Screen recording shield false positives | **CONFIRMED** | `HardwareSensorMonitor.swift:168` queries `CGWindowListCopyWindowInfo([.optionAll])` for `screencapture`/`screencaptured`/`replayd`. Taking a screenshot or opening macOS screenshot overlay triggers false positives. |
| **M3** | H3: Timer.scheduledTimer in default mode | **CONFIRMED** | `ClipboardHistoryService.swift:80` uses `Timer.scheduledTimer` in `.default` mode on `@MainActor`. Stalls during menu tracking or drags, lacks App Nap protection and sleep/wake re-arm. |
| **M3** | H4: Lazy pasteboard promises | **CONFIRMED** | Data may be nil immediately after `changeCount` increments; service does not retry transient failures before dropping. |
| **M3** | H5: macOS 15.4+ pasteboard privacy | **CONFIRMED** | `accessDenied` exists in UI but pasteboard privacy access behaviors are not handled gracefully with prompt/capture buttons. |
| **M3** | H6: Image dedupe prefix(256) | **CONFIRMED** | `ClipboardHistoryService.swift:266` compares `prefix(256)` of re-encoded thumbnail data, matching distinct same-dimension images. |
| **M3** | H7: Type priority drops text on image preview | **CONFIRMED** | `ClipboardHistoryService.swift:151` checks files > image > text; apps placing both image preview and text lose text content. |
| **M3** | H8: Main-thread image decode & synchronous JSON saves | **CONFIRMED** | `ClipboardHistoryService.swift:276, 398` does image resizing/compression and synchronous `JSONEncoder.encode` + `data.write` on the main actor. |
| **M4** | 1: NSLock thread mismatch & deadlock on missed callback | **CONFIRMED** | `KalamBridge.swift:200-203` calls `lock.lock()` on caller thread and `lock.unlock()` inside C callback on worker thread. Unfired callbacks permanently lock the bridge. |
| **M4** | 2: Overlapping calls overwrite static handlers | **CONFIRMED** | `KalamBridge.swift:102` uses static singletons `activeDoneHandler`, `activeProgressHandler`, `activePreprocessHandler`. Concurrent calls clobber each other. |
| **M4** | 3: Unknown error JSON counts as success | **CONFIRMED** | `KalamBridge.swift:318` checks `json.contains("\"error\":\"\"") || !json.contains("errorType")`. Responses without `errorType` are treated as success. |
| **M4** | 4: Hardcoded developer search paths for dylibs | **CONFIRMED** | `KalamBridge.swift:140-141` contains `/Users/sarvesh/...` and current directory search paths. |
| **M4** | 5: kalam.dylib and libusb.dylib missing from project.pbxproj | **CONFIRMED** | Neither dylib is referenced in `LiquidDynamo.xcodeproj/project.pbxproj`. |
| **M4** | 6: Dylibs are arm64-only | **CONFIRMED** | `file Frameworks/kalam.dylib Frameworks/libusb.dylib` reports `Mach-O 64-bit dynamically linked shared library arm64`. No x86_64 slice. |
| **M4** | 7: THIRD_PARTY_LICENSES lacks libusb, OpenMTP, kalam | **CONFIRMED** | `THIRD_PARTY_LICENSES` has zero mentions of libusb (LGPL-2.1), OpenMTP, or kalam. |
| **M5** | 1: Pipe buffer hang on large output (>64 KB) | **CONFIRMED** | `ADBClient.swift:556` reads pipe only in `process.terminationHandler` via `readDataToEndOfFile`. ADB blocks once pipe buffer fills. |
| **M5** | 2: Timeout returns exit code 15 instead of typed error | **CONFIRMED** | `ADBClient.swift:561` resumes continuation with `(stdout: outStr, stderr: errStr, exitCode: 15)` instead of throwing `ADBError.timeout`. |
| **M5** | 3: DispatchSourceTimer cancel without resume crash | **CONFIRMED** | `ADBClient.swift:756` calls `progressTimer.cancel()` in `terminationHandler` even when `finalBytes <= 0` where `resume()` was skipped, triggering libdispatch assertion failure. |
| **M5** | 4: Existing file deleted before moving temp download | **CONFIRMED** | `ADBClient.swift:761` calls `removeItem(at: localURL)` before `moveItem(at: tempDownloadURL, to: localURL)`. Failed move leaves user with no file. |
| **M6** | Non-Xcode fallback uses stale /tmp & /Applications | **CONFIRMED** | `build_dmg.sh:148-157` copies `/Applications/LiquidDynamo.app` or `build/LiquidDynamo.app`, hard-codes `CFBundleVersion 17`, and silently copies dylibs with `|| true`. |
| **M7** | Undisclosed outbound network hosts | **CONFIRMED** | Outbound requests found to `api64.ipify.org` (PublicIPService), `assets9.lottiefiles.com` (Music/LottieAnimationView), `api.meshy.ai` (DeviceShowcase/MeshyImageTo3DProvider), and GitHub releases without unified privacy disclosure or opt-in toggles. |

---

## 2. Milestone by Milestone Plan

### Milestone 1: Powerload Multi-Interface Network Engine
- **Status**: **CONFIRMED & FIXED (VERIFIED WITH PASSING TESTS & XCODEBUILD DEBUG BUILD)**
- **Cause**: Deprecated private KVC binding (`_socketStreamProperties`) is ignored by CFNetwork/libsystem_network. Missing gateway/probe validation leads to dead workers spinning on 20s timeouts. HTTP 200 accepted as Range 206, corrupting files. Substring classification mistakes adapters.
- **Change**:
  1. Implemented binding via Network.framework `NWConnection` HTTP client (`PowerloadHTTPClient.swift`) with strict `NWParameters.requiredInterface` binding and fallback to `/usr/bin/curl --interface <bsd>`.
  2. Implemented authoritative interface qualification: `IFF_UP`, `IFF_RUNNING`, non-link-local IPv4/global IPv6, SCDynamicStore `Router` gateway lookup, virtual interface filtering (`vmnet`, `utun`, `anpi`, `awdl`, `bridge`, `llw`, `lo`, `ipsec`), and bound probe against target host.
  3. Work-stealing scheduling pool with EWMA throughput weighting and circuit breaker (3 consecutive failures marks interface degraded with 30s backoff).
  4. Range correctness: Accepts only HTTP 206 with valid range. Strictly detects HTTP 200 / `rangeNotSupported` and triggers immediate single-stream fallback starting from byte 0 without file corruption.
  5. Authoritative classification using `SCNetworkInterface` types and language-agnostic hardware port mapping.
  6. Added metered connection setting (`Defaults[.powerloadUseMeteredConnections]`) and UI note explaining Wi-Fi hotspot single-radio limitation.
  7. Handle `FileHandle` open and seek errors explicitly.
- **Test Evidence**:
  - `scripts/test_powerload_milestone1.swift`: All 5 unit test suites passed (Virtual Interface Filtering, Metered Classification, Health State Transitions, Strict HTTP 206 / Range Error Classification, Worker Pool & Chunk Work Stealing).
  - `xcodebuild -scheme LiquidDynamo -configuration Debug CODE_SIGNING_ALLOWED=NO -destination "platform=macOS" build`: **BUILD SUCCEEDED**.

### Milestone 2: Secure Application Updater
- **Status**: **CONFIRMED & FIXED (VERIFIED WITH 25/25 PASSING UNIT TESTS & XCODEBUILD DEBUG BUILD)**
- **Cause**: Auto-updater stages apps without cryptographic verification, mounts DMGs with `-noverify`, strips quarantine, executes non-atomic copy without rollback, uses broken version comparison ("2.8-rc.1" > "2.8"), queries unversioned fallback repo, and lacks user opt-in controls.
- **Change**:
  1. Implemented `SemanticVersion` parser conforming to SemVer 2.0.0 specification with pre-release precedence ("2.8-rc.1" < "2.8", "1.10" > "1.9").
  2. Implemented cryptographic verification pipeline: binary existence in `Contents/MacOS`, `CFBundleIdentifier` match against `Bundle.main`, downgrade rejection (`stagedVer >= currentVer`), `/usr/bin/codesign --verify --deep --strict`, Team ID extraction and verification via `SecCodeCopySelf` / `SecCodeCopySigningInformation`, and Gatekeeper assessment via `/usr/sbin/spctl --assess --type execute`.
  3. Enforced strict HTTPS on official GitHub domains (`github.com`, `*.github.com`, `objects.githubusercontent.com`).
  4. Removed `-noverify` flag from `hdiutil attach` so DMG internal checksums are verified before mounting.
  5. Implemented safe atomic installation with rollback: stages temporary installation beside target in the same filesystem, moves target to backup, moves new installation to target, immediately rolls back backup if move fails, and never strips quarantine flags (`xattr -dr com.apple.quarantine` completely removed).
  6. Removed fallback repository `dynamomac` and mutable `app` release tag (`releases/download/app/...`); restricted downloads to version-pinned release tags.
  7. Added `autoCheckUpdates` toggle in `UpdaterSettingsView` bound to `Defaults[.autoCheckUpdates]` and added endpoint transparency disclosure.
- **Test Evidence**:
  - `scripts/test_updater_milestone2.swift`: 25/25 unit tests passed across SemVer comparison, pre-release precedence, HTTPS host filtering, staged bundle security validation, bundle ID spoof detection, downgrade detection, and atomic backup/rollback mechanics.
  - `xcodebuild -scheme LiquidDynamo -configuration Debug CODE_SIGNING_ALLOWED=NO -destination "platform=macOS" build`: **BUILD SUCCEEDED**.

### Milestone 3: Robust Clipboard History Service
- **Status**: **CONFIRMED & FIXED (VERIFIED WITH 23/23 PASSING UNIT TESTS & XCODEBUILD DEBUG BUILD)**
- **Cause**: `lastChangeCount` consumed before filter completion; `HardwareSensorMonitor` window list false-positives on screenshots; timer in default run-loop mode stalls; image prefix(256) collision; main-thread file I/O and JSON encoding.
- **Change**:
  1. Updated `lastChangeCount` consumption to occur strictly upon definitive terminal decisions (permanent skips or successful ingestion). Transient lazy promise conditions retry for up to 2.0s without advancing permanent count.
  2. Implemented dedicated clipboard-local screen-capture debouncer with hysteresis (active after 1.5s of sustained recording, inactive after 1.0s of continuous absence), filtering transient screenshot tool spikes (`screencapture`), wired to `Defaults[.clipboardShieldDuringScreenRecording]` with settings toggle.
  3. Replaced `Timer.scheduledTimer` with `DispatchSourceTimer` on background utility queue, holding `ProcessInfo.beginActivity` token for App Nap prevention, with automatic wake re-arming via `NSWorkspace.didWakeNotification`.
  4. Implemented image deduplication using SHA-256 hash of original raw bytes stored as an optional Codable property on `ClipboardEntry` with backward compatibility for legacy JSON files.
  5. Refined type priority to check text before standalone images, ensuring copied text is never dropped when companion rendered preview images are present.
  6. Offloaded image decompression / thumbnail compression to a detached background task and debounced JSON disk persistence to a dedicated background utility queue.
  7. Added explicit "Retry Access" button in `LiquidClipboardRegionView` for macOS 15.4+ pasteboard access.
- **Test Evidence**:
  - `scripts/test_clipboard_milestone3.swift`: 23/23 unit tests passed across SHA-256 deduplication, Codable backward compatibility, screen recording hysteresis debouncing, lazy promise retry with 2.0s timeout, and type priority text preservation.
  - `xcodebuild -scheme LiquidDynamo -configuration Debug CODE_SIGNING_ALLOWED=NO -destination "platform=macOS" build`: **BUILD SUCCEEDED**.

### Milestone 4: KalamBridge & FileDroid Thread Safety
- **Status**: **CONFIRMED & FIXED (VERIFIED WITH 14/14 PASSING UNIT TESTS & XCODEBUILD DEBUG BUILD)**
- **Cause**: NSLock locked on caller thread and unlocked inside C callback thread; static singletons overwrite concurrent calls; loose substring error check; hardcoded developer dylib paths; missing Xcode project references; arm64-only without Intel UI notice; missing third-party licenses.
- **Change**:
  1. Replaced NSLock with a serial FIFO `AsyncStream<Operation>` request queue that executes operations strictly one by one and guarantees thread-safe completion without lock thread mismatch.
  2. Added per-call 15-second timeout and automatic cancellation/recovery with typed `KalamError.timeout`.
  3. Replaced fragile substring checks (`json.contains("\"error\":\"\"") || !json.contains("errorType")`) with strict typed `Codable` envelope parsing (`KalamResponse<T>`), strictly rejecting any non-empty error field or decoding failure.
  4. Removed hardcoded developer paths (`/Users/sarvesh/...`), CWD search path, and `/Applications`; restricted dylib loading exclusively to `Bundle.main.privateFrameworksURL` with fallback to `@rpath`.
  5. Added runtime architecture detection (`isSupportedArchitecture`): on Intel x86_64, gracefully reports false and surfaces an actionable notice in UI (`availabilityHint`: "Native MTP bridge is unavailable on Intel Macs (Apple Silicon required)").
  6. Added comprehensive third-party license notices to `THIRD_PARTY_LICENSES` for libusb (LGPL-2.1 with dynamic linking & user relinking notice), OpenMTP, and Kalam (Ganesh Rathinavel).
- **Test Evidence**:
  - `scripts/test_kalam_bridge_milestone4.swift`: All 14/14 unit tests passed across Actor Request Serialization, Timeout & Recovery, Strict Codable Response Parsing & Error Rejection, Architecture Detection & Intel Fallback, and Third-Party Licenses Verification.
  - `xcodebuild -scheme LiquidDynamo -configuration Debug CODE_SIGNING_ALLOWED=NO -destination "platform=macOS" build`: **BUILD SUCCEEDED**.

### Milestone 5: ADBClient Concurrency & Process Safety
- **Status**: **CONFIRMED & FIXED (VERIFIED WITH 10/10 PASSING UNIT TESTS & XCODEBUILD DEBUG BUILD)**
- **Cause**: Output pipes read only in `terminationHandler`, deadlocking on >64KB output; process timeouts return exit code 15 instead of typed error; `progressTimer` canceled when never resumed; existing file deleted before download completes.
- **Change**:
  1. Implemented concurrent streaming of `standardOutput` and `standardError` using `readabilityHandler` and thread-safe `ConcurrentDataBuffer` (10 MB bound), completely preventing pipe deadlocks on outputs >64 KB.
  2. Implemented typed `ADBError` enum with `.timeout(timeoutSeconds:)`, `.cancelled`, `.commandFailed`, and `.transferFailed`. On process timeout, now throws `ADBError.timeout` instead of returning exit code 15.
  3. Added `withTaskCancellationHandler` and `ProcessHolder` so cooperative Task cancellation promptly terminates the underlying child process.
  4. Made `progressTimer` lifecycle exception-safe in both `pullFile` and `pushFile`: timer is instantiated and resumed only when `finalBytes > 0 && onProgress != nil`, eliminating the libdispatch inactive/suspended source crash.
  5. Implemented atomic file replacement using `FileManager.default.replaceItemAt` in `pullFile`, ensuring existing files are never deleted prior to successful download completion.
- **Test Evidence**:
  - `scripts/test_adb_client_milestone5.swift`: 10/10 tests passed covering 5 MB pipe buffer streaming without deadlocks, typed 0.3s timeout error validation, Task cancellation, exception-safe timer lifecycle, atomic file replacement without pre-deletion, and ADBShellSecurity escaping.
  - `xcodebuild -scheme LiquidDynamo -configuration Debug CODE_SIGNING_ALLOWED=NO -destination "platform=macOS" build`: **BUILD SUCCEEDED**.

### Milestone 6: Release Script Reproducibility
- **Status**: **CONFIRMED & FIXED**
- **Cause**: In `RELEASE=1` mode, missing xcodebuild fell back to copying `/Applications/LiquidDynamo.app`, hardcoded version "17" (ignoring project's `CURRENT_PROJECT_VERSION 18`), ignored dylib copy failures with `|| true`, and used shared `/tmp/spm_deps`.
- **Change**:
  1. In release mode (`RELEASE=1` or `--release`), strictly enforce `xcodebuild` requirement and reject fallback templates and `/Applications` copying with fatal error.
  2. For local test builds, use `mktemp -d` for isolated build artifacts instead of shared `/tmp/spm_deps`, display a loud warning banner, and clean up temporary build directories via trap.
  3. Staged and validated required Framework dynamic libraries (`kalam.dylib`, `libusb.dylib`) fail fast without `|| true` in release mode.
  4. Extracted version and build numbers dynamically from Xcode project settings (`MARKETING_VERSION 2.0.5`, `CURRENT_PROJECT_VERSION 18`), removing hardcoded "17".
- **Risk**: None; standard Xcode build process preserved.
- **Test Evidence**:
  - `scripts/test_release_script_milestone6.swift`: 10/10 tests passed covering release mode rejection of missing Developer ID, release mode rejection of non-Xcode fallback, extraction of CURRENT_PROJECT_VERSION 18, removal of hardcoded CFBundleVersion 17, and isolated `mktemp -d` usage in `compile_dynamo.sh` and `setup_spm_deps.sh`.
  - Validated syntax of `build_dmg.sh`, `scripts/compile_dynamo.sh`, `scripts/setup_spm_deps.sh`, and `scripts/verify_release.sh`.

### Milestone 7: Outbound Network Disclosure & Privacy Opt-Ins
- **Status**: **CONFIRMED & FIXED**
- **Cause**: Outbound connections were found to `api64.ipify.org` (public IP lookup), `assets9.lottiefiles.com` (remote Lottie wave visualizer), `api.meshy.ai` (image to 3D cloud generation), and GitHub Releases without unified disclosure or granular privacy opt-ins.
- **Change**:
  1. Added "Network Access & Endpoints" card in `SettingsPrivacyView.swift` detailing all outbound connections:
     - Software update checks (`api.github.com` / `github.com`) - default ON with toggle.
     - Public IP lookup (`api64.ipify.org`) - default OFF with toggle; guarded in `PublicIPService.swift`.
     - 3D Cloud model generation (`api.meshy.ai`) - default OFF with toggle; guarded in `MeshyImageTo3DProvider.swift`; explicit `NSAlert` modal consent before image upload in `CloudModelGenerationCoordinator.swift`; API key strictly in Keychain.
     - Synced lyrics (`lrclib.net`) - default OFF with toggle per existing `enableLyrics` preference.
     - Powerload multi-interface downloads - transparently disclosed as contacting user-provided URLs only.
     - Remote Lottie animation - replaced with bundled `default_wave_visualizer.json` in `liquiddinamo/Resources` for 100% offline rendering.
  2. Updated `README.md` and `RULES.md` to accurately disclose network boundaries and privacy opt-ins, removing inaccurate marketing claims.
- **Risk**: None; default states match privacy principles and existing features remain functional.
- **Test Evidence**:
  - `scripts/test_network_disclosure_milestone7.swift`: 13/13 tests passed covering bundled Lottie JSON validity, local JSON precedence in LottieAnimationContainer, PublicIPService opt-in guard, MeshyImageTo3DProvider opt-in guard, modal consent dialog in coordinator, SettingsPrivacyView disclosures and toggles, default values in Constants.swift, and accurate documentation in RULES.md and README.md.
  - `xcodebuild -scheme LiquidDynamo -configuration Debug build`: **BUILD SUCCEEDED**.

---

## 3. "Do Not Regress" Safeguard Checklist

- [x] **Island stays open and shows detail card when icon clicked**: Verified intact in `IslandController.swift` (pin-on-select line 111, hover-exit guard lines 808, 822) and verified by simulation in `scripts/test_reproduce_collapse.swift` (PASS).
- [x] **"Show on all displays" is permanently ON and options hidden**: Verified launch enforcement and permanent observer restoration in `LiquidDynamoApp.swift` (`Defaults[.showOnAllDisplays] = true`), with UI configuration options completely removed from settings views.
- [x] **Home dashboard rows wrap and Color Dropper is gone**: Verified dashboard layout preserves row wrapping and Color Dropper remains completely excised from the notch home grid.
- [x] **Net speed shows ONE combined value**: Verified unified formatted string in `ContentView.swift` line 1828 (`speedProvider.formattedCombined`).
- [x] **CPU-temp glow on left wing and RAM bar on right wing**: Verified `CPUTempGlowEdge` on left wing and `RAMBottomBar` on right wing in `WingBottomIndicators.swift`.
- [x] **Signing/notarization pipeline in build_dmg.sh**: Verified inside-out Developer ID code signing, Hardened Runtime, notarization submission, and stapling intact via `scripts/test_release_script_milestone6.swift` (10/10 PASS).

---

## 4. Hardware & Environment Verification Status

| Scope / Feature | Status | Notes |
|---|---|---|
| Apple Silicon Native Compilation | **VERIFIED** | Swift 6.4 arm64 toolchain validated. |
| Wi-Fi Single Interface | **VERIFIED** | Default route network interface active. |
| Intel (x86_64) Hardware Execution | **UNVERIFIED** | Host machine is Apple Silicon (arm64); Intel runtime verified via graceful fallback path. |
| Physical Android Device via ADB | **UNVERIFIED** | Physical Android phone not attached; verified via unit tests and mock ADB scripts. |
| Physical USB Tethering / iPhone Hotspot | **UNVERIFIED** | Physical secondary cellular tether not connected; verified via simulated multi-interface tests. |
| Physical MTP Device via KalamBridge | **UNVERIFIED** | Physical MTP device not connected; verified via mock bridge harness and unit tests. |
