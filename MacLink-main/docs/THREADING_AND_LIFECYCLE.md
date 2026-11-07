# Threading & Lifecycle

## 1. macOS Threading Model
- **Main Thread:** SwiftUI view hierarchy, window lifecycle, and AppKit gesture recognizer callbacks.
- **Dedicated Server Queue (`app.maclink.touchpad.server`):** Network.framework socket I/O, envelope decoding, validation, and CGEvent posting.
- **Lock-Free State Synchronization:** Atomic counters and thread-safe lock wrappers protect `SessionManager`, `SequenceManager`, and `RemoteInputController`.

## 2. Android Threading Model
- **Main Thread:** Jetpack Compose rendering and user interaction controls.
- **Input Pipeline:** Low-latency `MotionEvent` dispatch through `MotionEventHandler` directly triggering local non-blocking vibrator effects.
- **Network Pipeline:** Asynchronous coroutines and bounded queue coalescing movements for transmission.

