// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.telephony

import android.content.Context
import app.maclink.core.Call
import app.maclink.core.CallCommand
import app.maclink.core.CallLogEntry

/**
 * Protocol handler bridging UniFFI commands from Rust core to the Android telephony subsystems.
 */
class CallsProtocolHandler(
    private val context: Context,
    private val onCallChanged: (Call) -> Unit,
    private val onLogChanged: () -> Unit,
) {
    val settings = TelephonySettings.get(context)
    val contactResolver = ContactResolver(context)
    val controller = CallController(context, settings)
    val logRepository = CallLogRepository(context, settings)
    val monitor = CallStateMonitor(context, contactResolver, onCallChanged)

    fun start() {
        monitor.start()
    }

    fun stop() {
        monitor.stop()
    }

    /**
     * Dispatches a remote [CallCommand] received from the Mac.
     */
    fun handleCommand(callId: String, command: CallCommand): Boolean {
        val result = when (command) {
            is CallCommand.Answer -> controller.answerCall(callId)
            is CallCommand.Decline -> controller.endCall(callId)
            is CallCommand.Silence -> {
                // Silencing is handled on audio manager / phone calls
                CallCommandResult(callId, ok = true)
            }
            else -> {
                // Controls such as Mute/Speaker/Hold are dispatched via InCallService companion
                CallCommandResult(callId, ok = false, reason = "unsupported_companion_command")
            }
        }
        return result.ok
    }

    /**
     * Places an outgoing phone call requested by the Mac.
     */
    fun handleDial(number: String, simSlot: Int? = null): Boolean {
        monitor.updatePhoneNumber(number)
        val result = controller.placeCall(number, simSlot)
        return result.ok
    }

    /**
     * Reads recent call logs.
     */
    fun handleCallLog(before: Long?, limit: Int): List<CallLogEntry> {
        return logRepository.getRecentCalls(before, limit)
    }

    /**
     * Derives current capabilities to advertise to the Mac.
     */
    fun currentCapabilities(): TelephonyCapabilities {
        return TelephonyPermissions.deriveCapabilities(context, settings)
    }
}

