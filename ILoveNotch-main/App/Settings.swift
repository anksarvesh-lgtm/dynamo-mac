// SPDX-License-Identifier: MIT
import AppKit
import Carbon.HIToolbox
import NotchCore
import NotchFeatures
import ServiceManagement
import SwiftUI

/// Accessory apps have no app menu, so Settings opens from the menu bar item or the notch's gear
/// button, and activates the app while it's up. It's laid out like System Settings: a sidebar of
/// pages, each marked by a colored icon, and the chosen page as a grouped form.
@MainActor
final class SettingsWindowController {
    private let preferences: NotchPreferences
    private let updater: Updater
    private let notchKey: HotKey
    private let clipboardKey: HotKey
    private let previewAnimation: () -> Void
    private let featureSettings: (FeatureID) -> AnyView?
    private let selection = SettingsSelection()
    private var window: NSWindow?

    /// `featureSettings` supplies each tab's own settings, as the sections of its page.
    init(
        preferences: NotchPreferences, updater: Updater, notchKey: HotKey, clipboardKey: HotKey,
        previewAnimation: @escaping () -> Void, featureSettings: @escaping (FeatureID) -> AnyView?
    ) {
        self.preferences = preferences
        self.updater = updater
        self.notchKey = notchKey
        self.clipboardKey = clipboardKey
        self.previewAnimation = previewAnimation
        self.featureSettings = featureSettings
    }

