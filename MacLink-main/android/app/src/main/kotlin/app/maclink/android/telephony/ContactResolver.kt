// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.telephony

import android.content.Context
import android.net.Uri
import android.provider.ContactsContract
import java.util.Collections
import java.util.LinkedHashMap

/**
 * Resolves contact display names for phone numbers from the Android Contacts Provider.
 *
 * Implements an in-memory LRU cache of up to [MAX_CACHE_ENTRIES] to minimize SQLite queries
 * during active call state broadcasts. Preserves Unicode and Hindi (देवनागरी) text.
 */
class ContactResolver(
    private val context: Context,
    private val maxEntries: Int = MAX_CACHE_ENTRIES,
) {
    /** Synchronized LRU cache: key = normalized phone number, value = resolved name (or null if unlisted) */
    private val cache: MutableMap<String, String?> = Collections.synchronizedMap(
        object : LinkedHashMap<String, String?>(maxEntries + 1, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String?>?): Boolean =
                size > maxEntries
        }
    )

    fun cachedCount(): Int = cache.size

    fun getCached(number: String): String? = cache[normalize(number)]

    fun putInCache(number: String, name: String?) {
        cache[normalize(number)] = name
    }

    /**
     * Resolves the contact name for [number]. Returns cached value if present,
     * otherwise queries [ContactsContract.PhoneLookup].
     */
    fun resolveName(number: String?): String? {
        if (number.isNullOrBlank()) return null
        val normalized = normalize(number)
        if (cache.containsKey(normalized)) {
            return cache[normalized]
        }

        if (!TelephonyPermissions.hasReadContacts(context)) {
            return null
        }

        val name = queryPhoneLookup(normalized)
        cache[normalized] = name
        return name
    }

    private fun queryPhoneLookup(number: String): String? {
        return try {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(number)
            )
            val projection = arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME)
            context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val colIdx = cursor.getColumnIndex(ContactsContract.PhoneLookup.DISPLAY_NAME)
                    if (colIdx >= 0) cursor.getString(colIdx)?.takeIf { it.isNotBlank() } else null
                } else {
                    null
                }
            }
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        const val MAX_CACHE_ENTRIES = 50

        fun normalize(number: String): String =
            number.trim().replace(" ", "").replace("-", "")
    }
}

