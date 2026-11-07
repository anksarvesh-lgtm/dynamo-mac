// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.telephony

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import androidx.core.content.ContextCompat
import app.maclink.android.calls.CallCompanion

/**
 * Result of a telephony command issued from the Mac.
 */
data class CallCommandResult(
    val callId: String?,
    val ok: Boolean,
    val reason: String? = null,
)

/**
 * Controls telephony actions (answer, reject, hang up, dial) on the Android device.
 *
 * Safety & Privacy:
 * - Checks [TelephonySettings.allowCallControl] first.
 * - Blocks USSD injection (* and # characters).
 * - Strictly rejects emergency numbers (e.g. 112, 911, 100, 108).
 * - Multi-SIM aware: selects specified SIM slot or defaults to primary phone account.
 */
class CallController(
    private val context: Context,
    private val settings: TelephonySettings = TelephonySettings.get(context),
) {
    private val telecomManager: TelecomManager? by lazy {
        context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
    }

    /**
     * Answers a ringing call.
     */
    @SuppressLint("MissingPermission")
    fun answerCall(callId: String?): CallCommandResult {
        if (!settings.allowCallControl) {
            return CallCommandResult(callId, ok = false, reason = "setting_off")
        }
        if (!TelephonyPermissions.hasAnswerCalls(context)) {
            return CallCommandResult(callId, ok = false, reason = "permission_missing")
        }

        if (CallCompanion.answer()) {
            return CallCommandResult(callId, ok = true)
        }

        val tm = telecomManager ?: return CallCommandResult(callId, ok = false, reason = "telecom_unavailable")
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                tm.acceptRingingCall()
                CallCommandResult(callId, ok = true)
            } else {
                CallCommandResult(callId, ok = false, reason = "unsupported_os_version")
            }
        } catch (e: SecurityException) {
            CallCommandResult(callId, ok = false, reason = "permission_missing")
        } catch (e: Exception) {
            CallCommandResult(callId, ok = false, reason = e.message ?: "failed")
        }
    }

    /**
     * Rejects or ends a ringing or active call.
     */
    @SuppressLint("MissingPermission")
    fun endCall(callId: String?): CallCommandResult {
        if (!settings.allowCallControl) {
            return CallCommandResult(callId, ok = false, reason = "setting_off")
        }
        if (!TelephonyPermissions.hasAnswerCalls(context)) {
            return CallCommandResult(callId, ok = false, reason = "permission_missing")
        }

        if (CallCompanion.hangUp()) {
            return CallCommandResult(callId, ok = true)
        }

        val tm = telecomManager ?: return CallCommandResult(callId, ok = false, reason = "telecom_unavailable")
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val ended = tm.endCall()
                if (ended) {
                    CallCommandResult(callId, ok = true)
                } else {
                    CallCommandResult(callId, ok = false, reason = "no_active_call")
                }
            } else {
                CallCommandResult(callId, ok = false, reason = "unsupported_os_version")
            }
        } catch (e: SecurityException) {
            CallCommandResult(callId, ok = false, reason = "permission_missing")
        } catch (e: Exception) {
            CallCommandResult(callId, ok = false, reason = e.message ?: "failed")
        }
    }

    /**
     * Dials a phone number through [TelecomManager].
     *
     * @param number The destination phone number.
     * @param simSlot Optional SIM slot index (0, 1) for multi-SIM devices.
     */
    @SuppressLint("MissingPermission")
    fun placeCall(number: String, simSlot: Int? = null): CallCommandResult {
        if (!settings.allowCallControl) {
            return CallCommandResult(null, ok = false, reason = "setting_off")
        }
        if (!TelephonyPermissions.hasCallPhone(context)) {
            return CallCommandResult(null, ok = false, reason = "permission_missing")
        }

        val validation = validatePhoneNumber(number)
        if (validation != null) {
            return CallCommandResult(null, ok = false, reason = validation)
        }

        val tm = telecomManager ?: return CallCommandResult(null, ok = false, reason = "telecom_unavailable")
        return try {
            val extras = Bundle()
            val phoneAccount = selectPhoneAccount(tm, simSlot)
            if (phoneAccount != null) {
                extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, phoneAccount)
            }

            val uri = Uri.fromParts("tel", number.trim(), null)
            tm.placeCall(uri, extras)
            CallCommandResult(null, ok = true)
        } catch (e: SecurityException) {
            CallCommandResult(null, ok = false, reason = "permission_missing")
        } catch (e: Exception) {
            CallCommandResult(null, ok = false, reason = e.message ?: "failed")
        }
    }

    @SuppressLint("MissingPermission")
    private fun selectPhoneAccount(tm: TelecomManager, simSlot: Int?): PhoneAccountHandle? {
        if (!TelephonyPermissions.hasReadPhoneState(context)) {
            return null
        }
        return try {
            val accounts = tm.callCapablePhoneAccounts
            if (simSlot != null && simSlot in accounts.indices) {
                accounts[simSlot]
            } else {
                tm.getDefaultOutgoingPhoneAccount(PhoneAccount.SCHEME_TEL) ?: accounts.firstOrNull()
            }
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        /**
         * Global and regional emergency service numbers.
         * Must never be remotely initiated by desktop link.
         */
        val EMERGENCY_NUMBERS: Set<String> = setOf(
            "000", "100", "101", "102", "108", "110", "112", "119", "120", "911", "988", "999", "1091", "1098"
        )

        /**
         * Checks whether [number] is an emergency telephone number.
         */
        fun isEmergencyNumber(number: String): Boolean {
            val digits = number.filter { it.isDigit() }
            if (digits.isEmpty()) return false
            return digits in EMERGENCY_NUMBERS
        }

        /**
         * Validates a phone number for remote dialing.
         * Returns null if valid, or a descriptive reason code on failure.
         */
        fun validatePhoneNumber(number: String): String? {
            val trimmed = number.trim()
            if (trimmed.isEmpty()) return "empty"
            if (trimmed.length > 32) return "too_long"
            if (trimmed.contains('*') || trimmed.contains('#')) return "ussd_prohibited"
            if (!trimmed.any { it.isDigit() }) return "no_digits"
            if (trimmed.any { !it.isDigit() && it !in "+ -()" }) return "invalid_characters"
            if (isEmergencyNumber(trimmed)) return "emergency_number"
            return null
        }
    }
}

