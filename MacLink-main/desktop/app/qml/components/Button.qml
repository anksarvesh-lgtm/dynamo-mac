// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import app.maclink

// A pill button. Variants: "fill" (primary action), "tonal", "outline",
// "text". Sizes: "md" (40 px) and "sm" (32 px). Works with mouse, touch and
// keyboard (Tab to focus, Enter or Space to press).
FocusScope {
    id: button
    property string text
    property string iconPath
    property string variant: "fill"
    property string size: "md"
    property bool busy: false
    signal clicked

    readonly property bool small: size === "sm"
    readonly property bool interactive: enabled && !busy
    readonly property color background: {
        if (variant === "amber")
            return "transparent"
        if (variant === "fill")
            return Theme.graphite ? Theme.surfaceContent : Theme.primary
        if (variant === "tonal") {
            if (Theme.glass)
                return Qt.tint(
                    Qt.rgba(1, 1, 1, Theme.dark ? 0.10 : 0.54),
                    Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Theme.dark ? 0.18 : 0.14)
                )
            return Theme.secondaryContainer
        }
        return "transparent"
    }
    readonly property color foreground: {
        if (variant === "amber")
            return "#FFFFFF"
        if (variant === "fill")
            return Theme.graphite ? Theme.surface : Theme.primaryContent
        if (variant === "tonal")
            return Theme.glass ? Theme.surfaceContent : Theme.secondaryContainerContent
        if (variant === "text")
            return Theme.graphite ? Theme.surfaceContent : Theme.primary
        return Theme.surfaceContent
    }

    implicitHeight: small ? 32 : 40
    implicitWidth: row.implicitWidth + (variant === "text" ? 20 : (small ? 26 : 36))
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.38

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: if (interactive) button.clicked()
    Keys.onPressed: (event) => {
        if (interactive && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
            button.clicked()
            event.accepted = true
        }
    }

    // Hive: a soft honey halo around a filled button under the pointer.
    Rectangle {
        visible: Theme.hive && button.variant === "fill"
        x: -4; y: -4
        width: parent.width + 8; height: parent.height + 8
        radius: body.radius + 4
        color: Theme.glow
        opacity: button.interactive && (mouse.containsMouse || Theme.focusVisible(button)) ? 1 : 0
        scale: body.scale
        Behavior on opacity { enabled: !Theme.reduceMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    // Graphite's flat offset shadow under filled buttons.
    Rectangle {
        visible: Theme.graphite && button.variant === "fill"
        x: 3; y: 3
        width: parent.width; height: parent.height
        radius: body.radius
        color: Theme.buttonShadow
    }

    Rectangle {
        id: body
        width: parent.width
        height: parent.height
        radius: Theme.pill(height)
        color: button.background
        gradient: button.variant === "amber" ? amberBtnGrad : null
        Behavior on color { enabled: !Theme.reduceMotion; ColorAnimation { duration: Theme.fadeFast } }
        border.width: button.variant === "amber" ? 1 : (button.variant === "outline" || (Theme.glass && (button.variant === "tonal" || button.variant === "fill")) ? 1 : 0)
        border.color: button.variant === "amber"
            ? Qt.rgba(1, 0.85, 0.55, 0.65)
            : (button.variant === "outline"
                ? (Theme.glass ? Qt.rgba(1, 1, 1, Theme.dark ? 0.14 : 0.38)
                    : (Theme.hive ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, Theme.dark ? 0.42 : 0.38) : Theme.outline))
                : Qt.rgba(1, 1, 1, Theme.dark ? 0.10 : 0.32))
        scale: mouse.pressed && button.interactive ? Theme.pressScale : 1
        Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        Gradient {
            id: amberBtnGrad
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#A86210" }
            GradientStop { position: 1.0; color: "#F2A93B" }
        }

        // Hive: honey catches the light along the top of a filled button.
        Rectangle {
            visible: Theme.hive && button.variant === "fill"
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, Theme.dark ? 0.22 : 0.16) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0) }
            }
        }

        // Hover & Press state layer.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: button.foreground
            opacity: !button.interactive ? 0 : (mouse.pressed ? 0.14 : (mouse.containsMouse ? 0.07 : 0))
            Behavior on opacity { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.fadeFast } }
        }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8
            Spinner {
                visible: button.busy
                anchors.verticalCenter: parent.verticalCenter
                width: 16; height: 16
                color: button.foreground
            }
            Icon {
                visible: button.iconPath.length > 0 && !button.busy
                anchors.verticalCenter: parent.verticalCenter
                width: button.small ? 16 : 18; height: width
                path: button.iconPath
                color: button.foreground
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: button.text
                role: "label"
                color: button.foreground
                size: Theme.graphite ? 11 : (button.small ? 13 : 14)
                font.underline: Theme.graphite && button.variant === "text"
                maximumLineCount: 1
                elide: Text.ElideRight
            }
        }
    }

    // Keyboard focus ring.
    Rectangle {
        anchors.fill: body
        anchors.margins: -3
        radius: body.radius + 3
        color: "transparent"
        border.width: 2
        border.color: Theme.primary
        visible: Theme.focusVisible(button)
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: button.interactive
        hoverEnabled: true
        cursorShape: button.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: button.clicked()
    }
}
