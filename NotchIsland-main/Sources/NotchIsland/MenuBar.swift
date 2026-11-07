import AppKit

final class MenuBarController: NSObject {
    var openShade: (() -> Void)?
    var openLauncher: (() -> Void)?
    var openSettings: (() -> Void)?

    private var item: NSStatusItem?

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            make()
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    private func make() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                     accessibilityDescription: "NotchIsland")
        item.button?.image?.isTemplate = true
        item.menu = buildMenu()
        self.item = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Open Notifications", action: #selector(shade), keyEquivalent: "").target = self
        let launcher = menu.addItem(withTitle: "Search Apps", action: #selector(launcherAction), keyEquivalent: "")
        launcher.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Check for Updates…", action: #selector(updates), keyEquivalent: "").target = self
        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NotchIsland", action: #selector(quit), keyEquivalent: "q").target = self
        menu.delegate = self
        return menu
    }

    @objc private func shade() { openShade?() }
    @objc private func launcherAction() { openLauncher?() }
    @objc private func settings() { openSettings?() }
    @objc private func updates() {
        if Updater.shared.newer == nil { Updater.shared.check(manual: true) }
        SettingsWindowController.shared.show(tab: "updates")
    }
    @objc private func toggleLogin(_ sender: NSMenuItem) {
        LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension MenuBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items where item.action == #selector(toggleLogin) {
            item.state = LaunchAtLogin.isEnabled ? .on : .off
        }
        for item in menu.items where item.action == #selector(launcherAction) {
            item.title = "Search Apps   \(AppSettings.shared.hotkeyDescription)"
        }
        for item in menu.items where item.action == #selector(updates) {
            item.title = Updater.shared.available.map { "Update to \($0.version)…" } ?? "Check for Updates…"
        }
    }
}
