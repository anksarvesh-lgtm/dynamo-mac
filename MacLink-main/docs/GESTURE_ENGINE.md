# Gesture Recognition Engine

## 1. Multi-Touch Gesture Matrix

| Touch Input | Classified Gesture | Emitted Event | Local Haptic Trigger |
|---|---|---|---|
| 1 finger move | Pointer Movement | `POINTER_MOVE` | None |
| 1 finger tap (< 250ms, < 18px) | Left Click | `LEFT_CLICK` | `SINGLE_CLICK` |
| 1 finger double tap (< 300ms) | Double Click | `DOUBLE_CLICK` | `DOUBLE_CLICK` |
| 1 finger tap-and-hold + move | Mouse Drag | `POINTER_DOWN` + `POINTER_MOVE` | `DRAG_START` / `DRAG_RELEASE` |
| 2 finger tap | Right Click | `RIGHT_CLICK` | `RIGHT_CLICK` |
| 2 finger parallel movement | Scroll | `SCROLL` | `SCROLL_TICK` (optional) |
| 2 finger span delta (> 25px) | Pinch to Zoom | `PINCH` | None |
| 2 finger angular rotation (> 10°) | Rotation | `ROTATE` | None |
| 3 finger swipe up | Mission Control | `SWIPE` (up, 3 fingers) | `GESTURE_COMPLETE` |
| 3 finger swipe down | App Exposé | `SWIPE` (down, 3 fingers) | `GESTURE_COMPLETE` |
| 3 finger swipe left/right | Switch Spaces | `SWIPE` (left/right, 3 fingers) | `GESTURE_COMPLETE` |
| 4 finger swipes | Custom User Action | `SWIPE` (4 fingers) | `GESTURE_COMPLETE` |

## 2. Separation of Movement and Scrolling
- Pointer acceleration curve is applied **only** to single-finger pointer delta.
- Scroll deltas are linearly scaled without pointer acceleration curve and invert axis if Natural Scrolling is enabled.

