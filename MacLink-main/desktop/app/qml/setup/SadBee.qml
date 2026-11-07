// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

// Modern Task Manager Uninstall Telemetry Status Icon (replaces legacy SadBee).
Item {
    id: bee

    property bool animate: true
    property bool dark: false
    property color bodyColor: dark ? "#D9AE68" : "#E7B86A"
    property color stripeColor: dark ? "#2A2019" : "#3B2A1D"
    property color headColor: dark ? "#2A2019" : "#3B2A1D"
    property color wingColor: dark ? Qt.rgba(0.86, 0.90, 1.0, 0.30) : Qt.rgba(1, 1, 1, 0.92)
    property color wingEdge: dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0.23, 0.16, 0.11, 0.32)
    property color tearColor: dark ? "#9CC7F0" : "#6FA8DC"

    implicitWidth: 140
    implicitHeight: 120

    Accessible.role: Accessible.Graphic
    Accessible.name: qsTr("MacLink Removal")

    Rectangle {
        anchors.centerIn: parent
        width: 80
        height: 80
        radius: 40
        color: Qt.rgba(0.9, 0.3, 0.3, 0.12)
        border.width: 1.5
        border.color: Qt.rgba(0.9, 0.3, 0.3, 0.40)

        // Pulsing telemetry ring
        Rectangle {
            anchors.centerIn: parent
            width: 96
            height: 96
            radius: 48
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0.9, 0.3, 0.3, 0.25)
            opacity: bee.animate ? 0.7 : 0
            SequentialAnimation on scale {
                running: bee.animate
                loops: Animation.Infinite
                NumberAnimation { from: 0.95; to: 1.08; duration: 1800; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 1.08; to: 0.95; duration: 1800; easing.type: Easing.InOutQuad }
            }
        }

        // System Package Removal Icon
        Canvas {
            anchors.centerIn: parent
            width: 36
            height: 36
            onPaint: {
                let ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = bee.dark ? "#F0A39C" : "#9E2B25"
                ctx.lineWidth = 2.2
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(6, 10); ctx.lineTo(30, 10)
                ctx.moveTo(13, 10); ctx.lineTo(13, 6); ctx.lineTo(23, 6); ctx.lineTo(23, 10)
                ctx.moveTo(9, 10); ctx.lineTo(11, 30); ctx.lineTo(25, 30); ctx.lineTo(27, 10)
                ctx.moveTo(15, 15); ctx.lineTo(15, 25)
                ctx.moveTo(21, 15); ctx.lineTo(21, 25)
                ctx.stroke()
            }
        }
    }
}
