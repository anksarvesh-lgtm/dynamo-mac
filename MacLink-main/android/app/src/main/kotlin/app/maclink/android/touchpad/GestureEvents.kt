// SPDX-License-Identifier: MIT
package app.maclink.android.touchpad

sealed class RecognizedGesture {
    data class PointerMove(val deltaX: Float, val deltaY: Float) : RecognizedGesture()
    data class Click(val button: String = "left", val count: Int = 1) : RecognizedGesture()
    data class Scroll(val deltaX: Float, val deltaY: Float, val isContinuous: Boolean = true, val phase: String = "changed") : RecognizedGesture()
    data class DragStart(val x: Float, val y: Float) : RecognizedGesture()
    data class DragMove(val deltaX: Float, val deltaY: Float) : RecognizedGesture()
    data class DragEnd(val x: Float, val y: Float) : RecognizedGesture()
    data class Pinch(val scale: Float, val velocity: Float, val phase: String) : RecognizedGesture()
    data class Rotate(val degrees: Float, val velocity: Float, val phase: String) : RecognizedGesture()
    data class Swipe(val direction: String, val fingers: Int, val distance: Float) : RecognizedGesture()
}

enum class HapticGestureTrigger {
    SINGLE_CLICK,
    DOUBLE_CLICK,
    RIGHT_CLICK,
    LONG_PRESS,
    DRAG_START,
    DRAG_RELEASE,
    DROP_CONFIRM,
    GESTURE_COMPLETE,
    SCROLL_TICK
}

