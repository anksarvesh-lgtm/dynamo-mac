# LiquidDynamo 1.9.4 — Comprehensive Fix Plan

This document details the confirmed bugs identified during the Phase 1 audit of LiquidDynamo 1.9.3, along with exact architectural solutions, risk assessments, test verification protocols, and milestones for faithful Purge engine integration.

---

## 1. Island Collapse Residuals (Bugs A1, A2, A3)

### Bug 1.1: Alert & Notification Arrival Resets `isPinnedOpen` (A3)
* **Root Cause**: `IslandController.triggerEventExpansion(payload:)` unconditionally sets `self.isPinnedOpen = false`, so when transient alerts or device notifications expire, `dismissExpandedAlert()` treats the island as unpinned and collapses it back to idle.
* **Exact Files & Functions**:
  * `liquiddinamo/Features/Motion/IslandController.swift`:
    * In `triggerEventExpansion(payload:)`: Do not clear `isPinnedOpen` if the island is already pinned open (`if !isPinnedOpen { self.isPinnedOpen = false }`).
    * In `dismissExpandedAlert()`: Only transition to resting state if `!isPinnedOpen && !isHovering && activeOrganicItem == .none`.
* **Risk & Regressions**: Low. Must ensure transient alerts triggered while the notch is closed still close automatically after their dwell timer expires.
* **Verification**: Trigger a volume HUD or device connection alert while a device detail card is open; verify the island stays pinned open when the alert dismisses.
* **Effort**: S

### Bug 1.2: Hit-Testing & Hover Region During Animated Resizes (A1 & A2)
* **Root Cause**: `containsPointInVisibleShape` and `isMouseInHoverRegion` previously evaluated instantaneous `window.frame` and `targetSize`, causing clicks and hover tracking to misjudge the cursor as outside during 250ms window resize animations.
* **Exact Files & Functions**:
  * `liquiddinamo/LiquidDynamoApp.swift`: `allActiveWindows`, `calculateNotchCenteredRect(for:size:)`, and `targetFrame(for:targetSize:)`.
  * `liquiddinamo/Features/Motion/IslandController.swift`: `containsPointInVisibleShape(_:inWindow:)` and `isMouseInHoverRegion(_:)` using `window.frame.union(targetRect)`.
* **Risk & Regressions**: Low. Verified with zero regressions on click-outside closing.
* **Verification**: Run `scripts/test_verify_test_matrix.swift` across all 10 matrix scenarios.
* **Effort**: S

---

## 2. Alert-on-Home Rendering & Capsule Geometry (Bugs A5, B2)

### Bug 2.1: Alert on Home View Overlapping / Unmounting Dashboard (A5)
* **Root Cause**: In `ContentView.swift` line 686, `DashboardHomeView` was unmounted when `activeOrganicItem == .none && activeExpandedAlert != nil`, while `calculateDimensions(.expanded)` kept the window sized at `500 x 207`, leaving giant empty black space under the floating alert banner.
* **Exact Files & Functions**:
  * `liquiddinamo/ContentView.swift`: Refactor alert presentation on the home view so that transient alerts either resize to the compact capsule when on home without an active selection, or present as an in-place notification pill that does not displace or unmount the home row.
  * `liquiddinamo/Features/Motion/IslandController.swift`: In `calculateDimensions(for: .expanded)`, when an alert arrives on the home view with `activeOrganicItem == .none`, return the capsule size so the window fits the alert cleanly.
* **Risk & Regressions**: Must ensure switching from alert back to home restores `500 x 207` smoothly.
* **Verification**: Trigger volume, brightness, and clipboard alerts while on home view with no item selected, and while a device card is selected.
* **Effort**: M

### Bug 2.2: External Display Capsule Offset Clipping (B2)
* **Root Cause**: In `ContentView.swift` line 353, non-notched displays used `yOffset = 4`, but `LiquidDynamoApp.updateWindowFrame` sets window height to `capsuleSize.height`, clipping the bottom 4 pt of the capsule on external monitors.
* **Exact Files & Functions**:
  * `liquiddinamo/ContentView.swift`: For non-notched displays (`geom.isNotched == false`), set `yOffset = 0` so the capsule fills the window height symmetrically without clipping.
* **Risk & Regressions**: Zero risk to notched displays.
* **Verification**: Render `IslandAlertView` on external non-notched display bounds and verify 0 pt clipping.
* **Effort**: S

---

## 3. Purge Faithful Integration & Safety Engine (Bug C)

### Purge Architectural Parity Strategy
Purge (by Jithin Sabu, MIT License) is a mature, battle-tested macOS storage cleaner. LiquidDynamo will port Purge's safety architecture faithfully while strictly honoring LiquidDynamo's GPL-3.0 license, 100% local execution, zero-telemetry policy, and native notch aesthetic.

