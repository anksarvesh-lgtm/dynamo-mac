# MacLink Calls Architecture & Design Specification

## Overview

MacLink Calls enables seamless phone call management on macOS paired with an Android phone over an authenticated, encrypted local QUIC link.

The feature is split into two distinct tiers:
1. **Call Control & Telephony Synchronization (Wi-Fi QUIC)**: Call state observation, incoming call notification with Answer/Reject actions, dialing, contact resolution, and call log synchronization. This operates entirely over the existing peer-to-peer encrypted QUIC session.
2. **Call Audio Routing (Bluetooth HFP Voice Link)**: Bi-directional speech audio is gated behind Phase 0 feasibility analysis on macOS. Standard Android applications cannot intercept or inject in-call audio over IP networks; voice traffic requires Bluetooth Hands-Free Profile (HFP/SCO).

---

## 1. System Architecture

```text
┌──────────────────────────────────────────────┐
│                  macOS Host                  │
│                                              │
│  ┌────────────────────┐   ┌───────────────┐  │
│  │   MacLink QML UI   │   │  CallsPage    │  │
│  │ (Incoming Banner,  │   │ (Keypad, Logs,│  │
│  │  Active Call Bar)  │   │  Search)      │  │
│  └─────────┬──────────┘   └───────┬───────┘  │
│            │ CXX-Qt               │          │
│  ┌─────────▼──────────────────────▼───────┐  │
│  │  PhoneCall QObject (bridge/calls.rs)   │  │
│  └─────────────────┬──────────────────────┘  │
│                    │ Rust FFI                │
│  ┌─────────────────▼──────────────────────┐  │
│  │        maclink-core (calls.rs)         │  │
│  │  - Rate Limiter (5 req/s)              │  │
│  │  - Ephemeral Call Log Cache (RAM only) │  │
│  │  - Call State Tracker                  │  │
│  └──────┬──────────────────────┬──────────┘  │
│         │ @_cdecl              │ QUIC Stream │
│  ┌──────▼────────────┐         │             │
│  │ MacLinkTelephony  │         │             │
│  │ (Swift / UNCenter)│         │             │
│  └───────────────────┘         │             │
└────────────────────────────────┼─────────────┘
                                 │ TLS 1.3 / QUIC
                                 │ (Port 53317)
┌────────────────────────────────┼─────────────┐
│ Android Device                 │             │
│  ┌─────────────────────────────▼──────────┐  │
│  │  CallsProtocolHandler.kt (UniFFI)      │  │
│  └──────┬──────────────────────┬──────────┘  │
│         │                      │             │
│  ┌──────▼───────────┐   ┌──────▼──────────┐  │
│  │ CallStateMonitor │   │ CallController  │  │
│  │ (TelephonyMgr)   │   │ (TelecomManager)│  │
│  └──────┬───────────┘   └──────┬──────────┘  │
│         │                      │             │
│  ┌──────▼───────────┐   ┌──────▼──────────┐  │
│  │ ContactResolver  │   │CallLogRepository│  │
│  │ (ContactsContract│   │ (CallLog.Calls) │  │
│  └───────────────────┘  └─────────────────┘  │
└──────────────────────────────────────────────┘
```

---

## 2. Target File Map

### A. Protocol & Core (Rust)
- `core/maclink-protocol/src/messages.rs`:
  - `CallCapabilities`: `can_observe`, `can_answer`, `can_end`, `can_dial`, `has_call_log`, `has_contacts`, `sim_count`, `bt_audio_possible`.
  - `CallEvent`: `call_id`, `state` (`Ringing`, `Dialing`, `Active`, `Ended`, `Missed`), `direction` (`Incoming`, `Outgoing`), `number` (sanitized), `display_name`, `started_at`.
  - `CallCommand`: `Answer`, `Reject`, `End`, `Dial { number, sim_slot }`.
  - `CallCommandResult`: `call_id`, `ok`, `reason`.
  - `CallLogRequest`, `CallLogPage`.
- `core/maclink-core/src/calls.rs`: Core engine, rate limiting, memory-only session storage, audit-safe redaction.
- `desktop/app/src/bridge/calls.rs`: CXX-Qt bridge binding properties to QML.

### B. Android Telephony (Kotlin)
- Package: `app.maclink.android.telephony`
- `CallStateMonitor.kt`: Listens to `TelephonyCallback.CallStateListener` on API 31+, fallback to `PhoneStateListener` on API 26-30.
- `ContactResolver.kt`: Resolves caller identities via `ContactsContract.PhoneLookup` with full Devanagari (Hindi) UTF-8 handling.
- `CallController.kt`: Dispatches `TelecomManager.acceptRingingCall()`, `endCall()`, and `placeCall()`. Enforces user permission gates and filters emergency numbers.
- `CallLogRepository.kt`: Asynchronously fetches paged call logs (`CallLog.Calls`) when user preference is enabled.
- `TelephonyPermissions.kt`: Granular Android runtime permission handling.
- `CallsProtocolHandler.kt`: Marshals between Kotlin telephony services and UniFFI core.
- `ui/calls/CallsSetupScreen.kt`: Jetpack Compose permission onboarding and privacy switches.

### C. macOS Swift Module & C Bridge
- Package: `desktop/swift/MacLinkTelephony`
- `CallNotifier.swift`: Native `UNUserNotificationCenter` integration with interactive `Answer`, `Reject`, and `Hang Up` actions.
- `CAPI.swift`: C-compatible interface (`@_cdecl`) with UTF-8 JSON payloads:
  - `ml_tel_init`
  - `ml_tel_show_incoming`
  - `ml_tel_update`
  - `ml_tel_clear`
  - `ml_tel_shutdown`
  - `ml_tel_free_string`

### D. macOS QML UI
- `desktop/app/qml/pages/CallsPage.qml`: Keypad dialer, contact search, paged call log, and permission state banners.
- `desktop/app/qml/components/CallCard.qml`: In-window incoming call banner and active call floating bar.
- `desktop/app/qml/IslandWindow.qml`: Real-time Dynamic Island call expansion.

---

## 3. Security, Privacy & Safety Invariants

1. **Zero Disk Persistence of Call History on Mac**: Call logs reside solely in process RAM and are discarded immediately upon peer disconnect or app termination.
2. **Zero PII in Diagnostic Logs**: Phone numbers and contact names are never logged to console or crash files. Log statements truncate phone numbers to at most the last 2 digits.
3. **Emergency Number Rejection**: Any attempt to dial 112, 100, 101, 102, 108, 911 or carrier emergency numbers via MacLink is explicitly blocked client-side and server-side with the message *"Use your phone for emergency calls"*.
4. **USSD Code Injection Prevention**: Input strings containing `*` or `#` are strictly prohibited to prevent unauthorized MMI/USSD execution.
5. **Two-Way User Consent**: Android settings enforce two distinct switches (both defaulting to OFF):
   - *"Let my paired Mac answer and place calls"*
   - *"Share call history with Mac"*
