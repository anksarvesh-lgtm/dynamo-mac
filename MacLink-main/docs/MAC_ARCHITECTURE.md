# Mac Companion Architecture

## 1. Native Mac Input Engine
- **`TouchCaptureView`:** An AppKit `NSView` subclass registering resting and active touches, handling `NSPanGestureRecognizer`, `NSMagnificationGestureRecognizer`, `NSRotationGestureRecognizer`, `NSClickGestureRecognizer`, and `NSPressGestureRecognizer`.
- **`ForceTouchMonitor`:** Intercepts `pressureChange(with:)` events, classifies `stage 1` (normal click) and `stage 2` (force click), and triggers `NSHapticFeedbackManager.defaultPerformer` alignment or generic feedback.
- **`MagicMouseMonitor`:** Records scroll deltas, inertia momentum, and swipes. Adheres strictly to the architectural constraint: `isForceTouchSupported == false`.
- **`GlobalMouseMonitor`:** Observational listener using `NSEvent.addGlobalMonitorForEvents` and local monitors without modifying external events.

## 2. Remote Input Processing
- **`RemoteInputServer`:** Network.framework `NWListener` with WebSocket framing on port `52400`, broadcasting `_maclink-touchpad._tcp` via Bonjour.
- **`EventValidator` & `SequenceManager`:** Validates version 1, session ID, timestamp drift (< 60s), and strictly monotonic sequence numbers.
- **`RemoteInputController`:** Converts validated envelopes into native `CGEvent` posts (mouse moved, dragged, left down/up, right down/up, scroll wheel, and shortcut keys).
- **`emergencyInputCleanup()`:** Guaranteed release of any held mouse buttons or modifier keys on disconnect or timeout.

