// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.telephony

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat
import app.maclink.core.Call
import app.maclink.core.CallPhase
import java.util.UUID

/**
 * Monitors telephony call state transitions using [TelephonyCallback] on Android 12+ (API 31+)
 * and [PhoneStateListener] on older supported versions.
 */
class CallStateMonitor(
    private val context: Context,
    private val contactResolver: ContactResolver = ContactResolver(context),
    private val onCallChanged: (Call) -> Unit,
) {
    private val telephonyManager: TelephonyManager? by lazy {
        context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
    }

    private var telephonyCallback: Any? = null
    private var phoneStateListener: PhoneStateListener? = null

    /** Current call tracked across state transitions. */
    @Volatile
    private var activeCallId: String? = null
    @Volatile
    private var activeCallIncoming: Boolean = true
    @Volatile
    private var activeCallNumber: String? = null
    @Volatile
    private var activeCallName: String? = null
    @Volatile
    private var wasRinging: Boolean = false
    @Volatile
    private var wasAnswered: Boolean = false
    @Volatile
    private var startTimeMs: Long? = null

    /**
     * Starts listening for telephony state changes.
     */
    @SuppressLint("MissingPermission")
    fun start() {
        val tm = telephonyManager ?: return
        if (!TelephonyPermissions.hasReadPhoneState(context)) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    handleCallState(state, null)
                }
            }
            telephonyCallback = callback
            try {
                tm.registerTelephonyCallback(ContextCompat.getMainExecutor(context), callback)
            } catch (e: Exception) {
                // Handled gracefully
            }
        } else {
            @Suppress("DEPRECATION")
            val listener = object : PhoneStateListener() {
                @Deprecated("Deprecated in Java")
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    handleCallState(state, phoneNumber?.takeIf { it.isNotBlank() })
                }
            }
            phoneStateListener = listener
            try {
                @Suppress("DEPRECATION")
                tm.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
            } catch (e: Exception) {
                // Handled gracefully
            }
        }
    }

    /**
     * Stops listening for telephony state changes.
     */
    fun stop() {
        val tm = telephonyManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (telephonyCallback as? TelephonyCallback)?.let {
                try {
                    tm.unregisterTelephonyCallback(it)
                } catch (e: Exception) {
                    // Ignored
                }
            }
            telephonyCallback = null
        } else {
            phoneStateListener?.let {
                try {
                    @Suppress("DEPRECATION")
                    tm.listen(it, PhoneStateListener.LISTEN_NONE)
                } catch (e: Exception) {
                    // Ignored
                }
            }
            phoneStateListener = null
        }
    }

    /**
     * Informs the monitor of a known phone number (e.g. from outgoing dial or incoming notification).
     */
    fun updatePhoneNumber(number: String?) {
        if (!number.isNullOrBlank()) {
            activeCallNumber = number
            activeCallName = contactResolver.resolveName(number)
        }
    }

    private fun handleCallState(state: Int, number: String?) {
        if (!number.isNullOrBlank()) {
            updatePhoneNumber(number)
        }

        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                val callId = activeCallId ?: UUID.randomUUID().toString().also { activeCallId = it }
                activeCallIncoming = true
                wasRinging = true
                wasAnswered = false
                startTimeMs = null

                val call = Call(
                    id = callId,
                    state = CallPhase.RINGING,
                    incoming = true,
                    number = activeCallNumber,
                    name = activeCallName,
                    photo = null,
                    missed = false,
                    since = null,
                    controls = null,
                )
                onCallChanged(call)
            }

            TelephonyManager.CALL_STATE_OFFHOOK -> {
                val callId = activeCallId ?: UUID.randomUUID().toString().also { activeCallId = it }
                val isIncoming = wasRinging
                activeCallIncoming = isIncoming
                wasAnswered = true
                val since = startTimeMs ?: System.currentTimeMillis().also { startTimeMs = it }

                val call = Call(
                    id = callId,
                    state = CallPhase.ACTIVE,
                    incoming = isIncoming,
                    number = activeCallNumber,
                    name = activeCallName,
                    photo = null,
                    missed = false,
                    since = since,
                    controls = null,
                )
                onCallChanged(call)
            }

            TelephonyManager.CALL_STATE_IDLE -> {
                val callId = activeCallId
                if (callId != null) {
                    val missed = wasRinging && !wasAnswered
                    val call = Call(
                        id = callId,
                        state = CallPhase.ENDED,
                        incoming = activeCallIncoming,
                        number = activeCallNumber,
                        name = activeCallName,
                        photo = null,
                        missed = missed,
                        since = startTimeMs,
                        controls = null,
                    )
                    onCallChanged(call)
                }

                // Reset tracked state
                activeCallId = null
                activeCallNumber = null
                activeCallName = null
                wasRinging = false
                wasAnswered = false
                startTimeMs = null
            }
        }
    }
}

