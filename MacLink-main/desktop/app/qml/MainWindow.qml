// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import app.maclink

// The main window: navigation rail, title bar and pages. Before any device
// is paired it shows the welcome (pairing) screen instead.
NativeWindow {
    id: window

    readonly property bool showWalkthrough: AppController.status === "ready" && !Preferences.walkthroughCompleted
    readonly property bool welcome: AppController.status !== "ready" || showWalkthrough
    property string page: AppController.currentPage.length > 0 ? AppController.currentPage : "home"
    property string pendingSettingsSection: ""
    onPageChanged: if (AppController.currentPage !== page) AppController.currentPage = page
    Connections {
        target: AppController
        function onCurrentPageChanged() {
            if (AppController.currentPage.length > 0 && window.page !== AppController.currentPage)
                window.page = AppController.currentPage
        }
        function onHighlightTargetChanged() {
            const targetId = AppController.highlightTarget
            if (!targetId || targetId.length === 0)
                return
            if (targetId.indexOf("__size__:") === 0) {
                const dims = targetId.substring("__size__:".length).split("x")
                if (dims.length === 2) {
                    window.width = parseInt(dims[0], 10)
                    window.height = parseInt(dims[1], 10)
                }
                AppController.clearHighlight()
                return
            }
            if (targetId.indexOf("__grab__:") === 0) {
                const outPath = targetId.substring("__grab__:".length)
                AppController.clearHighlight()
                if (window.contentItem && outPath.length > 0) {
                    window.contentItem.grabToImage(function(result) {
                        result.saveToFile(outPath)
                    })
                }
                return
            }
            window.applyHighlightNavigation(targetId)
        }
    }
    Timer {
        id: highlightClearTimer
        interval: 2000
        onTriggered: AppController.clearHighlight()
    }
    function applyHighlightNavigation(targetId) {
        if (!targetId || targetId.length === 0)
            return
        highlightClearTimer.restart()
        if (targetId === "doctor:open") {
            AppController.runDoctor()
            return
        }
        if (targetId.indexOf("settings:") === 0) {
            const parts = targetId.split(":")
            const section = parts.length > 1 ? parts[1] : "connection"
            window.pendingSettingsSection = section
            window.page = "settings"
            if (pageLoader.item && "currentSection" in pageLoader.item) {
                pageLoader.item.currentSection = section
                window.pendingSettingsSection = ""
            }
            return
        }
        if (targetId.indexOf("messages:") === 0) {
            window.page = "messages"
            return
        }
        if (targetId.indexOf("calls:") === 0) {
            window.page = "calls"
            return
        }
        if (targetId.indexOf("photos:") === 0) {
            window.page = "photos"
            return
        }
        if (targetId.indexOf("deck:") === 0) {
            window.page = "deck"
            return
        }
        if (targetId.indexOf("files:") === 0 || targetId.indexOf("file_manager:") === 0) {
            window.page = "files"
            return
        }
        if (targetId.indexOf("apps:") === 0) {
            window.page = "apps"
            return
        }
        if (targetId.indexOf("timeline:") === 0) {
            window.page = "timeline"
            return
        }
        window.page = "home"
    }
    function navigateTab(tabId) {
        if (tabId === "guide")
            window.page = "help_center"
        else
            window.page = tabId
    }
    function navigateAndHighlight(targetId) {
        if (!targetId || targetId.length === 0)
            return
        AppController.triggerHighlight(targetId)
        window.applyHighlightNavigation(targetId)
    }
    readonly property int currentDeviceIndex: DeviceList.count > 0
        ? Math.min(Math.max(0, AppController.currentDevice), DeviceList.count - 1) : 0
    readonly property string currentDeviceId: DeviceList.count > 0
        ? DeviceList.deviceIdAt(currentDeviceIndex) : ""
    readonly property string currentDeviceName: DeviceList.count > 0
        ? DeviceList.deviceNameAt(currentDeviceIndex) : ""

    minimumWidth: Theme.layout.minWindow[0]
    minimumHeight: Theme.layout.minWindow[1]
    property string normalScreen: Preferences.windowScreen
    property int normalWidth: Math.max(minimumWidth, Preferences.windowWidth > 0 ? Preferences.windowWidth : 1120)
    property int normalHeight: Math.max(minimumHeight, Preferences.windowHeight > 0 ? Preferences.windowHeight : 740)
    property int normalX: Preferences.windowX
    property int normalY: Preferences.windowY
    property bool hasNormalPosition: Preferences.hasWindowPosition
    property bool restoringGeometry: true

    width: normalWidth
    height: normalHeight
    title: "MacLink"

    function screenKey(s) {
        if (!s) return ""
        const parts = [s.manufacturer || "", s.model || "", s.serialNumber || ""].filter(function(p) { return p.length > 0 })
        if (parts.length > 0) return parts.join(":")
        return s.name || ""
    }

    function findScreen(ident) {
        const screens = Qt.application.screens
        if (!ident || ident.length === 0 || !screens || screens.length === 0) return null
        for (let i = 0; i < screens.length; ++i) {
            const s = screens[i]
            if (screenKey(s) === ident || s.name === ident) {
                return s
            }
        }
        return null
    }

    function primaryScreen() {
        const screens = Qt.application.screens
        if (screens && screens.length > 0) return screens[0]
        return window.screen ? window.screen : null
    }

    function screenOriginX(s) {
        return (s && s.virtualX !== undefined) ? s.virtualX : 0
    }

    function screenOriginY(s) {
        return (s && s.virtualY !== undefined) ? s.virtualY : 0
    }

    // A screen's own size. Its desktopAvailable* properties cover the whole
    // virtual desktop, which spans every monitor.
    function screenAvailWidth(s) {
        if (s && s.width > 0) return s.width
        return Screen.width > 0 ? Screen.width : 1920
    }

    function screenAvailHeight(s) {
        if (s && s.height > 0) return s.height
        return Screen.height > 0 ? Screen.height : 1080
    }

    function currentScreen() {
        const screens = Qt.application.screens
        if (screens && screens.length > 0) {
            const cx = window.x + Math.round(window.width / 2)
            const cy = window.y + Math.round(window.height / 2)
            for (let i = 0; i < screens.length; ++i) {
                const s = screens[i]
                const sx = screenOriginX(s)
                const sy = screenOriginY(s)
                const sw = screenAvailWidth(s)
                const sh = screenAvailHeight(s)
                if (cx >= sx && cx < sx + sw && cy >= sy && cy < sy + sh) {
                    return s
                }
            }
        }
        return window.screen ? window.screen : primaryScreen()
    }

    function updateNormalPositionFromWindow() {
        const s = currentScreen()
        const key = screenKey(s)
        if (key.length > 0) {
            normalScreen = key
        }
        normalX = window.x - screenOriginX(s)
        normalY = window.y - screenOriginY(s)
        hasNormalPosition = true
    }

    Timer {
        id: restoreCompleteTimer
        interval: 180
        onTriggered: {
            if (!Preferences.windowMaximized && window.visibility === Window.Windowed) {
                const s = findScreen(window.normalScreen) || primaryScreen()
                const targetGlobalX = screenOriginX(s) + window.normalX
                const targetGlobalY = screenOriginY(s) + window.normalY
                // In case showing changed it (see restoreAndBringToFront).
                if (window.width !== window.normalWidth) window.width = window.normalWidth
                if (window.height !== window.normalHeight) window.height = window.normalHeight
                if (window.hasNormalPosition) {
                    if (window.x !== targetGlobalX) window.x = targetGlobalX
                    if (window.y !== targetGlobalY) window.y = targetGlobalY
                } else if (window.visible) {
                    window.updateNormalPositionFromWindow()
                }
            }
            window.restoringGeometry = false
        }
    }

    Timer {
        id: geometrySaveTimer
        interval: 250
        onTriggered: window.saveWindowState()
    }

    // Note: On Wayland compositors, client-side global window coordinates (x, y) read as 0
    // and setting them is a no-op; only window dimensions, target screen, and maximized state take effect.
    function restoreAndBringToFront() {
        restoringGeometry = true
        const savedScreen = findScreen(Preferences.windowScreen)
        const targetScreen = savedScreen ? savedScreen : primaryScreen()
        const sx = screenOriginX(targetScreen)
        const sy = screenOriginY(targetScreen)
        const availW = screenAvailWidth(targetScreen)
        const availH = screenAvailHeight(targetScreen)

        const desiredW = Math.max(minimumWidth, Preferences.windowWidth > 0 ? Preferences.windowWidth : 1120)
        const desiredH = Math.max(minimumHeight, Preferences.windowHeight > 0 ? Preferences.windowHeight : 740)
        const minW = Math.min(minimumWidth, availW)
        const minH = Math.min(minimumHeight, availH)
        const fittedW = Math.max(minW, Math.min(desiredW, availW))
        const fittedH = Math.max(minH, Math.min(desiredH, availH))

        normalWidth = fittedW
        normalHeight = fittedH
        width = fittedW
        height = fittedH

        const targetKey = screenKey(targetScreen)
        if (targetKey.length > 0) {
            normalScreen = targetKey
        }

        if (savedScreen && Preferences.hasWindowPosition) {
            const maxRelX = Math.max(0, availW - fittedW)
            const maxRelY = Math.max(0, availH - fittedH)
            normalX = Math.max(0, Math.min(Preferences.windowX, maxRelX))
            normalY = Math.max(0, Math.min(Preferences.windowY, maxRelY))
            hasNormalPosition = true
        } else {
            normalX = Math.max(0, Math.round((availW - fittedW) / 2))
            normalY = Math.max(0, Math.round((availH - fittedH) / 2))
            hasNormalPosition = true
        }

        // NativeWindow's QML type doesn't expose `screen`; a position in
        // desktop coordinates puts the window on the right monitor anyway.
        x = sx + normalX
        y = sy + normalY

        bringToFront()
        // Again once shown: a size set before the first show comes out
        // taller by the title bar on Windows. This is also the size
        // un-maximizing returns to.
        width = fittedW
        height = fittedH
        x = sx + normalX
        y = sy + normalY
        if (Preferences.windowMaximized)
            showMaximized()
        restoreCompleteTimer.restart()
    }

    function saveWindowState() {
        geometrySaveTimer.stop()
        if (window.visible && !restoringGeometry) {
            const s = currentScreen()
            const key = screenKey(s)
            if (key.length > 0) {
                normalScreen = key
            }
            if (window.visibility === Window.Windowed
                && window.width >= window.minimumWidth && window.height >= window.minimumHeight) {
                normalX = window.x - screenOriginX(s)
                normalY = window.y - screenOriginY(s)
                hasNormalPosition = true
                normalWidth = Math.max(window.minimumWidth, window.width)
                normalHeight = Math.max(window.minimumHeight, window.height)
            }
        }
        Preferences.saveWindowGeometry(
            normalScreen,
            hasNormalPosition,
            normalX,
            normalY,
            normalWidth,
            normalHeight,
            window.visibility === Window.Maximized
        )
    }

    property bool resizing: resizeSettleTimer.running
    Timer {
        id: resizeSettleTimer
        interval: 140
    }
    onXChanged: if (visible && !restoringGeometry) geometrySaveTimer.restart()
    onYChanged: if (visible && !restoringGeometry) geometrySaveTimer.restart()
    onWidthChanged: {
        if (visible) {
            resizeSettleTimer.restart()
            if (!restoringGeometry)
                geometrySaveTimer.restart()
        }
    }
    onHeightChanged: {
        if (visible) {
            resizeSettleTimer.restart()
            if (!restoringGeometry)
                geometrySaveTimer.restart()
        }
    }
    // QWindow::visibilityChanged is a revisioned signal that NativeWindow's
    // QML type doesn't expose as a handler, so connect to it instead.
    Connections {
        target: window
        function onVisibilityChanged() {
            if (window.visible && !window.restoringGeometry
                && (window.visibility === Window.Windowed || window.visibility === Window.Maximized))
                geometrySaveTimer.restart()
        }
    }

    // Mica/Acrylic is applied by Windows a moment after it's requested. Showing
    // through before it's there reveals the bare desktop (a flash), so the
    // window turns translucent only once the backdrop is in place, and opaque again
    // before it is removed.
    // Hive keeps its own fixed colors, so it never shows the wallpaper through.
    readonly property bool wantBackdrop: (Qt.platform.os === "windows" || Qt.platform.os === "osx") && !Theme.amoled && !Theme.hive
    property bool micaApplied: false
    property bool micaVisible: Qt.platform.os === "osx" || wantBackdrop
    backdrop: micaApplied
    acrylic: Theme.glass
    Timer {
        id: micaSettle
        interval: 220
        onTriggered: window.micaVisible = window.wantBackdrop
    }
    Timer {
        id: micaRelease
        interval: Theme.fadeNormal + 60
        onTriggered: window.micaApplied = window.wantBackdrop
    }
    function followBackdrop() {
        if (window.wantBackdrop) {
            micaRelease.stop()
            micaApplied = true
            micaSettle.restart()
        } else {
            micaSettle.stop()
            micaVisible = false
            micaRelease.restart()
        }
    }
    onWantBackdropChanged: followBackdrop()
    Connections {
        target: Preferences
        function onBackdropChanged() { window.followBackdrop() }
    }
    Connections {
        target: window
        function onActiveChanged() {
            if (window.active) {
                AppController.refreshToastsEnabled()
                if (!window.activeFocusItem && window.contentItem)
                    window.contentItem.forceActiveFocus()
            }
        }
        function onActiveFocusItemChanged() {
            if (!window.activeFocusItem && window.contentItem)
                Qt.callLater(() => {
                    if (!window.activeFocusItem && window.contentItem)
                        window.contentItem.forceActiveFocus()
                })
        }
    }
    Component.onCompleted: {
        followBackdrop()
        if (!window.activeFocusItem && window.contentItem)
            window.contentItem.forceActiveFocus()
    }
    darkFrame: Theme.dark
    captionHeight: Theme.topBarHeight

    function openPairing() { pairingSheet.open() }

    // Window background: a tinted veil of the theme over Mica/Acrylic (so the
    // theme's seed color is rich and clear), opaque otherwise.
    readonly property color windowSurface: Theme.graphite || Theme.amoled || Theme.hive
        ? Theme.surface
        : Qt.tint(
            Theme.surface,
            Qt.rgba(
                Theme.primaryContainer.r,
                Theme.primaryContainer.g,
                Theme.primaryContainer.b,
                Theme.isPhoneSeed ? (Theme.dark ? 0.22 : 0.30) : (Theme.dark ? 0.12 : 0.18)
            )
        )
    // Window backdrop layer (sampled by Liquid Glass panels)
    Item {
        id: windowBackdrop
        anchors.fill: parent

        // Warm near-black brown base
        Rectangle {
            anchors.fill: parent
            color: Theme.windowBg
        }

        // Soft amber glow at top-right
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: -90
            anchors.rightMargin: -90
            width: 520; height: 520; radius: 260
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.72, 0.45, 0.10, 0.22) }
                GradientStop { position: 0.45; color: Qt.rgba(0.72, 0.45, 0.10, 0.06) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Extended amber glow behind the left sidebar/rail for rich glass refraction
        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: -120
            width: 380; height: 520; radius: 190
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.72, 0.45, 0.10, 0.20) }
                GradientStop { position: 0.50; color: Qt.rgba(0.72, 0.45, 0.10, 0.06) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    // Hive: the living comb behind everything, growing from the logo. It
    // holds its frame while the window isn't in front or is minimized.
    HiveBackdrop {
        id: hiveComb
        anchors.fill: parent
        visible: opacity > 0
        opacity: Theme.hive ? 1 : 0
        Behavior on opacity {
            enabled: !Theme.reduceMotion
            NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
        }
        animate: Theme.combMotion
        ownClock: false
        time: Theme.combTime
        cell: Theme.comb.cell
        frameMs: Theme.comb.frameMs
        breathSeconds: Theme.comb.breathSeconds
        pulseSeconds: Theme.comb.pulseSeconds
        lineColor: Theme.combLine
        glowColor: Theme.combGlow
        // The center of the logo mark in the rail; the comb and its pulses
        // carry across the whole window.
        origin: Qt.point(Theme.railWidth / 2, Theme.topBarHeight / 2)
        reach: 2.4
        pulseReach: 1.05
    }

    // The comb's clock runs while this window is in front and showing Hive.
    Binding {
        target: Theme
        property: "combClockRunning"
        value: window.active && window.visible
               && window.visibility !== Window.Minimized && window.visibility !== Window.Hidden
    }

    // Dynamic native GPU-blurred ambient layer when "Glass" theme mode is active.
    Item {
        id: artworkAmbient
        anchors.fill: parent
        clip: true
        opacity: Theme.ambientBlurActive ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity {
            enabled: !Theme.reduceMotion
            NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
        }

        // Fixed-resolution 256x256 ambient mesh + blur so window resizing never
        // reallocates full-window GPU blur FBOs on every pixel.
        Item {
            id: glassColorMesh
            width: 256
            height: 256
            visible: false
            layer.enabled: glassMeshBlur.visible && window.visible && window.visibility !== Window.Minimized
            layer.textureSize: Qt.size(256, 256)
            layer.smooth: true

            Rectangle {
                width: 174; height: 174; radius: 87
                x: -31; y: -42
                color: Theme.primary
                opacity: Theme.dark ? 0.56 : 0.44
                Behavior on color { ColorAnimation { duration: 480 } }
            }
            Rectangle {
                width: 154; height: 154; radius: 77
                x: 123; y: 56
                color: Theme.primaryContainer
                opacity: Theme.dark ? 0.62 : 0.52
                Behavior on color { ColorAnimation { duration: 480 } }
            }
            Rectangle {
                width: 138; height: 138; radius: 69
                x: 31; y: 128
                color: Theme.secondaryContainer
                opacity: Theme.dark ? 0.54 : 0.46
                Behavior on color { ColorAnimation { duration: 480 } }
            }
            Rectangle {
                width: 108; height: 108; radius: 54
                x: 159; y: -15
                color: Qt.lighter(Theme.primary, 1.35)
                opacity: Theme.dark ? 0.34 : 0.28
                Behavior on color { ColorAnimation { duration: 480 } }
            }
        }

        MultiEffect {
            id: glassMeshBlur
            width: 256
            height: 256
            source: glassColorMesh
            visible: Theme.glass
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 48
            blur: 1.0
            saturation: Theme.dark ? 0.42 : 0.30
            transform: Scale {
                xScale: artworkAmbient.width / 256
                yScale: artworkAmbient.height / 256
            }
        }

        // Translucent surface veil so UI cards and typography stay crisp over the blurred backdrop.
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(
                Theme.surface.r,
                Theme.surface.g,
                Theme.surface.b,
                Theme.glass ? (Theme.amoled ? 0.62 : (Theme.dark ? 0.22 : 0.28)) : (Theme.dark ? 0.60 : 0.66)
            )
            Behavior on color {
                enabled: !Theme.reduceMotion
                ColorAnimation { duration: 360; easing.type: Easing.OutCubic }
            }
        }
    }

    // ---- Liquid Glass component (for rail, capsule, and buttons) ----
    component GlassPanel: Item {
        id: gpRoot
        property Item backdrop: windowBackdrop
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
                radius: gpRoot.radius
                color: "#FFFFFF"
            }
        }

        // 5. Shadow (soft shadow below and outside panel)
        MultiEffect {
            anchors.fill: parent
            visible: gpRoot.hasShadow && !gpRoot.reduceGlass && width > 0 && height > 0
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
            sourceItem: gpRoot.backdrop
            live: false
            recursive: false
            sourceRect: gpRoot.backdrop ? gpRoot.mapToItem(gpRoot.backdrop, 0, 0, gpRoot.width, gpRoot.height) : Qt.rect(0, 0, 0, 0)
        }

        MultiEffect {
            id: blurEffect
            anchors.fill: parent
            visible: !gpRoot.reduceGlass && gpRoot.backdrop !== null && width > 0 && height > 0
            source: snap
            blurEnabled: true
            blur: 1.0
            blurMax: 48
            saturation: 0.35
            brightness: 0.04
            maskEnabled: true
            maskSource: shapeMask
        }

        // 2. Tint
        Rectangle {
            id: tintLayer
            anchors.fill: parent
            radius: gpRoot.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(1, 1, 1, gpRoot.reduceGlass ? 0.22 : gpRoot.tintTop)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(1, 1, 1, gpRoot.reduceGlass ? 0.12 : gpRoot.tintBottom)
                }
            }
        }

        // Faint amber tint layer
        Rectangle {
            id: amberLayer
            anchors.fill: parent
            radius: gpRoot.radius
            visible: gpRoot.amberTint > 0
            color: Qt.rgba(0.95, 0.66, 0.23, gpRoot.amberTint)
        }

        // 3. Top light
        Rectangle {
            id: topLight
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: gpRoot.topLightHeight
            visible: gpRoot.hasTopLight && height > 0
            radius: gpRoot.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.12) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }

        // 4. Specular rim
        Item {
            id: rimContainer
            anchors.fill: parent
            visible: gpRoot.hasRim

            Rectangle {
                id: rimGradRect
                anchors.fill: parent
                radius: gpRoot.radius
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
                    radius: Math.max(0, gpRoot.radius - 1)
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
                snap.sourceRect = gpRoot.mapToItem(gpRoot.backdrop, 0, 0, gpRoot.width, gpRoot.height)
                snap.scheduleUpdate()
            }
        }

        onWidthChanged: updateSnapshot()
        onHeightChanged: updateSnapshot()
        onXChanged: updateSnapshot()
        onYChanged: updateSnapshot()
        Component.onCompleted: updateSnapshot()
    }

    // ---- Navigation rail (74pt Narrow Liquid Glass style matching Image 1) ----
    Item {
        id: railContainer
        visible: !window.welcome
        x: Theme.railInset
        y: Theme.railInset
        width: 74
        height: parent.height - Theme.railInset * 2

        // Floating Liquid Glass panel
        GlassPanel {
            id: railGlass
            anchors.fill: parent
            radius: Theme.railInset > 0 ? 28 : 0
            hasShadow: Theme.railInset > 0
            backdrop: windowBackdrop
        }

        // App logo (icon only, no "MacLink" text, below title bar)
        Image {
            id: railLogo
            anchors.horizontalCenter: parent.horizontalCenter
            y: 18
            width: 26; height: 26
            source: "qrc:/brand/maclink-liquid-logo.png"
            mipmap: true
            smooth: true
            fillMode: Image.PreserveAspectFit
        }

        readonly property var navItems: [
            { id: "home", label: qsTr("Home"), icon: Icons.home },
            { id: "messages", label: qsTr("Messages"), icon: Icons.messages },
            { id: "calls", label: qsTr("Calls"), icon: Icons.call },
            { id: "photos", label: qsTr("Photos"), icon: Icons.photo },
            { id: "files", label: qsTr("Files"), icon: Icons.folder },
            { id: "apps", label: qsTr("Apps"), icon: Icons.apps },
            { id: "deck", label: qsTr("Deck"), icon: Icons.deck },
            { id: "guide", label: qsTr("Guide"), icon: Icons.info },
            { id: "settings", label: qsTr("Settings"), icon: Icons.settings }
        ]

        readonly property real itemPitch: Math.min(54, Math.max(42, Math.floor((railFlickable.height - 4) / navItems.length)))

        readonly property int activeNavIndex: {
            switch (window.page) {
            case "home":
            case "timeline": return 0
            case "messages": return 1
            case "calls": return 2
            case "photos": return 3
            case "files":
            case "file_manager": return 4
            case "apps": return 5
            case "deck": return 6
            case "help_center":
            case "guide": return 7
            case "settings": return 8
            default: return 0
            }
        }

        onActiveNavIndexChanged: {
            if (!Theme.reduceMotion) {
                liquidStretch.restart()
            }
        }

        SequentialAnimation {
            id: liquidStretch
            NumberAnimation { target: capsuleStretch; property: "yScale"; to: 1.10; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: capsuleStretch; property: "yScale"; to: 1.0; duration: 130; easing.type: Easing.OutCubic }
        }

        // Middle navigation items list inside Flickable for short screens
        Flickable {
            id: railFlickable
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: railLogo.bottom
            anchors.topMargin: railContainer.height < 600 ? 6 : 14
            anchors.bottom: addDeviceButton.top
            anchors.bottomMargin: railContainer.height < 600 ? 6 : 14
            width: railContainer.width
            contentWidth: width
            contentHeight: navColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            // Keep active item scrolled into view if window is short
            Connections {
                target: railContainer
                function onActiveNavIndexChanged() {
                    const targetY = railContainer.activeNavIndex * railContainer.itemPitch
                    if (targetY < railFlickable.contentY) {
                        railFlickable.contentY = targetY
                    } else if (targetY + railContainer.itemPitch > railFlickable.contentY + railFlickable.height) {
                        railFlickable.contentY = targetY + railContainer.itemPitch - railFlickable.height
                    }
                }
            }

            // The ONE sliding active glass capsule behind the active icon
            GlassPanel {
                id: activeCapsule
                x: Math.round((railContainer.width - width) / 2)
                y: railContainer.activeNavIndex * railContainer.itemPitch + 2
                width: 46
                height: 26
                radius: 13
                backdrop: windowBackdrop
                tintTop: 0.22
                tintBottom: 0.12
                amberTint: 0.12
                hasShadow: false
                hasTopLight: true
                hasRim: true
                visible: railContainer.activeNavIndex >= 0

                // Amber rim/glow for the active capsule
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.amberBorder
                }

                transform: Scale {
                    id: capsuleStretch
                    origin.x: 23
                    origin.y: 13
                    xScale: 1.0
                    yScale: 1.0
                }

                Behavior on y {
                    enabled: !Theme.reduceMotion
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // Navigation items list
            Column {
                id: navColumn
                width: parent.width
                spacing: 0

                Repeater {
                    model: railContainer.navItems
                    delegate: FocusScope {
                        id: railItem
                        required property var modelData
                        required property int index
                        readonly property bool selected: railContainer.activeNavIndex === index
                        width: railContainer.width
                        height: railContainer.itemPitch
                        activeFocusOnTab: true

                        Accessible.role: Accessible.PageTab
                        Accessible.name: modelData.id === "files" ? qsTr("File Manager") : modelData.label
                        Accessible.selected: selected
                        Accessible.onPressAction: window.navigateTab(modelData.id)

                        Keys.onReturnPressed: window.navigateTab(modelData.id)
                        Keys.onEnterPressed: window.navigateTab(modelData.id)
                        Keys.onSpacePressed: window.navigateTab(modelData.id)

                        // Focus ring
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 0
                            width: 50; height: 30
                            radius: 15
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.amberAccent
                            visible: Theme.focusVisible(railItem)
                        }

                        // Hover capsule (fades in over 120 ms when hovered and not selected)
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 2
                            width: 46; height: 26
                            radius: 13
                            color: Qt.rgba(1, 1, 1, 0.08)
                            visible: itemMouse.containsMouse && !railItem.selected
                            opacity: visible ? 1.0 : 0.0
                            Behavior on opacity {
                                enabled: !Theme.reduceMotion
                                NumberAnimation { duration: 120 }
                            }
                        }

                        // Icon (22 pt, centered in top 26 pt area)
                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 4
                            width: 22; height: 22
                            path: railItem.modelData.icon
                            color: railItem.selected ? "#FFFFFF" : (itemMouse.containsMouse ? Theme.textPrimary : Theme.textSecondary)
                            scale: itemMouse.pressed ? 0.94 : (railItem.selected ? 1.05 : 1.0)
                            Behavior on color {
                                enabled: !Theme.reduceMotion
                                ColorAnimation { duration: 120 }
                            }
                            Behavior on scale {
                                enabled: !Theme.reduceMotion
                                NumberAnimation { duration: 80 }
                            }
                        }

                        // Label (11 pt, centered below capsule)
                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: railContainer.width - 4
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            y: railContainer.itemPitch >= 50 ? 32 : (railContainer.itemPitch >= 44 ? 29 : 27)
                            text: railItem.modelData.label
                            role: "caption"
                            size: 11
                            weight: railItem.selected ? 600 : 500
                            color: railItem.selected ? Theme.textPrimary : (itemMouse.containsMouse ? Theme.textPrimary : Theme.textSecondary)
                            Behavior on color {
                                enabled: !Theme.reduceMotion
                                ColorAnimation { duration: 120 }
                            }
                        }

                        MouseArea {
                            id: itemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.navigateTab(railItem.modelData.id)
                        }
                    }
                }
            }
        }

        // Bottom round "+" button (32 pt, glass style)
        Item {
            id: addDeviceButton
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            width: 32; height: 32

            GlassPanel {
                id: addGlassBg
                anchors.fill: parent
                radius: 16
                backdrop: windowBackdrop
                tintTop: addMouse.pressed ? 0.28 : (addMouse.containsMouse ? 0.22 : 0.14)
                tintBottom: addMouse.pressed ? 0.16 : (addMouse.containsMouse ? 0.12 : 0.06)
                amberTint: addMouse.containsMouse ? 0.10 : 0.04
                hasShadow: true
                hasRim: true
                scale: addMouse.pressed ? 0.94 : (addMouse.containsMouse ? 1.04 : 1.0)
                Behavior on scale {
                    enabled: !Theme.reduceMotion
                    NumberAnimation { duration: 80 }
                }
            }

            Icon {
                anchors.centerIn: parent
                width: 16; height: 16
                path: Icons.plus
                color: addMouse.containsMouse ? Theme.textPrimary : Theme.textSecondary
                Behavior on color {
                    enabled: !Theme.reduceMotion
                    ColorAnimation { duration: 120 }
                }
            }

            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Pair a new device")
            Accessible.onPressAction: window.openPairing()

            MouseArea {
                id: addMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: window.openPairing()
            }
        }
    }

    // ---- Title bar and pages ----
    Item {
        id: main
        visible: !window.welcome
        anchors.left: railContainer.right
        anchors.leftMargin: Theme.railInset > 0 ? 8 : 0
        anchors.right: parent.right
        height: parent.height

        Item {
            id: topBar
            width: parent.width - captionButtons.width
            height: Theme.topBarHeight
            IconButton {
                id: backToHome
                anchors.left: parent.left
                anchors.leftMargin: Theme.contentPadding - 6
                anchors.verticalCenter: parent.verticalCenter
                visible: window.page === "timeline"
                iconPath: Icons.back
                label: qsTr("Back to Home")
                onClicked: window.page = "home"
                Component.onCompleted: window.addCaptionHole(backToHome)
            }
            // Top bar search field (Image 2)
            Rectangle {
                id: topSearchPill
                anchors.left: backToHome.visible ? backToHome.right : parent.left
                anchors.leftMargin: backToHome.visible ? 8 : Theme.contentPadding
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(360, Math.max(220, topBarActions.x - x - 20))
                height: 34
                radius: 17
                color: Qt.rgba(1, 1, 1, 0.05)
                border.width: 1
                border.color: topSearchMouse.containsMouse ? Theme.cardBorderHover : Theme.cardBorderSubtle
                visible: Theme.showCommands && (topBarActions.x - x) > 180

                MouseArea {
                    id: topSearchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: AppController.openCommandPalette()
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 11
                    anchors.right: cmdKBadge.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        path: Icons.search
                        width: 14; height: 14
                        color: Theme.textSecondary
                    }
                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Search devices, files, or commands…")
                        role: "body"
                        size: 12
                        color: Theme.textSecondary
                        elide: Text.ElideRight
                        width: topSearchPill.width - 85
                    }
                }

                Rectangle {
                    id: cmdKBadge
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 18
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    Txt {
                        anchors.centerIn: parent
                        text: "⌘K"
                        role: "caption"
                        size: 10
                        weight: 600
                        color: Theme.textSecondary
                    }
                }
                Component.onCompleted: if (Theme.showCommands) window.addCaptionHole(topSearchPill)
            }

            Txt {
                id: pageTitle
                visible: !topSearchPill.visible
                anchors.left: backToHome.visible ? backToHome.right : parent.left
                anchors.leftMargin: backToHome.visible ? 6 : Theme.contentPadding
                anchors.verticalCenter: parent.verticalCenter
                text: window.page === "home" ? qsTr("Home")
                    : window.page === "timeline" ? qsTr("Timeline")
                    : window.page === "messages" ? qsTr("Messages")
                    : window.page === "calls" ? qsTr("Calls")
                    : window.page === "photos" ? qsTr("Photos")
                    : (window.page === "files" || window.page === "file_manager") ? qsTr("File Manager")
                    : window.page === "apps" ? qsTr("Apps")
                    : window.page === "deck" ? qsTr("Deck")
                    : (window.page === "help_center" || window.page === "guide") ? qsTr("Guide")
                    : qsTr("Settings")
                role: "headline"
                size: 20
            }
            // Screen sharing: a live pill in the title bar, so the page never shifts. It sits
            // centered, and slides aside rather than overlap the title or the actions.
            Rectangle {
                id: sharingPill
                readonly property bool shown: AppController.pcMirrorActive
                readonly property real room: topBarActions.x - (pageTitle.x + pageTitle.width) - 32
                readonly property string fullText: AppController.pcMirrorDeviceName.length > 0
                    ? qsTr("Sharing screen with %1").arg(AppController.pcMirrorDeviceName)
                    : qsTr("Sharing screen")

                height: 34
                width: Math.max(0, Math.min(14 + 10 + 8 + sharingLabel.implicitWidth + 12 + stopSharing.width + 4, room))
                radius: height / 2
                x: Math.max(pageTitle.x + pageTitle.width + 16,
                            Math.min((parent.width - width) / 2, topBarActions.x - width - 16))
                anchors.verticalCenter: parent.verticalCenter
                visible: (shown || opacity > 0) && room > 120
                opacity: shown ? 1 : 0
                scale: shown ? 1 : 0.94
                color: Theme.errorContainer
                border.width: 1
                border.color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, Theme.dark ? 0.45 : 0.30)
                Behavior on opacity { enabled: !Theme.reduceMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 240; easing.type: Easing.OutBack } }

                Accessible.role: Accessible.StatusBar
                Accessible.name: fullText

                // Live dot with a slow halo, like a recording light.
                Item {
                    id: liveDot
                    width: 10; height: 10
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        id: halo
                        anchors.centerIn: parent
                        width: 10; height: 10; radius: 5
                        color: Theme.error
                        opacity: 0
                        SequentialAnimation on opacity {
                            running: sharingPill.shown && !Theme.reduceMotion && Qt.application.state === Qt.ApplicationActive
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.45; to: 0; duration: 1400; easing.type: Easing.OutCubic }
                        }
                        SequentialAnimation on scale {
                            running: sharingPill.shown && !Theme.reduceMotion && Qt.application.state === Qt.ApplicationActive
                            loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 2.4; duration: 1400; easing.type: Easing.OutCubic }
                        }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 8; height: 8; radius: 4
                        color: Theme.error
                    }
                }
                Txt {
                    id: sharingLabel
                    anchors.left: liveDot.right
                    anchors.leftMargin: 8
                    anchors.right: stopSharing.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: sharingPill.fullText
                    role: "label"
                    color: Theme.errorContainerContent
                    elide: Text.ElideRight
                }
                Button {
                    id: stopSharing
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    size: "sm"
                    variant: "tonal"
                    text: qsTr("Stop")
                    Accessible.name: qsTr("Stop sharing this PC's screen")
                    onClicked: AppController.stopPcMirror()
                    Component.onCompleted: window.addCaptionHole(stopSharing)
                }
            }
            Row {
                id: topBarActions
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                IconButton {
                    id: paletteTopBtn
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Theme.showCommands
                    iconPath: Icons.search
                    iconSize: 16
                    text: qsTr("Commands")
                    label: Preferences.commandPaletteHotkey.length > 0
                        ? qsTr("Command palette (%1)").arg(Preferences.commandPaletteHotkey)
                        : qsTr("Command palette (Ctrl+K)")
                    onClicked: AppController.openCommandPalette()
                    Component.onCompleted: if (Theme.showCommands) window.addCaptionHole(paletteTopBtn)
                }
                IconButton {
                    id: timelineTopBtn
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (window.page === "home" || window.page === "timeline") && AppController.hasDevices
                    iconPath: Icons.history
                    iconSize: 16
                    text: topBar.width < 540 ? "" : qsTr("Timeline")
                    tonal: window.page === "timeline"
                    label: qsTr("Files, clips, links, photos, recordings and sessions")
                    Accessible.name: qsTr("Timeline")
                    onClicked: window.page = window.page === "timeline" ? "home" : "timeline"
                    Component.onCompleted: window.addCaptionHole(timelineTopBtn)
                }
                // Reconnects and syncs with the phones (the title bar lets
                // clicks through here).
                IconButton {
                    id: refresh
                    anchors.verticalCenter: parent.verticalCenter
                    visible: window.page === "home" && AppController.hasDevices
                    iconPath: Icons.refresh
                    iconSize: 16
                    label: qsTr("Refresh")
                    onClicked: {
                        AppController.syncNow()
                        if (!Theme.reduceMotion) spin.restart()
                    }
                    RotationAnimation on rotation {
                        id: spin
                        running: false
                        from: 0; to: 360
                        duration: 700
                        easing.type: Easing.OutCubic
                    }
                    Component.onCompleted: window.addCaptionHole(refresh)
                }
                IconButton {
                    id: settingsGearBtn
                    anchors.verticalCenter: parent.verticalCenter
                    iconPath: Icons.settings
                    iconSize: 16
                    label: qsTr("Settings")
                    tonal: window.page === "settings"
                    onClicked: window.page = "settings"
                    Component.onCompleted: window.addCaptionHole(settingsGearBtn)
                }
            }
        }

        Rectangle {
            id: pages
            anchors.top: topBar.bottom
            anchors.bottom: parent.bottom
            width: parent.width
            clip: true
            topLeftRadius: 18
            color: "transparent"
            Behavior on color { ColorAnimation { duration: Theme.fadeNormal } }
            border.width: 0

            Loader {
                id: pageLoader
                anchors.fill: parent
                active: !window.welcome && AppController.status === "ready"
                property bool firstLoadDone: false
                onStatusChanged: {
                    if (status === Loader.Error) {
                        console.error("[MacLink PageLoader Error]", source, sourceComponent ? sourceComponent.errorString() : "unknown error")
                    }
                }
                transform: [
                    Translate { id: pageSlide; y: 0 },
                    Scale {
                        id: pageScale
                        origin.x: pageLoader.width / 2
                        origin.y: pageLoader.height / 3
                        xScale: 1.0
                        yScale: 1.0
                    }
                ]
                ParallelAnimation {
                    id: pageEnterAnim
                    NumberAnimation {
                        target: pageLoader
                        property: "opacity"
                        from: 0.35
                        to: 1.0
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: pageSlide
                        property: "y"
                        from: 10
                        to: 0
                        duration: 210
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: pageScale
                        properties: "xScale,yScale"
                        from: 0.985
                        to: 1.0
                        duration: 210
                        easing.type: Easing.OutCubic
                    }
                }
                source: {
                    if (!active) return ""
                    switch (window.page) {
                    case "timeline": return "qrc:/qt/qml/app/maclink/qml/pages/TimelinePage.qml"
                    case "messages": return "qrc:/qt/qml/app/maclink/qml/pages/MessagesPage.qml"
                    case "calls": return "qrc:/qt/qml/app/maclink/qml/pages/CallsPage.qml"
                    case "photos": return "qrc:/qt/qml/app/maclink/qml/pages/PhotosPage.qml"
                    case "files":
                    case "file_manager": return "qrc:/qt/qml/app/maclink/qml/pages/FilesPage.qml"
                    case "apps": return "qrc:/qt/qml/app/maclink/qml/pages/AppsPage.qml"
                    case "deck": return "qrc:/qt/qml/app/maclink/qml/pages/DeckPage.qml"
                    case "help_center":
                    case "guide": return "qrc:/qt/qml/app/maclink/qml/pages/FeaturesGuidePage.qml"
                    case "settings": return "qrc:/qt/qml/app/maclink/qml/pages/SettingsPage.qml"
                    default: return "qrc:/qt/qml/app/maclink/qml/pages/HomePage.qml"
                    }
                }
                onLoaded: {
                    if ("deviceId" in item)
                        item.deviceId = Qt.binding(() => window.currentDeviceId)
                    if ("deviceName" in item)
                        item.deviceName = Qt.binding(() => window.currentDeviceName)
                    item.active = true
                    if (window.pendingSettingsSection.length > 0 && "currentSection" in item) {
                        item.currentSection = window.pendingSettingsSection
                        window.pendingSettingsSection = ""
                    }
                    if (item.pairRequested)
                        item.pairRequested.connect(window.openPairing)
                    if (item.showMeRequested)
                        item.showMeRequested.connect(window.navigateAndHighlight)
                    if (item.restartWalkthroughRequested)
                        item.restartWalkthroughRequested.connect(() => Preferences.restartWalkthrough())
                    if (item.textRequested) {
                        item.textRequested.connect((number, name) => {
                            Messages.startChat(window.currentDeviceId, number, name)
                            window.page = "messages"
                        })
                    }
                    if (!pageLoader.firstLoadDone || Theme.reduceMotion) {
                        pageLoader.firstLoadDone = true
                        pageLoader.opacity = 1.0
                        pageSlide.y = 0
                        pageScale.xScale = 1.0
                        pageScale.yScale = 1.0
                    } else {
                        pageLoader.opacity = 0.35
                        pageSlide.y = 10
                        pageScale.xScale = 0.985
                        pageScale.yScale = 0.985
                        Qt.callLater(() => pageEnterAnim.restart())
                    }
                }
            }
        }
    }

    // ---- First run ----
    Loader {
        anchors.fill: parent
        active: AppController.status !== "ready"
        source: active ? "qrc:/qt/qml/app/maclink/qml/pages/WelcomePage.qml" : ""
    }

    Loader {
        id: walkthroughLoader
        anchors.fill: parent
        active: window.showWalkthrough
        source: active ? "qrc:/qt/qml/app/maclink/qml/pages/WalkthroughPage.qml" : ""
        onLoaded: {
            if ("deviceId" in item)
                item.deviceId = Qt.binding(() => window.currentDeviceId)
            if ("deviceName" in item)
                item.deviceName = Qt.binding(() => window.currentDeviceName)
            item.completed.connect(() => { window.page = "home" })
            item.openGuideRequested.connect(() => { window.page = "help_center" })
            item.doctorRequested.connect(() => { AppController.runDoctor() })
        }
    }

    // ---- Overlays ----
    Connections {
        target: Pairing
        function onStateChanged() {
            if (Pairing.state === "comparing" && !window.welcome && !pairingSheet.opened) {
                pairingSheet.open()
            }
        }
    }
    Sheet {
        id: pairingSheet
        cardWidth: 480
        onOpenedChanged: if (!opened) Pairing.cancel()
        Loader {
            id: pairingLoader
            width: parent.width
            active: pairingSheet.opened
            source: active ? "qrc:/qt/qml/app/maclink/qml/pages/PairingPanel.qml" : ""
            onLoaded: {
                item.width = Qt.binding(() => pairingLoader.width)
                item.running = Qt.binding(() => pairingSheet.opened)
                item.finished.connect(() => pairingSheet.close())
                item.cancelled.connect(() => pairingSheet.close())
            }
        }
    }

    Sheet {
        id: ringingSheet
        opened: AppController.ringingFrom.length > 0
        dismissable: false
        cardWidth: 380
        Column {
            width: parent.width
            spacing: 16
            Avatar { anchors.horizontalCenter: parent.horizontalCenter; width: 56; height: 56; iconPath: Icons.ring; emphasized: true }
            Txt {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("%1 is ringing this PC").arg(AppController.ringingFrom)
                role: "headline"
                wrapMode: Text.WordWrap
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Stop ringing")
                onClicked: AppController.stopRinging()
            }
        }
    }

    Sheet {
        id: remotePromptSheet
        opened: AppController.remotePromptDeviceId.length > 0
        cardWidth: 420
        onOpenedChanged: {
            if (!opened && AppController.remotePromptDeviceId.length > 0)
                AppController.dismissRemotePrompt()
        }
        Column {
            width: parent.width
            spacing: 16
            Avatar {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 56; height: 56
                iconPath: Icons.phone
                emphasized: true
            }
            Txt {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Allow %1 to control this PC?").arg(AppController.remotePromptDeviceName)
                role: "headline"
                wrapMode: Text.WordWrap
            }
            Txt {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("%1 wants to use this PC's mouse and keyboard. You can change this in Settings.").arg(AppController.remotePromptDeviceName)
                role: "body"
                muted: true
                wrapMode: Text.WordWrap
            }
            Row {
                anchors.right: parent.right
                spacing: 10
                Button {
                    variant: "text"
                    text: qsTr("Not now")
                    onClicked: AppController.dismissRemotePrompt()
                }
                Button {
                    text: qsTr("Allow")
                    onClicked: AppController.allowRemoteInput(AppController.remotePromptDeviceId)
                }
            }
        }
    }

    Sheet {
        id: pcMirrorPromptSheet
        opened: AppController.pcMirrorPromptDeviceId.length > 0
        cardWidth: 460
        onOpenedChanged: {
            if (!opened && AppController.pcMirrorPromptDeviceId.length > 0)
                AppController.dismissPcMirrorPrompt()
        }
        Column {
            width: parent.width
            spacing: 16
            Avatar {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 56; height: 56
                iconPath: Icons.mirror
                emphasized: true
            }
            Txt {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Allow %1 to view this PC's screen?").arg(AppController.pcMirrorPromptDeviceName)
                role: "headline"
                wrapMode: Text.WordWrap
            }
            Txt {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("%1 wants to view this PC's screen. Control needs Remote mouse, keyboard & Deck in Settings.").arg(AppController.pcMirrorPromptDeviceName)
                role: "body"
                muted: true
                wrapMode: Text.WordWrap
            }
            Row {
                anchors.right: parent.right
                spacing: 10
                Button {
                    variant: "text"
                    text: qsTr("Not now")
                    onClicked: AppController.dismissPcMirrorPrompt()
                }
                Button {
                    variant: "tonal"
                    text: qsTr("Allow")
                    onClicked: AppController.allowPcMirrorOnce(AppController.pcMirrorPromptDeviceId)
                }
                Button {
                    text: qsTr("Allow for this device")
                    onClicked: AppController.allowPcMirrorDevice(AppController.pcMirrorPromptDeviceId)
                }
            }
        }
    }

    CaptionButtons {
        id: captionButtons
        window: window
        anchors.top: parent.top
        anchors.right: parent.right
    }

    Loader {
        id: doctorLoader
        anchors.fill: parent
        active: false
        source: active ? "qrc:/qt/qml/app/maclink/qml/components/DoctorSheet.qml" : ""
        onLoaded: item.open()
    }
    Connections {
        target: AppController
        function onDoctorRequested() {
            if (doctorLoader.active && doctorLoader.item)
                doctorLoader.item.open()
            else
                doctorLoader.active = true
        }
    }

    Shortcut {
        sequences: [StandardKey.Close]
        onActivated: window.close()
    }

    Shortcut {
        sequences: ["Ctrl+K", "Ctrl+P"]
        enabled: Theme.showCommands
        onActivated: {
            if (!Theme.showCommands) return
            if (AppController.commandPaletteOpen)
                AppController.closeCommandPalette()
            else
                AppController.openCommandPalette()
        }
    }

    Loader {
        id: commandPaletteLoader
        anchors.fill: parent
        active: Theme.showCommands && AppController.commandPaletteOpen
        source: active ? "qrc:/qt/qml/app/maclink/qml/components/CommandPalette.qml" : ""
    }

    Toast {
        id: toast
        onActionTriggered: AppController.runClipSuggestion()
    }
    Connections {
        target: AppController
        function onToast(message) { toast.show(message) }
        function onToastWithAction(message, actionLabel) { toast.showWithAction(message, actionLabel) }
        function onPendingDialChanged() {
            if (AppController.pendingDial.length > 0 && window.page !== "calls")
                window.page = "calls"
        }
    }
}
