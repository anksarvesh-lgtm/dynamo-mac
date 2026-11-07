// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import app.maclink

// A content surface: filled in Bloom, honey-edged in Hive, frosted optical glass in Glass,
// hairline-bordered in Graphite.
Rectangle {
    id: cardRoot
    property int padding: 16
    property bool hoverable: true
    default property alias content: inner.data

    radius: Theme.radiusLg
    color: Theme.cardColor
    border.width: 1
    border.color: (cardRoot.hoverable && cardHover.hovered) ? Theme.cardBorderHover : Theme.cardBorder
    implicitHeight: inner.childrenRect.height + padding * 2
    Behavior on color { ColorAnimation { duration: Theme.fadeNormal } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    HoverHandler {
        id: cardHover
        enabled: cardRoot.hoverable
    }

    GlassRim {
        radius: cardRoot.radius
    }

    Item {
        id: inner
        z: 1
        anchors.fill: parent
        anchors.margins: parent.padding
    }
}
