import AppKit
import ApplicationServices
import EventKit
import SwiftUI

extension Notification.Name {
    static let notchHotkeyChanged = Notification.Name("NotchIsland.hotkeyChanged")
    static let notchModulesChanged = Notification.Name("NotchIsland.modulesChanged")
}

/// Which Settings tab is showing; shared so the menu bar, the island and the updater can pick one.
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var tab = ProcessInfo.processInfo.environment["NOTCHISLAND_SETTINGS_TAB"] ?? "general"
}

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(tab: String? = nil) {
        if let tab { SettingsRouter.shared.tab = tab }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "NotchIsland Settings"
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var recording = false
    @State private var accent: Color = Theme.accent
    @State private var perms: [Permission: Permissions.Status] = [:]
    @State private var permissionNote: String?
    @ObservedObject private var router = SettingsRouter.shared

    var body: some View {
        TabView(selection: $router.tab) {
            general.tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            modules.tabItem { Label("Modules", systemImage: "square.grid.2x2") }.tag("modules")
            visibility.tabItem { Label("Visibility", systemImage: "eye") }.tag("visibility")
            UpdatesSettingsView().tabItem { Label("Updates", systemImage: "arrow.down.circle") }.tag("updates")
            permissions.tabItem { Label("Permissions", systemImage: "lock.shield") }.tag("permissions")
        }
        .frame(width: 540, height: 600)
    }

    // MARK: General

    private var general: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { launchAtLogin = $0; LaunchAtLogin.set($0) }))
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
            }
            Section("Hotkey") {
                HStack {
                    Text("Open app search")
                    Spacer()
                    Text(settings.hotkeyDescription)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    Button(recording ? "Press keys…" : "Change…") { recording.toggle() }
                        .background(KeyRecorder(active: $recording) { code, flags in
                            settings.hotkeyKeyCode = code
                            settings.hotkeyModifiers = Int(flags.rawValue)
                            NotificationCenter.default.post(name: .notchHotkeyChanged, object: nil)
                        })
                }
                Text("With Accessibility granted the key is swallowed (CGEvent tap); otherwise it is only observed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Feel") {
                HStack {
                    Text("Hover delay")
                    Slider(value: $settings.hoverDelay, in: 0...0.6, step: 0.05)
                    Text(String(format: "%.2fs", settings.hoverDelay)).monospacedDigit().frame(width: 44)
                }
                Toggle("Haptic feedback (Force Touch trackpads)", isOn: $settings.haptics)
                Toggle("Sound feedback", isOn: $settings.sounds)
                Text("Animations follow System Settings → Accessibility → Reduce Motion.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Theme") {
                ColorPicker("Accent colour", selection: $accent, supportsOpacity: false)
                    .onChange(of: accent) { newValue in settings.accentHex = NSColor(newValue).hexString }
                Button("Reset to white") { accent = .white; settings.accentHex = "#FFFFFF" }
                Toggle("Slightly translucent shade cards", isOn: $settings.translucentShade)
                Toggle("Shadow under the open island (like a window's)", isOn: $settings.islandShadow)
                Text("The island itself stays true black so it blends with the bezel.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Modules

    private var modules: some View {
        Form {
            Section("Live activities") {
                Toggle("Now Playing (TV, Music, Podcasts, QuickTime, Spotify, VLC, browsers and any other app)", isOn: $settings.mediaEnabled)
                Toggle("Notifications (banner + shade)", isOn: $settings.notificationsEnabled)
                Toggle("Volume HUD", isOn: $settings.volumeHUDEnabled)
                Toggle("Battery: charger and low-battery alerts", isOn: $settings.batteryAlertsEnabled)
                Toggle("Bluetooth / AirPods connect (with battery)", isOn: $settings.bluetoothEnabled)
                Toggle("Downloads progress (~/Downloads)", isOn: $settings.downloadsEnabled)
                Toggle("Mic / camera / Focus indicators", isOn: $settings.indicatorsEnabled)
            }
            Section("Shade") {
                Toggle("Next calendar event", isOn: $settings.calendarEnabled)
                Toggle("Timer / Pomodoro", isOn: $settings.timerEnabled)
                Toggle("Clipboard history", isOn: $settings.clipboardEnabled)
                Toggle("Shelf (drag files onto the notch)", isOn: $settings.shelfEnabled)
                Toggle("Quick toggles (dark mode, keep awake, Wi-Fi, mirror, Focus)", isOn: $settings.quickTogglesEnabled)
            }
            Text("Changes apply immediately.").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onChange(of: settings.mediaEnabled) { _ in NotificationCenter.default.post(name: .notchModulesChanged, object: nil) }
        .onChange(of: settings.notificationsEnabled) { _ in NotificationCenter.default.post(name: .notchModulesChanged, object: nil) }
        .onChange(of: settings.clipboardEnabled) { _ in NotificationCenter.default.post(name: .notchModulesChanged, object: nil) }
        .onChange(of: settings.downloadsEnabled) { _ in NotificationCenter.default.post(name: .notchModulesChanged, object: nil) }
        .onChange(of: settings.bluetoothEnabled) { _ in NotificationCenter.default.post(name: .notchModulesChanged, object: nil) }
        .onChange(of: settings.batteryAlertsEnabled) { _ in NotificationCenter.default.post(name: .notchModulesChanged, object: nil) }
        .onChange(of: settings.calendarEnabled) { _ in NotificationCenter.default.post(name: .notchModulesChanged, object: nil) }
        .onChange(of: settings.indicatorsEnabled) { _ in NotificationCenter.default.post(name: .notchModulesChanged, object: nil) }
    }

    // MARK: Visibility

    private var visibility: some View {
        Form {
            Section("Hide the island") {
                Toggle("When the frontmost app is full screen", isOn: $settings.hideInFullscreen)
                VStack(alignment: .leading, spacing: 4) {
                    Text("For these apps (bundle identifiers, comma-separated)")
                    TextField("com.apple.keynote, com.company.game", text: $settings.hiddenApps)
                        .textFieldStyle(.roundedBorder)
                }
            }
            Section("Displays") {
                Text("The island lives on the display with a notch. On a Mac without one it draws a 200 pt stand-in at the top of the main display.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Permissions

    private var permissions: some View {
        Form {
            Section("Status") {
                ForEach(Permission.allCases) { permissionRow($0) }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Switched on in System Settings but still red here? macOS ties each grant to the app's signature. An entry made by an earlier build of NotchIsland, or by a development binary (listed with a terminal icon), never matches this build, and flipping its switch changes nothing. Reset removes NotchIsland's entry so macOS asks fresh.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let permissionNote {
                        Text(permissionNote)
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !(perms[.fullDiskAccess]?.isGranted ?? false) {
                Section("Full Disk Access") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notifications come from Notification Center's own store, which macOS only opens for apps with Full Disk Access. There is no prompt for it: in that list click +, pick NotchIsland from Applications and switch it on, then relaunch. A NotchIsland entry with a terminal icon is a leftover from a development build and does not count.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Open Full Disk Access") { PrivacyPane.open(PrivacyPane.fullDiskAccess) }
                            Button("Relaunch NotchIsland") { QuickSystem.relaunch() }
                        }
                    }
                }
            }
            Section("Automation, Bluetooth, Camera") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Players and browsers (Automation), Bluetooth and the camera are asked for on first use. If one of them stopped responding after an update while System Settings shows it allowed, reset everything: macOS asks again on next use.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Reset All Permissions…") { confirmResetAll() }
                }
            }
            Section("Browser Now Playing") {
                Text("Chrome, Brave, Edge, Arc, Vivaldi, Opera: View ▸ Developer ▸ Allow JavaScript from Apple Events (once per browser).")
                    .font(.caption)
                Text("Safari: Settings ▸ Advanced ▸ Show features for web developers, then Develop ▸ Developer Settings ▸ Allow JavaScript from Apple Events.")
                    .font(.caption)
                Text("Every tab with media is a source. The island follows whichever stream started most recently and lists the others as chips in the card; tap one to switch. Without the switch (and in Firefox) the browser still shows through the system Now Playing feed, as one stream without tab chips.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Shortcuts integration") {
                Text("Push a custom live activity by writing JSON to:")
                Text(CustomActivityWatcher.fileURL.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Text(#"{"title":"Build done","subtitle":"main · 42s","symbol":"hammer.fill","progress":1,"seconds":5}"#)
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            Section("About") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NotchIsland \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "source")) · bundle id \(Bundle.main.bundleIdentifier ?? "none")")
                    Text(Permissions.identitySummary)
                    if !Permissions.isBundled {
                        Text("Running from source: macOS keys grants to this binary's path, and they are made again after every build.")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshPermissions() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: .notchPermissionsReset)) { _ in refreshPermissions() }
    }

    private func refreshPermissions() {
        var next: [Permission: Permissions.Status] = [:]
        for p in Permission.allCases { next[p] = Permissions.status(p) }
        if next != perms { perms = next }
    }

    private func permissionRow(_ p: Permission) -> some View {
        let s = perms[p] ?? Permissions.Status(grant: .unknown, stale: false)
        let symbol: String
        let tint: Color
        switch (s.grant, s.stale) {
        case (.granted, _): (symbol, tint) = ("checkmark.circle.fill", .green)
        case (.denied, true): (symbol, tint) = ("exclamationmark.triangle.fill", .orange)
        case (.denied, false): (symbol, tint) = ("xmark.circle.fill", .red)
        case (.notAsked, _): (symbol, tint) = ("questionmark.circle.fill", .secondary)
        case (.unknown, _): (symbol, tint) = ("minus.circle.fill", .secondary)
        }
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(tint).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.title)
                Text(p.purpose).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if s.stale {
                    Text("Was granted to an earlier build. System Settings may still show it on, but macOS no longer applies it: click Reset, then allow it again.")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if s.grant == .notAsked {
                    Text("Not asked yet.").font(.caption).foregroundStyle(.secondary)
                } else if s.grant == .unknown {
                    Text("Nothing to test against yet: no notification has been delivered on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if !s.isGranted {
                HStack(spacing: 6) {
                    Button(p.hasPrompt ? "Allow…" : "Open Settings") { Permissions.ask(p) }
                        .help(p.hasPrompt ? "Ask macOS for \(p.title)" : "Open the \(p.title) list in System Settings")
                    if s.grant == .denied {
                        Button("Reset…") { repair(p) }
                            .help("Remove NotchIsland's \(p.title) entry so macOS asks again")
                    }
                }
                .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }

    private func repair(_ p: Permission) {
        permissionNote = nil
        Permissions.repair(p) { ok, message in
            if !ok {
                permissionNote = "Reset failed\(message.isEmpty ? "" : " (\(message))"). Remove NotchIsland from the \(p.title) list with − and add it again with +."
            } else if p == .fullDiskAccess {
                permissionNote = "Entry removed. In the Full Disk Access list click +, pick NotchIsland from Applications, switch it on and relaunch."
            }
            refreshPermissions()
        }
    }

    private func confirmResetAll() {
        let alert = NSAlert()
        alert.messageText = "Reset all of NotchIsland's permissions?"
        alert.informativeText = "macOS forgets every grant NotchIsland has: Accessibility, Full Disk Access, Calendar, Automation for each player and browser, Bluetooth and Camera. It asks again on next use; Full Disk Access is added again by hand. NotchIsland relaunches afterwards."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset and Relaunch")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Permissions.reset(nil) { ok, message in
            if ok { QuickSystem.relaunch() } else { permissionNote = "Reset failed\(message.isEmpty ? "" : " (\(message))")." }
        }
    }
}

/// Invisible view that grabs the next key press while `active` is true.
struct KeyRecorder: NSViewRepresentable {
    @Binding var active: Bool
    var onKey: (Int, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        if active, context.coordinator.monitor == nil {
            context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .intersection([.command, .option, .control, .shift])
                if event.keyCode == 53 && flags.isEmpty {   // Esc cancels
                    DispatchQueue.main.async { active = false }
                    return nil
                }
                guard !flags.isEmpty || event.keyCode >= 96 else { return event }   // need a modifier unless F-key
                onKey(Int(event.keyCode), flags)
                DispatchQueue.main.async { active = false }
                return nil
            }
        } else if !active, let m = context.coordinator.monitor {
            NSEvent.removeMonitor(m)
            context.coordinator.monitor = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var monitor: Any? }
}
