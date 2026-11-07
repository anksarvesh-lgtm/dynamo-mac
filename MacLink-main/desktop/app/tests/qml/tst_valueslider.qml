// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtTest
import app.maclink

// A ValueSlider reports steps within its range, from the keyboard and a
// click, and leaves its value to its owner.
Item {
    id: root
    width: 300
    height: 60

    ValueSlider {
        id: slider
        x: 10
        y: 20
        width: 200
        from: 50
        to: 400
        step: 10
        value: 100
        label: "Microphone volume"
    }

    SignalSpy {
        id: moved
        target: slider
        signalName: "moved"
    }

    TestCase {
        name: "ValueSlider"
        when: windowShown

        function init() {
            slider.value = 100
            moved.clear()
            slider.forceActiveFocus()
        }

        function test_arrow_keys_step_and_stop_at_the_ends() {
            keyClick(Qt.Key_Right)
            compare(moved.signalArguments[0][0], 110)
            compare(slider.value, 100, "the owner sets the value")
            slider.value = 400
            moved.clear()
            keyClick(Qt.Key_Right)
            compare(moved.count, 0, "nothing past the end")
            keyClick(Qt.Key_Home)
            compare(moved.signalArguments[0][0], 50)
        }

        function test_a_click_picks_the_value_there() {
            // Three quarters along 50..400 is 312.5, a step of 10 makes 310.
            mouseClick(slider, slider.width * 0.75, slider.height / 2)
            compare(moved.signalArguments[0][0], 310)
        }
    }
}
