# MacLink Security Review

**Review Date:** 2026-10-10  
**Scope:** End-to-end audit of every network, local IPC, elevated privilege, shared-memory, and filesystem surface in MacLink (`maclink-protocol`, `maclink-core`, `maclink-adb`, `maclink-desktop`, `maclink-vcam`, Android app, and `maclink-shell` helper).

---

## Executive Summary

MacLink follows a strict **zero-trust, local-first security architecture**:
1. **Mutual Ed25519 + TLS 1.3 / QUIC Authentication:** Every peer has a persistent 256-bit Ed25519 identity key (`iroh::SecretKey`). Post-pairing sessions (`ALPN = "maclink/0"`) enforce mutual certificate verification and immediately drop any connection whose remote `EndpointId` is not present in the local SQLite `peers` table (`store.is_paired(&peer)`).
2. **Out-of-Band / Mutual-Consent Pairing:** Pairing (`ALPN = "maclink/pair/0"`) requires either scanning a QR code containing a one-time 128-bit cryptographic token (`tok`) with a 5-minute TTL, or explicit user confirmation of a 6-digit Short Authentication String (SAS) derived via BLAKE3 from the TLS exporter key (`EXPORTER-maclink-pair-v0`) and both peers' Ed25519 public keys (`derive_sas` in `core/maclink-protocol/src/sas.rs`).
3. **Strict Wire & Filesystem Boundaries:** Every incoming CBOR/JSON envelope is size-capped BEFORE allocation (`MAX_FRAME_LEN = 1 MiB`), validated via `.is_valid()` and `.sanitized()`, and gated by per-peer feature permissions (`PeerPermissions`). All incoming file and storage paths reject `..`, root prefixes, drive letters, and NUL bytes.

---

## Surface 1: `iroh` QUIC Sessions, Pairing & USB Transport

**Code Locations:**
- `core/maclink-core/src/pairing.rs`
- `core/maclink-core/src/session.rs`
- `core/maclink-core/src/usb.rs`
- `core/maclink-adb/src/lib.rs`
- `core/maclink-protocol/src/sas.rs`
- `core/maclink-protocol/src/frame.rs`
- `core/maclink-core/src/store.rs`

### Threat Model
- **MITM / Impersonation on untrusted LAN or Guest Wi-Fi:** An active attacker on the same Wi-Fi subnet attempts to intercept pairing or impersonate a paired device.
- **Unattended USB Auto-Pair Hijack:** A rogue host or phone connected over USB attempts to pair silently without user consent on one side.
- **Memory Exhaustion / Malformed Frame DoS:** A peer or attacker sends oversized frame length prefixes (`u32::MAX`) or deeply nested/invalid CBOR payloads.
- **Privilege Escalation Across Paired Devices:** A paired device (e.g., secondary tablet) attempts to invoke features (`clipboard`, `sms`, `mirror`, `files`, `storage`) that the user disabled for that peer in per-device permissions.

### Security Controls in Place
0. **Strict Application Package Verification Gate (`session.rs`):**
   - Every connection performs immediate peer validation via `is_authorized_maclink_app` rejecting any handshake whose advertised package identifier does not match `in.maclink.srv` (`REQUIRED_PACKAGE_ID`).
1. **SAS Bound to TLS Session Exporter (`sas.rs`):**
   - The 6-digit SAS code is derived from `conn.export_keying_material(b"EXPORTER-maclink-pair-v0", b"", 32)` combined with both peers' 32-byte Ed25519 public keys in role order (`initiator_pk || responder_pk`). An active MITM terminates two distinct TLS 1.3 sessions with different exporter secrets, producing non-matching 6-digit codes with probability $1 - 10^{-6}$.
2. **One-Time QR Token & Constant-Time Verification (`pairing.rs`):**
   - QR pairing requires a 128-bit random token (`tok`), expires after 300 seconds (`QR_LIFETIME`), and is invalidated on first use (`lock(&shared.qr_host).take()`).
