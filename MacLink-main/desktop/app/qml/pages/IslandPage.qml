// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import app.maclink

// MacLink Island Control Panel
// Provides configuration for the dynamic notch overlay, Keep Awake power management,
// Connected Devices Slot 1 behavior, and compact Clipboard History.
// Ships OFF by default adhering strictly to MacLink hard UI-preservation rules.
Flickable {
    id: islandPage

    contentWidth: width
    contentHeight: contentCol.implicitHeight + 48
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
        id: contentCol
        width: Math.min(parent.width - 48, 760)
        anchors.horizontalCenter: parent.horizontalCenter
        y: 24
        spacing: 20

        // Page Header
        Row {
            spacing: 14
            width: parent.width

            Rectangle {
                width: 44
                height: 44
                radius: 12
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
                border.width: 1

                Shape {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    ShapePath {
                        strokeColor: Theme.accent
                        strokeWidth: 1.8
                        fillColor: "transparent"
                        PathSvg { path: Icons.island }
                    }
                }
            }

            Column {
                spacing: 3
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 60

                Text {
                    text: qsTr("Dynamic Island")
                    font.family: Tokens.fontFamily
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    color: Theme.textPrimary
                }

                Text {
                    text: qsTr("Floating top-notch overlay for live phone activity, connected devices, and sleep prevention.")
                    font.family: Tokens.fontFamily
                    font.pixelSize: 12
                    color: Theme.textSecondary
                    elide: Text.ElideRight
                    width: parent.width
                }
            }
        }

        // Master Enable Card
        Rectangle {
            width: parent.width
            height: masterRow.implicitHeight + 24
            radius: 14
            color: Theme.surfaceVariant
            border.color: Preferences.maclinkIsland ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.outlineVariant
            border.width: 1

            RowLayout {
                id: masterRow
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: qsTr("Enable Dynamic Island")
                        font.family: Tokens.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: Theme.textPrimary
                    }

                    Text {
                        text: qsTr("When disabled, the island overlay remains completely inactive with zero background overhead or permission prompts.")
                        font.family: Tokens.fontFamily
                        font.pixelSize: 11
                        color: Theme.textSecondary
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                }

                Toggle {
                    checked: Preferences.maclinkIsland
                    onToggled: (on) => Preferences.maclinkIsland = on
                }
            }
        }

        // Configuration Sections (visible only when enabled)
        Column {
            width: parent.width
            spacing: 16
            visible: Preferences.maclinkIsland
            opacity: Preferences.maclinkIsland ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation { duration: 200 }
            }

            // Section 1: Keep Awake (IOKit Power Assertions)
            Rectangle {
                width: parent.width
                implicitHeight: kaCol.implicitHeight + 28
                radius: 14
                color: Theme.surfaceVariant
                border.color: Theme.outlineVariant
                border.width: 1

                Column {
                    id: kaCol
                    width: parent.width - 32
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 14
                    spacing: 12

                    Row {
                        spacing: 8
                        Shape {
                            width: 16; height: 16
                            ShapePath {
                                strokeColor: Theme.accent
                                strokeWidth: 1.6
                                fillColor: "transparent"
                                PathSvg { path: Icons.power }
                            }
                        }
                        Text {
                            text: qsTr("Keep Awake (Sleep Prevention)")
                            font.family: Tokens.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: Theme.textPrimary
                        }
                    }

                    Text {
                        text: qsTr("Prevents idle sleep using cleanroom Apple IOKit power assertions without simulating input or shelling out.")
                        font.family: Tokens.fontFamily
                        font.pixelSize: 11
                        color: Theme.textSecondary
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }

                    Row {
                        spacing: 8
                        Repeater {
                            model: ["15m", "30m", "1h", "2h", "4h", "Indefinite"]
                            delegate: Rectangle {
                                width: 58; height: 26
                                radius: 6
                                color: Qt.rgba(255, 255, 255, 0.06)
                                border.color: Qt.rgba(255, 255, 255, 0.12)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.family: Tokens.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    color: Theme.textPrimary
                                }
                            }
                        }
                    }

                    Text {
                        text: qsTr("Note: MacBooks require AC power and an external display to stay awake with lid closed (macOS clamshell requirement).")
                        font.family: Tokens.fontFamily
                        font.pixelSize: 10
                        color: Theme.textSecondary
                        font.italic: true
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // Section 2: Connected Devices (Slot 1 Behavior)
            Rectangle {
                width: parent.width
                implicitHeight: devCol.implicitHeight + 28
                radius: 14
                color: Theme.surfaceVariant
                border.color: Theme.outlineVariant
                border.width: 1

                Column {
                    id: devCol
                    width: parent.width - 32
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 14
                    spacing: 12

                    Row {
                        spacing: 8
                        Shape {
                            width: 16; height: 16
                            ShapePath {
                                strokeColor: Theme.accent
                                strokeWidth: 1.6
                                fillColor: "transparent"
                                PathSvg { path: Icons.bluetooth }
                            }
                        }
                        Text {
                            text: qsTr("Connected Devices (Slot 1)")
                            font.family: Tokens.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: Theme.textPrimary
                        }
                    }

                    Text {
                        text: qsTr("Monitors USB, Bluetooth, Phone, and Storage devices. Sits first when active; completely disappears (0 height) when zero devices are connected.")
                        font.family: Tokens.fontFamily
                        font.pixelSize: 11
                        color: Theme.textSecondary
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        width: parent.width
                        Text {
                            text: qsTr("Show External Storage Drives")
                            font.family: Tokens.fontFamily
                            font.pixelSize: 11.5
                            color: Theme.textPrimary
                            Layout.fillWidth: true
                        }
                        Toggle {
                            checked: true
                            onToggled: (on) => {}
                        }
                    }

                    RowLayout {
                        width: parent.width
                        Text {
                            text: qsTr("Show External Displays")
                            font.family: Tokens.fontFamily
                            font.pixelSize: 11.5
                            color: Theme.textPrimary
                            Layout.fillWidth: true
                        }
                        Toggle {
                            checked: true
                            onToggled: (on) => {}
                        }
                    }
                }
            }

            // Section 3: Clipboard History
            Rectangle {
                width: parent.width
                implicitHeight: clipCol.implicitHeight + 28
                radius: 14
                color: Theme.surfaceVariant
                border.color: Theme.outlineVariant
                border.width: 1

                Column {
                    id: clipCol
                    width: parent.width - 32
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 14
                    spacing: 12

                    Row {
                        spacing: 8
                        Shape {
                            width: 16; height: 16
                            ShapePath {
                                strokeColor: Theme.accent
                                strokeWidth: 1.6
                                fillColor: "transparent"
                                PathSvg { path: Icons.copy }
                            }
                        }
                        Text {
                            text: qsTr("Clipboard History")
                            font.family: Tokens.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: Theme.textPrimary
                        }
                    }

                    Text {
                        text: qsTr("Compact 28pt fixed-height rows hugging content up to 6–8 items. Automatically shields sensitive password manager copies.")
                        font.family: Tokens.fontFamily
                        font.pixelSize: 11
                        color: Theme.textSecondary
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        width: parent.width
                        Text {
                            text: qsTr("Enable Clipboard History in Island")
                            font.family: Tokens.fontFamily
                            font.pixelSize: 11.5
                            color: Theme.textPrimary
                            Layout.fillWidth: true
                        }
                        Toggle {
                            checked: true
                            onToggled: (on) => {}
                        }
                    }
                }
            }

            // Section 4: Live Phone Activities
            Rectangle {
                width: parent.width
                implicitHeight: phoneCol.implicitHeight + 28
                radius: 14
                color: Theme.surfaceVariant
                border.color: Theme.outlineVariant
                border.width: 1

                Column {
                    id: phoneCol
                    width: parent.width - 32
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 14
                    spacing: 12

                    Text {
                        text: qsTr("Live Phone Activities")
                        font.family: Tokens.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Theme.textPrimary
                    }

                    RowLayout {
                        width: parent.width
                        Text {
                            text: qsTr("Incoming & active calls")
                            font.family: Tokens.fontFamily
                            font.pixelSize: 11.5
                            color: Theme.textPrimary
                            Layout.fillWidth: true
                        }
                        Toggle {
                            checked: Preferences.maclinkIslandCalls
                            onToggled: (on) => Preferences.maclinkIslandCalls = on
                        }
                    }

                    RowLayout {
                        width: parent.width
                        Text {
                            text: qsTr("File transfers in progress")
                            font.family: Tokens.fontFamily
                            font.pixelSize: 11.5
                            color: Theme.textPrimary
                            Layout.fillWidth: true
                        }
                        Toggle {
                            checked: Preferences.maclinkIslandTransfers
                            onToggled: (on) => Preferences.maclinkIslandTransfers = on
                        }
                    }

                    RowLayout {
                        width: parent.width
                        Text {
                            text: qsTr("Now playing media")
                            font.family: Tokens.fontFamily
                            font.pixelSize: 11.5
                            color: Theme.textPrimary
                            Layout.fillWidth: true
                        }
                        Toggle {
                            checked: Preferences.maclinkIslandMedia
                            onToggled: (on) => Preferences.maclinkIslandMedia = on
                        }
                    }

                    RowLayout {
                        width: parent.width
                        Text {
                            text: qsTr("Phone notifications toast")
                            font.family: Tokens.fontFamily
                            font.pixelSize: 11.5
                            color: Theme.textPrimary
                            Layout.fillWidth: true
                        }
                        Toggle {
                            checked: Preferences.maclinkIslandNotifications
                            onToggled: (on) => Preferences.maclinkIslandNotifications = on
                        }
                    }
                }
            }
        }
    }
}
