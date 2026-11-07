// SPDX-License-Identifier: MIT
package app.maclink.android.touchpad

import kotlin.math.hypot
import kotlin.math.pow

class CoordinateProcessor(
    var pointerSensitivity: Float = 1.0f,
    var scrollSensitivity: Float = 1.0f,
    var accelerationEnabled: Boolean = true,
    var naturalScroll: Boolean = true
) {
    fun processPointerDelta(rawDx: Float, rawDy: Float): Pair<Float, Float> {
        if (rawDx == 0f && rawDy == 0f) return 0f to 0f

        val scaledDx = rawDx * pointerSensitivity
        val scaledDy = rawDy * pointerSensitivity

        if (!accelerationEnabled) {
            return scaledDx to scaledDy
        }

        val distance = hypot(scaledDx, scaledDy)
        val speedFactor = if (distance > 2.0f) {
            (distance / 2.0f).toDouble().pow(0.25).toFloat().coerceIn(1.0f, 3.5f)
        } else {
            1.0f
        }

        return (scaledDx * speedFactor) to (scaledDy * speedFactor)
    }

    fun processScrollDelta(rawDx: Float, rawDy: Float): Pair<Float, Float> {
        val dirMultiplier = if (naturalScroll) -1.0f else 1.0f
        val sx = rawDx * scrollSensitivity * dirMultiplier
        val sy = rawDy * scrollSensitivity * dirMultiplier
        return sx to sy
    }
}

