// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Effects
import app.maclink

// An image with rounded corners (a plain clip only cuts rectangles).
Item {
    id: root
    property alias source: image.source
    property alias status: image.status
    property alias fillMode: image.fillMode
    property alias sourceSize: image.sourceSize
    property alias implicitImageWidth: image.implicitWidth
    property alias implicitImageHeight: image.implicitHeight
    property real radius: Theme.radiusMd

    Image {
        id: image
        anchors.fill: parent
        asynchronous: true
        mipmap: true
        fillMode: Image.PreserveAspectCrop
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.fadeNormal } }
        // The mask runs as the image's own layer effect, so it redraws whenever the image
        // does: a new track's artwork, a switch between sources, or the card being shown
        // again. A separate MultiEffect sampling a hidden layer kept a stale, blank texture.
        layer.enabled: root.width > 0 && root.height > 0
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
        layer.smooth: true
    }
}
