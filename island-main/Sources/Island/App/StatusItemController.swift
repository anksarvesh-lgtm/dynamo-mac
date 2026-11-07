import AppKit
import IslandCore

/// Menu bar entry point (the app has no Dock icon).
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let env: AppEnvironment
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    init(env: AppEnvironment) {
        self.env = env
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Island")
            button.image?.isTemplate = true
        }
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let toggle = NSMenuItem(title: "Show Island", action: #selector(toggleIsland), keyEquivalent: "")
        toggle.state = env.settings.islandEnabled ? .on : .off
        toggle.target = self
        menu.addItem(toggle)
        if env.settings.searchEnabled, env.settings.islandEnabled {
            let s = NSMenuItem(title: "Search… (\(env.settings.searchShortcut.display))", action: #selector(openSearch), keyEquivalent: "")
            s.target = self
            menu.addItem(s)
        }
        menu.addItem(.separator())
        add("Settings…", #selector(openSettings), key: ",")
        add("Debug Panel", #selector(openDebug), key: "d")
        menu.addItem(.separator())
        add("Quit Island", #selector(quit), key: "q")
    }

    private func add(_ title: String, _ sel: Selector, key: String) {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        menu.addItem(i)
    }

    @objc private func toggleIsland() { env.settings.islandEnabled.toggle() }
    @objc private func openSearch() {
        // Let the menu finish closing before the panel takes key focus.
        DispatchQueue.main.async { self.env.commands.perform(.ui(.toggleSearch)) }
    }
    @objc private func openSettings() { env.commands.perform(.openSettings) }
    @objc private func openDebug() { env.showDebugPanel() }
    @objc private func quit() { NSApp.terminate(nil) }
}
