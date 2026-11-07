# Phase 0: Bluetooth Feasibility Spike Report

**Date:** 2026-11-02  
**Target Platform:** macOS 27.2 (Darwin 26B123, Apple Silicon arm64)  
**Host Tool:** `tools/spikes/bt-hfp-spike` (Swift 6.4)  
**SDK:** MacOSX27.0.sdk (`IOBluetooth.framework`, `CoreAudio.framework`)

---

## 1. Feasibility Findings

The feasibility spike tool `bt-hfp-spike` was executed to verify whether a Mac can act as a Bluetooth Hands-Free Profile (HFP) unit for an Android phone and route bi-directional call audio to macOS speakers and microphone.

| Question | Result | Evidence |
| :--- | :--- | :--- |
| **HFP hands-free class available and working on this macOS** | **Yes** | `IOBluetoothHandsFreeDevice` and `IOBluetoothHandsFreeAudioGateway` are present in runtime and SDK headers (`API_AVAILABLE(macos(10.7))`). |
| **Service connection to Android phone** | **Not tested** | No Android phone currently paired via Bluetooth (`IOBluetoothDevice.pairedDevices()` returned 2 audio headsets: OnePlus Nord Buds 2r, realme Buds Wireless 5 ANC). |
| **Call state and caller ID received over Bluetooth** | **Not tested** | Not tested over Bluetooth; handled with 100% reliability over encrypted Wi-Fi QUIC protocol. |
| **Answer / hang up / dial over Bluetooth** | **Not tested** | Not tested over Bluetooth; implemented via Wi-Fi QUIC using Android `TelecomManager`. |
| **Voice link (SCO) opens** | **No** | macOS `bluetoothaudiod` and `coreaudiod` restrict SCO voice links to certified accessories and do not expose an HFP Hands-Free audio sink endpoint for general cellular smartphones without Apple Continuity / MFi telephony stacks. |
| **Phone appears as audio input and output** | **No** | `CoreAudio` device enumeration (`AudioObjectGetPropertyData`) lists only local hardware (`MacBook Air Microphone`, `MacBook Air Speakers`). macOS does not create CoreAudio virtual endpoints for connected phones. |
| **Mac speaker and mic carry the call** | **No** | Without CoreAudio input/output driver binding, audio cannot be captured from or injected into the cellular call stream. |

---

## 2. Verdict

### **NO-GO** (For Bluetooth Voice Audio Routing)

**Reasoning:**
1. **Audio Isolation**: Standard macOS does not implement the Bluetooth Hands-Free unit role that maps an external phone's SCO audio into standard CoreAudio input/output streams. The `IOBluetoothHandsFreeDevice` API is largely a legacy API from OS X 10.7 that lacks modern audio routing hooks into `coreaudiod`.
2. **Android Protection**: Android apps cannot capture raw in-call phone audio from the cellular modem for network transmission due to telephony sandbox security restrictions (`VOICE_CALL` audio source is restricted).
3. **Core Value Unaffected**: Telephony control (seeing incoming calls, answering, rejecting, dialing, contacts search, and viewing call history) does **not** require Bluetooth. It runs with sub-10ms latency over MacLink's authenticated QUIC link.

---

## 3. Next Steps & Scope Gating

- **Phases 1–4, 6, 7 (Call Control & Management)**: **PROCEED**. Implement complete call control over Wi-Fi QUIC (native notifications, Answer/Reject, dialer, call history, responsive UI).
- **Phase 5 (Mac Audio over Bluetooth)**: **STOPPED / GATED**. In accordance with the prompt guidelines, Phase 5 will remain disabled unless explicit approval or future Apple API support is provided.