    /// Shows Settings, on `page` when one is given.
    func show(_ page: SettingsSelection.Page? = nil) {
        if let page { selection.page = page }
        if window == nil {
            let root = SettingsView(
                preferences: preferences, updater: updater, notchKey: notchKey, clipboardKey: clipboardKey,
                previewAnimation: previewAnimation, featureSettings: featureSettings, selection: selection)
            let host = NSHostingController(rootView: root)
            // The page's name goes in the toolbar, over a sidebar that runs to the top of the window.
            host.sceneBridgingOptions = [.title, .toolbars]
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.title = selection.page.title  // SwiftUI brings the title over when the page changes
            window.isReleasedWhenClosed = false
            window.setContentSize(SettingsView.size)
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Which Settings page is showing, so the notch and the menu bar item can open a given one.
@MainActor
@Observable
final class SettingsSelection {
    enum Page: Hashable {
        case about, general, appearance, displays, activities
        case feature(FeatureID)
    }
    var page = Page.general
}

struct SettingsView: View {
    /// System Settings' proportions: a fixed width, and taller if you like.
    static let size = CGSize(width: 715, height: 720)

    let preferences: NotchPreferences
    let updater: Updater
    let notchKey: HotKey
    let clipboardKey: HotKey
    let previewAnimation: () -> Void
    let featureSettings: (FeatureID) -> AnyView?
    @Bindable var selection: SettingsSelection

    var body: some View {
        NavigationSplitView {
            List(selection: $selection.page) {
                AppRow().tag(SettingsSelection.Page.about)
                Section {
                    ForEach([SettingsSelection.Page.general, .appearance, .displays, .activities], id: \.self) {
                        SidebarRow(page: $0).tag($0)
                    }
                }
                Section("Tabs") {
                    ForEach(preferences.tabOrder, id: \.self) { feature in
                        SidebarRow(page: .feature(feature), off: !preferences.isEnabled(feature))
                            .tag(SettingsSelection.Page.feature(feature))
                    }
                }
            }
            .frame(minWidth: 215)  // the column width modifier is ignored in a hosted split view
            .toolbar(removing: .sidebarToggle)
        } detail: {
            page
                .id(selection.page)  // each page opens scrolled to its top
                .navigationTitle(selection.page.title)
        }
        .frame(width: Self.size.width)
        .frame(minHeight: 460, idealHeight: Self.size.height)
    }

    @ViewBuilder private var page: some View {
        switch selection.page {
        case .about: AboutSettings(updater: updater)
        case .general: GeneralPage(preferences: preferences, notchKey: notchKey, clipboardKey: clipboardKey)
        case .appearance: AppearancePage(preferences: preferences, previewAnimation: previewAnimation)
        case .displays: DisplaysPage(preferences: preferences)
        case .activities: ActivitiesPage(preferences: preferences)
        case .feature(let feature):
            FeaturePage(feature: feature, preferences: preferences, settings: featureSettings(feature))
        }
    }
}

extension SettingsSelection.Page {
    var title: String {
        switch self {
        case .about: "About"
        case .general: "General"
        case .appearance: "Appearance"
        case .displays: "Displays"
        case .activities: "Live Activities"
        case .feature(let feature): feature.title
        }
    }

    /// Its icon: a white symbol on a color, after the Apple app or System Settings pane it's closest to.
    fileprivate var icon: (symbol: String, color: Color) {
        switch self {
        case .about: ("info.circle", .gray)
        case .general: ("gearshape", .gray)
        case .appearance: ("paintbrush", .indigo)
        case .displays: ("display", .blue)
        case .activities: ("bell.badge", .red)
        case .feature(let feature):
            switch feature {
            case .media: ("play", .pink)
            case .sound: (feature.symbol, .red)
            case .shelf: (feature.symbol, .blue)
            case .clipboard: (feature.symbol, .teal)
            case .calendar: (feature.symbol, .red)
            case .tasks: (feature.symbol, .orange)
            case .notes: (feature.symbol, .yellow)
            case .shortcuts: (feature.symbol, .indigo)
            case .timer: (feature.symbol, .orange)
            case .network: ("arrow.up.arrow.down", .blue)
            case .mirror: (feature.symbol, .green)
            case .usage: (feature.symbol, .purple)
            case .agents: (feature.symbol, .gray)
            }
        }
    }

    /// One line under its name at the top of the page.
    fileprivate var summary: String {
        switch self {
        case .about: "The app, its version, and where to find help."
        case .general: "Launch at login, keyboard shortcuts, and starting over."
        case .appearance: "How the open notch looks, and how it opens and closes."
        case .displays: "Which displays get a notch, and what the ones without one show."
        case .activities: "What the closed notch shows for a moment when something changes."
        case .feature(let feature):
            switch feature {
            case .media: "What's playing in any app, with artwork, controls, and a waveform."
            case .sound: "Your speakers and microphone, and every app's volume on its own fader."
            case .shelf: "Files you drop on the notch, at hand to drag out, preview, or share."
            case .clipboard: "A searchable history of what you copy, with favorites that stay."
            case .calendar: "Today's events, with a Join button and a countdown for calls."
            case .tasks: "Your Reminders, synced to your iPhone through iCloud."
            case .notes: "Markdown notes that save as you type."
            case .shortcuts: "The shortcuts you make in the Shortcuts app, a click away."
            case .timer: "Timers, a stopwatch with laps, and Keep Awake."
            case .network: "Your download and upload speed, and how much you've used."
            case .mirror: "Your camera, on only while its tab is open."
            case .usage: "How much of each AI coding plan you've used."
            case .agents: "When Claude Code or Codex needs you or finishes, in the closed notch."
            }
        }
    }
}

/// A white symbol on a colored rounded square, the way System Settings marks its panes.
private struct SettingsIcon: View {
    let page: SettingsSelection.Page
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: page.icon.symbol)
            .symbolVariant(.fill)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(page.icon.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// ILoveNotch itself, at the top of the sidebar where System Settings puts your account: it opens
/// About.
private struct AppRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("ILoveNotch").font(.headline)
                Text("Version \(Updater.version)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A page in the sidebar: its icon and name, and "Off" for a tab that's turned off.
private struct SidebarRow: View {
    let page: SettingsSelection.Page
    var off = false

    var body: some View {
        HStack {
            Label {
                Text(page.title)
            } icon: {
                SettingsIcon(page: page)
            }
            Spacer(minLength: 4)
            if off { Text("Off").foregroundStyle(.secondary) }
        }
    }
}

/// A page as System Settings lays one out: its icon, name, and what it's for, with the tab's
/// switch when it's a tab, then its settings in groups.
private struct SettingsPage<Content: View>: View {
    let page: SettingsSelection.Page
    var isOn: Binding<Bool>?
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    SettingsIcon(page: page, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(page.title).font(.headline)
                        Text(page.summary).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let isOn {
                        Toggle(page.title, isOn: isOn).labelsHidden().toggleStyle(.switch)
                    }
                }
                .padding(.vertical, 2)
            }
            content
        }
        .formStyle(.grouped)
    }
}

/// A tab's page: its switch, then its own settings while it's on.
private struct FeaturePage: View {
    let feature: FeatureID
    let preferences: NotchPreferences
    let settings: AnyView?

    var body: some View {
        // A closure, not a method reference: see GeneralPage.
        let isOn = Binding(get: { preferences.isEnabled(feature) }, set: { preferences.setEnabled(feature, $0) })
        SettingsPage(page: .feature(feature), isOn: isOn) {
            if preferences.isEnabled(feature), let settings { settings }
        }
    }
}

private struct GeneralPage: View {
    @Bindable var preferences: NotchPreferences
    let notchKey: HotKey
    let clipboardKey: HotKey
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var confirmsReset = false

    var body: some View {
        SettingsPage(page: .general) {
            Section {
                // A closure, not a method reference: converting the method to Binding's isolated
                // setter type crashes the Swift 6.3 compiler in IRGen.
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Keyboard Shortcuts") {
                LabeledContent {
                    ShortcutRecorder(shortcut: $preferences.notchShortcut, hotKey: notchKey)
                } label: {
                    Text("Open the notch")
                    shortcutNote(
                        notchKey, preferences.notchShortcut,
                        "From any app, on the display under the pointer. Press it again or Escape to close.")
                }
                if preferences.isEnabled(.clipboard) {
                    LabeledContent {
                        ShortcutRecorder(shortcut: $preferences.clipboardShortcut, hotKey: clipboardKey)
                    } label: {
                        Text("Search the clipboard")
                        shortcutNote(
                            clipboardKey, preferences.clipboardShortcut,
                            "Opens the Clipboard tab ready to type; Return copies the first match.")
                    }
                }
            }
            Section {
                LabeledContent {
                    Button("Reset\u{2026}", role: .destructive) { confirmsReset = true }
                } label: {
                    Text("Reset to defaults")
                    Text("Tabs, their order, shortcuts, appearance, and displays. Your notes, shelf, and history stay.")
                }
                .confirmationDialog("Reset ILoveNotch's settings?", isPresented: $confirmsReset) {
                    Button("Reset to Defaults", role: .destructive) { preferences.reset() }
                } message: {
                    Text("Every tab comes back in its first place, with the original shortcuts and look.")
                }
            }
        }
    }

    /// What a shortcut does, or that another app already has it.
    private func shortcutNote(_ hotKey: HotKey, _ shortcut: KeyShortcut?, _ explanation: String) -> Text {
        hotKey.isAvailable
            ? Text(explanation)
            : Text("Another app already uses \(shortcut?.display ?? "it"). Record another.").foregroundStyle(.red)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct AppearancePage: View {
    @Bindable var preferences: NotchPreferences
    let previewAnimation: () -> Void

    var body: some View {
        SettingsPage(page: .appearance) {
            Section {
                LabeledContent("Theme") {
                    ThemePicker(theme: $preferences.theme, glassAvailable: Self.glassAvailable)
                }
                // Shows the new look right away, the way Preview shows an animation.
                .onChange(of: preferences.theme) { previewAnimation() }
            } footer: {
                Text(themeNote).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent {
                    HStack {
                        Picker("Open and close", selection: $preferences.animationStyle) {
                            ForEach(NotchAnimationStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button("Preview", action: previewAnimation)
                    }
                } label: {
                    Text("Open and close")
                    Text(preferences.animationStyle.summary)
                }
                LabeledContent {
                    HStack {
                        Text("\(Int(preferences.expandedSize.width)) × \(Int(preferences.expandedSize.height))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button("Reset") { preferences.resizeExpanded(to: NotchPreferences.defaultExpandedSize) }
                            .disabled(preferences.expandedSize == NotchPreferences.defaultExpandedSize)
                    }
                } label: {
                    Text("Open notch size")
                    Text("Drag the open notch's bottom-right corner to make it smaller or larger.")
                }
            }
        }
    }

    /// Liquid Glass came with macOS 26.
    private static var glassAvailable: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    private var themeNote: String {
        guard Self.glassAvailable else { return "Glass needs macOS 26 or later." }
        let note =
            "Glass shows your desktop through the open notch, the way macOS draws Control Center. Closed, the notch "
            + "stays black to hide in the camera housing."
        let accessibility = NSWorkspace.shared
        let solid =
            accessibility.accessibilityDisplayShouldReduceTransparency
            || accessibility.accessibilityDisplayShouldIncreaseContrast
        return solid ? note + " Reduce Transparency and Increase Contrast keep it black." : note
    }
}

/// Each theme as a small open notch over a wallpaper, picked the way System Settings picks Light or
/// Dark.
private struct ThemePicker: View {
    @Binding var theme: NotchTheme
    let glassAvailable: Bool

    var body: some View {
        HStack(spacing: 14) {
            ForEach(NotchTheme.allCases) { option in
                let selected = option == theme
                Button {
                    theme = option
                } label: {
                    VStack(spacing: 5) {
                        preview(option)
                            .padding(3)
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5)
                            }
                        Text(option.title).font(.caption).foregroundStyle(selected ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(option == .glass && !glassAvailable)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func preview(_ option: NotchTheme) -> some View {
        let notch = UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9, style: .continuous)
        return ZStack(alignment: .top) {
            LinearGradient(
                colors: [AboutSettings.peach, AboutSettings.coral, .indigo], startPoint: .topLeading,
                endPoint: .bottomTrailing)
            if option == .glass {
                notch.fill(.white.opacity(0.28)).overlay(notch.stroke(.white.opacity(0.7), lineWidth: 0.75))
                    .frame(width: 58, height: 26)
            } else {
                notch.fill(.black).frame(width: 58, height: 26)
            }
        }
        .frame(width: 84, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Where the notch shows: every display or just one, and what a display without a notch gets.
private struct DisplaysPage: View {
    @Bindable var preferences: NotchPreferences
    @State private var screens = NSScreen.screens.filter { !$0.hasNotch }

    var body: some View {
        SettingsPage(page: .displays) {
            Section {
                Toggle(isOn: $preferences.showOnAllDisplays) {
                    Text("Show on all displays")
                    Text("Otherwise ILoveNotch uses the built-in display's notch, or the main display.")
                }
            }
            Section {
                ForEach(screens, id: \.uuid) { screen in
                    Picker(
                        screen.localizedName,
                        selection: Binding(
                            get: { preferences.notchlessStyle(for: screen.uuid) },
                            set: { preferences.setNotchlessStyle($0, for: screen.uuid) })
                    ) {
                        ForEach(NotchlessStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if screens.isEmpty {
                    Text("None connected").foregroundStyle(.secondary)
                }
            } header: {
                Text("Displays Without a Notch")
            } footer: {
                Text(
                    "Each gets a notch as tall as its menu bar and as wide as a MacBook's, or a floating pill"
                        + "\(screens.isEmpty ? ", which you can pick here when one is connected" : "")."
                )
                .foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) {
            _ in screens = NSScreen.screens.filter { !$0.hasNotch }
        }
    }
}

/// Live activities that belong to no tab: volume, battery, and accessories.
private struct ActivitiesPage: View {
    @Bindable var preferences: NotchPreferences
    @State private var trusted = VolumeKeyTap.isTrusted

    var body: some View {
        SettingsPage(page: .activities) {
            Section("Volume") {
                Toggle("Show volume changes", isOn: $preferences.showsVolume)
                #if !APP_STORE  // the App Sandbox allows neither the volume-key tap nor the accessory monitor
                    // A closure, not a method reference: see GeneralPage.
                    let replaces = Binding(
                        get: { preferences.replacesVolumeDisplay }, set: { setReplacesVolumeDisplay($0) })
                    Toggle(isOn: replaces) {
                        Text("Replace the macOS volume display")
                        Text("Catches the volume keys so the change shows in the notch. Needs Accessibility access.")
                    }
                    .disabled(!preferences.showsVolume)
                    if preferences.replacesVolumeDisplay, !trusted {
                        LabeledContent("Accessibility") {
                            Button("Open Accessibility Settings") {
                                NSWorkspace.shared.open(.privacySettings("Privacy_Accessibility"))
                            }
                        }
                    }
                #endif
            }
            Section("Battery") {
                Toggle("Show charging and battery", isOn: $preferences.showsBattery)
                #if !APP_STORE
                    Toggle(isOn: $preferences.showsAccessoryBattery) {
                        Text("Show a Bluetooth accessory's battery when it connects")
                        Text("Experimental: Apple keyboards, mice, and trackpads.")
                    }
                #endif
            }
        }
        .onAppear { trusted = VolumeKeyTap.isTrusted }
    }

    private func setReplacesVolumeDisplay(_ replaces: Bool) {
        preferences.replacesVolumeDisplay = replaces
        trusted = VolumeKeyTap.isTrusted
        if replaces, !trusted { VolumeKeyTap.requestTrust() }
    }
}

/// Click, then press the new shortcut; Escape cancels and Delete clears it. The shortcut stops
/// working while recording, so pressing the current one records it rather than opening the notch.
private struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut?
    let hotKey: HotKey
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(monitor != nil ? "Press the shortcut…" : shortcut?.display ?? "Record Shortcut") {
                monitor == nil ? record() : stop()
            }
            .help(monitor != nil ? "Escape cancels, Delete clears" : "Click, then press a new shortcut")
            if shortcut != nil, monitor == nil {
                Button("Clear") { shortcut = nil }
            }
        }
        .onDisappear(perform: stop)
    }

    private func record() {
        hotKey.isPaused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                let plain = event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift])
                switch Int(event.keyCode) {
                case kVK_Escape where plain:
                    stop()
                case kVK_Delete where plain, kVK_ForwardDelete where plain:
                    shortcut = nil
                    stop()
                default:
                    guard let recorded = KeyShortcut(event: event) else {
                        NSSound.beep()  // needs Command, Option, or Control
                        return
                    }
                    shortcut = recorded
                    stop()
                }
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        hotKey.isPaused = false
    }
}

/// The app, its version and updates, then asks for a star and for help, in the icon's coral and peach.
private struct AboutSettings: View {
    let updater: Updater

    static let coral = Color(red: 0.93, green: 0.30, blue: 0.24)
    static let peach = Color(red: 0.95, green: 0.50, blue: 0.22)

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .background {
                    Circle()
                        .fill(LinearGradient(colors: [Self.coral, Self.peach], startPoint: .top, endPoint: .bottom))
                        .blur(radius: 26)
                        .opacity(0.45)
                }
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                (Text("I") + Text("Love").foregroundStyle(Self.coral) + Text("Notch"))
                    .font(.system(.title, design: .rounded).bold())
                Text("Version \(Updater.version)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            #if !APP_STORE  // the App Store updates its edition
                if updater.sourceDirectory != nil {
                    Button(
                        updater.state == .updating ? "Updating…" : "Update ILoveNotch", action: updater.updateFromSource
                    )
                    .disabled(updater.state == .updating)
                    if updater.state == .failed {
                        Button("The update failed. Show Log", action: updater.showLog).buttonStyle(.link)
                    }
                    Text("Rebuilds from this Mac's checkout and relaunches.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Check for Updates…", action: updater.checkForUpdates)
                }
            #endif
            AboutCard(url: Links.repository, glow: Self.coral) {
                HStack(spacing: 12) {
                    Image(systemName: "star.fill").font(.title)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Star ILoveNotch on GitHub").font(.headline)
                        Text("A star is how other Mac users find it.").font(.callout).opacity(0.9)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.callout.bold())
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(
                    LinearGradient(colors: [Self.coral, Self.peach], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            HStack(spacing: 10) {
                AboutTile(
                    title: "Contribute", detail: "Good first issues", symbol: "chevron.left.forwardslash.chevron.right",
                    tint: .blue, url: Links.contributing)
                AboutTile(
                    title: "Report a Bug", detail: "Or ask for a feature", symbol: "ladybug.fill", tint: .orange,
                    url: Links.newIssue)
                #if !APP_STORE  // the App Store takes no outside payments (3.1.1)
                    AboutTile(
                        title: "Sponsor", detail: "Fuel the next one", symbol: "heart.fill", tint: .pink,
                        url: Links.sponsor)
                #endif
            }
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Text("MIT licensed. Local-first: no accounts, no telemetry.").foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Link("Privacy", destination: Links.privacy)
                    Link("Acknowledgements", destination: Links.acknowledgements)
                }
            }
            .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

/// One of the About tab's links: a card that lifts its glow under the pointer.
private struct AboutCard<Content: View>: View {
    let url: URL
    let glow: Color
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        Link(destination: url) { content }
            .buttonStyle(.plain)
            .compositingGroup()  // one shadow for the card, not one per label
            .shadow(color: glow.opacity(hovering ? 0.45 : 0.15), radius: hovering ? 10 : 4, y: 2)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isLink)
    }
}

private struct AboutTile: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let url: URL

    var body: some View {
        AboutCard(url: url, glow: tint) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.15), in: Circle())
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.25)))
        }
    }
}
