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
- **Cause**: Deprecated private KVC binding (`_socketStreamProperties`) is ignored by CFNetwork/libsystem_network. Missing gateway/probe validation leads to dead workers spinning on 20s timeouts. HTTP 200 accepted as Range 206. Substring classification mistakes adapters.
- **Change**:
  1. Implement binding via Network.framework `NWConnection` HTTP client (or fallback `/usr/bin/curl --interface <bsd> -r start-end` per chunk) with strict per-interface binding.
  2. Implement authoritative interface qualification: `IFF_UP`, `IFF_RUNNING`, non-link-local IPv4/global IPv6, SCDynamicStore router/scoped default route, and bound probe against download host.
  3. Work-stealing scheduling pool with EWMA throughput weighting and circuit breaker (3 consecutive failures marks interface degraded with exponential backoff).
  4. Range correctness: Accept only HTTP 206 with valid `Content-Range: bytes start-end/total`. Fall back to single-stream on 200 without writing to offset.
  5. Authoritative classification using `SCNetworkInterface` types and hardware port mapping.
  6. Add metered connection setting (`Use metered connections (phone tethers)`) and UI note explaining Wi-Fi hotspot single-radio limitation.
  7. Handle `FileHandle` open errors explicitly.
- **Risk**: Low-level network socket/stream handling across diverse hardware.
- **Test**: Multi-chunk download tests, 200 vs 206 local mock server tests, interface eligibility tests, circuit breaker simulation.

### Milestone 2: Secure Application Updater
- **Cause**: Auto-updater stages apps without cryptographic verification, mounts DMGs with `-noverify`, strips quarantine, executes non-atomic copy without rollback, and uses broken version comparison.
- **Change**:
  1. Add verification pipeline before replacing: `codesign --verify --deep --strict`, Team ID comparison against `Bundle.main`, `spctl --assess --type execute`, bundle identifier check, and version > current.
  2. Require HTTPS only and release asset SHA-256 match.
  3. Remove `-noverify` from `hdiutil attach`. Retain quarantine attributes.
  4. Safe atomic replacement: install beside running app, move running app to backup, rename new app into place, verify launch, and rollback on failure.
  5. Fix SemVer parser: proper handling of major.minor.patch-prerelease ("2.8-rc.1" < "2.8").
  6. Remove fallback repo `dynamomac` and mutable `app` tag.
  7. Add Settings toggle to disable automatic update checks and show contact endpoint.
- **Risk**: Interruption during updater file movement.
- **Test**: Unit tests with invalid signatures, mismatched Team IDs, SemVer test matrix, atomic replacement rollback simulation.

### Milestone 3: Robust Clipboard History Service
- **Cause**: `lastChangeCount` consumed before filter completion; `HardwareSensorMonitor` window list false-positives on screenshots; timer in default run-loop mode stalls; image prefix(256) collision; main-thread file I/O and JSON encoding.
- **Change**:
  1. Update `lastChangeCount` only on definitive terminal decisions (permanent skips or successful ingestion). Transient conditions retry for up to 2.0s without advancing permanent count.
  2. Implement dedicated clipboard-local screen-capture debouncer (on after 1.5s, off after 1.0s) and add `clipboardShieldDuringScreenRecording` setting (default true). Leave `HardwareSensorMonitor` and Island HUD unchanged.
  3. Replace `Timer` with `DispatchSourceTimer` on background utility queue monitoring `changeCount`, holding `ProcessInfo.beginActivity` token, and re-arming on wake/active.
  4. Implement image deduplication using SHA-256 hash of original bytes, stored as optional Codable property for backward compatibility.
  5. Refine type priority to preserve text when rich preview images accompany text.
  6. Offload image compression and file saving to background actor/queue with debounced disk persistence.
- **Risk**: Handling rapid burst copy operations.
- **Test**: Rapid copy stress tests, lazy promise retry test, SHA-256 dedupe verification, Codable backward-compatibility JSON decoding test.

