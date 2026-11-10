import Cocoa
import SwiftUI

@MainActor
class LiquidStatusMenu: NSMenu, NSMenuDelegate {
    
    var statusItem: NSStatusItem!
    private var storageItem: NSMenuItem?
    
    override init(title: String = "LiquidDynamo") {
        super.init(title: title)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = true
                button.image = image
            } else {
                button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "LiquidDynamo")
            }
        }
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu(menu)
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(menu)
    }
    
    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        
        // Header
        let titleItem = NSMenuItem(title: "LiquidDynamo 1.9.7", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        // Scopa Storage Clean Summary
        let cleaner = StorageCleanupManager.shared
        let reclaimableStr = cleaner.latestResult?.formattedTotalReclaimable ?? (cleaner.isScanning ? "Scanning…" : "0 B")
        let storageTitle = "Scopa Cleanable: \(reclaimableStr)"
        let stItem = NSMenuItem(title: storageTitle, action: #selector(openCleanerAction), keyEquivalent: "")
        stItem.target = self
        stItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        menu.addItem(stItem)
        
        if (cleaner.latestResult?.totalReclaimableBytes ?? 0) > 0 {
            let scopaItem = NSMenuItem(title: "Scopa: Clean Junk to Trash", action: #selector(scopaAllAction), keyEquivalent: "")
            scopaItem.target = self
            scopaItem.image = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: nil)
            menu.addItem(scopaItem)
        }
        
        let scanItem = NSMenuItem(title: "Rescan Storage", action: #selector(rescanStorageAction), keyEquivalent: "r")
        scanItem.target = self
        menu.addItem(scanItem)
        
        menu.addItem(NSMenuItem.separator())

        // Keep Awake Submenu
        let keepAwake = KeepAwakeManager.shared
        let keepAwakeTitle = keepAwake.isActive
            ? "Keep Awake: \(keepAwake.isIndefinite ? "Indefinite" : keepAwake.remainingFormatted)"
            : "Keep Awake: Off"
        let keepAwakeItem = NSMenuItem(title: keepAwakeTitle, action: nil, keyEquivalent: "")
        keepAwakeItem.image = NSImage(
            systemSymbolName: keepAwake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
            accessibilityDescription: nil
        )

        let kaSubmenu = NSMenu(title: "Keep Awake")
        if keepAwake.isActive {
            let stopItem = NSMenuItem(title: "Stop Keep Awake", action: #selector(stopKeepAwakeAction), keyEquivalent: "")
            stopItem.target = self
            stopItem.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)
            kaSubmenu.addItem(stopItem)

            if !keepAwake.isIndefinite {
                let extendItem = NSMenuItem(title: "Extend +15 Minutes", action: #selector(extendKeepAwakeAction), keyEquivalent: "")
                extendItem.target = self
                extendItem.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil)
                kaSubmenu.addItem(extendItem)
            }
            kaSubmenu.addItem(NSMenuItem.separator())
        }

        // Presets
        let presets: [(String, KeepAwakePreset)] = [
            ("15 Minutes", .m15),
            ("30 Minutes", .m30),
            ("1 Hour", .h1),
            ("2 Hours", .h2),
            ("4 Hours", .h4),
            ("Indefinitely", .indefinite)
        ]

        for (title, preset) in presets {
            let pItem = NSMenuItem(title: title, action: #selector(startPresetAction(_:)), keyEquivalent: "")
            pItem.target = self
            pItem.representedObject = preset
            if keepAwake.isActive, case .preset(let currentPreset) = keepAwake.activeDuration, currentPreset == preset {
                pItem.state = .on
            }
            kaSubmenu.addItem(pItem)
        }

        kaSubmenu.addItem(NSMenuItem.separator())

        // Mode Toggles
        let sysModeItem = NSMenuItem(title: "Keep System Awake", action: #selector(setSystemModeAction), keyEquivalent: "")
        sysModeItem.target = self
        sysModeItem.state = keepAwake.mode == .system ? .on : .off
        kaSubmenu.addItem(sysModeItem)

        let dispModeItem = NSMenuItem(title: "Keep System & Display Awake", action: #selector(setDisplayModeAction), keyEquivalent: "")
        dispModeItem.target = self
        dispModeItem.state = keepAwake.mode == .displayAndSystem ? .on : .off
        kaSubmenu.addItem(dispModeItem)

        kaSubmenu.addItem(NSMenuItem.separator())

        let openIslandKaItem = NSMenuItem(title: "Open in Dynamic Island…", action: #selector(openKeepAwakeInIslandAction), keyEquivalent: "")
        openIslandKaItem.target = self
        openIslandKaItem.image = NSImage(systemSymbolName: "bolt.shield", accessibilityDescription: nil)
        kaSubmenu.addItem(openIslandKaItem)

        keepAwakeItem.submenu = kaSubmenu
        menu.addItem(keepAwakeItem)

        menu.addItem(NSMenuItem.separator())
        
        // Settings & Controls
        let settingsItem = NSMenuItem(title: "Preferences…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit LiquidDynamo", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc func openCleanerAction() {
        DispatchQueue.main.async {
            IslandController.shared.setExpanded(view: .cleaner, pin: true)
        }
    }
    
    @objc func scopaAllAction() {
        Task {
            await StorageCleanupManager.shared.cleanAll()
        }
    }
    
    @objc func rescanStorageAction() {
        StorageCleanupManager.shared.scanAgain()
    }
    
    @objc func openSettingsAction() {
        DispatchQueue.main.async {
            SettingsWindowController.shared.showWindow()
        }
    }
    
    @objc func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Keep Awake Actions

    @objc func stopKeepAwakeAction() {
        KeepAwakeManager.shared.stop()
    }

    @objc func extendKeepAwakeAction() {
        KeepAwakeManager.shared.extend(by: 15 * 60)
    }

    @objc func startPresetAction(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? KeepAwakePreset else { return }
        KeepAwakeManager.shared.start(mode: KeepAwakeManager.shared.mode, duration: .preset(preset))
    }

    @objc func setSystemModeAction() {
        KeepAwakeManager.shared.changeMode(to: .system)
    }

    @objc func setDisplayModeAction() {
        KeepAwakeManager.shared.changeMode(to: .displayAndSystem)
    }

    @objc func openKeepAwakeInIslandAction() {
        DispatchQueue.main.async {
            IslandController.shared.setExpanded(view: .keepAwake, pin: true)
        }
    }
}
