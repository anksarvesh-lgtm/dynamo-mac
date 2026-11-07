// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.telephony

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TelephonyTests {

    @Test
    fun callControllerRejectsEmergencyNumbersAndUssd() {
        // Valid numbers return null (no validation error)
        assertNull(CallController.validatePhoneNumber("+1 (555) 123-4567"))
        assertNull(CallController.validatePhoneNumber("+91 98765 43210"))
        assertNull(CallController.validatePhoneNumber("555-0199"))
        assertNull(CallController.validatePhoneNumber("12345678"))

        // Empty / Whitespace
        assertEquals("empty", CallController.validatePhoneNumber(""))
        assertEquals("empty", CallController.validatePhoneNumber("   "))

        // Too long (> 32 chars)
        assertEquals("too_long", CallController.validatePhoneNumber("1".repeat(33)))

        // USSD / MMI codes prohibited
        assertEquals("ussd_prohibited", CallController.validatePhoneNumber("*21*12345#"))
        assertEquals("ussd_prohibited", CallController.validatePhoneNumber("#31#12345"))
        assertEquals("ussd_prohibited", CallController.validatePhoneNumber("*#06#"))

        // Non-digits / letters
        assertEquals("invalid_characters", CallController.validatePhoneNumber("123-ABC-456"))
        assertEquals("invalid_characters", CallController.validatePhoneNumber("555$0100"))
        assertEquals("no_digits", CallController.validatePhoneNumber("+() -"))

        // Global and regional emergency service numbers
        val emergency = listOf("112", "911", "999", "000", "100", "101", "102", "108", "988", "110", "119")
        for (em in emergency) {
            assertEquals("Blocked emergency $em", "emergency_number", CallController.validatePhoneNumber(em))
            assertTrue("Detected emergency $em", CallController.isEmergencyNumber(em))
            assertEquals("emergency_number", CallController.validatePhoneNumber(" $em "))
        }
    }

    @Test
    fun contactResolverCacheEvictionAndHindiNameHandling() {
        val resolver = ContactResolver(
            context = android.app.Application(),
            maxEntries = 3,
        )

        // Hindi (देवनागरी) and international Unicode names
        val hindiName1 = "अमित शर्मा"
        val hindiName2 = "प्रिया वर्मा"
        val englishName = "John Doe"
        val extraName = "Jane Smith"

        resolver.putInCache("+91 98765 43210", hindiName1)
        resolver.putInCache("+91 98765 43211", hindiName2)
        resolver.putInCache("+1 555 0100", englishName)

        assertEquals(3, resolver.cachedCount())
        assertEquals(hindiName1, resolver.getCached("+919876543210"))
        assertEquals(hindiName2, resolver.getCached("+91 98765-43211"))
        assertEquals(englishName, resolver.getCached("+15550100"))

        // Accessing first item so it becomes recently used
        resolver.getCached("+919876543210")

        // Inserting 4th item triggers LRU eviction of eldest entry (+91 98765 43211)
        resolver.putInCache("+1 555 0199", extraName)

        assertEquals(3, resolver.cachedCount())
        assertEquals(hindiName1, resolver.getCached("+919876543210"))
        assertNull(resolver.getCached("+91 98765 43211")) // Evicted
        assertEquals(englishName, resolver.getCached("+15550100"))
        assertEquals(extraName, resolver.getCached("+1 555 0199"))
    }

    @Test
    fun telephonyPermissionsDeriveCapabilities() {
        // Case 1: No permissions granted, switches off
        val caps1 = TelephonyPermissions.computeCapabilities(
            hasReadPhoneState = false,
            hasAnswerCalls = false,
            hasCallPhone = false,
            hasReadCallLog = false,
            hasReadContacts = false,
            allowCallControl = false,
            shareCallHistory = false,
        )
        assertFalse(caps1.canObserve)
        assertFalse(caps1.canAnswer)
        assertFalse(caps1.canEnd)
        assertFalse(caps1.canDial)
        assertFalse(caps1.hasCallLog)
        assertFalse(caps1.hasContacts)
        assertFalse(caps1.btAudioPossible)

        // Case 2: System permissions granted, but user switches are OFF
        val caps2 = TelephonyPermissions.computeCapabilities(
            hasReadPhoneState = true,
            hasAnswerCalls = true,
            hasCallPhone = true,
            hasReadCallLog = true,
            hasReadContacts = true,
            allowCallControl = false,
            shareCallHistory = false,
        )
        assertTrue(caps2.canObserve)
        assertTrue(caps2.hasContacts)
        assertFalse("Call control switch off must block answer", caps2.canAnswer)
        assertFalse("Call control switch off must block end", caps2.canEnd)
        assertFalse("Call control switch off must block dial", caps2.canDial)
        assertFalse("Call history switch off must block log", caps2.hasCallLog)
        assertFalse(caps2.btAudioPossible)

        // Case 3: System permissions granted and user switches are ON
        val caps3 = TelephonyPermissions.computeCapabilities(
            hasReadPhoneState = true,
            hasAnswerCalls = true,
            hasCallPhone = true,
            hasReadCallLog = true,
            hasReadContacts = true,
            allowCallControl = true,
            shareCallHistory = true,
            simCount = 2,
        )
        assertTrue(caps3.canObserve)
        assertTrue(caps3.canAnswer)
        assertTrue(caps3.canEnd)
        assertTrue(caps3.canDial)
        assertTrue(caps3.hasCallLog)
        assertTrue(caps3.hasContacts)
        assertEquals(2, caps3.simCount)
        assertFalse(caps3.btAudioPossible)

        // Case 4: Call control enabled, but CALL_PHONE permission missing
        val caps4 = TelephonyPermissions.computeCapabilities(
            hasReadPhoneState = true,
            hasAnswerCalls = true,
            hasCallPhone = false,
            hasReadCallLog = true,
            hasReadContacts = true,
            allowCallControl = true,
            shareCallHistory = true,
        )
        assertTrue(caps4.canAnswer)
        assertFalse("Missing CALL_PHONE must prevent dial", caps4.canDial)
    }
}