3. **Mutual Consent on USB Auto-Pair (`pairing.rs`, `usb.rs`):**
   - When an unpaired phone is connected via USB with ADB debugging active, `usb.rs` establishes a loopback UDP-over-TCP bridge (`127.0.0.1`) and initiates a standard `start_nearby` pairing ceremony (`method: "nearby"`). Both the PC and the phone display the 6-digit SAS code and require explicit user approval (`Codes match`) on **both** devices before storing the peer in `peers`.
   - Furthermore, the USB transport tunnel simply carries encrypted QUIC (`iroh`) packets over loopback UDP; all confidentiality, integrity, and Ed25519 peer authentication remain enforced by QUIC TLS 1.3.
4. **Hard ADB Serial Blocklist (`core/maclink-adb/src/lib.rs`):**
   - `maclink-adb` enforces `is_serial_allowed(serial)` across `parse_devices_l`, `forward_tcp`, and `kill_forward_tcp`, hard-blocking `BLOCKED_SERIALS` and honoring `MACLINK_ADB_ONLY_SERIAL`.
5. **Pre-Allocation Frame Size Cap (`frame.rs`):**
   - `read_frame` inspects the 4-byte big-endian length prefix and rejects any frame $> 1\text{ MiB}$ (`MAX_FRAME_LEN = 1_048_576`) with `ProtocolError::FrameTooLarge` before allocating buffer memory.
6. **Per-Device Feature Permissions (`session.rs`):**
   - `session.rs` checks `shared.peer_allows(&peer, |p| ...)` before processing incoming notifications, clipboard offers, file transfers, SMS commands, media control, camera, or mirror streams.
7. **At-Rest Key & History Encryption (`store.rs`, `clipboard_history.rs`):**
   - Clipboard history (`clipboard_history.enc`) is encrypted at rest using XChaCha20-Poly1305 (`chacha20poly1305`) with a 256-bit key derived via BLAKE3 (`derive_key("maclink clipboard history v1", secret_key.as_bytes())`) and fresh 192-bit random nonces per save.

### Audit Fixes Applied
- Eliminated a potential `.expect()` in `store.rs:594` when reading `secret_key` bytes from SQLite (`<[u8; 32]>::try_from`), returning a clean `rusqlite::Error::InvalidColumnType` if a database file is corrupted on disk.
- Added 10,000-iteration fuzz suites for `frame::read_frame`, `Envelope::from_cbor_bytes`, and all message body types in `core/maclink-protocol`.

---

## Surface 2: LocalSend HTTP Server (`core/maclink-core/src/localsend.rs`)

**Code Locations:**
- `core/maclink-core/src/localsend.rs`

### Threat Model
- **Unauthenticated LAN Attacker:** Because LocalSend v2.1 is an open LAN protocol (UDP multicast `224.0.0.167:53317` + HTTP/HTTPS on TCP port `53317`), any host on the same LAN can connect to `53317`.
- **HTTP Header / Body Memory Exhaustion (Slowloris / Giant Upload):** An attacker sends an unbounded HTTP header or claims a multi-terabyte `Content-Length`.
- **Directory Traversal via Malicious Filename (`../../AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Startup/evil.exe`):** A LAN sender supplies path traversal components, Windows reserved device names (`CON`, `NUL`, `COM1`), or alternate data streams (`file.txt:zone`).
- **Session / Token Guessing:** A second LAN host attempts to upload bytes into an accepted `sessionId` before the legitimate sender uploads.

### Security Controls in Place
1. **Strict Header & Metadata Caps:**
   - `MAX_HEADER_BYTES = 16 * 1024` (16 KiB) and `MAX_JSON_BODY_BYTES = 256 * 1024` (256 KiB) cap HTTP request headers and JSON bodies before parsing.
   - `MAX_FILES_PER_OFFER = 256` caps the number of files in a single `prepare-upload` offer.
2. **Explicit User Consent Before Any File Bytes Are Written:**
   - `handle_prepare_upload` emits a `TransferState::Requested` event and blocks until the user explicitly accepts (`accept_transfer`) or rejects/cancels (`cancel_transfer`) within 120 seconds.
