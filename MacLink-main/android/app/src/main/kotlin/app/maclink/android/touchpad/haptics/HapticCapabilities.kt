// SPDX-License-Identifier: MIT
package app.maclink.android.touchpad.haptics

import android.content.Context
import android.os.Build
import android.os.Vibrator
import android.os.VibratorManager

data class HapticCapabilities(
    val hasVibrator: Boolean,
    val hasAmplitudeControl: Boolean,
    val supportsPrimitives: Boolean
) {
    companion object {
        fun detect(context: Context): HapticCapabilities {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }

            if (vibrator == null || !vibrator.hasVibrator()) {
                return HapticCapabilities(hasVibrator = false, hasAmplitudeControl = false, supportsPrimitives = false)
            }

            val hasAmp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.hasAmplitudeControl()
            } else {
                false
            }

            val supportsPrimitives = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                vibrator.areAllPrimitivesSupported(
                    android.os.VibrationEffect.Composition.PRIMITIVE_CLICK,
                    android.os.VibrationEffect.Composition.PRIMITIVE_TICK
                )
            } else {
                false
            }

            return HapticCapabilities(
                hasVibrator = true,
                hasAmplitudeControl = hasAmp,
                supportsPrimitives = supportsPrimitives
            )
        }
    }
}

