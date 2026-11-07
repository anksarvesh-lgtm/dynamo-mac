// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import app.maclink

// A Material switch. Click, Space or Enter flips it; `toggled` reports the
// user's choice (bind `checked` to the source of truth).
FocusScope {
    id: toggle
    property bool checked: false
    property string label
    signal toggled(bool checked)

    implicitWidth: 46
    implicitHeight: 28
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.38

    Accessible.role: Accessible.CheckBox
    Accessible.name: label
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onToggleAction: toggle.toggled(!toggle.checked)
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            toggle.toggled(!toggle.checked)
            event.accepted = true
        }
    }

    // Hive: a soft honey halo around a switch that's on.
    Rectangle {
        visible: Theme.hive
        anchors.fill: track
        anchors.margins: -3
        radius: track.radius + 3
        color: Theme.glow
        opacity: toggle.checked ? (mouse.containsMouse ? 1 : 0.55) : 0
        Behavior on opacity { enabled: !Theme.reduceMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    Gradient {
        id: amberTrackGrad
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Theme.amberAccentDeep }
        GradientStop { position: 1.0; color: Theme.amberAccent }
    }

    Rectangle {
        id: track
        anchors.fill: parent
        radius: Theme.graphite ? Theme.radiusSm : height / 2
        gradient: (Theme.glass && toggle.checked) ? amberTrackGrad : null
        color: Theme.glass
            ? (toggle.checked
                ? Theme.amberAccent
                : Qt.rgba(1, 1, 1, 0.08))
            : (toggle.checked ? Theme.primary : Theme.surfaceContainerHighest)
        border.width: Theme.glass ? 1 : (toggle.checked ? 0 : 1.5)
        border.color: Theme.glass
            ? (toggle.checked ? Theme.amberBorder : Theme.cardBorderSubtle)
            : Theme.outline
        Behavior on color { ColorAnimation { duration: Theme.fadeFast } }

        Rectangle {
            id: thumb
            property real size: mouse.pressed ? 20 : (mouse.containsMouse ? 20 : (toggle.checked ? 18 : 16))
            width: mouse.pressed ? 22 : size
            height: size
            radius: Theme.graphite ? Theme.radiusXs : height / 2
            anchors.verticalCenter: parent.verticalCenter
            x: toggle.checked ? parent.width - width - 4.5 : 6.5
            color: Theme.glass
                ? (toggle.checked ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.70))
                : (toggle.checked ? Theme.primaryContent : (mouse.containsMouse ? Theme.surfaceContentVariant : Theme.outline))
            border.width: Theme.glass ? 1 : 0
            border.color: Qt.rgba(1, 1, 1, Theme.dark ? 0.55 : 0.90)
            // Quick and settled, never springy: a switch must feel immediate.
            Behavior on x { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.reduceMotion ? 0 : 140; easing.type: Easing.OutCubic } }
            Behavior on width { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.fadeFast; easing.type: Easing.OutCubic } }
            Behavior on height { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.fadeFast; easing.type: Easing.OutCubic } }
            Behavior on color { enabled: !Theme.reduceMotion; ColorAnimation { duration: Theme.fadeFast } }
        }
    }
    Rectangle {
        anchors.fill: track
        anchors.margins: -3
        radius: track.radius + 3
        color: "transparent"
        border.width: 2
        border.color: Theme.primary
        visible: Theme.focusVisible(toggle)
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: toggle.toggled(!toggle.checked)
    }
}
