import AppKit
import IslandCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: IslandSettings
    let env: AppEnvironment
    @State private var pane: Pane = .general

    enum Pane: String, CaseIterable, Identifiable {
        case general = "General", appearance = "Appearance", behavior = "Behavior", activities = "Activities"
        case search = "Search", ai = "AI", accessibility = "Accessibility", advanced = "Advanced"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "paintbrush"
            case .behavior: "hand.point.up.left"
            case .activities: "square.stack.3d.up"
            case .search: "magnifyingglass"
            case .ai: "sparkles"
            case .accessibility: "accessibility"
            case .advanced: "wrench.and.screwdriver"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label(p.rawValue, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            Group {
                switch pane {
                case .general: GeneralSettings(settings: settings, env: env)
                case .appearance: AppearanceSettings(settings: settings)
                case .behavior: BehaviorSettings(settings: settings)
                case .activities: ActivitySettings(settings: settings, env: env)
                case .search: SearchSettings(settings: settings, env: env)
                case .ai: AISettings(settings: settings)
                case .accessibility: AccessibilitySettings(settings: settings, env: env)
                case .advanced: AdvancedSettings(settings: settings, env: env)
                }
            }
            .navigationTitle(pane.rawValue)
        }
        .frame(minWidth: 720, minHeight: 500)
    }
}

private struct GeneralSettings: View {
    @Bindable var settings: IslandSettings
    let env: AppEnvironment
    @State private var loginError: String?

