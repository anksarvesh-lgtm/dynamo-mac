// SPDX-License-Identifier: MIT
package app.maclink.companion

import app.maclink.companion.gestureengine.HapticGestureTrigger
import app.maclink.companion.haptics.HapticCapabilities
import app.maclink.companion.haptics.HapticProfile
import app.maclink.companion.haptics.HapticProfileManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HapticEngineTests {

    @Test
    fun testProfileManagerGeneratesEffectsForAllTriggers() {
        val manager = HapticProfileManager()
        val caps = HapticCapabilities(hasVibrator = true, hasAmplitudeControl = true, supportsPrimitives = false)

        for (trigger in HapticGestureTrigger.entries) {
            val params = manager.calculateParams(trigger, caps)
            assertNotNull("Params should be generated for $trigger", params)
            assertTrue("Duration or waveform must be present", params.durationMs > 0L || params.timings != null)
        }
    }

    @Test
    fun testNaturalVsStandardVsEnhancedProfiles() {
        val caps = HapticCapabilities(hasVibrator = true, hasAmplitudeControl = true, supportsPrimitives = false)

        val naturalMgr = HapticProfileManager(activeProfile = HapticProfile.NATURAL)
        val standardMgr = HapticProfileManager(activeProfile = HapticProfile.STANDARD)
        val enhancedMgr = HapticProfileManager(activeProfile = HapticProfile.ENHANCED)

        val naturalParams = naturalMgr.calculateParams(HapticGestureTrigger.SINGLE_CLICK, caps)
        val standardParams = standardMgr.calculateParams(HapticGestureTrigger.SINGLE_CLICK, caps)
        val enhancedParams = enhancedMgr.calculateParams(HapticGestureTrigger.SINGLE_CLICK, caps)

        assertTrue(naturalParams.amplitude < standardParams.amplitude)
        assertTrue(standardParams.amplitude < enhancedParams.amplitude)
        assertEquals(10L, naturalParams.durationMs)
        assertEquals(15L, standardParams.durationMs)
    }

    @Test
    fun testUserIntensityClamping() {
        val caps = HapticCapabilities(hasVibrator = true, hasAmplitudeControl = true, supportsPrimitives = false)
        val manager = HapticProfileManager(activeProfile = HapticProfile.ENHANCED, userIntensity = 1.5f)

        val params = manager.calculateParams(HapticGestureTrigger.SINGLE_CLICK, caps)
        assertEquals(255, params.amplitude)
    }
}
