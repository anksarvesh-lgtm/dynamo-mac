// SPDX-License-Identifier: MIT
package app.maclink.companion.networking

import android.os.Handler
import android.os.Looper
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

enum class ConnectionState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    RECONNECTING
}

interface TouchpadConnectionListener {
    fun onStateChanged(state: ConnectionState)
    fun onLatencyMeasured(rttMs: Long)
    fun onMessageReceived(envelope: TouchpadEnvelope)
    fun onError(error: String)
}

class TouchpadWebSocketClient(
    val sessionId: String,
    private val listener: TouchpadConnectionListener? = null
) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    private var webSocket: WebSocket? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val isRunning = AtomicBoolean(false)

    var state: ConnectionState = ConnectionState.DISCONNECTED
        private set(value) {
            field = value
            mainHandler.post { listener?.onStateChanged(value) }
        }

    private var targetHost: String? = null
    private var targetPort: Int = 52400
    private var reconnectAttempts = 0
    private val seqTracker = SequenceTracker()
    private val coalescer = MovementCoalescer { sendEnvelope(it) }

    private var pingStartTimeMs = 0L

    private val heartbeatRunnable = object : Runnable {
        override fun run() {
            if (state == ConnectionState.CONNECTED) {
                sendPing()
                mainHandler.postDelayed(this, 2000L)
            }
        }
    }

    private val flushRunnable = object : Runnable {
        override fun run() {
            if (state == ConnectionState.CONNECTED) {
                coalescer.flushPendingMove(sessionId, seqTracker)
                mainHandler.postDelayed(this, 16L) // ~60fps flush for queued pointer movements
            }
        }
    }

    fun connect(host: String, port: Int = 52400) {
        targetHost = host
        targetPort = port
        isRunning.set(true)
        reconnectAttempts = 0
        doConnect()
    }

    private fun doConnect() {
        val host = targetHost ?: return
        state = if (reconnectAttempts > 0) ConnectionState.RECONNECTING else ConnectionState.CONNECTING

        val request = Request.Builder()
            .url("ws://$host:$targetPort/touchpad")
            .addHeader("X-MacLink-Session", sessionId)
            .addHeader("X-MacLink-Version", "1")
            .build()

        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) {
                reconnectAttempts = 0
                state = ConnectionState.CONNECTED
                mainHandler.post(heartbeatRunnable)
                mainHandler.post(flushRunnable)
            }

            override fun onMessage(ws: WebSocket, text: String) {
                val envelope = TouchpadEnvelope.fromJson(text) ?: return
                if (envelope.eventType == TouchpadEventType.CONNECTION_PONG) {
                    val now = System.currentTimeMillis()
                    val rtt = now - pingStartTimeMs
                    mainHandler.post { listener?.onLatencyMeasured(rtt) }
                } else {
                    mainHandler.post { listener?.onMessageReceived(envelope) }
                }
            }

            override fun onClosing(ws: WebSocket, code: Int, reason: String) {
                ws.close(1000, null)
                state = ConnectionState.DISCONNECTED
            }

            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                mainHandler.post { listener?.onError(t.localizedMessage ?: "WebSocket connection failed") }
                scheduleReconnect()
            }
        })
    }

    private fun scheduleReconnect() {
        if (!isRunning.get()) {
            state = ConnectionState.DISCONNECTED
            return
        }
        reconnectAttempts++
        state = ConnectionState.RECONNECTING
        val delay = (1000L * (1 shl reconnectAttempts.coerceAtMost(4))).coerceAtMost(8000L)
        mainHandler.postDelayed({ doConnect() }, delay)
    }

    fun sendEnvelope(envelope: TouchpadEnvelope): Boolean {
        val ws = webSocket ?: return false
        if (state != ConnectionState.CONNECTED) return false
        return ws.send(envelope.toJson())
    }

    fun queueGesture(gesture: app.maclink.companion.gestureengine.RecognizedGesture) {
        coalescer.queueGesture(gesture, sessionId, seqTracker)
    }

    private fun sendPing() {
        pingStartTimeMs = System.currentTimeMillis()
        val envelope = TouchpadEnvelope(
            version = 1,
            sessionId = sessionId,
            sequence = seqTracker.next(),
            eventType = TouchpadEventType.CONNECTION_PING,
            payload = mapOf("timestamp" to pingStartTimeMs)
        )
        sendEnvelope(envelope)
    }

    fun disconnect() {
        isRunning.set(false)
        mainHandler.removeCallbacks(heartbeatRunnable)
        mainHandler.removeCallbacks(flushRunnable)
        webSocket?.close(1000, "User disconnected")
        webSocket = null
        state = ConnectionState.DISCONNECTED
    }
}