### Milestone 4: KalamBridge & FileDroid Thread Safety
- **Cause**: NSLock locked on caller thread and unlocked inside C callback thread; static singletons overwrite concurrent calls; loose substring error check; hardcoded developer dylib paths; missing Xcode project references; arm64-only without Intel UI notice; missing third-party licenses.
- **Change**:
  1. Replace NSLock with a serial async actor / request queue managing operations sequentially.
  2. Add per-call timeout (e.g., 15s) and disconnection handling that safely resumes continuations with typed errors.
  3. Use strictly typed `Codable` response envelopes; reject any non-empty error field or decoding failure.
  4. Restrict dylib loading exclusively to `Bundle.main.privateFrameworksURL` with team signature / bundle validation.
  5. Add `kalam.dylib` and `libusb.dylib` to Xcode project target with Embed & Sign (`@rpath`).
  6. Detect architecture at runtime: gracefully show "MTP bridge unavailable on Intel" when running on x86_64.
  7. Add libusb (LGPL-2.1 with relinking notice), OpenMTP, and kalam notices to `THIRD_PARTY_LICENSES`.
- **Risk**: Native dylib loading in hardened runtime.
- **Test**: Simulating dropped C callbacks (timeout recovery), concurrent call serialization test, error response parsing test.

### Milestone 5: ADBClient Concurrency & Process Safety
- **Cause**: Output pipes read only in `terminationHandler`, deadlocking on >64KB output; process timeouts return exit code 15 instead of typed error; `progressTimer` canceled when never resumed; existing file deleted before download completes.
- **Change**:
  1. Read `standardOutput` and `standardError` concurrently while process runs using `readabilityHandler` / async chunks into bounded accumulators.
  2. Throw typed `ADBError.timeout` or `ADBError.cancelled` on timeouts and support Task cancellation.
  3. Guarantee `progressTimer` lifecycle safety: instantiate/resume cleanly or verify state before cancellation.
  4. Download to unique temporary file and use `FileManager.default.replaceItemAt` or atomic rename, preserving original file if transfer fails.
- **Risk**: Process management under heavy concurrent operations.
- **Test**: Mock 5MB pipe buffer test, hang/timeout test, cancellation test, atomic file replacement test.

### Milestone 6: Release Script Reproducibility
- **Cause**: In `RELEASE=1` mode, missing xcodebuild fell back to copying `/Applications/LiquidDynamo.app`, hardcoding version "17", and ignoring dylib copy failures.
- **Change**:
  1. In release mode (`RELEASE=1` or `--release`), strictly enforce `xcodebuild` requirement and reject fallback templates.
  2. For local test builds, use `mktemp -d` for isolated build artifacts instead of shared `/tmp/spm_deps`.
  3. Fail fast on missing dylibs (`set -e`, remove `|| true` on critical framework copies).
  4. Extract version and build numbers dynamically from Xcode project settings.
- **Risk**: Breaking existing local build workflows.
- **Test**: Run `scripts/verify_release.sh` and test build flags in release vs local test modes.

### Milestone 7: Outbound Network Disclosure & Privacy Opt-Ins
- **Cause**: Unannounced outbound network connections contradict zero-telemetry claims in README/RULES.
- **Change**:
  1. Add "Network Access" section in Settings > Privacy detailing all outbound endpoints:
     - Automatic Updates (`api.github.com` / `github.com`) - default ON.
     - Public IP Lookup (`api64.ipify.org`) - default OFF with toggle.
     - Meshy 3D Generation (`api.meshy.ai`) - default OFF, explicit consent dialog before upload, API key stored exclusively in Keychain.
     - Music Lyrics (`lrclib.net`) - respect existing user preference.
     - Lottie animations - bundle JSON locally or cache locally after consent.
  2. Clarify README and RULES.md to transparently document network capabilities and user opt-ins.
- **Risk**: UI layout regressions in Settings.
- **Test**: Verify default states, toggling behavior, keychain storage, and local offline fallback.

---

## 3. "Do Not Regress" Safeguard Checklist

- [ ] **Island stays open and shows detail card when icon clicked**: Verify pin-on-select and hover-exit guard in `IslandController.swift` remain intact.
- [ ] **"Show on all displays" is permanently ON and options hidden**: Verify setting remains locked and unexposed in UI.
- [ ] **Home dashboard rows wrap and Color Dropper is gone**: Verify dashboard layout preserves wrapping and Color Dropper remains removed from default grid.
- [ ] **Net speed shows ONE combined value**: Verify network upload/download aggregation displays unified throughput.
- [ ] **CPU-temp glow on left wing and RAM bar on right wing**: Verify wing sensor visualizers remain functional.
- [ ] **Signing/notarization pipeline in build_dmg.sh**: Verify inside-out code signing flags and verification checks remain unchanged.

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
