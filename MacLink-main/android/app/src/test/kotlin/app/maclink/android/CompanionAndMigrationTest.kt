// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android

import app.maclink.android.companion.PcCompanion
import app.maclink.android.ui.Preferences
import app.maclink.android.ui.theme.Appearance
import app.maclink.android.ui.theme.Tokens
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CompanionAndMigrationTest {

    @Test
    fun `PcCompanion buildBeaconPayload and buildBeaconMask encode 5-byte magic and 8-byte device ID prefix`() {
        val hexId = "0123456789abcdef-fedcba9876543210"
        val payload = PcCompanion.buildBeaconPayload(hexId)
        assertEquals(13, payload.size)
        assertArrayEquals(
            byteArrayOf(
                'N'.code.toByte(),
                'C'.code.toByte(),
                'T'.code.toByte(),
                'R'.code.toByte(),
                1,
                0x01,
                0x23,
                0x45,
                0x67,
                0x89.toByte(),
                0xAB.toByte(),
                0xCD.toByte(),
                0xEF.toByte(),
            ),
            payload,
        )

        val maskWithId = PcCompanion.buildBeaconMask(hasDeviceId = true)
        assertEquals(13, maskWithId.size)
        assertTrue(maskWithId.all { it == 0xFF.toByte() })

        val shortPayload = PcCompanion.buildBeaconPayload("abcd")
        assertArrayEquals(PcCompanion.BEACON_MAGIC, shortPayload)
        assertArrayEquals(PcCompanion.BEACON_MAGIC, PcCompanion.buildBeaconPayload(null))

        val maskWithoutId = PcCompanion.buildBeaconMask(hasDeviceId = false)
        assertEquals(5, maskWithoutId.size)
        assertTrue(maskWithoutId.all { it == 0xFF.toByte() })
    }

    @Test
    fun `Preferences sanitizeAppearance falls back on unknown legacy theme, mode, and seed values`() {
        val legacy = Preferences.sanitizeAppearance(
            theme = "sepia",
            mode = "neon",
            seed = "cyberpunk",
            dynamicColor = false,
        )
        assertEquals("glass", legacy.theme)
        assertEquals("system", legacy.mode)
        assertEquals(Tokens.DEFAULT_SEED, legacy.seed)
        assertFalse(legacy.dynamicColor)

        val empty = Preferences.sanitizeAppearance(
            Appearance(theme = "", mode = "", seed = "", dynamicColor = true),
        )
        assertEquals("glass", empty.theme)
        assertEquals("system", empty.mode)
        assertEquals(Tokens.DEFAULT_SEED, empty.seed)
        assertTrue(empty.dynamicColor)

        val valid = Preferences.sanitizeAppearance(
            theme = "graphite",
            mode = "dark",
            seed = "ocean",
            dynamicColor = false,
        )
        assertEquals("graphite", valid.theme)
        assertEquals("dark", valid.mode)
        assertEquals("ocean", valid.seed)
        assertFalse(valid.dynamicColor)
    }
}
