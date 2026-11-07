// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.ui.watch

import org.junit.Assert.assertEquals
import org.junit.Test

class ClockTest {
    @Test
    fun timesReadAsMinutesAndSecondsAndHoursWhenLong() {
        assertEquals("0:00", clock(0))
        assertEquals("0:09", clock(9_999))
        assertEquals("1:15", clock(75_000))
        assertEquals("59:59", clock(3_599_000))
        assertEquals("1:02:03", clock(3_723_000))
        assertEquals("0:00", clock(-5))
    }
}
