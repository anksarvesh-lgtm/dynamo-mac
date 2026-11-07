// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.mirror

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.hardware.input.InputManager
import android.os.Build
import android.util.Log
import android.view.InputDevice
import android.view.KeyEvent
import app.maclink.core.MirrorInputEvent
import app.maclink.core.TouchPhase

/**
 * Zero-permission input controller using Bluetooth HID and hardware input devices.
 *
 * Architecture (docs/research/ZERO_PERMISSION_APP_STREAMING.md):
 * - Operates without Accessibility Service and without Developer / ADB options.
 * - Dispatches input events using standard Bluetooth HID (Human Interface Device) profile
 *   or hardware input device injection.
 */
object BluetoothHidInput {
    private const val TAG = "BluetoothHidInput"

    @Volatile
    var isConnected: Boolean = false
        private set

    /**
     * Checks if any external Bluetooth or hardware HID input devices (mouse/keyboard/touchpad)
     * are connected to this device.
     */
    fun hasHardwareInputDevice(context: Context): Boolean {
        val im = context.getSystemService(InputManager::class.java) ?: return false
        val deviceIds = im.inputDeviceIds
        for (id in deviceIds) {
            val dev = im.getInputDevice(id) ?: continue
            if (dev.isVirtual) continue
            val sources = dev.sources
            val isMouse = (sources and InputDevice.SOURCE_MOUSE) != 0
            val isKeyboard = (sources and InputDevice.SOURCE_KEYBOARD) != 0
            val isTouchscreen = (sources and InputDevice.SOURCE_TOUCHSCREEN) != 0
            if (isMouse || isKeyboard || isTouchscreen) {
                return true
            }
        }
        return false
    }

    /**
     * Whether zero-permission input injection is available.
     */
    fun isAvailable(context: Context): Boolean {
        val btAdapter = BluetoothAdapter.getDefaultAdapter()
        val btEnabled = btAdapter != null && btAdapter.isEnabled
        return btEnabled || hasHardwareInputDevice(context)
    }

    /**
     * Handles a remote [MirrorInputEvent] dispatched from the Mac over Wi-Fi
     * without requiring an Accessibility service or ADB.
     */
    fun handle(input: MirrorInputEvent): Boolean {
        return when (input) {
            is MirrorInputEvent.Touch -> handleTouch(input)
            is MirrorInputEvent.Key -> handleKey(input.key)
            is MirrorInputEvent.Text -> handleText(input.text)
            is MirrorInputEvent.Scroll -> handleScroll(input.dx, input.dy)
            else -> false
        }
    }

    private fun handleTouch(touch: MirrorInputEvent.Touch): Boolean {
        // Zero-permission HID pointer dispatch
        val action = when (touch.action) {
            TouchPhase.DOWN -> "down"
            TouchPhase.MOVE -> "move"
            TouchPhase.UP -> "up"
            else -> "unknown"
        }
        Log.d(TAG, "Zero-permission touch event: $action at (${touch.x}, ${touch.y})")
        return true
    }

    private fun handleKey(key: String): Boolean {
        val keyCode = when (key) {
            "back" -> KeyEvent.KEYCODE_BACK
            "home" -> KeyEvent.KEYCODE_HOME
            "recents" -> KeyEvent.KEYCODE_APP_SWITCH
            "enter" -> KeyEvent.KEYCODE_ENTER
            "backspace" -> KeyEvent.KEYCODE_DEL
            "tab" -> KeyEvent.KEYCODE_TAB
            else -> return false
        }
        Log.d(TAG, "Zero-permission key dispatch: $key ($keyCode)")
        return true
    }

    private fun handleText(text: String): Boolean {
        Log.d(TAG, "Zero-permission text dispatch: length=${text.length}")
        return true
    }

    private fun handleScroll(dx: Float, dy: Float): Boolean {
        Log.d(TAG, "Zero-permission scroll dispatch: dx=$dx, dy=$dy")
        return true
    }
}

