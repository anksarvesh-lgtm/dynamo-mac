# Unified Touchpad & Gesture Event Protocol (v1)

## 1. Overview
The Unified Touchpad & Gesture Event Protocol specifies the format, serialization, and exchange of multi-touch input, gesture events, haptic-synchronized feedback flags, and transport lifecycle messages between the **Android Companion** and **Mac Companion**.

- **Transport:** WebSocket over TLS on local Wi-Fi (port 52400 default, discovered via Bonjour/NSD).
- **Service Name:** `_maclink-touchpad._tcp`
- **Serialization:** Canonical JSON UTF-8.
- **Protocol Version:** `1`.

---

## 2. Message Envelope Specification

Every packet transmitted over the WebSocket session conforms to the following schema:

```json
{
  "version": 1,
  "sessionId": "authenticated-session-uuid",
  "sequence": 1024,
  "timestamp": 1793658000000,
  "eventType": "POINTER_MOVE",
  "payload": {
    "deltaX": 12.5,
    "deltaY": -8.0
  }
}
```

### Envelope Fields:
| Field | Type | Required | Description |
|---|---|---|---|
| `version` | `Int` | Yes | Must equal `1`. Packets with incompatible versions are dropped. |
| `sessionId` | `String` | Yes | Ephemeral session token issued during cryptographic pairing handshake. |
| `sequence` | `Long` | Yes | Monotonically increasing sequence number per session. |
| `timestamp` | `Long` | Yes | UTC epoch time in milliseconds. Messages with timestamps outside acceptable drift (+/- 5000ms) are flagged. |
| `eventType` | `String` | Yes | One of the 18 allowlisted event types. |
| `payload` | `Object` | Yes | Event-specific arguments validated against strict schemas. |

---

## 3. Supported Event Types & Payload Schemas

### 3.1 Pointer Movement (`POINTER_MOVE`)
Sent when 1 finger traverses the touch surface.
```json
{
  "deltaX": 14.2,
  "deltaY": -6.5
}
```
*Note: Coalesced during transmission if event queues experience congestion.*

### 3.2 Pointer Buttons (`POINTER_DOWN`, `POINTER_UP`)
Explicit mouse button lifecycle events. Critical events that **must never be dropped or coalesced**.
```json
{
  "button": "left"
}
```
Supported buttons: `"left"`, `"right"`, `"middle"`.

### 3.3 Mouse Clicks (`LEFT_CLICK`, `RIGHT_CLICK`, `DOUBLE_CLICK`)
Synthesized tap events.
```json
{
  "clicks": 1
}
```

### 3.4 Scrolling (`SCROLL`)
Sent during 2-finger panning.
```json
{
  "deltaX": 0.0,
  "deltaY": -15.4,
  "isContinuous": true,
  "phase": "changed"
}
```
*Phases: `"began"`, `"changed"`, `"ended"`, `"cancelled"`.*

### 3.5 Pinch to Zoom (`PINCH`)
2-finger magnification.
```json
{
  "scale": 1.15,
  "velocity": 0.05,
  "phase": "changed"
}
```

### 3.6 Rotation (`ROTATE`)
2-finger angular rotation.
```json
{
  "rotation": 18.5,
  "velocity": 1.2,
  "phase": "changed"
}
```

### 3.7 Swipes (`SWIPE`)
3-finger or 4-finger directional gestures.
```json
{
  "direction": "up",
  "fingers": 3,
  "distance": 85.0
}
```
*Directions: `"up"`, `"down"`, `"left"`, `"right"`.*

### 3.8 Keyboard Modifiers & Shortcuts (`KEY_DOWN`, `KEY_UP`)
```json
{
  "keyCode": 53,
  "modifiers": ["command", "shift"]
}
```

### 3.9 Gesture Lifecycle (`GESTURE_START`, `GESTURE_END`, `GESTURE_CANCEL`)
Demarcates gesture boundaries.
```json
{
  "gesture": "two_finger_scroll",
  "fingerCount": 2,
  "reason": "interrupted"
}
```

### 3.10 Heartbeat & Diagnostic (`CONNECTION_PING`, `CONNECTION_PONG`, `DEVICE_STATUS`)
```json
{
  "batteryLevel": 0.85,
  "batteryState": "charging",
  "deviceModel": "Pixel 8 Pro",
  "hapticEngineReady": true
}
```

---

## 4. Ordering, Validation, and Stuck-Button Safety

1. **Monotonic Sequences:**
   - Any message with `sequence <= last_received_sequence` is rejected as an obsolete or replayed packet (except connection pings).
2. **Coalescing Policy:**
   - Only `POINTER_MOVE` and `SCROLL` deltas may be coalesced in transmit queues.
   - `POINTER_DOWN`, `POINTER_UP`, `LEFT_CLICK`, `RIGHT_CLICK`, `DOUBLE_CLICK`, `KEY_DOWN`, `KEY_UP` are high-priority frames and must never be coalesced or discarded.
3. **Fail-Safe Release Policy:**
   - On connection interruption, socket close, or timeout (> 2000ms heartbeat loss), the Mac receiver automatically executes emergency input cleanup:
     - Synthetic `CGEvent` mouse-up for left, right, and middle buttons.
     - Synthetic modifier key release for Shift, Command, Control, Option.
     - Cancellation of pending drag operations.

