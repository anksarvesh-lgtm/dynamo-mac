# MacLink Unified Touchpad & Gesture Ecosystem

Turn your Android phone into a responsive, premium wireless multi-touch trackpad for Mac with instantaneous, local tactile haptics, paired with a comprehensive macOS input-monitoring and gesture-management companion.

---

## Architecture Overview
The system consists of two native applications communicating over an authenticated local WebSocket transport discovered automatically via Bonjour / mDNS:

1. **Mac Companion (`MacCompanion`)**:
   - Native Swift / SwiftUI / AppKit application.
   - Monitors built-in trackpad (multi-touch, pinch, rotation, Force Touch pressure stages).
   - Monitors Apple Magic Mouse (scrolling inertia, gestures, no false Force Touch).
   - Receives remote input frames over WebSocket (`_maclink-touchpad._tcp`).
   - Synthesizes smooth pointer movements, clicks, and scroll deltas via `CGEvent`.
   - Enforces fail-safe emergency input cleanup on disconnect (no stuck buttons or modifiers).

2. **Android Companion (`AndroidCompanion`)**:
   - Native Kotlin / Jetpack Compose application.
   - Multi-touch gesture classifier (1, 2, 3, 4 fingers: move, tap, double tap, right click, scroll, pinch, rotation, directional swipes).
   - Standalone, latency-independent Local Haptic Engine (Natural, Standard, Enhanced profiles).
   - Movement coalescer for fluid 60fps+ cursor movement without dropping button down/up transitions.

---

## Documentation Sitemap
- [System Architecture](SYSTEM_ARCHITECTURE.md)
- [Android Architecture](ANDROID_ARCHITECTURE.md)
- [Mac Architecture](MAC_ARCHITECTURE.md)
- [Network Architecture](NETWORK_ARCHITECTURE.md)
- [Gesture Engine](GESTURE_ENGINE.md)
- [Haptic Engine](HAPTIC_ENGINE.md)
- [Event Protocol (v1)](EVENT_PROTOCOL.md)
- [Security Architecture](SECURITY_ARCHITECTURE.md)
- [Permission Guide](PERMISSION_GUIDE.md)
- [Threading and Lifecycle](THREADING_AND_LIFECYCLE.md)
- [Testing Strategy](TESTING_STRATEGY.md)
- [Deployment Guide](DEPLOYMENT_GUIDE.md)
- [Mermaid Diagrams](diagrams/)

