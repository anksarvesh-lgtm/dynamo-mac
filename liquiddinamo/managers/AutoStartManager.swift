//
//  AutoStartManager.swift
//  LiquidDynamo
//
//  Single-source login autostart manager supporting macOS 14 Sonoma and 15 Sequoia.
//  Uses native SMAppService (macOS 13+) as primary authority, with fallback to user
//  LaunchAgent plist (~/Library/LaunchAgents). Eliminates duplicate registrations
//  and prevents registration when running from transient DMG or temp volumes.
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

    /// Validates whether the application is installed in a permanent location eligible for autostart
    public var isEligibleForAutoStart: Bool {
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasPrefix("/Volumes/") || bundlePath.contains("/tmp/") || bundlePath.contains("/var/folders/") {
            return false
        }
        return true
    }

    private init() {
        self.isEnabled = queryCurrentStatus()
    }

    /// Evaluates if any of the autostart mechanisms or user defaults are active
    public func queryCurrentStatus() -> Bool {
        // 1. Check SMAppService mainApp status (macOS 13+)
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled {
                return true
            }
        }

        // 2. Check LaunchAgent plist existence
        if FileManager.default.fileExists(atPath: launchAgentPlistURL.path) {
            return true
        }

        // 3. Fallback check user defaults persistence
        return Defaults[.launchAtLogin]
    }

    /// Toggles autostart on or off cleanly without duplicate persistence entries
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

    /// Synchronizes startup registration on app launch and prunes legacy duplicates
    public func syncOnLaunch() {
        if Defaults[.launchAtLogin] {
            enableAutoStart()
            self.isEnabled = true
        } else {
            disableAutoStart()
            self.isEnabled = false
        }
    }

    // MARK: - Internal Registration

    private func enableAutoStart() {
        guard isEligibleForAutoStart else {
            NSLog("⚠️ [AutoStartManager] Skipping autostart registration: running from volume or transient path: %@", Bundle.main.bundlePath)
            return
        }

        var smRegistered = false
        // Primary modern mechanism: SMAppService (macOS 13+)
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try? SMAppService.mainApp.unregister()
                }
                try SMAppService.mainApp.register()
                smRegistered = true
                NSLog("✓ [AutoStartManager] SMAppService registration succeeded.")
            } catch {
                NSLog("⚠️ [AutoStartManager] SMAppService registration note: %@", error.localizedDescription)
            }
        }

        if smRegistered {
            // Clean up any redundant legacy LaunchAgent and System Events login item to avoid duplicate spawns
            removeLaunchAgentPlist()
            removeSystemEventsLoginItem()
        } else {
            // Fallback for environments where SMAppService is restricted
            installLaunchAgentPlist()
            removeSystemEventsLoginItem()
        }
    }

    private func disableAutoStart() {
        // Clean up all persistence tiers thoroughly
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.unregister()
        }

        removeLaunchAgentPlist()
        removeSystemEventsLoginItem()
    }

    // MARK: - LaunchAgent Plist Implementation

    private func installLaunchAgentPlist() {
        guard isEligibleForAutoStart else { return }

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

    // MARK: - Legacy System Events Cleanup

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
