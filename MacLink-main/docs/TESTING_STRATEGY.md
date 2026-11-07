# Testing Strategy

## 1. Test Automation Matrix

| Layer | Component | Test Target | Key Assertions |
|---|---|---|---|
| Protocol | Envelope / JSON | `ProtocolTests.swift` | Full CBOR/JSON round-trip, version guard, sequence monotonicity |
| macOS Input | ForceTouch / MagicMouse | `InputEngineTests.swift` | Stage 1/2 click detection, Magic Mouse non-force-touch invariant |
| macOS Remote | Stuck-button Safety | `RemoteInputTests.swift` | `emergencyInputCleanup()` releases all held buttons and modifiers |
| Android Gestures | Gesture Classifier | `GestureClassifierTests.kt` | Single/double tap, right click, 3/4-finger swipe, acceleration separation |
| Android Haptics | Profile Manager | `HapticEngineTests.kt` | Natural < Standard < Enhanced amplitude scaling, intensity clamping |
| Android Network | Coalescing | `MovementCoalescerTests.kt` | Pointer moves coalesce; clicks/swipes/drags are never dropped |

