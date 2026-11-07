# MacLink Calls: Phase 6 Security & Privacy Review

**Audit Date:** November 2, 2026  
**Auditors:** MacLink Security & Platform Engineering Team  
**Scope:** Telephony control, call state synchronization, call log retrieval, Swift notifications, and QML UI.

---

## 1. Threat Analysis & Self-Audit Checklist

### Q1: Can an attacker dial arbitrary numbers from the Mac? (Emergency numbers, premium numbers, USSD codes like `*#21#` to forward calls). How is each blocked?
* **Blocking Mechanism:** Multi-layered defense-in-depth across 4 separate components:
  1. **Mac UI Layer (`CallsPage.qml`):**
     - Dial input detects `*` and `#` via `hasUssdChars`.
     - When present, the `Call` button is disabled, Enter/Return submission is rejected, and an inline warning banner is displayed: *"USSD codes (*, #) cannot be dialed"*.
  2. **Desktop Core Layer (`maclink-core::calls::dial`):**
     - Checks `validate_phone_number(&cmd.number)` before constructing or dispatching any wire message.
     - Rate-limited to max 5 call commands per second.
  3. **Protocol Layer (`maclink-protocol::messages::validate_phone_number`):**
     - Character whitelist: only ASCII digits `0..=9`, `+`, spaces, dashes `-`, and parentheses `(`, `)`.
     - Explicit rejection of `*` and `#`.
     - Maximum string length capped at 32 characters.
     - Normalized emergency check: Strips non-digits and validates against `EMERGENCY_NUMBERS` set (`112`, `911`, `999`, `000`, `100`, `101`, `102`, `108`, `988`, `110`, `118`, `119`, etc.). Returns `Err("emergency_number")`.
  4. **Android Host Layer (`CallController.kt`):**
     - `TelephonyPermissions.isEmergencyNumber(number)` is called prior to invoking `TelecomManager.placeCall()`.
     - If detected or if `TelephonyPermissions.isValidDialNumber(number)` fails (contains `*` or `#` or illegal characters), dialing is rejected immediately and `CallCommandResult { ok: false, reason: "emergency_number" / "invalid_number" }` is returned to the Mac.
* **Conclusion:** Dialing arbitrary emergency numbers, USSD/MMI codes, and call-forwarding exploits from the Mac is strictly blocked at every layer.

---

### Q2: Does the feature leak call history or contacts to an unpaired device?
* **Blocking Mechanism:**
  1. **Mandatory Authenticated TLS/QUIC Channel:**
     - All MacLink RPCs, events, and envelope exchanges require an established session over mutual TLS with X.509 certificate pinning.
     - Unknown or unpaired devices cannot complete TLS handshake or establish an authenticated QUIC session. Unauthenticated packets are discarded at the transport layer before any application message parsing occurs.
  2. **Capability & Consent Verification:**
     - Even over an authenticated link, `CallsProtocolHandler.kt` checks `TelephonySettings.isShareHistoryEnabled(context)` before querying Android `CallLog.Calls` or returning entries. If toggled off by the user, empty results are returned.
* **Conclusion:** Unpaired and untrusted devices cannot access any telephony data or events.

---

### Q3: Where are phone numbers and names logged?
* **Audit of Codebase:**
  - **Rust Protocol (`maclink-protocol`):**
    - `CallEvent` has a custom `std::fmt::Debug` implementation that strictly masks phone numbers to the last 2 digits at most (`***56`), completely suppresses `display_name`, and never leaks raw numbers in debug logs.
  - **Rust Core (`maclink-core`):**
    - Tracing statements in `calls.rs` only log actions and error reasons (e.g. `tracing::warn!(reason, action = command.as_str(), "a call action failed")`). No phone numbers or caller names are logged.
  - **Android Telephony (`app.maclink.android.telephony`):**
    - Zero `Log.d`, `Log.i`, `Log.w`, or `println` statements print raw numbers or contact names.
  - **Swift Module (`MacLinkTelephony`):**
    - No `NSLog`, `os_log`, or `print` statements print caller identities or phone numbers.
* **Conclusion:** Full phone numbers and contact names are never written to standard logs, telemetry, or debug traces.

---

### Q4: Is call history written to disk on the Mac?
* **Storage Audit:**
  - Call history received over QUIC is held solely in memory in the `CallView` runtime state within `maclink-desktop/src/calls.rs`.
  - No database tables (e.g. SQLite), cache files, or disk files are created for call logs or contacts.
  - On app termination or device disconnection, the in-memory array is reset to empty (`[]`).
* **Conclusion:** Call history is transient and in-memory only on the Mac; no sensitive call logs persist to the Mac disk.

---

### Q5: Does the phone user have explicit consent switches for both control and history? What are their default values?
* **Consent Architecture:**
  - In `TelephonySettings.kt`, two dedicated user switches are stored in private SharedPreferences:
    1. `KEY_ALLOW_CALL_CONTROL` (*"Let my paired Mac answer and place calls"*): Defaults to **`false`** (OFF).
    2. `KEY_SHARE_CALL_HISTORY` (*"Share call history with Mac"*): Defaults to **`false`** (OFF).
  - Even if Android runtime permissions (`ANSWER_PHONE_CALLS`, `CALL_PHONE`, `READ_CALL_LOG`) are granted at the OS level, `CallController.kt` and `CallsProtocolHandler.kt` will reject Mac actions and log retrieval unless the user has explicitly enabled these in-app switches.
* **Conclusion:** Strict user consent model with secure, opt-in default values (`false`).

---

### Q6: Can a malicious app on the same local network send `CallCommand` to the phone?
* **Network Security:**
  - The phone binds the QUIC listener using mutual TLS authentication.
  - To send a `CallCommand`, a client must present a client certificate signed by the paired device identity key established during out-of-band pairing.
  - An untrusted local network attacker cannot forge the certificate or private key, cannot complete the QUIC handshake, and will have their connection dropped before any protocol frames are decoded.
* **Conclusion:** Local network attackers cannot inject or send `CallCommand` messages to the phone.

---

### Q7: What happens if the phone is locked when the Mac answers a call?
* **OS Telephony Behavior:**
  - `TelecomManager.acceptRingingCall()` is the official Android system API for hands-free answering.
  - When invoked while the phone is screen-locked, the Android Telecom framework transitions the call to the off-hook state in the background without unlocking the phone or exposing the user's home screen, apps, or private data.
  - The phone remains securely locked; only the call state changes.
* **Conclusion:** Answering from the Mac does not compromise or bypass the phone's lock screen security.

---

## 2. Summary & Verification

| Security Requirement | Status | Verification Evidence |
| :--- | :--- | :--- |
| Emergency number dialing blocked | **VERIFIED** | Unit tests in `messages.rs`, `TelephonyTests.kt`, QML input guard |
| USSD / MMI codes blocked (`*`, `#`) | **VERIFIED** | Whitelist regex and explicit checks across Rust, Kotlin, and QML |
| Rate-limiting on call commands | **VERIFIED** | 5 req/sec sliding window in `maclink-core::calls::rate_limit` |
| Privacy masking in logs | **VERIFIED** | Custom `Debug` implementation for `CallEvent`; clean grep audit |
| RAM-only call history on Mac | **VERIFIED** | In-memory `CallView` struct; no disk writes |
| Explicit opt-in switches on phone | **VERIFIED** | Default `false` in `TelephonySettings.kt` and `CallsSetupScreen.kt` |
| Local network attacker isolation | **VERIFIED** | Mutual TLS QUIC link with pinned peer certificates |

**Result:** Security and privacy review passed with 0 blocking issues.

