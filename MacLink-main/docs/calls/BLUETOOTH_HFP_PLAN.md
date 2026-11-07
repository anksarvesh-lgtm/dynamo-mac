# MacLink Bluetooth Voice Calling (HFP): Technical Research & Implementation Plan

**Author:** MacLink Systems Architecture Team  
**Status:** Technical Investigation & Architectural Specification  
**Scope:** macOS (12 Monterey through 15 Sequoia) + Android (API 29 through 35)

---

## 1. Executive Summary & Feasibility Assessment

### 1.1 The Objective
Allow a user sitting at their Mac to participate in phone calls placed on or received by their Android phone, using the Mac's built-in microphone and speakers, connected over Bluetooth—similar to Microsoft Phone Link on Windows.

### 1.2 The Reality of Call Audio
- Cellular and telephony call audio **cannot** be routed over local Wi-Fi or normal network sockets directly from a standard non-root Android application. Android's Linux kernel and Telephony framework restrict in-call audio streams to:
  1. The physical phone earpiece / speaker / wired headset.
  2. The Bluetooth hardware audio path (**SCO / eSCO** channel handled directly by the Bluetooth baseband modem and Qualcomm/MediaTek audio DSP).
- Therefore, **voice audio must travel over a Bluetooth link** where the phone acts as the **Audio Gateway (AG)** and the Mac acts as the **Hands-Free unit (HF)**.

### 1.3 Feasibility on Modern macOS
| Component | Windows (Phone Link) | macOS (MacLink Target) | Feasibility on macOS |
| :--- | :--- | :--- | :--- |
| **Control Plane** | Bluetooth RFCOMM / Wi-Fi | Local QUIC / Wi-Fi (MacLink core) | **100% Feasible & Implemented** |
| **HFP Profile Role** | Hands-Free (HF) supported by OS stack | Audio Gateway (AG) native; HF legacy | **Gated by OS Architecture** |
| **SDP Announcement** | Standard Windows Hands-Free SDP | Custom SDP record via `IOBluetooth` | **Feasible** |
| **RFCOMM AT Commands** | Handled by OS driver | Handled by `IOBluetoothHandsFreeDevice` | **Feasible** |
| **SCO Audio Channel** | Exposed as WASAPI Audio Endpoint | Handled by `BTAudioHALPlugin.driver` | **Requires Custom Audio Bridge** |

---

## 2. Bluetooth HFP Architecture Deep Dive

### 2.1 Profile Roles & UUIDs
- **Audio Gateway (AG)**: Android Phone (UUID `0x111F`)
  - Acts as the gateway to the cellular telephony network.
  - Sends ring indicators, caller ID, and call state.
  - Receives dial commands, answer commands, and hook status.
- **Hands-Free Unit (HF)**: Mac Companion (UUID `0x111E`)
  - Acts as the remote operator and voice interface.
  - Emits user commands (Answer, Hangup, DTMF).
  - Routes microphone audio into the SCO link and speaker audio out.

### 2.2 Bluetooth Channel Architecture
```
+-------------------------------------------------------------------+
|                        MACBOOK (HF Role)                         |
|  +------------------------+        +---------------------------+  |
|  |   Control: RFCOMM      |        |     Voice: SCO / eSCO     |  |
|  | (AT Commands, Status)  |        |  (mSBC 16kHz / CVSD 8kHz) |  |
|  +-----------+------------+        +-------------+-------------+  |
+--------------|-----------------------------------|----------------+
               | (RFCOMM Channel)                  | (Synchronous Audio)
               |                                   |
+--------------|-----------------------------------|----------------+
|  +-----------+------------+        +-------------+-------------+  |
|  |   Telephony Manager    |        |    Baseband Modem DSP     |  |
|  |  (BluetoothHeadset AG) |        |    (Voice Call Audio)     |  |
|  +------------------------+        +---------------------------+  |
|                     ANDROID PHONE (AG Role)                       |
+-------------------------------------------------------------------+
```