3. **Per-File Cryptographic Upload Tokens:**
   - Only after acceptance does the server generate random 128-bit hex tokens per file (`tokens.insert(file_id, token)`) and a random 128-bit `session_id`. `handle_upload` verifies `sessionId` and the per-file `token` before reading body bytes.
4. **Filename Sanitization & Atomic Staging (`sanitize_file_name`, `unique_destination`):**
   - `sanitize_file_name` splits on both `/` and `\`, takes only the final component, strips control characters and Windows-forbidden characters (`<>:"/\|?*`), rejects `.` and `..`, prefixes Windows reserved device names (`CON`, `PRN`, `AUX`, `NUL`, `COM1..9`, `LPT1..9`) with `_`, and truncates to 200 UTF-8 characters.
   - Incoming bytes are streamed to a `.part` file inside `<data_dir>/incoming/localsend/<session_id>/` and strictly capped at the declared `entry.size` (`io::AsyncReadExt::take(stream, remaining)`). Only when `written == entry.size` is the file moved to the user's Downloads directory via `unique_destination` (which never overwrites existing files).

### Audit Fixes Applied
- Replaced two `.expect("checked non-empty")` calls in `localsend.rs` (lines 1701 and 1762) with safe `if let Some(last) = entries.last_mut()` bindings.
- Added a 10,000-iteration fuzz suite (`fuzz_localsend_http_parser_and_dtos_10k`) testing `read_http_head`, `parse_content_length`, `parse_query`, `sanitize_file_name`, and DTO deserialization against arbitrary/adversarial inputs.

---

## Surface 3: Local Authenticated API (`desktop/app/src/local_api.rs`)

**Code Locations:**
- `desktop/app/src/local_api.rs`
- `desktop/app/src/settings.rs`
- `docs/api.md`

### Threat Model
- **Cross-Site Request Forgery / Drive-By Browser Attack (`localhost` SSRF):** A malicious website open in the user's web browser attempts `fetch("http://127.0.0.1:53320/v1/send", ...)` or DNS rebinding to exfiltrate clipboard history or send files.
- **Unauthorized Local Process:** Another unprivileged account or untrusted sandboxed process attempts to call the API without reading the user's profile directory.

### Security Controls in Place
1. **Off by Default (`local_api_enabled: false`):**
   - The Local API server does not bind or listen unless the user explicitly enables **Local automation API** in Settings.
2. **Loopback-Only Binding (`127.0.0.1`):**
   - Bound strictly to `Ipv4Addr::LOCALHOST` (`127.0.0.1`), never `0.0.0.0` or `::`.
3. **256-Bit Random Bearer Token in `<data_dir>/api-token.json`:**
   - Generated using 32 bytes from OS CSPRNG (`BCryptGenRandom`), stored inside the user's private `<data_dir>/api-token.json`.
   - Every HTTP request must supply `Authorization: Bearer <token>`, verified using constant-time byte comparison (`constant_time_eq`). Missing or invalid tokens immediately receive `401 Unauthorized`.
4. **Browser `Origin` / `Sec-Fetch-Site` Rejection:**
   - Any HTTP request carrying an `Origin` header or `Sec-Fetch-Mode: cors` / `no-cors` is rejected with `403 Forbidden` before inspecting the route, and no `Access-Control-Allow-Origin` header is ever emitted.
5. **Bounded Request Size:**
   - Request buffers are capped at 64 KiB (`MAX_REQUEST_BYTES = 65_536`) with a 5-second read timeout.

### Audit Fixes Applied
- Designed and implemented from scratch with constant-time Bearer token comparison, `Origin` header rejection (`403 Forbidden`), and automated unit tests covering `401 Unauthorized`, `403 Forbidden`, and authenticated `/v1/*` endpoints.

---

## Surface 4: Single-Instance IPC & Launch Queue (`desktop/app/src/launch.rs`)

