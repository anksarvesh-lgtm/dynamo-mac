# Manual Test Checklist — LiquidDynamo 2.0.6

Use this checklist to manually verify all features and bug fixes across all hardware configurations (MacBook Pro / Air with physical notch, and external / non-notched monitors).

---

## 0. 13-Point Interaction & Regression Test Matrix

- [x] **Scenario 1**: Open hover -> click device -> island stays open, sized to 520x422 detail card.
- [x] **Scenario 2**: Open click -> click device -> island stays open and pinned, sized to 520x422.
- [x] **Scenario 3**: Click clipboard -> entry copied -> visual checkmark feedback, stays open.
- [x] **Scenario 4**: Click dropper -> stays open, shelf height locked at 352 pt floor.
- [x] **Scenario 5**: Rapidly switch item A -> item B -> item A without jitter or collapse.
- [x] **Scenario 6**: Click icon while volume/charging alert active -> detail size takes strict precedence.
- [x] **Scenario 7**: Click icon on non-notched external display -> expands cleanly without clipping.
- [x] **Scenario 8**: Cursor moves across hover border: 20 pt boundary buffer keeps alive; truly exiting triggers closing.
- [x] **Scenario 9**: Click outside island frame or press `Escape` -> smoothly collapses back to closed state.
- [x] **Scenario 10**: Disconnect active device -> fallback card rendered without collapse or `EmptyView`.
- [x] **Scenario 11**: Alert arrives on home dashboard with no item selected -> sizes smoothly to compact capsule (no 500x207 black box).
- [x] **Scenario 12**: Alert on external display -> 0 pt bottom clipping (`yOffset = 0`, `topNotchGap = 0`).
- [x] **Scenario 13**: Purge safety audit -> developer folders like `dist-notes` or `rebuild-plan` are NOT marked `Safe to Clean`.

---

## 1. Bug 1: Premature Island Collapse Verification

- [ ] **Device Selection**:
  - Connect a Bluetooth or USB device (or click a remembered device in the hover row).
  - Confirm the island smoothly expands to display the device detail card (3D SceneKit model, battery percentage, serial number).
  - Confirm the island remains pinned open and does not shrink or collapse.
  - Move the mouse cursor off the island; confirm the island stays pinned open.
- [ ] **Clipboard Selection**:
  - Click the **Clipboard** button in the hover row.
  - Confirm the clipboard card expands and displays recent/pinned items.
  - Move cursor away; confirm the island does not collapse.
- [ ] **Dropper Shelf Selection**:
  - Click the **Dropper** button in the hover row.
  - Confirm the shelf view expands to display staged items.
  - Confirm the island height remains locked at or above 340 pt.
- [ ] **Storage Cleaner Selection**:
  - Click the **Clean / Purge** button in the hover row.
  - Confirm the Purge storage breakdown view expands and stays open during scan.
- [ ] **Dismissal**:
  - Click outside the island frame or press `Escape`; confirm the island smoothly collapses back to the closed state.

---

## 2. Bug 2: 3D Liquid Capsule Alert & HUD Verification

- [ ] **Volume / Brightness Adjustment**:
  - Use media keys (F1/F2 for brightness, F11/F12 for volume) or trackpad gestures.
  - Confirm HUD renders as a sleek, unified **3D liquid capsule** below the notch, rather than an oversized 460-wide rectangular box.
  - Confirm the width matches `IslandController.alertCapsuleSize(for:)` (~280 pt) with fluid rounded pill geometry.
  - Confirm the HUD automatically retracts after the dwell duration.
- [ ] **Display Adaptation**:
  - On a MacBook with a hardware notch: confirm the capsule attaches flush under the physical cutout.
  - On an external display / non-notched Mac: confirm the capsule floats cleanly as a detached dynamic island pill.
- [ ] **Track Change & Charging Announcements**:
  - Play a track in Music/Spotify; verify track change pill appearance.
  - Connect MagSafe/USB-C power cable; verify power connected pill appearance.

---

## 3. Bug 3: Purge Storage Cleaner Verification

- [ ] **Scanning Engine**:
  - Expand the Storage Cleaner card.
  - Click **Scan Storage** (or verify automatic initial scan).
  - Confirm total reclaimable space is calculated in seconds without freezing the UI.
- [ ] **Category Inspection**:
  - Click on individual categories (Caches, Developer, Logs, Downloads).
  - Confirm individual items are displayed with path, size, and safety tier badge (Safe vs Check First).
  - Click the magnifying glass icon; verify it reveals the folder in Finder.
- [ ] **Safe Deletion**:
  - Click **Purge Selected**.
  - Confirm items are moved to the macOS **Trash** (`~/.Trash`), never deleted permanently.
  - Open Trash to verify discarded cache folders are recoverable.
- [ ] **Safety Allowlists**:
  - Confirm protected folders (e.g. Git repositories, JetBrains LocalHistory, Ruby gems) are never flagged for deletion.
  - Run allowlist test suite via `swift scripts/test_allowlist_audit.swift` (must pass 100%).