### 2.3 The Service Level Connection (SLC) AT Command Sequence
1. **Feature Negotiation (`AT+BRSF`)**:
   - HF -> AG: `AT+BRSF=<HF_FEATURES_BITMAP>` (Mac announces capability for 3-way calling, CLI presentation, remote volume, codec negotiation).
   - AG -> HF: `+BRSF: <AG_FEATURES_BITMAP>` followed by `OK`.
2. **Codec Selection (`AT+BAC` & `+BCS`)**:
   - HF -> AG: `AT+BAC=1,2` (Supports CVSD [1] and wideband mSBC [2]).
   - AG -> HF: `+BCS: 2` (AG selects mSBC for HD Voice).
   - HF -> AG: `AT+BCS=2` (HF confirms mSBC).
3. **Indicator Mapping (`AT+CIND=?` & `AT+CIND?`)**:
   - HF queries AG supported indicators (`service`, `call`, `callsetup`, `callheld`, `signal`, `roam`, `battchg`).
   - AG returns current indicators (e.g. `call=0, callsetup=0`).
4. **Event Reporting Activation (`AT+CMER`)**:
   - HF -> AG: `AT+CMER=3,0,0,1` (Enables unsolicited indicator updates `+CIEV: <ind>,<val>`).
5. **Call Status Reporting (`AT+CLIP=1`)**:
   - HF enables Calling Line Identification.

---

## 3. macOS Native Stack Analysis

### 3.1 SDK Header Inspection Results
Inspected at: `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/IOBluetooth.framework/Headers/objc/`

1. **`IOBluetoothHandsFreeDevice`**:
   - Inherits from `IOBluetoothHandsFree`.
   - Primary methods:
     ```objc
     - (instancetype)initWithDevice:(IOBluetoothDevice *)device delegate:(id)delegate;
     - (void)connect;
     - (void)disconnect;
     - (void)acceptCall;
     - (void)endCall;
     - (void)dialNumber:(NSString *)aNumber;
     - (void)connectSCO;
     - (void)disconnectSCO;
     - (BOOL)isSCOConnected;
     ```
2. **CoreAudio HAL Plugin**:
   - Located at `/System/Library/Audio/Plug-Ins/HAL/BTAudioHALPlugin.driver`.
   - Contains symbols for `HFPAudioDevice`, `18HFPInputShimDevice`, `kBTAudioMsgPropertyScoIsEnabled`.
   - **Crucial finding**: In macOS Monterey, Ventura, Sonoma, and Sequoia, `BTAudioHALPlugin` is activated when macOS acts as an **Audio Gateway** connecting to a Bluetooth headset. When macOS acts as a **Hands-Free unit** connected to an external phone, `IOBluetoothHandsFreeDevice` manages the RFCOMM SLC connection and can issue `connectSCO`, but CoreAudio does not automatically expose the remote phone as a standard audio input/output device without an aggregate or virtual audio HAL client.

---

## 4. End-to-End Implementation Architecture

To ensure 100% stability, reliability, and security without private APIs or kernel hacking, MacLink uses a **Dual-Layer Architecture**:

```
+------------------------------------------------------------------------------------+
|                                    MACLINK ARCHITECTURE                             |
|                                                                                    |
|  +------------------------------------------------------------------------------+  |
|  | LAYER 1: QUIC CONTROL & TELEPHONY TELEMETRY (Primary / Zero-Friction)        |  |
|  | - Incoming call notification with native macOS buttons (Answer / Reject)     |  |
|  | - Keypad dialer, contact search, caller photos, and live duration           |  |
|  | - Call history synchronization and pagination                               |  |
|  | - Completely wireless over authenticated Wi-Fi (No Bluetooth pairing needed) |  |
|  +------------------------------------------------------------------------------+  |
|                                                                                    |
|  +------------------------------------------------------------------------------+  |
|  | LAYER 2: BLUETOOTH HFP VOICE ENGINE (Opt-in Hands-Free Audio)                |  |
|  | - MacLink Swift daemon: MacLinkHFP (IOBluetooth + CoreAudio bridge)          |  |
|  | - Registers HFP HF SDP service record with macOS Bluetooth daemon            |  |
|  | - Pairs with Android BluetoothHeadset profile                                |  |
|  | - Opens SCO audio channel on call answer / dial                              |  |
|  | - Routes SCO PCM audio to Mac default microphone & speaker                    |  |
|  +------------------------------------------------------------------------------+  |
+------------------------------------------------------------------------------------+
```

