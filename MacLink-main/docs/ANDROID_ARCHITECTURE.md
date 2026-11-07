# Android Companion Architecture

## 1. Internal Module Structure
The Android Companion is organized into modular layers:
- `touchinput`: Captures raw `MotionEvent`s, manages pointer IDs, and normalizes coordinates.
- `gestureengine`: Independent gesture recognizers for single-touch, two-touch, pinch, rotation, and multi-finger directional swipes.
- `haptics`: Local haptic feedback engine detecting device capabilities and providing Natural, Standard, and Enhanced vibration profiles.
- `networking`: WebSocket client with automatic reconnection backoff, heartbeat management, and a movement coalescer.
- `presentation`: Jetpack Compose UI implementing the full-screen trackpad surface, status bar, and controls.

## 2. Touch Pipeline
1. `TouchpadScreen` intercepts touch events via `pointerInteropFilter`.
2. `MotionEventHandler` passes masked actions to `GestureClassifier`.
3. `PointerTracker` maintains coordinates, displacements, centroids, and spans.
4. When a tap or gesture is classified:
   - It fires `onHapticRequested` immediately to `HapticEngine`.
   - It enqueues `RecognizedGesture` into `MovementCoalescer`.
5. High-frequency pointer moves are coalesced and flushed at ~60fps over the WebSocket transport.