    var body: some View {
        Form {
            Toggle("Enable Island", isOn: $settings.islandEnabled)
            Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: { v in
                loginError = LaunchAtLogin.set(v)
                settings.launchAtLogin = loginError == nil ? v : LaunchAtLogin.isEnabled
            }))
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            Picker("Display", selection: $settings.display) {
                Text("Automatic (notched display first)").tag(DisplaySelection.automatic)
                Text("Main display").tag(DisplaySelection.main)
                ForEach(env.display.screens, id: \.id) { s in
                    Text(s.name).tag(DisplaySelection.specific(name: s.name))
                }
            }
            if let g = env.display.geometry {
                LabeledContent("Current", value: "\(g.screen.name) · \(g.hasNotch ? "notch \(Int(g.notchSize.width))×\(Int(g.notchSize.height))pt" : "no notch")")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettings: View {
    @Bindable var settings: IslandSettings
    var body: some View {
        Form {
            Section {
                LabeledContent("Glass intensity") {
                    HStack { Slider(value: $settings.glassIntensity, in: 0...1); Text("\(Int(settings.glassIntensity * 100))%").monospacedDigit().frame(width: 40) }
                }
                LabeledContent("Island size") {
                    HStack { Slider(value: $settings.islandScale, in: 0.8...1.3); Text("\(Int(settings.islandScale * 100))%").monospacedDigit().frame(width: 40) }
                }
                Toggle("See-through compact Island", isOn: $settings.compactGlass)
                Toggle("Show song title in compact Island", isOn: $settings.compactShowsTitle)
                LabeledContent("Corner radius") {
                    HStack { Slider(value: $settings.cornerRadius, in: 12...48); Text("\(Int(settings.cornerRadius))").monospacedDigit().frame(width: 40) }
                }
            } footer: {
                Text("Glass intensity controls how see-through the Island is. The empty Island stays black so it disappears into the notch. Liquid Glass is used on macOS 26 and later.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct BehaviorSettings: View {
    @Bindable var settings: IslandSettings
    var body: some View {
        Form {
            Toggle("Expand on hover", isOn: $settings.hoverExpansion)
            if settings.hoverExpansion {
                LabeledContent("Hover delay") {
                    HStack { Slider(value: $settings.hoverDelay, in: 0...0.6); Text(String(format: "%.2fs", settings.hoverDelay)).monospacedDigit().frame(width: 48) }
                }
            }
            LabeledContent("Stay open after pointer leaves") {
                HStack { Slider(value: $settings.collapseDelay, in: 0.1...2); Text(String(format: "%.1fs", settings.collapseDelay)).monospacedDigit().frame(width: 48) }
            }
            Toggle("Auto-collapse after clicking", isOn: $settings.autoCollapse)
            if settings.autoCollapse {
                LabeledContent("Collapse after") {
                    HStack { Slider(value: $settings.autoCollapseDelay, in: 1...15); Text("\(Int(settings.autoCollapseDelay))s").monospacedDigit().frame(width: 48) }
                }
            }
            LabeledContent("Animation speed") {
                HStack { Slider(value: $settings.animationSpeed, in: 0.5...2); Text(String(format: "%.1f×", settings.animationSpeed)).monospacedDigit().frame(width: 48) }
            }
            Toggle("Trackpad haptics on expand", isOn: $settings.hapticFeedback)
        }
        .formStyle(.grouped)
    }
}

private struct ActivitySettings: View {
    @Bindable var settings: IslandSettings
    let env: AppEnvironment
    static let configurable: [(ActivityKind, String)] = [
        (.media, "Music, Spotify, VLC"), (.timer, "Countdown timers"), (.download, "Safari, Chrome & Finder downloads"),
        (.recording, "Shows when an app uses the mic or camera"), (.battery, "Charging, low battery, full"),
        (.network, "Going offline / back online"), (.device, "AirPods, headphones, speakers"),
        (.calendar, "Upcoming events (asks for Calendar access)"), (.clipboard, "Local “Copied” confirmations"),
        (.notification, "Short system events"),
    ]

    var body: some View {
        Form {
            Section("Activities") {
                ForEach(Self.configurable, id: \.0) { kind, detail in
                    Toggle(isOn: Binding(get: { settings.enabledKinds.contains(kind) }, set: { on in
                        if on { settings.enabledKinds.insert(kind) } else { settings.enabledKinds.remove(kind) }
                    })) {
                        VStack(alignment: .leading) { Text(kind.displayName); Text(detail).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Section {
                Toggle("Browser media (Safari, Chrome, Brave, Edge)", isOn: $settings.browserMediaEnabled)
            } footer: {
                Text("Requires “Allow JavaScript from Apple Events” in the browser's Develop/Developer menu. Island reads the playing media's title and position; it checks tabs every few seconds while the browser is open.")
            }
            if env.settings.enabledKinds.contains(.calendar) {
                LabeledContent("Calendar", value: env.calendar.status).font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SearchSettings: View {
    @Bindable var settings: IslandSettings
    let env: AppEnvironment
    @State private var braveKey = Keychain.get(account: "brave-search") ?? ""

    var body: some View {
        Form {
            Toggle("Enable search", isOn: $settings.searchEnabled)
            LabeledContent("Shortcut") { ShortcutRecorder(shortcut: $settings.searchShortcut) }
            Toggle("Files (Spotlight)", isOn: $settings.fileSearchEnabled)
            Toggle("Web", isOn: $settings.webSearchEnabled)
            if settings.webSearchEnabled {
                Section("Web providers") {
                    providerToggle("wikipedia", "Wikipedia (free, no key)")
                    providerToggle("duckduckgo", "DuckDuckGo Instant Answers (free, no key)")
                    providerToggle("brave", "Brave Search API (needs key)")
                    if settings.webSearchProviders.contains("brave") {
                        SecureField("Brave Search API key", text: $braveKey)
                            .onSubmit { try? Keychain.set(braveKey, account: "brave-search") }
                            .onDisappear { try? Keychain.set(braveKey, account: "brave-search") }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func providerToggle(_ id: String, _ title: String) -> some View {
        Toggle(title, isOn: Binding(get: { settings.webSearchProviders.contains(id) }, set: { on in
            if on { settings.webSearchProviders.insert(id) } else { settings.webSearchProviders.remove(id) }
        }))
    }
}

private struct AISettings: View {
    @Bindable var settings: IslandSettings
    @State private var key = ""

    var body: some View {
        Form {
            Picker("Provider", selection: $settings.aiProvider) {
                ForEach(AIProviderKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            if settings.aiProvider != .none {
                TextField("Model", text: $settings.aiModel, prompt: Text(AIProviderFactory.defaultModel(settings.aiProvider)))
                if settings.aiProvider != .ollama {
                    SecureField("API key (stored in Keychain)", text: $key)
                        .onAppear { key = Keychain.get(account: settings.aiProvider.rawValue) ?? "" }
                        .onChange(of: settings.aiProvider) { _, p in key = Keychain.get(account: p.rawValue) ?? "" }
                        .onSubmit { save() }
                        .onDisappear { save() }
                }
            }
            Section {} footer: {
                Text("Ask questions from search with “ask …” or by ending with “?”. Island searches the web, fetches sources, and shows a short answer with citations. AI can only return text — it cannot run commands or change your system.")
            }
        }
        .formStyle(.grouped)
    }

    private func save() { try? Keychain.set(key, account: settings.aiProvider.rawValue) }
}

private struct AccessibilitySettings: View {
    @Bindable var settings: IslandSettings
    let env: AppEnvironment
    var body: some View {
        Form {
            Section {
                Toggle("Reduce motion", isOn: $settings.forceReduceMotion)
                Toggle("Reduce transparency", isOn: $settings.forceReduceTransparency)
                Toggle("Increase contrast", isOn: $settings.forceHighContrast)
            } footer: {
                Text("Island always follows the matching System Settings › Accessibility › Display options. These switches force them on for Island only.")
            }
            Section("System") {
                LabeledContent("Reduce motion", value: env.accessibility.reduceMotion ? "On" : "Off")
                LabeledContent("Reduce transparency", value: env.accessibility.reduceTransparency ? "On" : "Off")
                LabeledContent("Increase contrast", value: env.accessibility.increaseContrast ? "On" : "Off")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettings: View {
    @Bindable var settings: IslandSettings
    let env: AppEnvironment
    var body: some View {
        Form {
            Toggle("Debug mode", isOn: $settings.debugMode)
            Toggle("Performance overlay", isOn: $settings.performanceOverlay)
            Button("Open Debug Panel") { env.showDebugPanel() }
            Button("Reset all settings", role: .destructive) { settings.resetToDefaults() }
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
        }
        .formStyle(.grouped)
    }
}

/// Click, then press the new key combination (must include ⌘, ⌥ or ⌃).
struct ShortcutRecorder: View {
    @Binding var shortcut: IslandShortcut
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press shortcut…" : shortcut.display) { recording ? stop() : start() }
            .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if e.keyCode == 53 { stop(); return nil }
            guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
            shortcut = IslandShortcut(keyCode: UInt32(e.keyCode), carbonModifiers: HotKey.carbonModifiers(from: flags),
                                        display: HotKey.display(keyCode: e.keyCode, characters: e.charactersIgnoringModifiers, flags: flags))
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    func show(env: AppEnvironment) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Island Settings"
            w.titlebarAppearsTransparent = true
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(settings: env.settings, env: env))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
