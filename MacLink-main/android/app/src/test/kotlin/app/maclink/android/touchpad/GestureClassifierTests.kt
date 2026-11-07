// SPDX-License-Identifier: MIT
package app.maclink.android.touchpad

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GestureClassifierTests {

    private class TestListener : GestureListener {
        val recognized = mutableListOf<RecognizedGesture>()
        val haptics = mutableListOf<HapticGestureTrigger>()

        override fun onGestureRecognized(gesture: RecognizedGesture) {
            recognized.add(gesture)
        }

        override fun onHapticRequested(trigger: HapticGestureTrigger) {
            haptics.add(trigger)
        }
    }

    @Test
    fun testPointerAccelerationSeparatedFromScroll() {
        val processor = CoordinateProcessor(pointerSensitivity = 1.0f, scrollSensitivity = 1.0f, naturalScroll = true)

        val (pDx, _) = processor.processPointerDelta(20f, 0f)
        assertTrue("Pointer delta should be accelerated: $pDx", pDx > 20f)

        val (sDx, sDy) = processor.processScrollDelta(20f, -10f)
        assertEquals(-20f, sDx, 0.001f)
        assertEquals(10f, sDy, 0.001f)
    }

    @Test
    fun testSingleTapProducesClickAndLocalHaptic() {
        val processor = CoordinateProcessor()
        val listener = TestListener()
        val classifier = GestureClassifier(processor, listener)

        classifier.onPointerDown(0, 100f, 100f, 100L)
        classifier.onPointerUp(0, 100f, 100f, 200L)

        assertEquals(1, listener.haptics.size)
        assertEquals(HapticGestureTrigger.SINGLE_CLICK, listener.haptics[0])

        assertEquals(1, listener.recognized.size)
        val click = listener.recognized[0] as? RecognizedGesture.Click
        assertNotNull(click)
        assertEquals("left", click?.button)
        assertEquals(1, click?.count)
    }

    @Test
    fun testDoubleTapProducesDoubleTapHapticAndDoubleClick() {
        val processor = CoordinateProcessor()
        val listener = TestListener()
        val classifier = GestureClassifier(processor, listener)

        classifier.onPointerDown(0, 100f, 100f, 100L)
        classifier.onPointerUp(0, 100f, 100f, 150L)

        classifier.onPointerDown(0, 102f, 101f, 250L)
        classifier.onPointerUp(0, 102f, 101f, 300L)

        assertEquals(2, listener.haptics.size)
        assertEquals(HapticGestureTrigger.SINGLE_CLICK, listener.haptics[0])
        assertEquals(HapticGestureTrigger.DOUBLE_CLICK, listener.haptics[1])

        assertEquals(2, listener.recognized.size)
        val click2 = listener.recognized[1] as? RecognizedGesture.Click
        assertNotNull(click2)
        assertEquals("left", click2?.button)
        assertEquals(2, click2?.count)
    }

    @Test
    fun testTwoFingerTapProducesRightClick() {
        val processor = CoordinateProcessor()
        val listener = TestListener()
        val classifier = GestureClassifier(processor, listener)

        classifier.onPointerDown(0, 100f, 100f, 100L)
        classifier.onPointerDown(1, 150f, 100f, 110L)

        classifier.onPointerUp(1, 150f, 100f, 180L)
        classifier.onPointerUp(0, 100f, 100f, 190L)

        assertTrue("Should request right click haptic", listener.haptics.contains(HapticGestureTrigger.RIGHT_CLICK))
        val rightClick = listener.recognized.filterIsInstance<RecognizedGesture.Click>().firstOrNull { it.button == "right" }
        assertNotNull("Should recognize right click", rightClick)
    }

    @Test
    fun testThreeFingerSwipeUp() {
        val processor = CoordinateProcessor()
        val listener = TestListener()
        val classifier = GestureClassifier(processor, listener)

        classifier.onPointerDown(0, 100f, 300f, 100L)
        classifier.onPointerDown(1, 150f, 300f, 100L)
        classifier.onPointerDown(2, 200f, 300f, 100L)

        classifier.onPointerMove(0, 100f, 200f, 150L)
        classifier.onPointerMove(1, 150f, 200f, 150L)
        classifier.onPointerMove(2, 200f, 200f, 150L)

        assertTrue(listener.haptics.contains(HapticGestureTrigger.GESTURE_COMPLETE))
        val swipe = listener.recognized.filterIsInstance<RecognizedGesture.Swipe>().firstOrNull()
        assertNotNull(swipe)
        assertEquals("up", swipe?.direction)
        assertEquals(3, swipe?.fingers)
    }
}

