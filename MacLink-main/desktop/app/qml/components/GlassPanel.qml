// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Effects
import app.maclink

Item {
    id: root
    property Item backdrop: null          // background item to sample
    property real radius: 28
    property bool reduceGlass: Theme.reduceGlass
    property bool hasShadow: true
    property real tintTop: 0.14
    property real tintBottom: 0.06
    property real amberTint: 0.05
    property real topLightHeight: Math.min(40, height * 0.45)
    property bool hasTopLight: true
    property bool hasRim: true

    // Mask for panel shape
    Item {
        id: shapeMask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: "#FFFFFF"
        }
    }

    // 5. Shadow (soft shadow below and outside panel)
    MultiEffect {
        anchors.fill: parent
        visible: root.hasShadow && !root.reduceGlass && width > 0 && height > 0
        source: shapeMask
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.45)
        shadowBlur: 0.6
        shadowOpacity: 0.35
        shadowVerticalOffset: 6
        shadowHorizontalOffset: 0
    }

    // 1. Blurred backdrop
    ShaderEffectSource {
        id: snap
        anchors.fill: parent
        visible: false
        sourceItem: root.backdrop
        live: false
        recursive: false
        sourceRect: root.backdrop ? root.mapToItem(root.backdrop, 0, 0, root.width, root.height) : Qt.rect(0, 0, 0, 0)
    }

    MultiEffect {
        id: blurEffect
        anchors.fill: parent
        visible: !root.reduceGlass && root.backdrop !== null && width > 0 && height > 0
        source: snap
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        saturation: 0.35
        brightness: 0.04
        maskEnabled: true
        maskSource: shapeMask
    }

    // 2. Tint (white vertical gradient 14% to 6% with faint amber tint)
    Rectangle {
        id: tintLayer
        anchors.fill: parent
        radius: root.radius
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop {
                position: 0.0
                color: Qt.rgba(1, 1, 1, root.reduceGlass ? 0.22 : root.tintTop)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(1, 1, 1, root.reduceGlass ? 0.12 : root.tintBottom)
            }
        }
    }

    // Faint amber tint layer
    Rectangle {
        id: amberLayer
        anchors.fill: parent
        radius: root.radius
        visible: root.amberTint > 0
        color: Qt.rgba(0.95, 0.66, 0.23, root.amberTint)
    }

    // 3. Top light (soft white gradient over the top 40 pt: 10% to 0)
    Rectangle {
        id: topLight
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.topLightHeight
        visible: root.hasTopLight && height > 0
        radius: root.radius
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.12) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
        }
    }

    // 4. Specular rim (1 pt edge with gradient: 45% white top-left, fading in middle, 20% bottom-right)
    Item {
        id: rimContainer
        anchors.fill: parent
        visible: root.hasRim

        Rectangle {
            id: rimGradRect
            anchors.fill: parent
            radius: root.radius
            visible: false
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.45) }
                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.05) }
                GradientStop { position: 0.85; color: Qt.rgba(1, 1, 1, 0.08) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.20) }
            }
        }

        Item {
            id: innerCutout
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Math.max(0, root.radius - 1)
                color: "#FFFFFF"
            }
        }

        MultiEffect {
            anchors.fill: parent
            source: rimGradRect
            maskEnabled: true
            maskSource: innerCutout
            maskInverted: true
        }
    }

    function updateSnapshot() {
        if (snap && snap.sourceItem) {
            snap.sourceRect = root.mapToItem(root.backdrop, 0, 0, root.width, root.height)
            snap.scheduleUpdate()
        }
    }

    onWidthChanged: updateSnapshot()
    onHeightChanged: updateSnapshot()
    onXChanged: updateSnapshot()
    onYChanged: updateSnapshot()
    Component.onCompleted: updateSnapshot()
}
