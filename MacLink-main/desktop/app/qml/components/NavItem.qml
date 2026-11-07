// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import app.maclink

// A navigation rail / sidebar destination: an icon in a pill indicator above a label,
// or a wide row with icon + label in wide sidebar mode.
FocusScope {
    id: item
    property string iconPath
    property string text
    property bool selected: false
    property bool wide: false
    readonly property alias hovered: mouse.containsMouse
    property bool activeHover: mouse.containsMouse
    signal clicked

    implicitWidth: wide ? (parent ? parent.width : 206) : 72
    implicitHeight: wide ? 38 : 56
    activeFocusOnTab: true

    Accessible.role: Accessible.PageTab
    Accessible.name: text
    Accessible.selected: selected
    Accessible.onPressAction: item.clicked()
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            item.clicked()
            event.accepted = true
        }
    }

    // ---- Wide sidebar mode ----
    Rectangle {
        id: widePill
        visible: item.wide
        anchors.fill: parent
        radius: 12
        scale: mouse.pressed ? Theme.pressScale : 1.0
        Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        gradient: item.selected ? amberGrad : null
        color: item.selected ? "transparent" : (item.activeHover ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
        border.width: item.selected ? 1 : (item.activeHover ? 1 : 0)
        border.color: item.selected ? Qt.rgba(1, 0.85, 0.55, 0.65) : Qt.rgba(1, 1, 1, 0.08)

        Gradient {
            id: amberGrad
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#A86210" }
            GradientStop { position: 1.0; color: "#F2A93B" }
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 11

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                path: item.iconPath
                color: item.selected ? "#FFFFFF" : (item.activeHover ? Theme.textPrimary : Theme.textSecondary)
                width: 18; height: 18
            }

            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: item.text
                role: "body"
                size: 13
                weight: item.selected ? 600 : 500
                color: item.selected ? "#FFFFFF" : (item.activeHover ? Theme.textPrimary : Theme.textSecondary)
                elide: Text.ElideRight
            }
        }
    }

    // ---- Compact rail mode ----
    Rectangle {
        id: pill
        visible: !item.wide
        anchors.horizontalCenter: parent.horizontalCenter
        y: 2
        width: 52; height: 30
        radius: Theme.pill(height)
        color: "transparent"
        scale: mouse.pressed ? Theme.pressScale : 1.0
        Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.centerIn: parent
            height: parent.height
            width: item.selected ? parent.width : (item.activeHover ? 42 : 24)
            radius: parent.radius
            color: item.selected
                ? (Theme.glass
                    ? Qt.tint(Qt.rgba(1, 1, 1, Theme.dark ? 0.14 : 0.62), Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Theme.dark ? 0.28 : 0.22))
                    : Theme.indicator)
                : Theme.surfaceContent
            opacity: item.selected ? 1.0 : (item.activeHover ? 0.08 : 0.0)
            border.width: Theme.glass && item.selected ? 1 : 0
            border.color: Qt.rgba(1, 1, 1, Theme.dark ? 0.28 : 0.78)
            Behavior on width {
                enabled: !Theme.reduceMotion
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                enabled: !Theme.reduceMotion
                NumberAnimation { duration: Theme.fadeFast; easing.type: Easing.OutCubic }
            }
            Behavior on color {
                enabled: !Theme.reduceMotion
                ColorAnimation { duration: Theme.fadeFast }
            }
        }

        Icon {
            anchors.centerIn: parent
            path: item.iconPath
            color: item.selected ? Theme.indicatorContent : (item.activeHover ? Theme.surfaceContent : Theme.surfaceContentVariant)
            scale: item.selected ? 1.05 : (item.activeHover ? 1.02 : 1.0)
            Behavior on scale {
                enabled: !Theme.reduceMotion
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
            Behavior on color {
                enabled: !Theme.reduceMotion
                ColorAnimation { duration: Theme.fadeFast }
            }
        }
    }
    Txt {
        visible: !item.wide
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: pill.bottom
        anchors.topMargin: 4
        text: item.text
        role: "caption"
        weight: Theme.graphite ? 400 : (item.selected ? 600 : 500)
        color: item.selected || item.activeHover ? Theme.surfaceContent : Theme.surfaceContentVariant
        Behavior on color {
            enabled: !Theme.reduceMotion
            ColorAnimation { duration: Theme.fadeFast }
        }
    }
    Rectangle {
        anchors.fill: pill
        anchors.margins: -3
        radius: pill.radius + 3
        color: "transparent"
        border.width: 2
        border.color: Theme.primary
        visible: Theme.focusVisible(item)
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: item.clicked()
    }
}
