// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.telephony

import android.content.Context
import androidx.core.content.edit

/**
 * Persisted telephony privacy toggles for MacLink.
 *
 * Rules:
 * - Both default to false (user explicitly controls remote telephony control).
 * - [allowCallControl]: Let paired Mac answer, hang up, and place calls.
 * - [shareCallHistory]: Share recent call log with paired Mac.
 */
class TelephonySettings(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    var allowCallControl: Boolean
        get() = prefs.getBoolean(KEY_ALLOW_CALL_CONTROL, false)
        set(value) = prefs.edit { putBoolean(KEY_ALLOW_CALL_CONTROL, value) }

    var shareCallHistory: Boolean
        get() = prefs.getBoolean(KEY_SHARE_CALL_HISTORY, false)
        set(value) = prefs.edit { putBoolean(KEY_SHARE_CALL_HISTORY, value) }

    companion object {
        private const val PREFS_NAME = "telephony_settings"
        const val KEY_ALLOW_CALL_CONTROL = "allow_call_control"
        const val KEY_SHARE_CALL_HISTORY = "share_call_history"

        @Volatile
        private var instance: TelephonySettings? = null

        fun get(context: Context): TelephonySettings =
            instance ?: synchronized(this) {
                instance ?: TelephonySettings(context).also { instance = it }
            }
    }
}

