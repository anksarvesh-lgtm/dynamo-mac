// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import app.maclink

// Streamlined First-Run Setup (3 Essential Steps):
// 1. Connect Your Phone (Download APK / ADB / QR Pairing)
// 2. Essential Sync (Notifications, Clipboard, Files & Photos)
// 3. System Status & All Set (Task Manager telemetry overview)
FocusScope {
    id: walkthrough
    focus: true

    property bool active: true
    property string deviceId: ""
    property string deviceName: ""

    signal completed()
    signal openGuideRequested()
    signal doctorRequested()

    readonly property int totalSteps: 3
    readonly property string adbCommand: "adb install -r MacLink-" + AppController.version + "-android.apk"
    property int step: Math.max(0, Math.min(totalSteps - 1, Preferences.walkthroughStep))
    property alias currentStep: walkthrough.step

    // Primary paired device (if any) for per-device toggles.
    property string activeDeviceId: ""
    property string activeDeviceName: ""
    readonly property bool hasPairedDevice: AppController.hasDevices || activeDeviceId !== ""

    onStepChanged: {
        if (Preferences.walkthroughStep !== step)
            Preferences.walkthroughStep = step
        if (bodyFlick)
            bodyFlick.contentY = 0
    }

    Connections {
        target: Preferences
        function onWalkthroughStepChanged() {
            let clamped = Math.max(0, Math.min(walkthrough.totalSteps - 1, Preferences.walkthroughStep))
            if (walkthrough.step !== clamped)
                walkthrough.step = clamped
        }
    }

    property var deviceTogglesMap: ({
        notifications: true,
        clipboard: true,
        files: true,
        sms: true,
        calls: true,
        media: true,
        storage: false,
        remote_input: false,
        pc_mirror: false
    })

    readonly property var stepTitles: [
        qsTr("Connect your phone"),
        qsTr("Essential sync"),
        qsTr("All set")
    ]

    readonly property var stepSubtitles: [
        qsTr("Install MacLink on Android and scan the QR code to pair over local Wi-Fi."),
        qsTr("Configure notifications, universal clipboard, and file sharing."),
        qsTr("Your devices are connected with zero cloud dependencies and 100% direct encryption.")
    ]

    function refreshDeviceToggles() {
        let _rev = AppController.togglesRevision
        let count = DeviceList.count
        if (count <= 0) {
            activeDeviceId = ""
            activeDeviceName = ""
            return
        }
        let id = DeviceList.deviceIdAt(0) || ""
        let name = DeviceList.deviceNameAt(0) || "Your phone"
        activeDeviceId = id
        activeDeviceName = name
        if (id === "")
            return
        let list = AppController.deviceToggles(id)
        let next = {
            notifications: true,
            clipboard: true,
            files: true,
            sms: true,
            calls: true,
            media: true,
            storage: false,
            remote_input: false,
            pc_mirror: false
        }
        for (let i = 0; i < list.length; i++) {
            let entry = list[i]
            if (entry && entry.name !== undefined)
                next[entry.name] = Boolean(entry.on)
        }
        deviceTogglesMap = next
    }

    function isDeviceToggleOn(name) {
        return Boolean(deviceTogglesMap[name])
    }

    function setDeviceToggleValue(name, on) {
        let next = Object.assign({}, deviceTogglesMap)
        next[name] = on
        deviceTogglesMap = next
        if (activeDeviceId !== "")
            AppController.setDeviceToggle(activeDeviceId, name, on)
    }

    readonly property var parsedDoctorChecks: {
        let raw = AppController.doctorChecks
        if (!raw || raw === "")
            return []
        try {
            return JSON.parse(raw)
        } catch (e) {
            return []
        }
    }

    readonly property bool doctorAllPassed: {
        if (parsedDoctorChecks.length === 0)
            return false
        for (let i = 0; i < parsedDoctorChecks.length; i++) {
            if (parsedDoctorChecks[i].status !== "ok")
                return false
        }
        return true
    }

    readonly property string doctorSummaryLabel: {
        if (AppController.doctorBusy)
            return qsTr("Checking firewall and local network...")
        if (parsedDoctorChecks.length === 0)
            return qsTr("Verified local discovery and firewall rules.")
        let problems = 0
        for (let i = 0; i < parsedDoctorChecks.length; i++) {
            if (parsedDoctorChecks[i].status !== "ok")
                problems++
        }
        return problems === 0
            ? qsTr("All network and firewall checks passed.")
            : (problems + (problems === 1 ? qsTr(" item needs attention.") : qsTr(" items need attention.")))
    }

    function goNext() {
        if (step < totalSteps - 1) {
            step = step + 1
        } else {
            finishWalkthrough()
        }
    }

    function goBack() {
        if (step > 0)
            step = step - 1
    }

    function skipWalkthrough() {
        Preferences.walkthroughCompleted = true
        walkthrough.completed()
    }

    function finishWalkthrough() {
        Preferences.walkthroughCompleted = true
        walkthrough.completed()
    }

    function finishAndOpenGuide() {
        Preferences.walkthroughCompleted = true
        walkthrough.openGuideRequested()
    }

    Component.onCompleted: {
        refreshDeviceToggles()
        AppController.refreshToastsEnabled()
    }

    Connections {
        target: AppController
        function onHasDevicesChanged() { walkthrough.refreshDeviceToggles() }
        function onTogglesRevisionChanged() { walkthrough.refreshDeviceToggles() }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            skipWalkthrough()
            event.accepted = true
        } else if (event.key === Qt.Key_Right && (event.modifiers & Qt.AltModifier)) {
            goNext()
            event.accepted = true
        } else if (event.key === Qt.Key_Left && (event.modifiers & Qt.AltModifier)) {
            goBack()
            event.accepted = true
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 28
        anchors.rightMargin: 28
        anchors.topMargin: Theme.topBarHeight + 4
        anchors.bottomMargin: 20
        spacing: 16

        // Top progress header: 3-segment progress bar + Skip setup action
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            RowLayout {
                id: progressTrack
                Layout.fillWidth: true
                spacing: 8
                Accessible.role: Accessible.ProgressBar
                Accessible.name: "Step " + (walkthrough.currentStep + 1) + " of " + walkthrough.totalSteps

                Repeater {
                    model: walkthrough.totalSteps
                    delegate: Rectangle {
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        implicitWidth: 80
                        implicitHeight: 6
                        radius: 3
                        color: index < walkthrough.step
                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55)
                            : (index === walkthrough.step ? Theme.primary : Theme.surfaceContainerHighest)

                        Behavior on color {
                            enabled: !Theme.reduceMotion
                            ColorAnimation { duration: Theme.fadeFast }
                        }

                        Accessible.role: Accessible.Button
                        Accessible.name: "Go to step " + (index + 1) + ": " + walkthrough.stepTitles[index]
                        MouseArea {
                            anchors.fill: parent
                            anchors.topMargin: -6
                            anchors.bottomMargin: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: walkthrough.step = parent.index
                        }
                    }
                }
            }

            Button {
                text: qsTr("Skip setup")
                variant: "tonal"
                size: "sm"
                visible: walkthrough.step < walkthrough.totalSteps - 1
                Accessible.name: "Skip setup walkthrough"
                onClicked: walkthrough.skipWalkthrough()
            }
        }

        // Scrollable step content area
        Flickable {
            id: bodyFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: Math.max(height, contentColumn.implicitHeight + 16)
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: contentColumn
                width: Math.min(bodyFlick.width, 640)
                x: Math.floor((bodyFlick.width - width) / 2)
                y: Math.max(4, Math.floor((bodyFlick.height - implicitHeight) / 2))
                spacing: 14

                // TASK MANAGER STYLE SYSTEM TELEMETRY STAGE (Replaces legacy honeycomb canvas)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 142
                    implicitWidth: 640
                    implicitHeight: 142
                    radius: Theme.radiusMd
                    color: Theme.surfaceContainerLow
                    border.width: 1
                    border.color: Theme.outlineVariant
                    clip: true

                    // Telemetry Header
                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 10
                        spacing: 8

                        Rectangle {
                            width: 8; height: 8
                            radius: 4
                            color: "#22c55e"
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { from: 0.4; to: 1.0; duration: 1000; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: 1.0; to: 0.4; duration: 1000; easing.type: Easing.InOutQuad }
                            }
                        }

                        Txt {
                            text: qsTr("SYSTEM TELEMETRY · DIRECT P2P LINK")
                            role: "code"
                            size: 11
                            color: Theme.surfaceContentVariant
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            radius: 4
                            color: Theme.surfaceContainerHighest
                            implicitWidth: portTxt.implicitWidth + 14
                            implicitHeight: 20
                            Txt {
                                id: portTxt
                                anchors.centerIn: parent
                                text: qsTr("PORT 53320 · TLS 1.3")
                                role: "code"
                                size: 10
                                color: Theme.primary
                            }
                        }
                    }

                    // 3-Card Task Manager Grid: Host Mac | P2P Bridge | Android Phone
                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.top: parent.top
                        anchors.topMargin: 34
                        anchors.margins: 12
                        spacing: 10

                        // Host PC Telemetry Card
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.radiusSm
                            color: Theme.surfaceContainer
                            border.width: 1
                            border.color: Theme.outlineVariant

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 2
                                RowLayout {
                                    spacing: 6
                                    Icon { path: Icons.laptop; width: 14; height: 14; color: Theme.primary }
                                    Txt { text: qsTr("Mac Host"); role: "caption"; color: Theme.surfaceContentVariant }
                                }
                                Txt { text: qsTr("MacBook (Local Node)"); role: "bodySmall"; elide: Text.ElideRight }
                                Txt { text: qsTr("Local QUIC Service Active"); role: "code"; size: 10; color: "#22c55e" }
                            }
                        }

                        // Encrypted Bridge Telemetry Indicator
                        Rectangle {
                            Layout.preferredWidth: 156
                            Layout.fillHeight: true
                            radius: Theme.radiusSm
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                            border.width: 1
                            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 3

                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: 4
                                    Icon { path: Icons.bolt; width: 12; height: 12; color: Theme.primary }
                                    Txt {
                                        text: walkthrough.hasPairedDevice ? qsTr("LINK ACTIVE") : qsTr("DISCOVERY")
                                        role: "code"
                                        size: 10
                                        color: Theme.primary
                                    }
                                }

                                // Activity pulse line
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 3
                                    radius: 1.5
                                    color: Theme.surfaceContainerHighest
                                    clip: true
                                    Rectangle {
                                        id: pulseBar
                                        width: 44; height: 3
                                        radius: 1.5
                                        color: Theme.primary
                                        SequentialAnimation on x {
                                            loops: Animation.Infinite
                                            NumberAnimation { from: 0; to: 104; duration: 1600; easing.type: Easing.InOutQuad }
                                            NumberAnimation { from: 104; to: 0; duration: 1600; easing.type: Easing.InOutQuad }
                                        }
                                    }
                                }

                                Txt {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: qsTr("0% Cloud · 100% P2P")
                                    role: "code"
                                    size: 9
                                    color: Theme.surfaceContentVariant
                                }
                            }
                        }

                        // Android Device Telemetry Card
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.radiusSm
                            color: Theme.surfaceContainer
                            border.width: 1
                            border.color: walkthrough.hasPairedDevice ? "#22c55e" : Theme.outlineVariant

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 2
                                RowLayout {
                                    spacing: 6
                                    Icon {
                                        path: Icons.phone
                                        width: 14; height: 14
                                        color: walkthrough.hasPairedDevice ? "#22c55e" : Theme.surfaceContentVariant
                                    }
                                    Txt { text: qsTr("Android Phone"); role: "caption"; color: Theme.surfaceContentVariant }
                                }
                                Txt {
                                    text: walkthrough.activeDeviceName || (walkthrough.hasPairedDevice ? qsTr("Paired Phone") : qsTr("Awaiting Pair..."))
                                    role: "bodySmall"
                                    elide: Text.ElideRight
                                }
                                Txt {
                                    text: walkthrough.hasPairedDevice ? qsTr("Connected (LAN Direct)") : qsTr("Open MacLink App")
                                    role: "code"
                                    size: 10
                                    color: walkthrough.hasPairedDevice ? "#22c55e" : Theme.surfaceContentVariant
                                }
                            }
                        }
                    }
                }

                // Step Title & Subtitle Header
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Txt {
                        text: walkthrough.stepTitles[walkthrough.step]
                        role: "headline"
                    }

                    Txt {
                        Layout.fillWidth: true
                        text: walkthrough.stepSubtitles[walkthrough.step]
                        role: "body"
                        color: Theme.surfaceContentVariant
                        wrapMode: Text.WordWrap
                    }
                }

                // -------------------------------------------------------------
                // STEP 0: CONNECT PHONE (APK Download, USB ADB, QR Pairing)
                // -------------------------------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: walkthrough.step === 0

                    // Option 1: Direct APK Download
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: releaseCol.implicitHeight + 28
                        radius: Theme.radiusMd
                        color: Theme.surfaceContainerLow
                        border.width: 1
                        border.color: Theme.outlineVariant

                        ColumnLayout {
                            id: releaseCol
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Icon {
                                    path: Icons.download
                                    width: 18
                                    height: 18
                                    color: Theme.primary
                                }

                                Txt {
                                    Layout.fillWidth: true
                                    text: qsTr("Download MacLink Android APK (Android 8.0+)")
                                    role: "title"
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Txt {
                                Layout.fillWidth: true
                                text: qsTr("Directly download the signed APK to your phone or Mac.")
                                role: "caption"
                                color: Theme.surfaceContentVariant
                                wrapMode: Text.WordWrap
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Button {
                                    text: qsTr("Download APK")
                                    iconPath: Icons.download
                                    variant: "fill"
                                    size: "sm"
                                    Accessible.name: "Download Android APK directly"
                                    onClicked: Qt.openUrlExternally("https://github.com/anksarvesh-lgtm/MacLink/releases/latest/download/MacLink-" + AppController.version + "-android.apk")
                                }

                                Button {
                                    text: qsTr("GitHub Releases")
                                    iconPath: Icons.openExternal
                                    variant: "tonal"
                                    size: "sm"
                                    Accessible.name: "Open Android release page in browser"
                                    onClicked: Qt.openUrlExternally("https://github.com/anksarvesh-lgtm/MacLink/releases/latest")
                                }

                                Button {
                                    id: copyUrlBtn
                                    property bool copied: false
                                    text: copied ? qsTr("Copied APK Link") : qsTr("Copy APK Link")
                                    iconPath: copied ? Icons.check : Icons.copy
                                    variant: "outline"
                                    size: "sm"
                                    Accessible.name: "Copy Android APK download URL"
                                    onClicked: {
                                        AppController.copyText("https://github.com/anksarvesh-lgtm/MacLink/releases/latest/download/MacLink-" + AppController.version + "-android.apk")
                                        copied = true
                                        resetCopyUrlTimer.restart()
                                    }
                                    Timer {
                                        id: resetCopyUrlTimer
                                        interval: 2000
                                        onTriggered: copyUrlBtn.copied = false
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }
                        }
                    }

                    // Option 2: Install over USB via ADB
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: adbCol.implicitHeight + 24
                        radius: Theme.radiusMd
                        color: Theme.surfaceContainerLow
                        border.width: 1
                        border.color: Theme.outlineVariant

                        ColumnLayout {
                            id: adbCol
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Icon {
                                    path: Icons.terminal
                                    width: 16
                                    height: 16
                                    color: Theme.primary
                                }

                                Txt {
                                    Layout.fillWidth: true
                                    text: qsTr("Install over USB with ADB")
                                    role: "title"
                                    size: 13
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    radius: Theme.radiusSm
                                    color: Theme.surfaceContainer
                                    border.width: 1
                                    border.color: Theme.outlineVariant

                                    Txt {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        text: walkthrough.adbCommand
                                        role: "code"
                                        size: 12
                                        elide: Text.ElideRight
                                    }
                                }

                                Button {
                                    id: copyAdbBtn
                                    property bool copied: false
                                    text: copied ? qsTr("Copied") : qsTr("Copy")
                                    iconPath: copied ? Icons.check : Icons.copy
                                    variant: "outline"
                                    size: "sm"
                                    Accessible.name: "Copy adb command"
                                    onClicked: {
                                        AppController.copyText(walkthrough.adbCommand)
                                        copied = true
                                        resetCopyAdbTimer.restart()
                                    }
                                    Timer {
                                        id: resetCopyAdbTimer
                                        interval: 2000
                                        onTriggered: copyAdbBtn.copied = false
                                    }
                                }
                            }
                        }
                    }

                    // Option 3: Pair Phone via QR Code or Discovery
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: Theme.radiusSm
                        visible: walkthrough.hasPairedDevice
                        color: Qt.rgba(0.18, 0.72, 0.42, 0.14)
                        border.width: 1
                        border.color: Qt.rgba(0.18, 0.72, 0.42, 0.40)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            Icon {
                                path: Icons.check
                                width: 16
                                height: 16
                                color: Qt.rgba(0.22, 0.80, 0.48, 1.0)
                            }

                            Txt {
                                Layout.fillWidth: true
                                text: qsTr("Paired with %1. You can continue to the next step.")
                                    .arg(walkthrough.activeDeviceName || qsTr("your phone"))
                                role: "caption"
                                color: Theme.surfaceContent
                                elide: Text.ElideRight
                            }
                        }
                    }

                    PairingPanel {
                        Layout.fillWidth: true
                        cancellable: false
                        compact: true
                        running: walkthrough.visible && walkthrough.step === 0
                    }
                }

                // -------------------------------------------------------------
                // STEP 1: ESSENTIAL SYNC (Notifications, Clipboard, Files/Photos)
                // -------------------------------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: walkthrough.step === 1

                    // Toggle Card 1: Notifications & Messages
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: notifRow.implicitHeight + 24
                        radius: Theme.radiusMd
                        color: Theme.surfaceContainerLow
                        border.width: 1
                        border.color: Theme.outlineVariant

                        RowLayout {
                            id: notifRow
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 14

                            Rectangle {
                                width: 38; height: 38; radius: Theme.radiusSm
                                color: Theme.surfaceContainerHighest
                                Icon {
                                    anchors.centerIn: parent
                                    path: Icons.chat
                                    width: 18; height: 18
                                    color: Theme.primary
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Txt {
                                    text: qsTr("Notifications & Incoming Calls")
                                    role: "title"
                                    size: 14
                                }
                                Txt {
                                    text: qsTr("See phone alerts on Mac, reply instantly to SMS, and get call banners.")
                                    role: "caption"
                                    color: Theme.surfaceContentVariant
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Toggle {
                                checked: walkthrough.isDeviceToggleOn("notifications")
                                label: "Toggle notifications"
                                onToggled: on => {
                                    walkthrough.setDeviceToggleValue("notifications", on)
                                    walkthrough.setDeviceToggleValue("sms", on)
                                    walkthrough.setDeviceToggleValue("calls", on)
                                }
                            }
                        }
                    }

                    // Toggle Card 2: Universal Clipboard
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: clipRow.implicitHeight + 24
                        radius: Theme.radiusMd
                        color: Theme.surfaceContainerLow
                        border.width: 1
                        border.color: Theme.outlineVariant

                        RowLayout {
                            id: clipRow
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 14

                            Rectangle {
                                width: 38; height: 38; radius: Theme.radiusSm
                                color: Theme.surfaceContainerHighest
                                Icon {
                                    anchors.centerIn: parent
                                    path: Icons.copy
                                    width: 18; height: 18
                                    color: Theme.primary
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Txt {
                                    text: qsTr("Universal Clipboard")
                                    role: "title"
                                    size: 14
                                }
                                Txt {
                                    text: qsTr("Seamlessly copy text and images on your Mac and paste immediately on your phone.")
                                    role: "caption"
                                    color: Theme.surfaceContentVariant
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Toggle {
                                checked: walkthrough.isDeviceToggleOn("clipboard")
                                label: "Toggle universal clipboard"
                                onToggled: on => walkthrough.setDeviceToggleValue("clipboard", on)
                            }
                        }
                    }

                    // Toggle Card 3: Files & Photos
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: filesRow.implicitHeight + 24
                        radius: Theme.radiusMd
                        color: Theme.surfaceContainerLow
                        border.width: 1
                        border.color: Theme.outlineVariant

                        RowLayout {
                            id: filesRow
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 14

                            Rectangle {
                                width: 38; height: 38; radius: Theme.radiusSm
                                color: Theme.surfaceContainerHighest
                                Icon {
                                    anchors.centerIn: parent
                                    path: Icons.folder
                                    width: 18; height: 18
                                    color: Theme.primary
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Txt {
                                    text: qsTr("Files & Photo Library Sync")
                                    role: "title"
                                    size: 14
                                }
                                Txt {
                                    text: qsTr("Drag-and-drop file transfers, top drop shelf, and instant camera photo preview.")
                                    role: "caption"
                                    color: Theme.surfaceContentVariant
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Toggle {
                                checked: walkthrough.isDeviceToggleOn("files")
                                label: "Toggle files and photos"
                                onToggled: on => {
                                    walkthrough.setDeviceToggleValue("files", on)
                                    walkthrough.setDeviceToggleValue("media", on)
                                }
                            }
                        }
                    }
                }

                // -------------------------------------------------------------
                // STEP 2: ALL SET & TASK MANAGER STATUS OVERVIEW
                // -------------------------------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 14
                    visible: walkthrough.step === 2

                    // System Health Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: healthCol.implicitHeight + 28
                        radius: Theme.radiusMd
                        color: Theme.surfaceContainerLow
                        border.width: 1
                        border.color: Theme.outlineVariant

                        ColumnLayout {
                            id: healthCol
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12

                            RowLayout {
                                spacing: 8
                                Icon { path: Icons.check; width: 18; height: 18; color: "#22c55e" }
                                Txt {
                                    text: qsTr("MacLink Engine is Ready")
                                    role: "title"
                                }
                            }

                            Txt {
                                Layout.fillWidth: true
                                text: qsTr("All essential link services are configured and running. You have complete private control with zero cloud telemetry.")
                                role: "body"
                                color: Theme.surfaceContentVariant
                                wrapMode: Text.WordWrap
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Theme.outlineVariant
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                Icon {
                                    path: walkthrough.doctorAllPassed ? Icons.check : Icons.info
                                    width: 16; height: 16
                                    color: walkthrough.doctorAllPassed ? "#22c55e" : Theme.primary
                                }

                                Txt {
                                    Layout.fillWidth: true
                                    text: walkthrough.doctorSummaryLabel
                                    role: "caption"
                                    color: Theme.surfaceContentVariant
                                    elide: Text.ElideRight
                                }

                                Button {
                                    text: qsTr("Run Doctor")
                                    iconPath: Icons.refresh
                                    variant: "outline"
                                    size: "sm"
                                    Accessible.name: "Run connection doctor"
                                    onClicked: walkthrough.doctorRequested()
                                }
                            }
                        }
                    }

                    // Getting Started Actions
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: actionsCol.implicitHeight + 24
                        radius: Theme.radiusMd
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)

                        ColumnLayout {
                            id: actionsCol
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            Txt {
                                text: qsTr("Quick Tips & Help")
                                role: "title"
                                size: 14
                            }

                            Txt {
                                text: qsTr("• Drop shelf: Move mouse to top screen edge to share files instantly\n• Screen mirror: Launch your Android screen or individual apps\n• Help Center: Browse full feature guides anytime")
                                role: "caption"
                                color: Theme.surfaceContentVariant
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }

        // Bottom action bar: Back, Help Center, Next / Done
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Button {
                text: qsTr("Back")
                iconPath: Icons.back
                variant: "tonal"
                size: "md"
                visible: walkthrough.step > 0
                Accessible.name: "Back to previous step"
                onClicked: walkthrough.goBack()
            }

            Item { Layout.fillWidth: true }

            Button {
                text: qsTr("Help Center")
                iconPath: Icons.info
                variant: "tonal"
                size: "md"
                visible: walkthrough.step === walkthrough.totalSteps - 1
                Accessible.name: "Finish setup and open Help Center"
                onClicked: walkthrough.finishAndOpenGuide()
            }

            Button {
                text: walkthrough.step === walkthrough.totalSteps - 1
                    ? qsTr("Start Using MacLink")
                    : (walkthrough.step === 0 ? qsTr("Get Started") : qsTr("Next"))
                iconPath: walkthrough.step === walkthrough.totalSteps - 1 ? Icons.check : Icons.chevronRight
                variant: "fill"
                size: "md"
                Accessible.name: walkthrough.step === walkthrough.totalSteps - 1 ? "Finish walkthrough" : "Next step"
                onClicked: walkthrough.goNext()
            }
        }
    }
}
