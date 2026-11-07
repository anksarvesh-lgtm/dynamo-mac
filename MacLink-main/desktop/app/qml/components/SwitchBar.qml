// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import app.maclink

// A full-width row with an icon, a title, an optional caption and a switch
// (Phone as speaker, Play on phone). It fills in while on; `enabled: false`
// greys it out until it can be used.
Rectangle {
    id: bar
    property string iconPath
    property string title
    // Shown under the title when not empty.
    property string caption
    property bool checked: false
    signal toggled(bool on)

    readonly property color ink: checked
        ? Theme.textPrimary
        : Theme.textSecondary

    implicitHeight: Math.max(48, textCol.implicitHeight + 16)
    height: implicitHeight
    radius: 14
    color: checked
        ? Qt.rgba(0.95, 0.66, 0.23, 0.12)
        : Theme.cardFill
    border.width: 1
    border.color: checked ? Theme.amberAccent : Theme.cardBorderSubtle

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: barSwitch.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10
        opacity: bar.enabled ? 1 : 0.38
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: 17; height: 17
            path: bar.iconPath
            color: bar.ink
        }
        Column {
            id: textCol
            width: parent.width - 27
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Txt {
                width: parent.width
                role: "label"
                elide: Text.ElideRight
                color: bar.ink
                text: bar.title
            }
            Txt {
                visible: bar.caption.length > 0
                width: parent.width
                role: "caption"
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: bar.ink
                opacity: 0.85
                text: bar.caption
            }
        }
    }
    Toggle {
        id: barSwitch
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        label: bar.title
        checked: bar.checked
        onToggled: (on) => bar.toggled(on)
    }
}
