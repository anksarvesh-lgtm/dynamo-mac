// SPDX-License-Identifier: MIT
package app.maclink.companion.touchinput

import kotlin.math.hypot
import kotlin.math.pow
import kotlin.math.sign

/**
 * Coordinate processor handling sensitivity scaling and acceleration curves.
 *
 * CRITICAL ARCHITECTURE RULE (Part 3, Section 6):
 * Use separate calculations for pointer movement and scrolling.
 * Never apply pointer acceleration curves to scroll deltas.
 */
class CoordinateProcessor(
    var pointerSensitivity: Float = 1.0f,
    var scrollSensitivity: Float = 1.0f,
    var accelerationEnabled: Boolean = true,
    var naturalScroll: Boolean = true
) {
    /**
     * Calculates relative pointer movement deltas with optional acceleration curve.
     */
    fun processPointerDelta(rawDx: Float, rawDy: Float): Pair<Float, Float> {
        if (rawDx == 0f && rawDy == 0f) return 0f to 0f

        val scaledDx = rawDx * pointerSensitivity
        val scaledDy = rawDy * pointerSensitivity

        if (!accelerationEnabled) {
            return scaledDx to scaledDy
        }

        // Acceleration curve: boost higher velocity movements while maintaining precision for small movements
        val distance = hypot(scaledDx, scaledDy)
        val speedFactor = if (distance > 2.0f) {
            (distance / 2.0f).toDouble().pow(0.25).toFloat().coerceIn(1.0f, 3.5f)
        } else {
            1.0f
        }

        return (scaledDx * speedFactor) to (scaledDy * speedFactor)
    }

    /**
     * Calculates 2-finger scroll deltas linearly without non-linear pointer acceleration.
     */
    fun processScrollDelta(rawDx: Float, rawDy: Float): Pair<Float, Float> {
        val dirMultiplier = if (naturalScroll) -1.0f else 1.0f
        val sx = rawDx * scrollSensitivity * dirMultiplier
        val sy = rawDy * scrollSensitivity * dirMultiplier
        return sx to sy
    }
}

