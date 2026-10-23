# Manual Test Checklist — LiquidDynamo 1.9.4

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
