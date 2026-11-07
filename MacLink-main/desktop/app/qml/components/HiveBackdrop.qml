// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

// Modern Task Manager Telemetry Backdrop (replaces legacy hive honeycomb shader).
// Preserves all properties and clock bindings for complete backward compatibility.
Item {
    id: hive

    property bool animate: true
    property bool paused: false
    property bool ownClock: true
    property bool growIn: true
    property real cell: 24
    property real strength: 1
    property color lineColor: Qt.rgba(1, 1, 1, 0.08)
    property color glowColor: Qt.rgba(1, 1, 1, 0.12)
    property point origin: Qt.point(width / 2, height / 3)
    property int frameMs: 33
    property real breathSeconds: 6.0
    property real pulseSeconds: 4.5
    property real corner: 0
    property real reach: 0.62
    property real pulseReach: 0.75

    readonly property size itemSize: Qt.size(width, height)
    readonly property real pulse: animate ? 1 : 0
    readonly property real breathPeriod: breathSeconds
    readonly property real pulsePeriod: pulseSeconds
    property real time: 0
    property real grow: 1
    readonly property real reveal: grow * Math.hypot(width, height)

    Canvas {
        anchors.fill: parent
        visible: hive.visible && hive.opacity > 0
        opacity: 0.15

        onPaint: {
            let ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = hive.lineColor.toString()
            ctx.lineWidth = 1
            let step = Math.max(20, hive.cell)
            for (let x = 0; x < width; x += step) {
                ctx.beginPath()
                ctx.moveTo(x, 0)
                ctx.lineTo(x, height)
                ctx.stroke()
            }
            for (let y = 0; y < height; y += step) {
                ctx.beginPath()
                ctx.moveTo(0, y)
                ctx.lineTo(width, y)
                ctx.stroke()
            }
        }
    }

    property real _base: 0
    property double _since: 0
    Timer {
        interval: hive.frameMs
        repeat: true
        running: hive.ownClock && hive.animate && !hive.paused && hive.visible && hive.width > 0
        onRunningChanged: {
            if (running)
                hive._since = Date.now()
            else
                hive._base = hive.time
        }
        onTriggered: hive.time = hive._base + (Date.now() - hive._since) / 1000
    }
}