- [ ] **Full Disk Access (FDA)**:
  - If FDA is missing, verify the onboarding notice appears with a direct button to macOS System Settings.

---

## 4. Bug 4: Configurable Wing Slots Verification

- [ ] **Settings Configuration**:
  - Open **LiquidDynamo Settings** > **Appearance / Look** > **Notch Wings & Slots**.
  - Change **Left Wing Metric** (e.g. to `CPU Usage`).
  - Change **Right Wing Metric** (e.g. to `Network (Up/Down)`).
  - Observe the live **Mock Notch Preview** at the top of the section updating in real time.
- [ ] **Clean Collapse ("None" Option)**:
  - Set **Left Wing Metric** to `None`.
  - Confirm the left wing collapses completely flush against the notch without empty gaps or phantom margins.
  - Set **Right Wing Metric** to `None`; confirm both wings are cleanly hidden.
- [ ] **Telemetry Accuracy**:
  - CPU Usage: Verify percentage matches Activity Monitor.
  - Network Speed: Verify download and upload speeds update dynamically during web browsing.
  - Sensor Fallback: If SMC temperature sensor is unsupported, verify em dash (`—`) is displayed instead of "Unavailable".
- [ ] **Idle CPU Efficiency**:
  - Check Activity Monitor while LiquidDynamo is idling with wings active; verify CPU usage remains ~0.0% to 0.2%.

---

## 5. Bug 5: Clipboard, Dropper & Color Dropper Verification

- [ ] **Clipboard Ingestion & Alerts**:
  - Copy text in an external app (e.g. Safari, Notes).
  - Confirm a transient Bug 2 liquid capsule appears announcing "Copied to Clipboard".
  - Confirm copying in a password manager (1Password, Bitwarden, Keychain) is **ignored** and never added to history.
  - Copy sensitive or concealed text (`org.nspasteboard.ConcealedType`); verify exclusion.
- [ ] **Clipboard History Card**:
  - Open the Clipboard card in the island.
  - Click any entry; confirm text is copied back to pasteboard with green checkmark / "Copied!" feedback.
  - Confirm clicking an entry does **not** re-add a duplicate entry to the top of the history.
- [ ] **File Dropper / Shelf**:
  - Drag files, image files, web URLs, and snippets into the Dropper button.
  - Confirm items appear in the shelf.
  - Drag an item out to the Desktop; confirm the reference is removed from the shelf but the original file is intact.
  - Press `Space` on an item in the shelf; verify Quick Look preview opens.
- [ ] **Color Dropper Tool**:
  - Click the **Color Dropper** button in the hover row.
  - Click **Pick from Screen** (or `viewfinder` icon).
  - Confirm the screen loupe / magnifying glass opens.
  - Click anywhere on screen to pick a pixel color (or press `Escape` to cancel).
  - Confirm the island stays open and displays the new color swatch.
  - Click the **HEX**, **RGB**, or **HSL** chips; confirm value is copied to pasteboard with "Copied" feedback.
  - Confirm sampled color is added to the **Recent Colors** swatch row.

---

## 6. Milestone 1: Powerload Multi-Interface Hardware Test Matrix

| Test Scenario | Setup / Interfaces | Expected Behavior | Verification Status |
|---|---|---|---|
| **Wi-Fi + USB Ethernet** | Both active, connected to internet | Both interfaces carry byte traffic (>25% each on 60s large download). Total throughput approximates sum. | **Verified** (via simulated multi-stream benchmark; physical dual NIC requires hardware) |
| **Wi-Fi + iPhone USB Hotspot** | Wi-Fi active, iPhone tethered via USB | "iPhone USB" detected as separate interface; both carry byte traffic. Unplugging phone mid-download continues cleanly on Wi-Fi without corruption. | **Unverified** (physical iPhone tether device not connected) |
| **Wi-Fi + Android USB Tether** | Wi-Fi active, Android tether via CDC-ECM / RNDIS | Detected as Android tether; traffic bonded or clear UI explanation provided if RNDIS driver lacks gateway. | **Unverified** (physical Android USB tether not connected) |
| **Ethernet Only** | Wi-Fi disabled, Ethernet connected | Downloads proceed cleanly over single Ethernet interface at full speed. | **Verified** |
| **Wi-Fi Only** | Wi-Fi connected, no secondary interfaces | Standard single-stream / multi-chunk download on default route. | **Verified** |
| **Tether with No Internet** | Wi-Fi active, secondary tether has no route/gateway | Tether marked `unusable(reason: "No default gateway" or "Probe failed")` in UI; never claims chunks or stalls download. | **Verified** |
| **Server Ignoring Range** | Local HTTP server returning HTTP 200 to Range GET | Engine detects 200, aborts chunked write, cleanly falls back to single-stream download from byte 0. File SHA-256 matches reference. | **Verified** (`test_powerload_milestone1.swift`) |
| **Server Supporting Range** | HTTP 206 with `Content-Range: bytes start-end/total` | Validated chunk byte count matches range; written at correct file offsets. Reference SHA-256 matches 100%. | **Verified** (`test_powerload_milestone1.swift`) |
| **Download Cancellation & Quit Resume** | Cancel mid-download or quit app | Partial progress persisted; resume picks up missing chunks without data corruption. | **Verified** |
| **Settings Toggles & Speed Limits** | Disable interface in settings; set speed cap | Scheduler respects disabled state; throughput throttled to configured allowance. | **Verified** |
| **Idle CPU Efficiency** | No active Powerload downloads | Observers idle, network monitor idle, CPU ~0.0%. | **Verified** |

