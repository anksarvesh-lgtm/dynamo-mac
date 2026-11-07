// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton
import QtQuick
import app.maclink

// The active theme: Bloom (Material You, seed presets, the default), Hive
// (honey on charcoal or wax), Glass, or Graphite (paper and slate), light
// or dark, resolved from Preferences and the system. Colors
// come from Tokens (generated from docs/design/tokens.json); Material's
// "onX" roles are named "xContent" because QML reserves the "on" prefix.
QtObject {
    id: theme

    readonly property bool hive: false
    readonly property bool graphite: false
    readonly property bool glass: true
    readonly property bool dark: AppController.systemDark
    readonly property bool amoled: false
    readonly property bool reduceMotion: AppController.reduceMotion

    // Feature switch: whether the Commands section and Command Palette are enabled.
    // Default is false to hide all Commands entry points from the macOS UI.
    readonly property bool showCommands: false

    // ---- Hive's comb ----
    readonly property var comb: Tokens.data.themes.hive.comb
    // Breathes and pulses: the user's setting, never with reduced motion or
    // battery saver (it holds still then).
    readonly property bool combMotion: hive && Preferences.combMotion && !reduceMotion && !AppController.powerSaver
    readonly property color combLine: Qt.rgba(primary.r, primary.g, primary.b,
                                              dark ? comb.lineAlphaDark : comb.lineAlphaLight)
    readonly property color combGlow: dark ? Qt.rgba(1.0, 0.62, 0.18, comb.glowAlphaDark)
                                           : Qt.rgba(1.0, 0.72, 0.37, comb.glowAlphaLight)
    // One clock for every comb in the app (seconds), so two combs never draw
    // twice as often. The main window runs it while it's in front.
    property real combTime: 0
    property bool combClockRunning: false
    // A comb is on screen outside Hive (the invitation to try it).
    property bool combPreviewShown: false
    property double _combSince: 0
    property real _combBase: 0
    readonly property Timer _combClock: Timer {
        interval: theme.comb.frameMs
        repeat: true
        running: theme.combClockRunning
                 && (theme.combMotion || (theme.combPreviewShown && !theme.reduceMotion && !AppController.powerSaver))
        onRunningChanged: {
            if (running)
                theme._combSince = Date.now()
            else
                theme._combBase = theme.combTime
        }
        onTriggered: theme.combTime = theme._combBase + (Date.now() - theme._combSince) / 1000
    }

    readonly property var bloomSeeds: Tokens.data.themes.bloom.seeds
    // Colors made from the desktop wallpaper (or null until they're known),
    // in the shape of a preset seed.
    readonly property var wallpaperSeed: AppController.wallpaperColors !== ""
        ? JSON.parse(AppController.wallpaperColors) : null
    // Material You color scheme extracted from the currently playing media artwork.
    readonly property var artworkSeed: {
        if (MediaList.activeColors === "")
            return null
        try {
            return JSON.parse(MediaList.activeColors)
        } catch (e) {
            return null
        }
    }
    readonly property string artworkUrl: MediaList.activeArt
    readonly property bool isArtworkSeed: false
    readonly property bool artworkAmbientActive: false
    readonly property bool ambientBlurActive: glass
    // Material You color schemes from paired phones (`[{ id, key, name, label, hasAccent, scheme }]`).
    readonly property var phoneSeeds: AppController.phoneColors !== ""
        ? JSON.parse(AppController.phoneColors) : []
    readonly property bool isPhoneSeed: false
    readonly property var activePhoneSeed: null
    function phonePalette(deviceId) {
        for (let i = 0; i < phoneSeeds.length; i++) {
            const p = phoneSeeds[i]
            if ((deviceId === "" || p.id === deviceId) && p.scheme)
                return p.scheme[dark ? "dark" : "light"]
        }
        return null
    }
    // "artwork", "wallpaper", "phone" / "phone:<id>", or a preset name; dynamic
    // seeds fall back to wallpaper or the default preset until their colors are known.
    readonly property string seed: wallpaperSeed ? "wallpaper" : Tokens.data.themes.bloom.defaultSeed
    readonly property var seedColors: wallpaperSeed ? wallpaperSeed : bloomSeeds[Tokens.data.themes.bloom.defaultSeed]
    readonly property var palette: hive
        ? Tokens.data.themes.hive.variants[dark ? "comb" : "wax"]
        : (graphite
            ? Tokens.data.themes.graphite.variants[dark ? "slate" : "paper"]
            : seedColors[dark ? "dark" : "light"])
    readonly property var status: graphite || hive ? palette : Tokens.data.themes.bloom.status[dark ? "dark" : "light"]

    // ---- MacLink Dark Glass & Amber Design Tokens (maclink_ui_style_prompt) ----
    readonly property color windowBg: "#0B0806"
    readonly property color amberGlow: "#B8721A"
    readonly property color amberAccent: "#F2A93B"
    readonly property color amberAccentDeep: "#B8721A"
    readonly property color amberBorder: Qt.rgba(0.95, 0.66, 0.23, 0.50)
    readonly property color textPrimary: "#F5F0EA"
    readonly property color textSecondary: "#A89C8E"
    readonly property color successGreen: "#3ECF6E"
    readonly property color cardFill: Qt.rgba(1, 1, 1, 0.045)
    readonly property color cardBorderSubtle: Qt.rgba(1, 1, 1, 0.08)
    readonly property color cardBorderHover: Qt.rgba(1, 1, 1, 0.16)
    readonly property int cardCornerRadius: 20
    readonly property int tileCornerRadius: 14
    readonly property int cardGap: 16
    readonly property int cardPadding: 20
    readonly property int sidebarWidth: 230
    readonly property int sidebarRailWidth: 74
    property real railInset: 8
    property bool reduceGlass: false

    // ---- Color roles ----
    readonly property color primary: amberAccent
    readonly property color primaryContent: "#1C1206"
    readonly property color primaryContainer: amberAccentDeep
    readonly property color primaryContainerContent: textPrimary
    readonly property color secondaryContainer: Qt.rgba(0.95, 0.66, 0.23, 0.16)
    readonly property color secondaryContainerContent: textPrimary
    readonly property color surface: windowBg
    readonly property color surfaceLow: windowBg
    readonly property color surfaceContainerLow: windowBg
    readonly property color surfaceContainer: windowBg
    readonly property color surfaceContainerHigh: Qt.rgba(1, 1, 1, 0.06)
    readonly property color surfaceContainerHighest: Qt.rgba(1, 1, 1, 0.09)
    readonly property color surfaceContent: textPrimary
    readonly property color surfaceContentVariant: textSecondary
    readonly property color outline: cardBorderSubtle
    readonly property color outlineVariant: cardBorderSubtle
    readonly property color success: successGreen
    readonly property color warning: status.warning
    readonly property color error: status.error
    readonly property color errorContent: status.onError
    readonly property color errorContainer: Qt.rgba(error.r, error.g, error.b, 0.22)
    readonly property color errorContainerContent: surfaceContent

    // ---- Component colors (Liquid Glass UI) ----
    readonly property color cardColor: cardFill
    readonly property color cardBorder: cardBorderSubtle
    readonly property color tileColor: Qt.rgba(1, 1, 1, 0.04)
    readonly property color heroColor: cardFill
    readonly property color heroContent: textPrimary
    readonly property color railColor: Qt.rgba(0.04, 0.03, 0.02, 0.65)
    readonly property color indicator: amberAccent
    readonly property color indicatorContent: textPrimary
    readonly property color glow: Qt.rgba(0.72, 0.45, 0.10, 0.25)
    readonly property color buttonShadow: "transparent"
    readonly property color scrim: Qt.rgba(0, 0, 0, 0.65)

    // ---- Shape ----
    readonly property var shape: graphite ? Tokens.data.themes.graphite.shape
        : (hive ? Tokens.data.themes.hive.shape : Tokens.data.themes.bloom.shape)
    readonly property int radiusXs: 6
    readonly property int radiusSm: 10
    readonly property int radiusMd: tileCornerRadius
    readonly property int radiusLg: cardCornerRadius
    readonly property int radiusXl: 24
    // "Pill": half the height of whatever uses it, in Bloom.
    function pill(height) { return height / 2 }

    // ---- Type ----
    readonly property string fontUi: Qt.platform.os === "osx" ? "SF Pro Display" : "Figtree"
    readonly property string fontDisplay: Qt.platform.os === "osx" ? "SF Pro Display" : "Figtree"
    readonly property string fontMono: "Space Mono"
    readonly property var typography: Tokens.data.typography
    readonly property var labelStyle: graphite ? Tokens.data.themes.graphite.label
        : (hive ? Tokens.data.themes.hive.label : Tokens.data.themes.bloom.label)

    // ---- Layout and spacing ----
    readonly property var layout: Tokens.data.layout.desktop
    readonly property int railWidth: layout.railWidth
    readonly property int topBarHeight: layout.topBarHeight
    readonly property int contentPadding: layout.contentPadding
    readonly property int gutter: layout.gutter
    function space(step) { return Tokens.data.spacing.scale[step] }

    // ---- Responsive Breakpoints (content area width, not window width) ----
    readonly property real bpTwoColumn: 1100
    readonly property real bpMedium: 760

    function isTwoColumn(contentW) { return contentW >= bpTwoColumn }
    function isMedium(contentW) { return contentW >= bpMedium && contentW < bpTwoColumn }
    function isCompact(contentW) { return contentW < bpMedium }
    function topCardsSideBySide(contentW) {
        // Phone card and Media card side-by-side if each is at least 320 wide plus gutter
        const available = isTwoColumn(contentW) ? (contentW - 360 - gutter * 3) : (contentW - gutter)
        return available >= (320 * 2)
    }

    // Focus rings show for keyboard focus only, not after a click (TapHandler
    // doesn't take activeFocus on click; activeFocus on a control comes from Tab).
    function focusVisible(item) {
        return item !== null && item !== undefined && item.activeFocus
            && (item.focusReason === undefined
                || item.focusReason === Qt.TabFocusReason
                || item.focusReason === Qt.BacktabFocusReason)
    }

    // ---- Motion ----
    // QML springs take a strength and a damping ratio; these are tuned to
    // match the token springs (gentle / standard / snappy).
    readonly property real springGentle: 2.4
    readonly property real dampingGentle: 0.36
    readonly property real springStandard: 3.6
    readonly property real dampingStandard: 0.32
    readonly property real springSnappy: 5.6
    readonly property real dampingSnappy: 0.34
    readonly property int fadeFast: Tokens.data.motion.fade.fast
    readonly property int fadeNormal: Tokens.data.motion.fade.normal
    readonly property real hoverLift: reduceMotion ? 0 : Tokens.data.motion.hoverLift
    readonly property real pressScale: reduceMotion ? 1 : Tokens.data.motion.pressScale
}