#### Milestone M1: Safety Engine, Exact Allowlists & Safety Tiers
* **Root Cause**: `StorageSafetyPolicy.safetyTier` in 1.9.3 used substring matching (`path.contains("dist") || path.contains("build")`), mislabeling developer folders like `dist-notes` or `rebuild-plan` as `Safe to Clean`.
* **Changes**:
  * Replace substring matching with exact path component matching using `URL.pathComponents` and Purge's `SafetyTierList.swift`.
  * Import Purge's `DeletionSafetyPolicy.swift` rules verbatim (protected cache folders, cloud daemons, JetBrains LocalHistory, Ruby gems, Zed db, and exact home directory protections).
  * Port Purge's allowlist test suite into an executable regression test (`scripts/test_allowlist_audit.swift`).
* **Effort**: M

#### Milestone M2: Specialized Cleaners & Scan Policies
* **Scope**:
  * Port Purge's `CacheScanner.swift` & `CacheDiscoveryPaths.swift` (application support caches, merged duplicate definitions, system logs).
  * Port `DevScanner.swift` & `CommandLineToolScanPolicy.swift` (Xcode DerivedData, simulators via `simctl`, global package manager caches, stale-project threshold, and in-use process checks).
  * Port `LargeFileScanner.swift` & `DuplicateFileDetector.swift` (3-stage duplicate detection, managed-library skips for Photos/Music, VM bundles, unfinished downloads, Ollama/LM Studio models).
  * Port `AppUninstallScanner.swift` & `AppUninstallScanPolicy.swift` (strict bundle-ID matching, running-app graceful termination via `NSRunningApplication`).
* **Effort**: L

#### Milestone M3: Deletion Engine, Ledger & Full Disk Access
* **Scope**:
  * Port `FileDeleter.swift` and `CleanupLedgerStore.swift` ensuring all non-privileged deletions use `FileManager.default.trashItem` (never emptying trash).
  * Implement excluded paths store and persistent cleanup history ledger.
  * Integrate graceful degradation when Full Disk Access is absent (limiting scans to user caches and dev tools).
* **Effort**: M

#### Milestone M4: Liquid Notch UI & Storage Entry Points
* **Scope**:
  * Connect the scan results to `LiquidOrganicNotchView`'s storage status button, `NotchStorageCleanerView`, and `SettingsStorageCleanerView`.
  * Multi-segment animated storage breakdown bar with interactive category inspection.
* **Effort**: M

---

## 4. Documentation & Version Alignment (Bug D5)

* **Changes**:
  * Update `CHANGELOG.md` with new `[1.9.4]` release section.
  * Update `docs/MANUAL_TEST_CHECKLIST.md` to version 1.9.4 and include the 13-point click test matrix.
  * Update `docs/CODEBASE_MAP.md` to reflect 1.9.4 architecture and Purge scanner services.
  * Ensure `THIRD_PARTY_LICENSES` and `NOTICE.md` maintain complete Purge MIT attribution.
* **Effort**: S

---

## 5. Decisions Needed

1. **iOS Simulator Runtimes & Time Machine Snapshots**:
   * *Purge Behavior*: Purge offers deletion of old iOS simulator runtimes via `xcrun simctl` and local Time Machine snapshots via `tmutil`, which are permanent (cannot be moved to Trash).
   * *Recommended Default*: In LiquidDynamo, keep all deletions **strictly Trash-only** via `FileManager.default.trashItem`. Do not invoke destructive CLI commands (`simctl delete` or `tmutil deletelocalsnapshots`) without explicit user opt-in and confirmation modals.
2. **Xcode Build Tooling**:
   * The host machine currently has Command Line Tools active (`/Library/Developer/CommandLineTools`) rather than a full Xcode installation. Compilation and testing will be performed using `swiftc` and standalone Swift test suites, with packaging handled via `build_dmg.sh`.

---

## 6. Implementation Status & Verification Summary

| Milestone | Scope | Status | Verification Protocol | Result |
| :--- | :--- | :--- | :--- | :--- |
| **Milestone 1** | Alert Pinning Lifecycle (Bug A3) | **COMPLETE** | `triggerEventExpansion` guards `isPinnedOpen`; `dismissExpandedAlert` restores `.expanded`. | Verified with `swiftc -parse` and test matrix. |
| **Milestone 2** | Alert-on-Home & Clipping (Bugs A5, B2) | **COMPLETE** | Removed `currentView != .home` constraint; set `yOffset` & `topNotchGap` to 0 on non-notched screens. | Verified with `swiftc -parse` and test matrix. |
| **Milestone 3** | Purge Safety Engine & Scanner Parity (Bug C) | **COMPLETE** | Replaced substring checks with exact `url.pathComponents`; added AI model locations (`.ollama`, `.lmstudio`) & managed library skips. | `scripts/test_allowlist_audit.swift` 100% PASS with counter-examples. |
| **Milestone 4** | Documentation & Release Alignment (Bug D5) | **COMPLETE** | Updated `CHANGELOG.md` (1.9.4), `MANUAL_TEST_CHECKLIST.md` (1.9.4 + 13-point matrix), and `CODEBASE_MAP.md`. | Verified docs and zero leftover `[AUDIT]`/`[COLLAPSE]` logs. |

