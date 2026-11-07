import AppKit
import SwiftUI
import NotchIslandInfoPlist

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel!
    private let state = IslandState()
    private let hotkey = HotkeyManager()
    private let menuBar = MenuBarController()
    private let visibility = VisibilityMonitor()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var accessibilityPoll: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = NotchIslandInfoPlistMarker()   // keeps the embedded Info.plist linked in

        panel = NotchPanel(state: state)
        panel.show()
        state.start()
        Updater.shared.startSchedule()   // launch + daily check against GitHub Releases (Settings ▸ Updates)

        // Menu bar icon
        menuBar.openShade = { [weak self] in self?.state.openShade() }
        menuBar.openLauncher = { [weak self] in self?.state.toggleLauncher() }
        menuBar.openSettings = { SettingsWindowController.shared.show() }
        menuBar.setVisible(AppSettings.shared.showMenuBarIcon)

        // Hotkey: CGEvent tap (swallows the key) when Accessibility allows, NSEvent monitors otherwise.
        hotkey.onTrigger = { [weak self] in self?.state.toggleLauncher() }
        installHotkey()
        state.setAccessibilityGranted(AXIsProcessTrusted())
        NotificationCenter.default.addObserver(forName: .notchHotkeyChanged, object: nil, queue: .main) { [weak self] _ in
            self?.installHotkey()
        }
        // A grant made (or lost) while running must be picked up without a relaunch: macOS announces
        // changes to the Accessibility list, and a slow poll covers the cases it does not.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.rearmHotkeyIfNeeded() }
        }
        accessibilityPoll = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.rearmHotkeyIfNeeded()
        }
        Permissions.calendarRequest = { [weak self] in self?.state.calendar.requestAccess() }

        // Hide over full-screen / listed apps.
        visibility.onChange = { [weak self] visible in self?.panel.setHiddenByPolicy(!visible) }
        visibility.start()

        // Settings that take effect live.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.menuBar.setVisible(AppSettings.shared.showMenuBarIcon)
            self.visibility.evaluate()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.panel.reposition() }

        // NOTCHISLAND_PREVIEW=expanded|shade|launcher|banner|activity|settings opens the island (or the
        // Settings window, on the NOTCHISLAND_SETTINGS_TAB tab) for screenshots and layout work.
        // NOTCHISLAND_DEMO=1 swaps the live sources for sample data first (see IslandState.seedDemo);
        // NOTCHISLAND_QUERY pre-fills the launcher.
        let env = ProcessInfo.processInfo.environment
        let demo = env["NOTCHISLAND_DEMO"] == "1"
        if !demo, env["NOTCHISLAND_PREVIEW"] == nil {
            // After an update, grants that belong to the previous build are cleared so System
            // Settings stops showing switches that do nothing, and Accessibility is asked for again.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { Permissions.repairAfterLaunchIfNeeded() }
        }
        if demo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.state.seedDemo() }
        }
        if let preview = env["NOTCHISLAND_PREVIEW"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + (demo ? 2.2 : 1.5)) { [weak self] in
                guard let self else { return }
                switch preview {
                case "expanded": self.state.setHovering(true)
                case "shade": self.state.toggleShade()
                case "launcher":
                    self.state.toggleLauncher()
                    if let q = env["NOTCHISLAND_QUERY"] {
                        self.state.query = q
                        // Focusing the field selects its text; park the caret at the end instead.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            if let tv = NSApp.keyWindow?.firstResponder as? NSTextView {
                                tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
                            }
                        }
                    }
                case "banner": self.state.demoBanner()
                case "activity": self.state.demoActivity()
                case "settings": SettingsWindowController.shared.show()
                default: break
                }
            }
        }
    }

    /// The CGEvent tap needs Accessibility. Re-run the install when the grant appears (tap replaces
    /// the observe-only monitors) or disappears (macOS disables the tap; fall back to monitors).
    private func rearmHotkeyIfNeeded() {
        let trusted = AXIsProcessTrusted()
        if hotkey.isActive != trusted { installHotkey() }
        state.setAccessibilityGranted(trusted)
    }

    private func installHotkey() {
        let settings = AppSettings.shared
        hotkey.configure(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyFlags)
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }

        if hotkey.start() { return }

        // Fallback: observe only (can't swallow). The global monitor still needs Accessibility to
        // see keys while another app is frontmost; the local one covers when we're frontmost.
        let code = UInt16(settings.hotkeyKeyCode)
        let flags = settings.hotkeyFlags.intersection([.command, .option, .control, .shift])
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard event.keyCode == code,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]) == flags
            else { return }
            self?.state.toggleLauncher()
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
            return event
        }
    }
}