---

## 7. Milestone 3: Clipboard History Robustness Test Matrix

| Test Scenario | Test Action | Expected Behavior | Verification Status |
|---|---|---|---|
| **Text from Native Apps** | Copy text from Safari, Notes, Xcode, Terminal | Text captured immediately; `lastChangeCount` consumed; entry displayed in history. | **Verified** |
| **Text from Web / Cross-Platform** | Copy text from Chrome, Electron, Slack, VS Code | Rich and plain text captured without dropping or formatting corruption. | **Verified** |
| **Spreadsheet Copy (Excel / Numbers)** | Copy tabular cells placing both image preview and text on pasteboard | Type priority preserves text table content; does not discard text in favor of bitmap preview. | **Verified** (`test_clipboard_milestone3.swift`) |
| **Image Copy & SHA-256 Dedupe** | Copy image; copy second different image with identical dimensions; re-copy first image | Both distinct images preserved; second identical copy deduplicated via SHA-256 raw byte hash. | **Verified** (`test_clipboard_milestone3.swift`) |
| **File / Folder Copy** | Copy files in Finder | File URLs captured and listed in history card. | **Verified** |
| **Rapid Successive Copies** | Copy 10 different strings within 1 second | All 10 items queued and captured without losing intermediate change counts. | **Verified** |
| **Copy During Menu / Window Drag** | Open menu or drag window, press Cmd+C | `DispatchSourceTimer` on background queue captures copy; does not stall on main run-loop tracking. | **Verified** |
| **MacBook Sleep / Wake** | Put Mac to sleep for 30s, wake, copy immediately | Timer re-arms via `NSWorkspace.didWakeNotification`; immediate copy is detected. | **Verified** |
| **Extended Idle (>30 Minutes)** | Leave app idling in background for 30+ minutes | Background activity token prevents App Nap freeze; copy is captured instantly. | **Verified** |
| **Screen Recording vs Screenshot** | Take screenshot (Cmd+Shift+4) vs start QuickTime recording | Hysteresis debouncer ignores brief screenshot tool spikes; sustained screen recording activates privacy shield. | **Verified** (`test_clipboard_milestone3.swift`) |
| **Password Manager Suppression** | Copy password in 1Password / Bitwarden / Keychain | Sensitive and concealed types (`org.nspasteboard.ConcealedType`) ignored; nothing logged or stored. | **Verified** |
| **macOS 15.4+ Pasteboard Privacy** | Pasteboard permission set to Ask or Deny | If denied, displays actionable "Retry Access" button in `LiquidClipboardRegionView` without crashing. | **Verified** |
| **Settings Toggle On/Off** | Toggle `Defaults[.enableClipboardHistory]` | Setting observed immediately; timer stopped on false and started on true. | **Verified** |

---

## 8. Hardware & Environment Verification Status

| Component / Subsystem | Verification State | Verification Evidence / Reason for Unverified Status |
|---|---|---|
| **Apple Silicon Host Compilation** | **VERIFIED** | Clean build with Xcode 16.4 / macOS 15.7 SDK on arm64 host. Zero warnings, zero errors. |
| **Default Wi-Fi Interface** | **VERIFIED** | Native `en0` Wi-Fi routing and download engine verified live. |
| **Local Range-Handling HTTP Server** | **VERIFIED** | Full HTTP 206 range validation and HTTP 200 fallback verified via integration test suite. |
| **Intel (x86_64) Hardware Execution** | **UNVERIFIED** | Host machine is Apple Silicon (arm64); binary runtime execution on physical Intel CPU unverified. Intel architecture guard surfaces UI guidance. |
| **Physical Android Device via USB (ADB)** | **UNVERIFIED** | Physical Android phone not attached; verified via unit tests, toybox output parser tests, and mock ADB streaming harness. |
| **Physical iPhone USB Tethering** | **UNVERIFIED** | Physical iPhone with USB Personal Hotspot not connected to test bench; verified via simulated multi-interface network harness. |
| **Physical Android USB Tethering (RNDIS)** | **UNVERIFIED** | Physical Android USB tether not connected; verified via network classification table and simulated CDC-ECM routing. |
| **Physical MTP Camera / Media Device** | **UNVERIFIED** | Physical MTP device not connected to test bench; verified via mock C bridge callback harness and timeout recovery tests. |

