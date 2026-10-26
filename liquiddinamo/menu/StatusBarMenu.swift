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
}
