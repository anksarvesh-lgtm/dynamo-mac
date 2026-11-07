// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtTest
import app.maclink

// A SwitchBar reports the user's choice, shows its caption only when there
// is one, and takes no input while greyed out.
Item {
    id: root
    width: 360
    height: 60

    SwitchBar {
        id: bar
        x: 10
        y: 8
        width: 320
        iconPath: Icons.video
        title: "Play on phone"
    }

    SignalSpy {
        id: toggled
        target: bar
        signalName: "toggled"
    }

    TestCase {
        name: "SwitchBar"
        when: windowShown

        function init() {
            bar.enabled = true
            bar.checked = false
            bar.caption = ""
            toggled.clear()
        }

        function test_a_click_on_the_switch_reports_on() {
            mouseClick(bar, bar.width - 30, bar.height / 2)
            compare(toggled.count, 1)
            compare(toggled.signalArguments[0][0], true)
            verify(!bar.checked, "the owner decides")
        }

        function test_a_greyed_out_bar_takes_no_click() {
            bar.enabled = false
            mouseClick(bar, bar.width - 30, bar.height / 2)
            compare(toggled.count, 0)
        }

        function test_the_caption_shows_only_when_set() {
            bar.caption = "Watching on Pixel"
            verify(hasText(bar, "Watching on Pixel"))
            bar.caption = ""
            verify(!hasText(bar, "Watching on Pixel"))
        }

        // Whether a visible text item under `item` shows `text`.
        function hasText(item, text) {
            for (let i = 0; i < item.children.length; i++) {
                const child = item.children[i]
                if (child.visible && child.text === text)
                    return true
                if (child.visible && hasText(child, text))
                    return true
            }
            return false
        }
    }
}
