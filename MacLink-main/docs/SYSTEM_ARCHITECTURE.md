# System Architecture

## 1. System Vision & Context
The ecosystem enables bi-directional input intelligence and remote trackpad capability across macOS and Android platforms.

```mermaid
flowchart TB
    subgraph ANDROID["ANDROID COMPANION APPLICATION"]
        A1["Android Touchscreen"]
        A2["Touch Input Capture"]
        A3["Multi-Touch Recognition"]
        A4["Gesture State Machine"]
        A5["Local Haptic Engine"]
        A6["Input Event Processor"]
        A7["Network Transport"]
        A1 --> A2 --> A3 --> A4
        A4 --> A5
        A4 --> A6 --> A7
    end

    subgraph NETWORK["LOCAL WI-FI"]
        N1["Bonjour Discovery (_maclink-touchpad._tcp)"]
        N2["Authenticated WebSocket"]
        N1 --> N2
    end

    subgraph MAC["MAC COMPANION APPLICATION"]
        M1["Network Receiver (NWListener)"]
        M2["Event Validator & Sequence Manager"]
        M3["Remote Input Controller (CGEvent)"]
        M4["Native Input Engine (AppKit/CoreGraphics)"]
        M5["SwiftUI Dashboard & Action Router"]
        M1 --> M2 --> M3
        M4 --> M5
        M3 --> M5
    end

    A7 <-->|"Encrypted WebSocket"| N2
    N2 --> M1
```

## 2. Core Architectural Pillars
1. **Decoupled Haptics:** The Android tactile engine runs immediately in the touch capture lifecycle. Network latency, socket backpressure, or connection drops never delay haptic clicks.
2. **Fail-Safe Release Policy:** If the Wi-Fi connection drops, the Mac Companion immediately issues synthetic mouse-up and modifier-up events, preventing stuck inputs.
3. **Hardware Truth:** The Mac Companion distinguishes between trackpads (which support Force Touch) and Magic Mouse (which does not). It never fakes unsupported hardware capabilities.
4. **Rate-Limited Monotonic Protocol:** All input events are sequenced monotonically and validated against clock drift and replay bounds.

