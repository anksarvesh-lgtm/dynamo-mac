// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.telephony

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat

/**
 * Telephony capabilities advertised to paired PCs over the encrypted link.
 */
data class TelephonyCapabilities(
    val canObserve: Boolean,
    val canAnswer: Boolean,
    val canEnd: Boolean,
    val canDial: Boolean,
    val hasCallLog: Boolean,
    val hasContacts: Boolean,
    val simCount: Int,
    val btAudioPossible: Boolean,
)

/**
 * Single source of truth for telephony-related Android runtime permissions.
 */
object TelephonyPermissions {

    fun hasPermission(context: Context, permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    fun hasReadPhoneState(context: Context): Boolean =
        hasPermission(context, Manifest.permission.READ_PHONE_STATE)

    fun hasAnswerCalls(context: Context): Boolean =
        hasPermission(context, Manifest.permission.ANSWER_PHONE_CALLS)

    fun hasCallPhone(context: Context): Boolean =
        hasPermission(context, Manifest.permission.CALL_PHONE)

    fun hasReadCallLog(context: Context): Boolean =
        hasPermission(context, Manifest.permission.READ_CALL_LOG)

    fun hasReadContacts(context: Context): Boolean =
        hasPermission(context, Manifest.permission.READ_CONTACTS)

    fun hasBluetoothConnect(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            hasPermission(context, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            true
        }

    /**
     * Derives telephony capabilities combining OS permissions and user privacy switches.
     */
    fun deriveCapabilities(
        context: Context,
        settings: TelephonySettings,
        simCount: Int = 1,
    ): TelephonyCapabilities {
        val canObserve = hasReadPhoneState(context)
        val canControl = settings.allowCallControl
        val canAnswer = hasAnswerCalls(context) && canControl
        val canEnd = hasAnswerCalls(context) && canControl
        val canDial = hasCallPhone(context) && canControl
        val hasCallLog = hasReadCallLog(context) && settings.shareCallHistory
        val hasContacts = hasReadContacts(context)

        return TelephonyCapabilities(
            canObserve = canObserve,
            canAnswer = canAnswer,
            canEnd = canEnd,
            canDial = canDial,
            hasCallLog = hasCallLog,
            hasContacts = hasContacts,
            simCount = simCount.coerceAtLeast(1),
            btAudioPossible = false, // Gated: macOS cannot route cellular HFP SCO to CoreAudio devices
        )
    }

    /**
     * Pure function for testing capability derivation across permission permutations.
     */
    fun computeCapabilities(
        hasReadPhoneState: Boolean,
        hasAnswerCalls: Boolean,
        hasCallPhone: Boolean,
        hasReadCallLog: Boolean,
        hasReadContacts: Boolean,
        allowCallControl: Boolean,
        shareCallHistory: Boolean,
        simCount: Int = 1,
    ): TelephonyCapabilities = TelephonyCapabilities(
        canObserve = hasReadPhoneState,
        canAnswer = hasAnswerCalls && allowCallControl,
        canEnd = hasAnswerCalls && allowCallControl,
        canDial = hasCallPhone && allowCallControl,
        hasCallLog = hasReadCallLog && shareCallHistory,
        hasContacts = hasReadContacts,
        simCount = simCount.coerceAtLeast(1),
        btAudioPossible = false,
    )
}

