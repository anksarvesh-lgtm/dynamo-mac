// SPDX-License-Identifier: MIT
package app.maclink.companion

import app.maclink.companion.gestureengine.RecognizedGesture
import app.maclink.companion.networking.MovementCoalescer
import app.maclink.companion.networking.SequenceTracker
import app.maclink.companion.networking.TouchpadEnvelope
import app.maclink.companion.networking.TouchpadEventType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MovementCoalescerTests {

    @Test
    fun testPointerMoveCoalescing() {
        val emitted = mutableListOf<TouchpadEnvelope>()
        val coalescer = MovementCoalescer { emitted.add(it) }
        val seqTracker = SequenceTracker()
        val sessionId = "test-session-12345"

        // Queue 3 move deltas
        coalescer.queueGesture(RecognizedGesture.PointerMove(5f, 2f), sessionId, seqTracker)
        coalescer.queueGesture(RecognizedGesture.PointerMove(3f, -1f), sessionId, seqTracker)
        coalescer.queueGesture(RecognizedGesture.PointerMove(2f, 4f), sessionId, seqTracker)

        // Prior to flush, no packet is sent
        assertEquals(0, emitted.size)

        // Flush
        coalescer.flushPendingMove(sessionId, seqTracker)
        assertEquals(1, emitted.size)
        val env = emitted[0]
        assertEquals(TouchpadEventType.POINTER_MOVE, env.eventType)
        assertEquals(10.0, env.payload["deltaX"] as Double, 0.001)
        assertEquals(5.0, env.payload["deltaY"] as Double, 0.001)
        assertEquals(1L, env.sequence)
    }

    @Test
    fun testClickFlushesPendingMoveAndNeverDrops() {
        val emitted = mutableListOf<TouchpadEnvelope>()
        val coalescer = MovementCoalescer { emitted.add(it) }
        val seqTracker = SequenceTracker()
        val sessionId = "test-session-12345"

        coalescer.queueGesture(RecognizedGesture.PointerMove(4f, 8f), sessionId, seqTracker)
        // Click arrives
        coalescer.queueGesture(RecognizedGesture.Click(button = "left", count = 1), sessionId, seqTracker)

        // Should have flushed the move FIRST, then sent the click
        assertEquals(2, emitted.size)
        assertEquals(TouchpadEventType.POINTER_MOVE, emitted[0].eventType)
        assertEquals(TouchpadEventType.LEFT_CLICK, emitted[1].eventType)
        assertEquals(1L, emitted[0].sequence)
        assertEquals(2L, emitted[1].sequence)
    }
}

