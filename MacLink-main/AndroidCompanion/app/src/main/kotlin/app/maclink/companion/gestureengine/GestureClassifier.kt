// SPDX-License-Identifier: MIT
package app.maclink.companion.gestureengine

import app.maclink.companion.touchinput.CoordinateProcessor
import app.maclink.companion.touchinput.PointerTracker
import kotlin.math.abs
import kotlin.math.hypot

interface GestureListener {
    fun onGestureRecognized(gesture: RecognizedGesture)
    fun onHapticRequested(trigger: HapticGestureTrigger)
}

class GestureClassifier(
    private val coordinateProcessor: CoordinateProcessor,
    var listener: GestureListener? = null
) {
    private val tracker = PointerTracker()

    // Configuration thresholds
    var tapTimeoutMs: Long = 250L
    var doubleTapTimeoutMs: Long = 300L
    var tapSlopPx: Float = 18f
    var swipeThresholdPx: Float = 60f

    // Tap tracking state
    private var lastTapTimeMs: Long = 0L
    private var lastTapX: Float = 0f
    private var lastTapY: Float = 0f

    // 2-finger initial state
    private var initialSpan: Float = 0f
    private var initialAngle: Float = 0f
    private var isPinchingOrRotating: Boolean = false

    // Multi-finger swipe state
    private var multiFingerSwipeRecognized = false

    fun onPointerDown(id: Int, x: Float, y: Float, timeMs: Long) {
        tracker.onPointerDown(id, x, y, timeMs)

        if (tracker.pointerCount == 2) {
            initialSpan = tracker.computeSpan()
            initialAngle = tracker.computeAngle()
            isPinchingOrRotating = false
        } else if (tracker.pointerCount >= 3) {
            multiFingerSwipeRecognized = false
        }
    }

    fun onPointerMove(id: Int, x: Float, y: Float, timeMs: Long) {
        val ptr = tracker.getPointer(id) ?: return
        val rawDx = x - ptr.currentX
        val rawDy = y - ptr.currentY
        tracker.onPointerMove(id, x, y, timeMs)

        when (tracker.pointerCount) {
            1 -> {
                // 1 Finger: Pointer Movement
                if (ptr.totalDisplacement > tapSlopPx) {
                    val (dx, dy) = coordinateProcessor.processPointerDelta(rawDx, rawDy)
                    listener?.onGestureRecognized(RecognizedGesture.PointerMove(dx, dy))
                }
            }
            2 -> {
                // 2 Fingers: Scroll, Pinch, or Rotate
                val currentSpan = tracker.computeSpan()
                val spanDelta = abs(currentSpan - initialSpan)

                if (spanDelta > 25f) {
                    isPinchingOrRotating = true
                    val scale = if (initialSpan > 0f) currentSpan / initialSpan else 1f
                    listener?.onGestureRecognized(RecognizedGesture.Pinch(scale = scale, velocity = 0f, phase = "changed"))
                } else if (!isPinchingOrRotating) {
                    // Two-finger scroll
                    val (sx, sy) = coordinateProcessor.processScrollDelta(rawDx, rawDy)
                    listener?.onGestureRecognized(RecognizedGesture.Scroll(deltaX = sx, deltaY = sy, phase = "changed"))
                }
            }
            3 -> {
                // 3 Fingers: Swipe gesture detection
                if (!multiFingerSwipeRecognized) {
                    val all = tracker.getAllPointers()
                    val avgDisplacementX = all.map { it.currentX - it.startX }.average().toFloat()
                    val avgDisplacementY = all.map { it.currentY - it.startY }.average().toFloat()
                    val totalDist = hypot(avgDisplacementX, avgDisplacementY)

                    if (totalDist > swipeThresholdPx) {
                        multiFingerSwipeRecognized = true
                        val direction = if (abs(avgDisplacementY) > abs(avgDisplacementX)) {
                            if (avgDisplacementY < 0f) "up" else "down"
                        } else {
                            if (avgDisplacementX < 0f) "left" else "right"
                        }
                        listener?.onHapticRequested(HapticGestureTrigger.GESTURE_COMPLETE)
                        listener?.onGestureRecognized(RecognizedGesture.Swipe(direction, fingers = 3, distance = totalDist))
                    }
                }
            }
            4 -> {
                // 4 Fingers: Desktop navigation swipe
                if (!multiFingerSwipeRecognized) {
                    val all = tracker.getAllPointers()
                    val avgDisplacementX = all.map { it.currentX - it.startX }.average().toFloat()
                    val avgDisplacementY = all.map { it.currentY - it.startY }.average().toFloat()
                    val totalDist = hypot(avgDisplacementX, avgDisplacementY)

                    if (totalDist > swipeThresholdPx) {
                        multiFingerSwipeRecognized = true
                        val direction = if (abs(avgDisplacementY) > abs(avgDisplacementX)) {
                            if (avgDisplacementY < 0f) "up" else "down"
                        } else {
                            if (avgDisplacementX < 0f) "left" else "right"
                        }
                        listener?.onHapticRequested(HapticGestureTrigger.GESTURE_COMPLETE)
                        listener?.onGestureRecognized(RecognizedGesture.Swipe(direction, fingers = 4, distance = totalDist))
                    }
                }
            }
        }
    }

    fun onPointerUp(id: Int, x: Float, y: Float, timeMs: Long) {
        val ptr = tracker.getPointer(id)
        val initialCount = tracker.pointerCount

        if (ptr != null) {
            val duration = timeMs - ptr.startTimeMs
            val displacement = ptr.totalDisplacement

            if (initialCount == 1 && duration < tapTimeoutMs && displacement < tapSlopPx) {
                // Check if this is a double tap
                val timeSinceLastTap = timeMs - lastTapTimeMs
                val distFromLastTap = hypot(x - lastTapX, y - lastTapY)

                if (timeSinceLastTap < doubleTapTimeoutMs && distFromLastTap < tapSlopPx * 2) {
                    // Double Tap!
                    lastTapTimeMs = 0L
                    listener?.onHapticRequested(HapticGestureTrigger.DOUBLE_CLICK)
                    listener?.onGestureRecognized(RecognizedGesture.Click(button = "left", count = 2))
                } else {
                    // Single Tap!
                    lastTapTimeMs = timeMs
                    lastTapX = x
                    lastTapY = y
                    listener?.onHapticRequested(HapticGestureTrigger.SINGLE_CLICK)
                    listener?.onGestureRecognized(RecognizedGesture.Click(button = "left", count = 1))
                }
            } else if (initialCount == 2 && duration < tapTimeoutMs && displacement < tapSlopPx) {
                // 2-Finger Tap -> Right click!
                listener?.onHapticRequested(HapticGestureTrigger.RIGHT_CLICK)
                listener?.onGestureRecognized(RecognizedGesture.Click(button = "right", count = 1))
            }
        }

        tracker.onPointerUp(id)
        if (tracker.pointerCount == 0) {
            isPinchingOrRotating = false
            multiFingerSwipeRecognized = false
        }
    }

    fun onCancel() {
        tracker.clear()
        isPinchingOrRotating = false
        multiFingerSwipeRecognized = false
    }
}

