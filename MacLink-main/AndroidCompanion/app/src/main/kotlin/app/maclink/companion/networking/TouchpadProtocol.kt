// SPDX-License-Identifier: MIT
package app.maclink.companion.networking

import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicLong

enum class TouchpadEventType(val wireName: String) {
    POINTER_MOVE("POINTER_MOVE"),
    POINTER_DOWN("POINTER_DOWN"),
    POINTER_UP("POINTER_UP"),
    LEFT_CLICK("LEFT_CLICK"),
    RIGHT_CLICK("RIGHT_CLICK"),
    DOUBLE_CLICK("DOUBLE_CLICK"),
    SCROLL("SCROLL"),
    PINCH("PINCH"),
    ROTATE("ROTATE"),
    SWIPE("SWIPE"),
    KEY_DOWN("KEY_DOWN"),
    KEY_UP("KEY_UP"),
    GESTURE_START("GESTURE_START"),
    GESTURE_END("GESTURE_END"),
    GESTURE_CANCEL("GESTURE_CANCEL"),
    CONNECTION_PING("CONNECTION_PING"),
    CONNECTION_PONG("CONNECTION_PONG"),
    DEVICE_STATUS("DEVICE_STATUS");

    companion object {
        fun fromWire(name: String): TouchpadEventType? = entries.firstOrNull { it.wireName == name }
    }
}

data class TouchpadEnvelope(
    val version: Int = 1,
    val sessionId: String,
    val sequence: Long,
    val timestamp: Long = System.currentTimeMillis(),
    val eventType: TouchpadEventType,
    val payload: Map<String, Any>
) {
    fun toJson(): String {
        val root = JSONObject()
        root.put("version", version)
        root.put("sessionId", sessionId)
        root.put("sequence", sequence)
        root.put("timestamp", timestamp)
        root.put("eventType", eventType.wireName)

        val payloadObj = JSONObject()
        for ((key, value) in payload) {
            when (value) {
                is List<*> -> {
                    val arr = JSONArray()
                    value.forEach { arr.put(it) }
                    payloadObj.put(key, arr)
                }
                else -> payloadObj.put(key, value)
            }
        }
        root.put("payload", payloadObj)
        return root.toString()
    }

    companion object {
        fun fromJson(jsonStr: String): TouchpadEnvelope? {
            return try {
                val root = JSONObject(jsonStr)
                val version = root.getInt("version")
                val sessionId = root.getString("sessionId")
                val sequence = root.getLong("sequence")
                val timestamp = root.getLong("timestamp")
                val eventType = TouchpadEventType.fromWire(root.getString("eventType")) ?: return null

                val payloadObj = root.getJSONObject("payload")
                val map = mutableMapOf<String, Any>()
                val keys = payloadObj.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    map[k] = payloadObj.get(k)
                }
                TouchpadEnvelope(version, sessionId, sequence, timestamp, eventType, map)
            } catch (_: Exception) {
                null
            }
        }
    }
}

class SequenceTracker(initial: Long = 0) {
    private val seq = AtomicLong(initial)

    fun next(): Long = seq.incrementAndGet()

    fun reset(value: Long = 0) {
        seq.set(value)
    }

    val current: Long get() = seq.get()
}

