// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.update

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppUpdaterTest {
    @Test
    fun versionsCompare() {
        assertTrue(AppUpdater.isNewer("0.1.0", "0.0.1"))
        assertTrue(AppUpdater.isNewer("1.0", "0.9.9"))
        assertTrue(AppUpdater.isNewer("0.2.0", "0.2.0-beta.1"))
        assertTrue(AppUpdater.isNewer("0.2.0-beta.2", "0.2.0-beta.1"))
        assertFalse(AppUpdater.isNewer("0.0.1", "0.0.1"))
        assertFalse(AppUpdater.isNewer("0.0.1", "0.1.0"))
        assertFalse(AppUpdater.isNewer("garbage", "0.1.0"))
    }

    @Test
    fun findsTheApkHash() {
        val hash = "a".repeat(64)
        val sums = "$hash  MacLink-9.0.0-android.apk\n${"b".repeat(64)}  MacLink-9.0.0-x64-setup.exe\n"
        assertEquals(hash, AppUpdater.listedHash(sums, "MacLink-9.0.0-android.apk"))
        assertNull(AppUpdater.listedHash(sums, "missing.apk"))
        assertEquals("c".repeat(64), AppUpdater.listedHash("${"C".repeat(64)} *x.apk", "x.apk"))
    }

    @Test
    fun readsTheFullSizeFromContentRange() {
        assertEquals(49_362_916L, AppUpdater.rangeTotal("bytes 1048576-49362915/49362916"))
        assertNull(AppUpdater.rangeTotal("bytes 0-99/*"))
        assertNull(AppUpdater.rangeTotal(null))
        assertNull(AppUpdater.rangeTotal("garbage"))
    }
}
