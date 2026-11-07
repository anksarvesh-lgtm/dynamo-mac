// SPDX-License-Identifier: MIT
package app.maclink.android.touchpad.haptics

import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import app.maclink.android.touchpad.HapticGestureTrigger
import java.util.concurrent.atomic.AtomicLong

class HapticEngine(
    private val context: Context,
    val profileManager: HapticProfileManager = HapticProfileManager()
) {
    val capabilities: HapticCapabilities = HapticCapabilities.detect(context)

    var enabled: Boolean = true
    var respectSystemSetting: Boolean = true
    var minInterHapticIntervalMs: Long = 30L

    private val lastTriggerTime = AtomicLong(0L)

    private val vibrator: Vibrator? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vm?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    fun trigger(trigger: HapticGestureTrigger) {
        if (!enabled || !capabilities.hasVibrator) return

        if (respectSystemSetting) {
            val sysHaptics = Settings.System.getInt(
                context.contentResolver,
                Settings.System.HAPTIC_FEEDBACK_ENABLED,
                1
            )
            if (sysHaptics == 0) return
        }

        val now = SystemClock.uptimeMillis()
        val last = lastTriggerTime.get()
        if (now - last < minInterHapticIntervalMs && trigger == HapticGestureTrigger.SCROLL_TICK) {
            return
        }
        lastTriggerTime.set(now)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val effect = profileManager.createVibrationEffect(trigger, capabilities)
                if (effect != null) {
                    vibrator?.vibrate(effect)
                }
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(15L)
            }
        } catch (_: Exception) {}
    }

    fun cancel() {
        try {
            vibrator?.cancel()
        } catch (_: Exception) {}
    }
}

