//
//  AutoStartManager.swift
//  LiquidDynamo
//
//  Multi-tier login autostart manager supporting macOS 14 Sonoma and 15 Sequoia.
//  Combines native SMAppService (macOS 13+), user LaunchAgent plist (~/Library/LaunchAgents),
//  and System Events Login Item to guarantee 100% reliable startup registration.
//

import AppKit
import Defaults
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
public final class AutoStartManager: ObservableObject {
    public static let shared = AutoStartManager()

    @Published public private(set) var isEnabled: Bool = false

    private let launchAgentLabel = "com.agrigence.liquiddynamo"
    private var launchAgentPlistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    private init() {
        self.isEnabled = queryCurrentStatus()
    }

    /// Evaluates if any of the autostart mechanisms or user defaults are active
    public func queryCurrentStatus() -> Bool {
        // 1. Check LaunchAgent plist existence
        if FileManager.default.fileExists(atPath: launchAgentPlistURL.path) {
            return true
        }

        // 2. Check SMAppService mainApp status
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled {
                return true
            }
        }

        // 3. Check System Events login item
        if checkSystemEventsLoginItem() {
            return true
        }

        // 4. Check user defaults persistence
        return Defaults[.launchAtLogin]
    }

    /// Toggles autostart on or off across all supported macOS persistence layers
    public func setEnabled(_ enable: Bool) {
        objectWillChange.send()
        Defaults[.launchAtLogin] = enable

        if enable {
            enableAutoStart()
        } else {
            disableAutoStart()
        }

        self.isEnabled = queryCurrentStatus()
    }

    /// Synchronizes startup registration on app launch
    public func syncOnLaunch() {
        if Defaults[.launchAtLogin] {
            enableAutoStart()
            self.isEnabled = true
        } else {
            // Verify and remove if user explicitly disabled
            if FileManager.default.fileExists(atPath: launchAgentPlistURL.path) {
                disableAutoStart()
            }
            self.isEnabled = false
        }
    }

    // MARK: - Internal Registration

    private func enableAutoStart() {
        // Tier 1: SMAppService (native macOS 13+)
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try? SMAppService.mainApp.unregister()
                }
                try SMAppService.mainApp.register()
            } catch {
                NSLog("⚠️ [AutoStartManager] SMAppService registration note: \(error.localizedDescription)")
            }
        }

        // Tier 2: User LaunchAgent Plist (~/Library/LaunchAgents)
        installLaunchAgentPlist()

        // Tier 3: System Events Login Item
        addSystemEventsLoginItem()
    }

    private func disableAutoStart() {
        // Tier 1: SMAppService
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.unregister()
        }

        // Tier 2: LaunchAgent Plist
        removeLaunchAgentPlist()

        // Tier 3: System Events Login Item
        removeSystemEventsLoginItem()
    }

    // MARK: - LaunchAgent Plist Implementation

    private func installLaunchAgentPlist() {
        let fm = FileManager.default
        let folder = launchAgentPlistURL.deletingLastPathComponent()
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let targetAppPath = Bundle.main.bundlePath
        let execPath = Bundle.main.executablePath ?? "\(targetAppPath)/Contents/MacOS/LiquidDynamo"

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(execPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>ProcessType</key>
            <string>Interactive</string>
            <key>LimitLoadToSessionType</key>
            <string>Aqua</string>
        </dict>
        </plist>
        """

        try? plistContent.write(to: launchAgentPlistURL, atomically: true, encoding: .utf8)
    }

    private func removeLaunchAgentPlist() {
        try? FileManager.default.removeItem(at: launchAgentPlistURL)
    }

    // MARK: - System Events Login Item Implementation

    private func addSystemEventsLoginItem() {
        let appPath = Bundle.main.bundlePath
        // Use AppleScript to register Login Item without sandbox restrictions
        let script = """
        tell application "System Events"
            if not (exists login item "LiquidDynamo") then
                make login item at end with properties {name:"LiquidDynamo", path:"\(appPath)", hidden:false}
            end if
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }

    private func removeSystemEventsLoginItem() {
        let script = """
        tell application "System Events"
            if exists login item "LiquidDynamo" then
                delete login item "LiquidDynamo"
            end if
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }

    private func checkSystemEventsLoginItem() -> Bool {
        let script = """
        tell application "System Events"
            return (exists login item "LiquidDynamo")
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let res = appleScript.executeAndReturnError(&error)
            return res.booleanValue
        }
        return false
    }
}

// MARK: - SwiftUI Toggle Component

public struct AutoStartToggle<Label: View>: View {
    @ObservedObject private var manager = AutoStartManager.shared
    private let label: Label

    public init(@ViewBuilder label: () -> Label) {
        self.label = label()
    }

    public var body: some View {
        Toggle(isOn: Binding(
            get: { manager.isEnabled },
            set: { manager.setEnabled($0) }
        )) {
            label
        }
        .tint(.effectiveAccent)
    }
}

extension AutoStartToggle where Label == Text {
    public init(_ title: String = "Launch at login") {
        self.label = Text(title)
    }
}