---

## 5. Step-by-Step Implementation Roadmap

### Phase 1: SDP Service Registration on macOS
1. Create `desktop/swift/MacLinkTelephony/Sources/MacLinkHFP/HfpServiceRecord.swift`.
2. Construct an `IOBluetoothSDPServiceRecord` containing:
   - Service Class ID List: `UUID 0x111E` (Handsfree), `UUID 0x1203` (Generic Audio).
   - Protocol Descriptor List: L2CAP (`0x0100`), RFCOMM (`0x0003`, Channel 6).
   - Bluetooth Profile Descriptor: HFP Version 1.7 (`0x0107`).
   - Supported Features: Bitmap with EC/NR, CLI presentation, remote volume, codec negotiation.
3. Publish the SDP record to macOS Bluetooth daemon via `IOBluetoothSDPServiceRecord.addServiceRecordDictionary()`.

### Phase 2: Android Pairing & Profile Recognition
1. User pairs Mac and Android via standard macOS Bluetooth Settings / Android Bluetooth menu.
2. Android detects the `Handsfree (0x111E)` SDP record and binds the `BluetoothHeadset` service to the Mac.
3. In Android Bluetooth device settings, the toggle **"Phone calls"** becomes enabled for the Mac.

### Phase 3: Service Level Connection (SLC) Management
1. When Android connects or receives a call, `MacLinkHFP` accepts the RFCOMM connection.
2. Complete the HFP handshake:
   - Exchange `AT+BRSF`.
   - Agree on wideband mSBC codec via `AT+BAC` / `+BCS`.
   - Subscribe to call indicators via `AT+CMER=3,0,0,1`.
3. Synchronize state with MacLink's Rust core so the QML UI immediately reflects Bluetooth audio readiness (`btAudioPossible = true`).

### Phase 4: SCO Audio Link & CoreAudio Loopback
1. Upon call answer (`ATA` or answering from Mac UI) or outgoing dial (`ATD`):
   - Invoke `[handsFreeDevice connectSCO]` to open the synchronous voice channel.
2. CoreAudio routing:
   - Hook into the `IOBluetooth` SCO audio buffer callback.
   - For microphone: Capture input from `kAudioHardwarePropertyDefaultInputDevice` (Mac mic) at 16 kHz mono, encode mSBC frames, and stream over SCO.
   - For speaker: Decode incoming mSBC frames from SCO to 16 kHz PCM and feed to `kAudioHardwarePropertyDefaultOutputDevice` (Mac speakers).
3. Upon call termination (`+CIEV: call=0` or user hangs up):
   - Invoke `[handsFreeDevice disconnectSCO]` to return audio to normal macOS system state.

### Phase 5: Graceful Degradation & Fallback
- If the user has not paired Bluetooth, or if macOS Bluetooth is disabled, MacLink operates seamlessly in **Control-Only Mode**:
  - The user can still dial, answer, hang up, and see notifications on their Mac.
  - Call audio naturally stays on the phone or connected wireless earbuds (e.g. Galaxy Buds / AirPods paired to phone).
  - The UI displays an informative badge: `"Audio on Phone • Pair Bluetooth for Mac Audio"`.

---

## 6. Safety, Privacy & Technical Constraints
- **Zero Private APIs**: All Objective-C / Swift classes utilize public `IOBluetooth` and `CoreAudio` frameworks.
- **Privacy Protection**: Phone numbers and contact names in the AT command exchange are never written to disk or transmitted to any external server.
- **Battery & Radio Conservation**: The SCO voice channel is strictly opened when a call is active and immediately torn down on call termination. Idle Bluetooth link consumes negligible BLE/L2CAP energy.

