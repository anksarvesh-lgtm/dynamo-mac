// SPDX-License-Identifier: MIT
package app.maclink.companion.haptics

import android.os.Build
import android.os.VibrationEffect
import androidx.annotation.RequiresApi
import app.maclink.companion.gestureengine.HapticGestureTrigger

enum class HapticProfile {
    NATURAL,
    STANDARD,
    ENHANCED
}

data class VibrationParams(
    val durationMs: Long = 0L,
    val amplitude: Int = 255,
    val timings: LongArray? = null,
    val amplitudes: IntArray? = null,
    val primitiveId: Int? = null,
    val primitiveScale: Float? = null
)

class HapticProfileManager(
    var activeProfile: HapticProfile = HapticProfile.STANDARD,
    var userIntensity: Float = 1.0f
) {
    fun calculateParams(
        trigger: HapticGestureTrigger,
        capabilities: HapticCapabilities
    ): VibrationParams {
        val baseMultiplier = when (activeProfile) {
            HapticProfile.NATURAL -> 0.4f
            HapticProfile.STANDARD -> 0.7f
            HapticProfile.ENHANCED -> 1.0f
        }
        val targetAmpFloat = (baseMultiplier * userIntensity.coerceIn(0.1f, 1.0f) * 255f)
        val amp = targetAmpFloat.toInt().coerceIn(1, 255)

        if (capabilities.supportsPrimitives) {
            val scale = (baseMultiplier * userIntensity).coerceIn(0.1f, 1.0f)
            return when (trigger) {
                HapticGestureTrigger.SINGLE_CLICK -> VibrationParams(primitiveId = 1, primitiveScale = scale)
                HapticGestureTrigger.DOUBLE_CLICK -> VibrationParams(primitiveId = 1, primitiveScale = scale)
                HapticGestureTrigger.RIGHT_CLICK -> VibrationParams(primitiveId = 3, primitiveScale = scale)
                HapticGestureTrigger.SCROLL_TICK -> VibrationParams(primitiveId = 7, primitiveScale = scale * 0.5f)
                HapticGestureTrigger.GESTURE_COMPLETE,
                HapticGestureTrigger.DROP_CONFIRM -> VibrationParams(primitiveId = 3, primitiveScale = scale)
                HapticGestureTrigger.DRAG_START,
                HapticGestureTrigger.DRAG_RELEASE,
                HapticGestureTrigger.LONG_PRESS -> VibrationParams(primitiveId = 4, primitiveScale = scale * 0.8f)
            }
        }

        val durationMs: Long
        when (trigger) {
            HapticGestureTrigger.SINGLE_CLICK -> durationMs = if (activeProfile == HapticProfile.NATURAL) 10L else 15L
            HapticGestureTrigger.DOUBLE_CLICK -> {
                val timings = longArrayOf(0, 12, 50, 12)
                val amps = if (capabilities.hasAmplitudeControl) intArrayOf(0, amp, 0, amp) else intArrayOf(0, 255, 0, 255)
                return VibrationParams(timings = timings, amplitudes = amps)
            }
            HapticGestureTrigger.RIGHT_CLICK -> durationMs = 25L
            HapticGestureTrigger.SCROLL_TICK -> durationMs = 6L
            HapticGestureTrigger.GESTURE_COMPLETE,
            HapticGestureTrigger.DROP_CONFIRM -> {
                val timings = longArrayOf(0, 10, 30, 20)
                val amps = if (capabilities.hasAmplitudeControl) intArrayOf(0, (amp * 0.7f).toInt().coerceAtLeast(1), 0, amp) else intArrayOf(0, 255, 0, 255)
                return VibrationParams(timings = timings, amplitudes = amps)
            }
            HapticGestureTrigger.DRAG_START,
            HapticGestureTrigger.DRAG_RELEASE,
            HapticGestureTrigger.LONG_PRESS -> durationMs = 20L
        }

        return VibrationParams(durationMs = durationMs, amplitude = if (capabilities.hasAmplitudeControl) amp else 255)
    }

    @RequiresApi(Build.VERSION_CODES.O)
    fun createVibrationEffect(
        trigger: HapticGestureTrigger,
        capabilities: HapticCapabilities
    ): VibrationEffect? {
        val params = calculateParams(trigger, capabilities)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && capabilities.supportsPrimitives && params.primitiveId != null) {
            val composition = VibrationEffect.startComposition()
            return composition.addPrimitive(params.primitiveId, params.primitiveScale ?: 1.0f).compose()
        }

        if (params.timings != null && params.amplitudes != null) {
            return VibrationEffect.createWaveform(params.timings, params.amplitudes, -1)
        }

        return if (capabilities.hasAmplitudeControl) {
            VibrationEffect.createOneShot(params.durationMs, params.amplitude)
        } else {
            VibrationEffect.createOneShot(params.durationMs, VibrationEffect.DEFAULT_AMPLITUDE)
        }
    }
}
