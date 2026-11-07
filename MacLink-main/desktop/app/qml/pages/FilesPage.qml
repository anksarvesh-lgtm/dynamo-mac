// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import app.maclink

// Android File Manager: Browse, search, upload, and download files and folders
// across internal storage on the paired Android device.
Item {
    id: page
    property bool active: false
    property string deviceId: ""
    property string deviceName: ""

    property string currentPath: "Download"
    property string searchQuery: ""
    property string selectedFolderCategory: "Download"
    property bool showNewFolderRow: false
    property string newFolderName: ""

    FileDialog {
        id: uploadDialog
        title: qsTr("Choose files to upload to %1 (%2)").arg(page.deviceName || qsTr("Phone")).arg(page.currentPath.length > 0 ? page.currentPath : qsTr("Root"))
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            if (page.deviceId.length > 0 && selectedFiles.length > 0) {
                let urls = []
                for (let i = 0; i < selectedFiles.length; i++) {
                    urls.push(selectedFiles[i].toString())
                }
                AppController.uploadFilesToRemote(page.deviceId, page.currentPath, JSON.stringify(urls))
            }
        }
    }

    // Quick access categories mapped to standard Android storage directories
    readonly property var quickFolders: [
        { name: qsTr("Download"), path: "Download", icon: Icons.download, count: qsTr("Recent downloads") },
        { name: qsTr("Documents"), path: "Documents", icon: Icons.text, count: qsTr("Work & PDFs") },
        { name: qsTr("DCIM"), path: "DCIM/Camera", icon: Icons.camera, count: qsTr("Camera photos") },
        { name: qsTr("Pictures"), path: "Pictures", icon: Icons.photo, count: qsTr("Screenshots & Images") },
        { name: qsTr("Music"), path: "Music", icon: Icons.sound, count: qsTr("Audio files") },
        { name: qsTr("Movies"), path: "Movies", icon: Icons.video, count: qsTr("Videos & Recordings") },
        { name: qsTr("Root"), path: "", icon: Icons.folder, count: qsTr("Internal storage root") }
    ]

    // Real remote files loaded from device via AppController
    readonly property var remoteItems: {
        try {
            let json = AppController.remoteStorageEntriesJson
            if (!json || json.length === 0) return []
            return JSON.parse(json)
        } catch (e) {
            return []
        }
    }

    readonly property var displayedItems: {
        let q = searchQuery.trim().toLowerCase()
        if (q.length === 0) return remoteItems
        return remoteItems.filter(item => item.name.toLowerCase().indexOf(q) >= 0)
    }

    function navigateTo(folderPath, categoryName) {
        currentPath = folderPath || ""
        if (categoryName)
            selectedFolderCategory = categoryName
        showNewFolderRow = false
        AppController.browseRemoteStorage(page.deviceId, currentPath)
    }

    function navigateUp() {
        if (!currentPath || currentPath.length === 0) return
        let parts = currentPath.split("/").filter(p => p.length > 0)
        parts.pop()
        currentPath = parts.join("/")
        showNewFolderRow = false
        AppController.browseRemoteStorage(page.deviceId, currentPath)
    }

    function refresh() {
        showNewFolderRow = false
        AppController.browseRemoteStorage(page.deviceId, currentPath)
    }

    function submitNewFolder() {
        let name = newFolderName.trim()
        if (name.length > 0) {
            AppController.createRemoteFolder(page.deviceId, currentPath, name)
            newFolderName = ""
            showNewFolderRow = false
        }
    }

    Component.onCompleted: {
        let dev = page.deviceId.length > 0 ? page.deviceId : (typeof window !== "undefined" && window.currentDeviceId ? window.currentDeviceId : "")
        if (dev.length > 0) {
            if (page.deviceId !== dev) page.deviceId = dev
            AppController.browseRemoteStorage(dev, page.currentPath)
        }
    }

    onActiveChanged: {
        if (active) {
            let dev = page.deviceId.length > 0 ? page.deviceId : (typeof window !== "undefined" && window.currentDeviceId ? window.currentDeviceId : "")
            if (dev.length > 0) {
                if (page.deviceId !== dev) page.deviceId = dev
                AppController.browseRemoteStorage(dev, page.currentPath)
            }
        }
    }

    onDeviceIdChanged: {
        if (page.deviceId.length > 0 && active) {
            AppController.browseRemoteStorage(page.deviceId, page.currentPath)
        }
    }

    // No phone connected banner
    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.contentPadding * 2, 440)
        spacing: 12
        visible: page.deviceId.length === 0

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 44; height: 44
            path: Icons.folder
            color: Theme.surfaceContentVariant
        }
        Txt {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            role: "title"
            text: qsTr("Android File Manager")
        }
        Txt {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            role: "body"
            muted: true
            text: qsTr("Connect your Android phone to browse internal storage folders, upload files, and download documents to your Mac.")
        }
    }

    // Main File Manager View
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.contentPadding
        spacing: 14
        visible: page.deviceId.length > 0

        // 1. Storage Telemetry Header
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: storageCol.implicitHeight + 24
            radius: Theme.cardCornerRadius
            color: Theme.cardFill
            border.width: 1
            border.color: Theme.cardBorderSubtle

            ColumnLayout {
                id: storageCol
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Icon {
                        path: Icons.folder
                        width: 18; height: 18
                        color: Theme.primary
                    }

                    Txt {
                        text: qsTr("%1 · Internal Storage").arg(page.deviceName || qsTr("Phone"))
                        role: "title"
                        size: 15
                    }

                    Item { Layout.fillWidth: true }

                    Txt {
                        text: AppController.remoteStorageSummary || qsTr("%1 items").arg(page.remoteItems.length)
                        role: "code"
                        size: 11
                        color: Theme.surfaceContentVariant
                    }

                    Button {
                        text: page.width < 560 ? qsTr("Downloads") : qsTr("Downloads Folder")
                        iconPath: Icons.folder
                        variant: "ghost"
                        size: "sm"
                        Accessible.name: qsTr("Open local MacLink Downloads folder in Finder")
                        onClicked: AppController.openLocalDownloads()
                    }

                    Button {
                        text: page.width < 620 ? qsTr("FTP") : qsTr("Connect via FTP")
                        iconPath: Icons.globe
                        variant: "tonal"
                        size: "sm"
                        Accessible.name: qsTr("Connect to phone FTP server in Finder")
                        onClicked: ftpSheet.open()
                    }
                }
            }
        }

        // 2. Action Toolbar & Breadcrumb Navigation
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Up folder navigation button
            IconButton {
                iconPath: Icons.back
                label: qsTr("Go up one folder")
                enabled: page.currentPath.length > 0
                onClicked: page.navigateUp()
            }

            // Refresh button
            IconButton {
                iconPath: Icons.sparkle
                label: qsTr("Refresh folder contents")
                onClicked: page.refresh()
            }

            // Path Breadcrumbs
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: Theme.tileCornerRadius
                color: Theme.cardFill
                border.width: 1
                border.color: Theme.cardBorderSubtle

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 6

                    Icon {
                        path: Icons.phone
                        width: 14; height: 14
                        color: Theme.surfaceContentVariant
                    }

                    Txt {
                        Layout.fillWidth: true
                        text: page.currentPath.length > 0 ? ("/storage/emulated/0/" + page.currentPath) : "/storage/emulated/0"
                        role: "code"
                        size: 12
                        elide: Text.ElideMiddle
                    }
                }
            }

            // New Folder Toggle Button
            IconButton {
                iconPath: Icons.folder
                label: qsTr("New Folder")
                onClicked: {
                    page.showNewFolderRow = !page.showNewFolderRow
                    if (page.showNewFolderRow) {
                        newFolderInput.forceActiveFocus()
                    }
                }
            }

            // Search Bar
            Rectangle {
                implicitWidth: 180
                implicitHeight: 36
                radius: height / 2
                color: Theme.cardFill
                border.width: 1
                border.color: searchInput.activeFocus ? Theme.amberAccent : Theme.cardBorderSubtle
                Behavior on border.color { ColorAnimation { duration: 120 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    spacing: 6

                    Icon { path: Icons.search; width: 14; height: 14; color: Theme.surfaceContentVariant }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        color: Theme.surfaceContent
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        selectByMouse: true
                        clip: true
                        Accessible.name: qsTr("Search files")
                        onTextChanged: page.searchQuery = text

                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Search files...")
                            role: "caption"
                            muted: true
                            visible: searchInput.text.length === 0
                        }
                    }
                }
            }

            // Upload File Button
            Button {
                text: page.width < 620 ? qsTr("Upload") : qsTr("Upload to Phone")
                iconPath: Icons.download
                variant: Theme.glass ? "amber" : "fill"
                size: "sm"
                Accessible.name: qsTr("Upload files from Mac to Android phone")
                onClicked: uploadDialog.open()
            }
        }

        // New Folder Inline Bar
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            visible: page.showNewFolderRow
            radius: Theme.tileCornerRadius
            color: Theme.cardFill
            border.width: 1
            border.color: Theme.amberAccent

            RowLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 8

                Icon {
                    path: Icons.folder
                    width: 16; height: 16
                    color: Theme.amberAccent
                }

                TextInput {
                    id: newFolderInput
                    Layout.fillWidth: true
                    color: Theme.surfaceContent
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    selectByMouse: true
                    clip: true
                    text: page.newFolderName
                    onTextChanged: page.newFolderName = text
                    onAccepted: page.submitNewFolder()

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Enter new folder name...")
                        role: "caption"
                        muted: true
                        visible: newFolderInput.text.length === 0
                    }
                }

                Button {
                    text: qsTr("Create")
                    variant: "amber"
                    size: "sm"
                    onClicked: page.submitNewFolder()
                }

                Button {
                    text: qsTr("Cancel")
                    variant: "ghost"
                    size: "sm"
                    onClicked: {
                        page.showNewFolderRow = false
                        page.newFolderName = ""
                    }
                }
            }
        }

        // 3. Quick Access Shortcut Folder Chips
        Flow {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: page.quickFolders
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool selected: page.currentPath === modelData.path
                    height: 32
                    implicitWidth: chipRow.implicitWidth + 20
                    implicitHeight: 32
                    radius: 16
                    gradient: selected && Theme.glass ? amberChipGrad : null
                    color: selected
                        ? (Theme.glass ? Theme.amberAccentDeep : Theme.primary)
                        : (chipHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : Theme.cardFill)
                    border.width: 1
                    border.color: selected
                        ? (Theme.glass ? Theme.amberBorder : Theme.primary)
                        : (chipHover.hovered ? Theme.cardBorderHover : Theme.cardBorderSubtle)
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    Gradient {
                        id: amberChipGrad
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Theme.amberAccentDeep }
                        GradientStop { position: 1.0; color: Theme.amberAccent }
                    }

                    HoverHandler {
                        id: chipHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: page.navigateTo(modelData.path, modelData.name)
                    }

                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6

                        Icon {
                            path: modelData.icon
                            width: 13; height: 13
                            color: parent.parent.selected ? (Theme.glass ? "#FFFFFF" : Theme.primaryContent) : Theme.surfaceContent
                        }

                        Txt {
                            text: modelData.name
                            role: "label"
                            size: 12
                            color: parent.parent.selected ? (Theme.glass ? "#FFFFFF" : Theme.primaryContent) : Theme.surfaceContent
                        }
                    }
                }
            }
        }

        // Permission Warning Card
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: permCol.implicitHeight + 24
            visible: AppController.remoteStoragePermissionNeeded
            radius: Theme.cardCornerRadius
            color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12)
            border.width: 1
            border.color: Theme.error

            ColumnLayout {
                id: permCol
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                RowLayout {
                    spacing: 8
                    Icon { path: Icons.sparkle; width: 18; height: 18; color: Theme.error }
                    Txt {
                        text: qsTr("Storage Permission Required on Phone")
                        role: "title"
                        size: 14
                        color: Theme.error
                    }
                }

                Txt {
                    Layout.fillWidth: true
                    text: qsTr("To view files and folders on your Android device, open MacLink on your phone and toggle on 'Storage' permissions, or grant 'All files access' in Android Settings.")
                    role: "body"
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    spacing: 8
                    Button {
                        text: qsTr("Retry Connection")
                        variant: "fill"
                        size: "sm"
                        onClicked: page.refresh()
                    }
                }
            }
        }

        // 4. File and Folder List View
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: fileListView
                anchors.fill: parent
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: page.displayedItems

                delegate: Rectangle {
                    required property var modelData
                    width: fileListView.width
                    implicitHeight: 52
                    radius: Theme.tileCornerRadius
                    color: itemHover.hovered ? Qt.rgba(1, 1, 1, 0.06) : Theme.cardFill
                    border.width: 1
                    border.color: itemHover.hovered ? Theme.cardBorderHover : Theme.cardBorderSubtle
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    HoverHandler {
                        id: itemHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: {
                            if (modelData.isDir) {
                                let target = modelData.folder ? (modelData.folder + "/" + modelData.name) : modelData.name
                                page.navigateTo(target)
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 14

                        // File / Folder Type Icon
                        Rectangle {
                            width: 32; height: 32
                            radius: Theme.radiusSm
                            color: modelData.isDir ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.14) : Theme.surfaceContainer
                            Icon {
                                anchors.centerIn: parent
                                path: modelData.icon ? Icons[modelData.icon] || Icons.file : (modelData.isDir ? Icons.folder : Icons.file)
                                width: 16; height: 16
                                color: modelData.isDir ? Theme.primary : Theme.surfaceContent
                            }
                        }

                        // File Information
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Txt {
                                Layout.fillWidth: true
                                text: modelData.name
                                role: "body"
                                weight: modelData.isDir ? 600 : 400
                                elide: Text.ElideRight
                            }

                            RowLayout {
                                spacing: 12
                                Txt { text: modelData.size; role: "caption"; size: 10; color: Theme.surfaceContentVariant }
                                Txt { text: "•"; role: "caption"; size: 10; color: Theme.surfaceContentVariant }
                                Txt { text: modelData.date; role: "caption"; size: 10; color: Theme.surfaceContentVariant }
                            }
                        }

                        // Action Buttons for File / Folder
                        RowLayout {
                            spacing: 6

                            IconButton {
                                visible: !modelData.isDir
                                iconPath: Icons.download
                                iconSize: 14
                                label: qsTr("Download to Mac")
                                onClicked: {
                                    let fullPath = modelData.folder ? (modelData.folder + "/" + modelData.name) : modelData.name
                                    AppController.downloadRemoteFile(page.deviceId, fullPath)
                                }
                            }

                            IconButton {
                                iconPath: Icons.copy
                                iconSize: 14
                                label: qsTr("Copy path")
                                onClicked: {
                                    let fullPath = modelData.folder ? (modelData.folder + "/" + modelData.name) : modelData.name
                                    AppController.copyText(fullPath)
                                }
                            }

                            IconButton {
                                iconPath: Icons.trash
                                iconSize: 14
                                label: qsTr("Delete from phone")
                                onClicked: {
                                    let fullPath = modelData.folder ? (modelData.folder + "/" + modelData.name) : modelData.name
                                    AppController.deleteRemoteItem(page.deviceId, fullPath)
                                }
                            }
                        }
                    }
                }
            }

            // Loading indicator
            Column {
                anchors.centerIn: parent
                spacing: 12
                visible: AppController.remoteStorageLoading

                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 32; height: 32
                    path: Icons.sparkle
                    color: Theme.amberAccent
                }
                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Fetching files from %1...").arg(page.deviceName || qsTr("Phone"))
                    role: "body"
                    muted: true
                }
            }

            // Empty folder indicator
            Txt {
                anchors.centerIn: parent
                visible: page.displayedItems.length === 0 && !AppController.remoteStorageLoading && !AppController.remoteStoragePermissionNeeded
                text: qsTr("This folder is empty or no matching files found.")
                role: "body"
                muted: true
            }
        }
    }

    // FTP Connection Sheet
    Sheet {
        id: ftpSheet
        cardWidth: 500

        ColumnLayout {
            width: parent.width
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    width: 36; height: 36
                    radius: 18
                    color: Qt.rgba(0.95, 0.66, 0.23, 0.15)
                    border.width: 1
                    border.color: Qt.rgba(0.95, 0.66, 0.23, 0.28)

                    Icon {
                        anchors.centerIn: parent
                        width: 18; height: 18
                        path: Icons.globe
                        color: Theme.amberAccent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Txt {
                        text: qsTr("Connect via FTP")
                        role: "title"
                        size: 16
                    }
                    Txt {
                        text: qsTr("MinimalFTP on Android · macOS Finder Mount")
                        role: "caption"
                        color: Theme.textSecondary
                    }
                }

                IconButton {
                    iconPath: Icons.close
                    label: qsTr("Close")
                    onClicked: ftpSheet.close()
                }
            }

            Txt {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Mount your Android phone directly in macOS Finder as an external volume or browse files using FileZilla, Cyberduck, or one-ftpserver.")
                role: "bodySmall"
                color: Theme.textSecondary
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: ftpRow.implicitHeight + 16
                radius: 12
                color: Qt.rgba(Theme.cardFill.r, Theme.cardFill.g, Theme.cardFill.b, 0.7)
                border.width: 1
                border.color: Theme.cardBorderSubtle

                RowLayout {
                    id: ftpRow
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    TextInput {
                        id: ftpUrlInput
                        Layout.fillWidth: true
                        text: AppController.remoteStorageFtpUrl.length > 0 ? AppController.remoteStorageFtpUrl : "ftp://192.168.1.100:2121"
                        color: Theme.amberAccent
                        font.family: Theme.fontFamilyMono
                        font.pixelSize: 13
                        selectByMouse: true
                    }

                    Button {
                        text: qsTr("Copy")
                        iconPath: Icons.copy
                        variant: "ghost"
                        size: "sm"
                        onClicked: {
                            AppController.copyText(ftpUrlInput.text)
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: stepCol.implicitHeight + 16
                radius: 10
                color: Qt.rgba(0, 0, 0, 0.2)

                ColumnLayout {
                    id: stepCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Txt {
                        Layout.fillWidth: true
                        text: qsTr("1. On your phone: Open MacLink › Settings › Data & Storage › Turn on 'FTP file server'.")
                        role: "caption"
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                    }
                    Txt {
                        Layout.fillWidth: true
                        text: qsTr("2. Enter the phone's FTP URL above, then click 'Open in Finder' or press Cmd+K in Finder.")
                        role: "caption"
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Item { Layout.fillWidth: true }

                Button {
                    text: qsTr("Cancel")
                    variant: "ghost"
                    size: "sm"
                    onClicked: ftpSheet.close()
                }

                Button {
                    text: qsTr("Open in Finder")
                    iconPath: Icons.laptop
                    variant: "primary"
                    size: "sm"
                    onClicked: {
                        Qt.openUrlExternally(ftpUrlInput.text)
                        ftpSheet.close()
                    }
                }
            }
        }
    }
}
