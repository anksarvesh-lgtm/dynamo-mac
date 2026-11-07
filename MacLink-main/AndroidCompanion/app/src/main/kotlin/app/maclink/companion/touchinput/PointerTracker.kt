// SPDX-License-Identifier: MIT
package app.maclink.companion.touchinput

import android.view.MotionEvent
import kotlin.math.atan2
import kotlin.math.hypot

data class PointerRecord(
    val id: Int,
    val startX: Float,
    val startY: Float,
    var currentX: Float,
    var currentY: Float,
    var lastX: Float,
    var lastY: Float,
    val startTimeMs: Long,
    var lastTimeMs: Long
) {
    val totalDisplacement: Float
        get() = hypot(currentX - startX, currentY - startY)

    val deltaX: Float
        get() = currentX - lastX

    val deltaY: Float
        get() = currentY - lastY
}

class PointerTracker {
    private val activePointers = mutableMapOf<Int, PointerRecord>()

    val pointerCount: Int get() = activePointers.size

    fun getPointer(id: Int): PointerRecord? = activePointers[id]

    fun getAllPointers(): Collection<PointerRecord> = activePointers.values

    fun onPointerDown(id: Int, x: Float, y: Float, timeMs: Long) {
        activePointers[id] = PointerRecord(
            id = id,
            startX = x,
            startY = y,
            currentX = x,
            currentY = y,
            lastX = x,
            lastY = y,
            startTimeMs = timeMs,
            lastTimeMs = timeMs
        )
    }

    fun onPointerMove(id: Int, x: Float, y: Float, timeMs: Long) {
        activePointers[id]?.let {
            it.lastX = it.currentX
            it.lastY = it.currentY
            it.currentX = x
            it.currentY = y
            it.lastTimeMs = timeMs
        }
    }

    fun onPointerUp(id: Int) {
        activePointers.remove(id)
    }

    fun clear() {
        activePointers.clear()
    }

    /**
     * Calculates the centroid (center of mass) of all currently active pointers.
     */
    fun computeCentroid(): Pair<Float, Float> {
        if (activePointers.isEmpty()) return 0f to 0f
        var sumX = 0f
        var sumY = 0f
        for (p in activePointers.values) {
            sumX += p.currentX
            sumY += p.currentY
        }
        val count = activePointers.size.toFloat()
        return (sumX / count) to (sumY / count)
    }

    /**
     * Computes the average distance from centroid (span) for 2+ pointers.
     */
    fun computeSpan(): Float {
        if (activePointers.size < 2) return 0f
        val (cx, cy) = computeCentroid()
        var sumDist = 0f
        for (p in activePointers.values) {
            sumDist += hypot(p.currentX - cx, p.currentY - cy)
        }
        return (sumDist / activePointers.size) * 2f
    }

    /**
     * Computes the angle in radians between first 2 pointers for rotation gestures.
     */
    fun computeAngle(): Float {
        if (activePointers.size < 2) return 0f
        val list = activePointers.values.toList()
        val p1 = list[0]
        val p2 = list[1]
        return atan2(p2.currentY - p1.currentY, p2.currentX - p1.currentX)
    }
}

