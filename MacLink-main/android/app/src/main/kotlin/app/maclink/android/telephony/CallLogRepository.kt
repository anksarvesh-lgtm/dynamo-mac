// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.telephony

import android.content.Context
import android.provider.CallLog
import app.maclink.core.CallLogEntry

/**
 * Accesses recent call history with pagination and privacy filtering.
 *
 * Rules:
 * - Requires [TelephonySettings.shareCallHistory] to be enabled by user.
 * - Requires [android.Manifest.permission.READ_CALL_LOG].
 * - Queries minimal projection columns.
 * - Sorts by [CallLog.Calls.DATE] descending.
 * - Withheld/unknown numbers are properly anonymized.
 */
class CallLogRepository(
    private val context: Context,
    private val settings: TelephonySettings = TelephonySettings.get(context),
) {

    /**
     * Reads a page of recent call logs.
     *
     * @param before Unix milliseconds timestamp; only calls older than this are returned.
     * @param limit Maximum number of entries to return (capped at [MAX_LIMIT]).
     */
    fun getRecentCalls(before: Long?, limit: Int): List<CallLogEntry> {
        if (!settings.shareCallHistory) {
            return emptyList()
        }
        if (!TelephonyPermissions.hasReadCallLog(context)) {
            return emptyList()
        }

        val safeLimit = limit.coerceIn(1, MAX_LIMIT)
        val selection = if (before != null) "${CallLog.Calls.DATE} < ?" else null
        val selectionArgs = if (before != null) arrayOf(before.toString()) else null
        val sortOrder = "${CallLog.Calls.DATE} DESC LIMIT $safeLimit"

        val projection = arrayOf(
            CallLog.Calls._ID,
            CallLog.Calls.NUMBER,
            CallLog.Calls.CACHED_NAME,
            CallLog.Calls.TYPE,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION,
        )

        val results = mutableListOf<CallLogEntry>()
        try {
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )?.use { cursor ->
                val idIdx = cursor.getColumnIndex(CallLog.Calls._ID)
                val numIdx = cursor.getColumnIndex(CallLog.Calls.NUMBER)
                val nameIdx = cursor.getColumnIndex(CallLog.Calls.CACHED_NAME)
                val typeIdx = cursor.getColumnIndex(CallLog.Calls.TYPE)
                val dateIdx = cursor.getColumnIndex(CallLog.Calls.DATE)
                val durIdx = cursor.getColumnIndex(CallLog.Calls.DURATION)

                while (cursor.moveToNext()) {
                    val rawId = if (idIdx >= 0) cursor.getString(idIdx) else ""
                    val rawNum = if (numIdx >= 0) cursor.getString(numIdx).orEmpty() else ""
                    val rawName = if (nameIdx >= 0) cursor.getString(nameIdx) else null
                    val rawType = if (typeIdx >= 0) cursor.getInt(typeIdx) else CallLog.Calls.INCOMING_TYPE
                    val date = if (dateIdx >= 0) cursor.getLong(dateIdx) else 0L
                    val duration = if (durIdx >= 0) cursor.getLong(durIdx).toUInt() else 0u

                    val cleanNumber = cleanPhoneNumber(rawNum)
                    val direction = mapDirection(rawType)

                    results.add(
                        CallLogEntry(
                            id = rawId,
                            number = cleanNumber,
                            name = rawName?.takeIf { it.isNotBlank() },
                            direction = direction,
                            date = date,
                            duration = duration,
                            photo = null,
                        )
                    )
                }
            }
        } catch (e: Exception) {
            // Handled gracefully: returns whatever entries were parsed
        }
        return results
    }

    companion object {
        const val MAX_LIMIT = 100

        fun cleanPhoneNumber(raw: String): String {
            val trimmed = raw.trim()
            if (trimmed.isEmpty() || trimmed == "-1" || trimmed == "-2" ||
                trimmed.equals("UNKNOWN", ignoreCase = true) ||
                trimmed.equals("PRIVATE", ignoreCase = true)
            ) {
                return "Unknown"
            }
            return trimmed
        }

        fun mapDirection(type: Int): String = when (type) {
            CallLog.Calls.INCOMING_TYPE -> "incoming"
            CallLog.Calls.OUTGOING_TYPE -> "outgoing"
            CallLog.Calls.MISSED_TYPE -> "missed"
            CallLog.Calls.REJECTED_TYPE -> "rejected"
            CallLog.Calls.BLOCKED_TYPE -> "rejected"
            else -> "incoming"
        }
    }
}

