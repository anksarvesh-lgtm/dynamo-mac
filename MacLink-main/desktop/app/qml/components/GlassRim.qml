// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import app.maclink

// The rim of a Liquid Glass surface (shaders/glassrim.frag): a specular edge lit from the
// top left with a softer reflection at the bottom right, and a faint inner glow that reads
// as the glass's thickness. Fill its parent; it only draws in the Glass theme.
ShaderEffect {
    id: rim
    property real radius: Theme.radiusLg
    property real strength: 1.0
    readonly property size itemSize: Qt.size(width, height)
    readonly property color rimColor: Qt.rgba(1, 1, 1, 0.35)

    anchors.fill: parent
    visible: Theme.glass && width > 0 && height > 0
    blending: true
    fragmentShader: "qrc:/shaders/glassrim.frag.qsb"
}