**Code Locations:**
- `desktop/app/src/launch.rs`
- `desktop/app/src/send_to.rs`
- `desktop/app/src/main.rs`

### Threat Model
- **Cross-Session / Multi-User Local Spoofing:** On a multi-user Windows machine, another logged-in user attempts to signal MacLink's Win32 event or write a malicious `Request` into the launch queue.
- **Malformed / Oversized Launch Queue File:** Corrupted or adversarial JSON in `<data_dir>/launch/` attempts to crash the running tray process.

### Security Controls in Place
1. **Per-Data-Dir Scoped Win32 Event & Mutex (`Local\` namespace):**
   - Both the single-instance mutex (`Local\MacLink.SingleInstance.<fnv1a64>`) and the wake event (`Local\MacLink.Launch.<fnv1a64>`) are created in the Windows `Local\` session namespace (isolated to the current logon session) and keyed by the FNV-1a hash of the canonicalized `--data-dir` path.
2. **Filesystem ACL Isolation in `<data_dir>/launch`:**
   - Queue files (`<nanos>-<pid>.json`) live inside `<data_dir>/launch/`, which inherits the user profile's `%LOCALAPPDATA%` NTFS DACL (accessible only to `SYSTEM`, `Administrators`, and the owning user SID).
3. **Resilient Drain & Deserialization (`launch::drain`):**
   - `drain()` unlinks each `.json` file before parsing (`fs::remove_file(&path)`) so a malformed file can never cause an infinite retry loop, and ignores any invalid JSON cleanly without panicking.

### Audit Fixes Applied
- Verified `launch::drain` and `send_to::handle` have zero `.unwrap()`/`.expect()` calls on runtime paths and handle `Request::SendTo`, `Request::Share`, and `Request::Task` safely.

---

## Surface 5: Elevated Shell Helper (`maclink-shell` / UID 2000)

**Code Locations:**
- `android/shell-helper/src/main/kotlin/app/maclink/shell/InputServer.kt`
- `android/app/src/main/kotlin/app/maclink/android/elevated/Elevated.kt`

### Threat Model
- **Local Untrusted App Connecting to `@maclink.shell.v1`:** Any unprivileged Android app on the same device can attempt to connect to the abstract UNIX domain socket `\0maclink.shell.v1` and inject touch/keystrokes, read the clipboard, toggle Wi-Fi/Bluetooth, or capture internal audio if peer credentials are not checked.
- **Command Injection / Unbounded Input on Socket:** A malformed command line sent over the local socket could crash the helper or execute unintended shell commands.

### Security Controls in Place
1. **Mandatory Kernel `SO_PEERCRED` UID Verification (`isAllowedPeer` in `InputServer.kt`):**
   - Immediately upon `server.accept()`, `handleClient` reads the kernel-verified `StructUcred` (`client.peerCredentials`) and calls `isAllowedPeer(cred.uid, allowedUid)`:
     ```kotlin
     private fun isAllowedPeer(peerUid: Int, appUid: Int): Boolean {
         if (peerUid == Process.ROOT_UID || peerUid == Process.SHELL_UID) return true
         val appId = peerUid % PER_USER_RANGE
         return appUid > 0 && appId == (appUid % PER_USER_RANGE)
     }
     ```
   - `allowedUid` is resolved at startup from `pm.getApplicationInfo("in.maclink.srv", 0).uid`. Any connection from any other app UID is immediately closed and rejected before reading a single byte.
2. **No Shell Evaluation on Socket Commands:**
   - Socket commands (`T`, `S`, `K`, `KD`, `KU`, `G`, `TEXT`, `BACK`, `HOME`, `RECENTS`, `LOCK`, `NOTIF`, `QS`, `SHOT`, `CLIPGET`, `CLIPWAIT`, `WIFI`, `BT`, `DND`, `PANEL`, `ROTATE`, `A`) are parsed as fixed verbs with typed numeric arguments (`toFloatOrNull()`, `toIntOrNull()`) and dispatched directly to Android Binder APIs (`IInputManager`, `IClipboard`, `IStatusBarService`, `ConnectivityManager`, `AudioRecord`, `/dev/uhid`). No command ever passes user strings to `Runtime.exec("sh -c ...")`.
3. **Sensitive Clipboard & Notification Redaction:**
   - `readPrimaryClipLine` inspects `ClipDescription.EXTRA_IS_SENSITIVE`; if the user copied a password from a credential manager that marks the clip sensitive, `InputServer` returns `SENSITIVE` without reading or transmitting the text.
   - Neither `InputServer.kt` nor `NotificationListener.kt` ever logs notification bodies or clipboard text to `logcat`.

### Audit Fixes Applied
- Eliminated the remaining `!!` in `InputServer.kt:402` (`getClip!!`) by capturing the local `Method` reference safely.
- Added authenticated command `"A"` (48 kHz stereo PCM audio capture via `REMOTE_SUBMIX` / internal capture) and `"G"` (UHID / `InputManager` gamepad injection), both gated behind the same `SO_PEERCRED` check.

---

## Surface 6: Virtual Camera Shared Memory (`desktop/vcam/src/shm.rs`, `source.rs`)

**Code Locations:**
- `desktop/vcam/src/shm.rs`
- `desktop/vcam/src/source.rs`
- `desktop/app/src/webcam.rs`

### Threat Model
- **Buffer Overflow / Out-of-Bounds Read in Host Apps (Teams, Zoom, OBS, Chrome):** The Media Foundation virtual camera DLL (`maclink_vcam.dll`) is loaded into third-party camera consumer processes. If `maclink-desktop.exe` (or a local process writing to `Local\MacLinkVirtualCamera_v2`) writes corrupt `width`, `height`, `stride`, or `active_slot` headers in shared memory, the reader in `maclink_vcam.dll` could panic or read out of bounds inside the host application process.
- **Torn Frame Reads:** Concurrent reader/writer access without synchronization could read half of a 1080p frame and half of a 4K frame.

### Security Controls in Place
1. **Strict Bounds Validation on Every Read (`ShmReader::read_into` in `shm.rs`):**
   - `ShmReader::read_into` reads `magic`, `version`, `active_slot`, `width`, `height`, `stride`, and `seq` using atomic `Ordering::Acquire` loads, and validates:
     - `magic == MAGIC` (`0x4E4C_5643`) and `version == VERSION` (`1`),
     - `width > 0 && width <= MAX_WIDTH` (`3840`) and `height > 0 && height <= MAX_HEIGHT` (`2160`),
     - `stride >= width * 4`,
     - `needed = (stride as usize).checked_mul(height as usize)` fits within `MAX_FRAME_BYTES` (`3840 * 2160 * 4 = 33,177,600` bytes),
     - `slot_idx = (slot as usize) & 1` (masked to `0` or `1`, preventing out-of-bounds slot indexing).
2. **Double-Buffered Optimistic Concurrency Check:**
   - The writer writes to the inactive slot (`1 - (active_slot & 1)`), performs an `Ordering::Release` store to `active_slot` and `seq`, and never mutates the active slot in place.
   - The reader checks `seq_before == seq_after` (`Ordering::Acquire`) after copying the frame and discards the read if the writer flipped slots mid-copy.
3. **Logon-Session Scoped Mapping (`Local\MacLinkVirtualCamera_v2`):**
   - Uses the `Local\` kernel object namespace so processes in other Windows logon sessions cannot access the mapping.

### Audit Fixes Applied
- Upgraded `MAX_WIDTH = 3840` and `MAX_HEIGHT = 2160` for 4K support and bumped mapping name to `Local\MacLinkVirtualCamera_v2` so older v1 DLLs and v2 writers cannot misinterpret slot offsets.

---

## Surface 7: Storage Provider & Remote File Browser (`storage.rs`, `files.rs`, `StorageHandler.kt`)

**Code Locations:**
- `core/maclink-core/src/storage.rs`
- `core/maclink-protocol/src/messages.rs`
- `desktop/app/src/files.rs`
- `android/app/src/main/kotlin/app/maclink/android/storage/StorageHandler.kt`

### Threat Model
- **Path Traversal Outside Shared Root (`/sdcard` on Android or Cloud Files Sync Root on PC):** A peer sends `storage.read`, `storage.write`, `storage.list`, `storage.mkdir`, or `storage.delete` with `"../../data/data/in.maclink.srv/databases/maclink.db"` or symlinks pointing outside `/sdcard`.
- **Cloud Files Hydration Abuse on Windows (`cfapi`):** A malicious filename or relative path in `StorageEntry` attempts to hydrate or overwrite files outside `%USERPROFILE%\MacLink (<Phone>)`.

### Security Controls in Place
1. **Protocol-Level Path Validation (`is_valid_storage_path` in `messages.rs`):**
   - Rejects paths $> 1024$ bytes, paths containing `\0` or `\`, and any `Path::components()` containing `Component::ParentDir` (`..`) or `Component::Prefix` (`C:`).
2. **Canonical Path Sandboxing on Android (`StorageHandler.resolve` in `StorageHandler.kt`):**
   - `StorageHandler.resolve(rawPath)` resolves the target `File` against `Environment.getExternalStorageDirectory().canonicalFile` (`root`) and enforces:
     ```kotlin
     val canonical = target.canonicalFile
     if (canonical != root && !canonical.path.startsWith(root.path + File.separator)) {
         return null
     }
     ```
   - Because `canonicalFile` resolves all symlinks and `..` segments on the Android filesystem before checking the prefix, symlink escape from `/sdcard` into `/data/data/in.maclink.srv` is impossible.
3. **Chunk Size & Offset Bounds (`MAX_STORAGE_CHUNK = 256 KiB`):**
   - `StorageReadRequest::is_valid()` and `StorageWriteChunk::is_valid()` cap every read/write chunk to `262,144` bytes (`256 KiB`), preventing memory exhaustion on either side.
4. **Per-Device Permission Enforcement:**
   - Every `storage.*` message in `session.rs` checks `shared.peer_allows(&peer, |p| p.files)` before invoking the storage handler.

### Audit Fixes Applied
- Verified `is_valid_storage_path` and `StorageHandler.resolve` canonical path checks across all `storage.list`, `storage.read`, `storage.write`, `storage.mkdir`, and `storage.delete` operations, and included `StorageListResponse` / `StorageReadRequest` / `StorageWriteChunk` in the 10,000-iteration protocol fuzz suite.
- Enforced `REMOTE_FILES_TOGGLE` (`"remote_files"`, off by default) on both PC and phone in `core/maclink-core/src/storage.rs` whenever `session.path() == ConnectionPath::Relay`, so away-mode / relay sessions cannot browse or mutate storage unless `remote_files` is explicitly enabled in addition to `storage`.

---

## Surface 8: PC-Side Continuity Capabilities & Reverse Mirroring Consent

**Code Locations:**
- `core/maclink-core/src/features.rs`
- `core/maclink-core/src/mirror.rs`
- `core/maclink-core/src/remote.rs`
- `core/maclink-core/src/storage.rs`
- `core/maclink-ffi/src/lib.rs`
- `desktop/app/src/core_host.rs`
- `desktop/app/src/pc_mirror.rs`
- `desktop/app/src/pc_audio_stream.rs`
- `desktop/app/src/pc_notifications.rs`
- `desktop/app/src/pc_storage.rs`
- `desktop/app/src/input_share.rs`
- `desktop/app/qml/MainWindow.qml`

### Threat Model
- **Unattended PC Screen Capture or Input Injection from Paired Phone:** A paired phone (which could be unlocked or used by someone else in another room) attempts to silently stream the PC's desktop (`mirror.start` against a Desktop/Laptop node) or inject mouse/keyboard events (`mirror.input` / `remote.input`) without the PC user's knowledge or consent.
- **Silent Toggle Escalation from FFI:** A phone client attempts to flip per-device toggles on silently inside `maclink-ffi` before issuing an RPC.
- **Over-Broad Capability Advertisement:** The PC advertises `mirror.capture`, `mirror.input`, or `input.inject` in its `Hello` / `HelloUpdate` capability list when those features are disabled for all paired devices.

### Security Controls Across All PC-Side Capabilities
1. **Reverse Mirroring (`pc_mirror` / `desktop/app/src/pc_mirror.rs`):**
   - **Dedicated Toggle, Off by Default:** `PC_MIRROR_TOGGLE = "pc_mirror"` is registered in `DEVICE_TOGGLES` (`core/maclink-core/src/features.rs`) with default **`false`**, separate from phone-to-PC `mirroring`.
   - **No Silent Auto-Enable:** `start_pc_mirror` in `core/maclink-ffi/src/lib.rs` never mutates device toggles; it only sends `mirror_start`.
   - **PC Consent Prompt:** When a phone calls `mirror_start` against a PC while `pc_mirror` is off (and no one-time session allowance is active), `mirror::handle` denies the request with `Error::Denied` and emits `NodeEvent::PcMirrorRequested { device, options }`. The PC shows a modal consent sheet (`pcMirrorPromptSheet` in `MainWindow.qml`) with **"Not now"**, **"Allow"** (one-time session consent via `Node::set_pc_mirror_session_allowed`, automatically cleared on disconnect), and **"Allow for this device"** (enables `pc_mirror` for that phone).
   - **Persistent Sharing Banner with One-Click Stop:** Whenever `pc_mirror::is_active()` is true, `MainWindow.qml` displays a persistent top banner (`"Sharing this PC's screen with <Phone>"`) with a one-click **"Stop sharing"** button (`AppController.stopPcMirror()`).
   - **Input Injection Gated on `remote_input`:** Both `core/maclink-core/src/mirror.rs` (`MIRROR_INPUT`, `input()`) and `desktop/app/src/pc_mirror.rs` (`handle_input()`) require the `remote_input` per-device toggle (`false` by default) to be enabled in addition to an active reverse-mirror session before any touch, scroll, key, or text event is injected on a PC.
   - **Conditional Capability Advertisement:** `core_host::compute_capabilities` only advertises `mirror.capture` when `pc_mirror` is enabled for at least one paired device (or actively sharing), and only advertises `mirror.input` and `input.inject` when `remote_input` is enabled for at least one paired device.
2. **Cross-Device Mouse & Keyboard Flow (`desktop/app/src/input_share.rs`):**
   - PC-to-phone edge cursor/keyboard flow is off by default (`Settings::edge_flow_enabled = false`) and initiates outbound from the PC when the PC user moves the physical mouse across the configured screen edge. Incoming remote input from the phone to the PC (`remote.rs`) is strictly gated on `remote_input` (`false` by default) with a one-time consent prompt (`RemoteInputRequested`).
3. **PC Audio Streaming to Phone (`desktop/app/src/pc_audio_stream.rs`):**
   - Off by default (`Settings::pc_audio_to_phone = false`). Audio loopback capture (`WASAPI`) can only be enabled locally from the PC's Settings UI (`Camera & Audio -> Stream PC audio to phone`) and only streams to connected phones that have the `media` toggle enabled.
4. **PC Storage Provider (`desktop/app/src/pc_storage.rs`, `core/maclink-core/src/storage.rs`):**
   - Gated by the `storage` toggle (`false` by default), plus `remote_files` (`false` by default) when connected over a non-LAN `ConnectionPath::Relay` path. Sandboxed to the user's non-sensitive `MacLink Shared` folder via `FolderStorage` (which rejects `..`, absolute paths, and symlink escapes).
5. **PC Notifications to Phone (`desktop/app/src/pc_notifications.rs`):**
   - Off by default (`Settings::forward_pc_notifications = false`). Only forwards when explicitly enabled by the PC user in Settings AND Windows `UserNotificationListener` access is granted AND the per-device `notifications` toggle is on.

