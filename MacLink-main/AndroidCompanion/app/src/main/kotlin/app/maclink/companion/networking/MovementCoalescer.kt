// SPDX-License-Identifier: MIT
package app.maclink.companion.networking

import app.maclink.companion.gestureengine.RecognizedGesture
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Coalesces high-frequency POINTER_MOVE and SCROLL deltas during network congestion,
 * while strictly guaranteeing that button down/up, clicks, and gestures are NEVER dropped.
 */
class MovementCoalescer(
    private val sendCallback: (TouchpadEnvelope) -> Unit
) {
    private val queue = ConcurrentLinkedQueue<TouchpadEnvelope>()
    private val isFlushing = AtomicBoolean(false)

    private var pendingMoveDx = 0f
    private var pendingMoveDy = 0f
    private val moveLock = Any()

    fun queueGesture(
        gesture: RecognizedGesture,
        sessionId: String,
        seqTracker: SequenceTracker
    ) {
        when (gesture) {
            is RecognizedGesture.PointerMove -> {
                synchronized(moveLock) {
                    pendingMoveDx += gesture.deltaX
                    pendingMoveDy += gesture.deltaY
                }
            }
            is RecognizedGesture.Click -> {
                flushPendingMove(sessionId, seqTracker)
                val type = when {
                    gesture.button == "right" -> TouchpadEventType.RIGHT_CLICK
                    gesture.count == 2 -> TouchpadEventType.DOUBLE_CLICK
                    else -> TouchpadEventType.LEFT_CLICK
                }
                val envelope = TouchpadEnvelope(
                    version = 1,
                    sessionId = sessionId,
                    sequence = seqTracker.next(),
                    eventType = type,
                    payload = mapOf("clicks" to gesture.count)
                )
                sendCallback(envelope)
            }
            is RecognizedGesture.Scroll -> {
                flushPendingMove(sessionId, seqTracker)
                val envelope = TouchpadEnvelope(
                    version = 1,
                    sessionId = sessionId,
                    sequence = seqTracker.next(),
                    eventType = TouchpadEventType.SCROLL,
                    payload = mapOf(
                        "deltaX" to gesture.deltaX.toDouble(),
                        "deltaY" to gesture.deltaY.toDouble(),
                        "isContinuous" to gesture.isContinuous,
                        "phase" to gesture.phase
                    )
                )
                sendCallback(envelope)
            }
            is RecognizedGesture.Swipe -> {
                flushPendingMove(sessionId, seqTracker)
                val envelope = TouchpadEnvelope(
                    version = 1,
                    sessionId = sessionId,
                    sequence = seqTracker.next(),
                    eventType = TouchpadEventType.SWIPE,
                    payload = mapOf(
                        "direction" to gesture.direction,
                        "fingers" to gesture.fingers,
                        "distance" to gesture.distance.toDouble()
                    )
                )
                sendCallback(envelope)
            }
            is RecognizedGesture.Pinch -> {
                flushPendingMove(sessionId, seqTracker)
                val envelope = TouchpadEnvelope(
                    version = 1,
                    sessionId = sessionId,
                    sequence = seqTracker.next(),
                    eventType = TouchpadEventType.PINCH,
                    payload = mapOf(
                        "scale" to gesture.scale.toDouble(),
                        "velocity" to gesture.velocity.toDouble(),
                        "phase" to gesture.phase
                    )
                )
                sendCallback(envelope)
            }
            is RecognizedGesture.Rotate -> {
                flushPendingMove(sessionId, seqTracker)
                val envelope = TouchpadEnvelope(
                    version = 1,
                    sessionId = sessionId,
                    sequence = seqTracker.next(),
                    eventType = TouchpadEventType.ROTATE,
                    payload = mapOf(
                        "rotation" to gesture.degrees.toDouble(),
                        "velocity" to gesture.velocity.toDouble(),
                        "phase" to gesture.phase
                    )
                )
                sendCallback(envelope)
            }
            is RecognizedGesture.DragStart -> {
                flushPendingMove(sessionId, seqTracker)
                val envelope = TouchpadEnvelope(
                    version = 1,
                    sessionId = sessionId,
                    sequence = seqTracker.next(),
                    eventType = TouchpadEventType.POINTER_DOWN,
                    payload = mapOf("button" to "left")
                )
                sendCallback(envelope)
            }
            is RecognizedGesture.DragMove -> {
                synchronized(moveLock) {
                    pendingMoveDx += gesture.deltaX
                    pendingMoveDy += gesture.deltaY
                }
            }
            is RecognizedGesture.DragEnd -> {
                flushPendingMove(sessionId, seqTracker)
                val envelope = TouchpadEnvelope(
                    version = 1,
                    sessionId = sessionId,
                    sequence = seqTracker.next(),
                    eventType = TouchpadEventType.POINTER_UP,
                    payload = mapOf("button" to "left")
                )
                sendCallback(envelope)
            }
        }
    }

    fun flushPendingMove(sessionId: String, seqTracker: SequenceTracker) {
        val dx: Float
        val dy: Float
        synchronized(moveLock) {
            dx = pendingMoveDx
            dy = pendingMoveDy
            pendingMoveDx = 0f
            pendingMoveDy = 0f
        }

        if (dx != 0f || dy != 0f) {
            val envelope = TouchpadEnvelope(
                version = 1,
                sessionId = sessionId,
                sequence = seqTracker.next(),
                eventType = TouchpadEventType.POINTER_MOVE,
                payload = mapOf(
                    "deltaX" to dx.toDouble(),
                    "deltaY" to dy.toDouble()
                )
            )
            sendCallback(envelope)
        }
    }
}

