//
//  AppPermissionManager.swift
//  LiquidDynamo
//
//  Centralized unified permission manager for LiquidDynamo.
//  Provides permission status monitoring, auto-refresh on app activation,
//  plain-language reasons, one-click repair linking, and on-demand gating.
//

import AppKit
import AVFoundation
import Combine
import CoreBluetooth
import Defaults
import EventKit
import Foundation
import SwiftUI

public enum AppPermissionKind: String, CaseIterable, Identifiable, Sendable {
    case accessibility
    case music
    case calendar
    case reminders
    case camera
    case bluetooth
    case fullDiskAccess

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .music: return "Music & Automation"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .camera: return "Camera Mirror"
        case .bluetooth: return "Bluetooth Devices"
        case .fullDiskAccess: return "Full Disk Access"
        }
    }

    public var iconName: String {
        switch self {
        case .accessibility: return "accessibility"
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .camera: return "camera.fill"
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .fullDiskAccess: return "internaldrive"
        }
    }

    public var reasonText: String {
        switch self {
        case .accessibility:
            return "Allows media key detection, volume gestures, and active app tracking."
        case .music:
            return "Enables Apple Music and Spotify playback controls from the liquid notch."
        case .calendar:
            return "Displays your upcoming meetings and event countdowns."
        case .reminders:
            return "Shows scheduled tasks and to-do reminders alongside your events."
        case .camera:
            return "Powers the optional quick mirror preview directly in your notch."
        case .bluetooth:
            return "Enables battery levels, connection status, and device metadata for paired accessories."
        case .fullDiskAccess:
            return "Allows comprehensive storage cleaning including deep app leftovers, system caches, and large files without per-folder prompts."
        }
    }

    public var systemSettingsURL: URL? {
        switch self {
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .music:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case .calendar:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        case .reminders:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
        case .camera:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
        case .bluetooth:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
        case .fullDiskAccess:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        }
    }
}

public enum AppPermissionStatus: String, Sendable {
    case allowed = "Allowed"
    case needsPermission = "Needs Permission"
    case needsRepair = "Needs Repair"
    case notNeeded = "Not Needed"

    public var badgeColor: Color {
        switch self {
        case .allowed: return .green
        case .needsPermission: return .orange
        case .needsRepair: return .red
        case .notNeeded: return .secondary
        }
    }
}

@MainActor
public final class AppPermissionManager: ObservableObject {
    public static let shared = AppPermissionManager()

    @Published public private(set) var statuses: [AppPermissionKind: AppPermissionStatus] = [:]
    @Published public private(set) var isChecking: Bool = false
    @Published public private(set) var recentlyGrantedKinds: Set<AppPermissionKind> = []

    private var cancellables = Set<AnyCancellable>()
    private var pollingTask: Task<Void, Never>?
    private var eventStore = EKEventStore()

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df
    }()

    private init() {
        // Evaluate initial statuses immediately
        self.statuses = evaluateAllPermissions()

        // Asynchronous immediate refresh
        DispatchQueue.main.async { [weak self] in
            self?.refreshAll()
        }

        // Automatic Refresh Trigger 1: App becomes active (e.g. returning from System Settings)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.log("App became active -> refreshing permissions")
                    self?.refreshAll()
                }
            }
            .store(in: &cancellables)

        // Automatic Refresh Trigger 2: Settings window becomes key
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { [weak self] notif in
                Task { @MainActor [weak self] in
                    if let win = notif.object as? NSWindow, win.title.contains("Settings") {
                        self?.log("Settings window became key -> refreshing permissions")
                        self?.refreshAll()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Core Permission Evaluation

    private func evaluateAllPermissions() -> [AppPermissionKind: AppPermissionStatus] {
        var evaluated: [AppPermissionKind: AppPermissionStatus] = [:]

        // 1. Accessibility: Check both AXIsProcessTrusted and with options dictionary
        let checkOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let axTrusted = AXIsProcessTrusted() || AXIsProcessTrustedWithOptions(checkOptions)
        evaluated[.accessibility] = axTrusted ? .allowed : .needsPermission

        // 2. Calendar: Fresh EventKit evaluation
        let calStatus = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            evaluated[.calendar] = (calStatus == .fullAccess || calStatus == .authorized || calStatus == .writeOnly) ? .allowed : .needsPermission
        } else {
            evaluated[.calendar] = (calStatus == .authorized) ? .allowed : .needsPermission
        }

        // 3. Reminders: Fresh EventKit evaluation
        let remStatus = EKEventStore.authorizationStatus(for: .reminder)
        if #available(macOS 14.0, *) {
            evaluated[.reminders] = (remStatus == .fullAccess || remStatus == .authorized || remStatus == .writeOnly) ? .allowed : .needsPermission
        } else {
            evaluated[.reminders] = (remStatus == .authorized) ? .allowed : .needsPermission
        }

        // 4. Camera: AVCaptureDevice authorization status
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        evaluated[.camera] = (camStatus == .authorized) ? .allowed : .needsPermission

        // 5. Bluetooth: CoreBluetooth authorization status
        let btStatus = CBCentralManager.authorization
        evaluated[.bluetooth] = (btStatus == .allowedAlways) ? .allowed : .needsPermission

        // 6. Music: preserve current or default to needsPermission
        evaluated[.music] = statuses[.music] ?? .needsPermission

        // 7. Full Disk Access: check readability of protected library directories without prompting
        let fdaGranted = Self.probeFullDiskAccess()
        evaluated[.fullDiskAccess] = fdaGranted ? .allowed : .needsPermission

        return evaluated
    }

    /// Probes if the current process has Full Disk Access by testing protected library locations.
    public static func probeFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let probes: [URL] = [
            home.appendingPathComponent("Library/Safari", isDirectory: true),
            home.appendingPathComponent("Library/Containers", isDirectory: true),
            home.appendingPathComponent("Library/Application Support", isDirectory: true)
        ]

        for url in probes {
            do {
                _ = try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsSubdirectoryDescendants]
                )
            } catch {
                return false
            }
        }
        return true
    }

    // MARK: - Status Checking & Logging

    public func status(for kind: AppPermissionKind) -> AppPermissionStatus {
        statuses[kind] ?? .needsPermission
    }

    public func refreshAll(targetKind: AppPermissionKind? = nil) {
        isChecking = true
        let timeStr = dateFormatter.string(from: Date())
        let previousStatuses = self.statuses
        let newStatuses = evaluateAllPermissions()

        for (kind, newStatus) in newStatuses {
            let oldStatus = previousStatuses[kind] ?? .needsPermission
            if oldStatus != newStatus {
                log("[\(timeStr)] 🟢 Permission Change Event: \(kind.displayName) [\(oldStatus.rawValue) ➡️ \(newStatus.rawValue)]")
                if newStatus == .allowed {
                    recentlyGrantedKinds.insert(kind)
                    if kind == .accessibility {
                        Task { @MainActor in
                            await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                        }
                    }
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        self?.recentlyGrantedKinds.remove(kind)
                    }
                }
            }
        }

        self.statuses = newStatuses

        log("[\(timeStr)] 🔄 Refreshed: AX=\(newStatuses[.accessibility]?.rawValue ?? "?"), Cal=\(newStatuses[.calendar]?.rawValue ?? "?"), Rem=\(newStatuses[.reminders]?.rawValue ?? "?"), Cam=\(newStatuses[.camera]?.rawValue ?? "?"), Music=\(newStatuses[.music]?.rawValue ?? "?")")

        // 5. Music Automation Check (background thread)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let musicStatus = self?.checkMusicAutomationStatus() ?? .needsPermission
            DispatchQueue.main.async {
                guard let self = self else { return }
                let oldMusic = self.statuses[.music] ?? .needsPermission
                if oldMusic != musicStatus {
                    self.log("[\(timeStr)] 🟢 Permission Change Event: Music [\(oldMusic.rawValue) ➡️ \(musicStatus.rawValue)]")
                    if musicStatus == .allowed {
                        self.recentlyGrantedKinds.insert(.music)
                    }
                }
                self.statuses[.music] = musicStatus
                self.isChecking = false
            }
        }
    }

    private func checkMusicAutomationStatus() -> AppPermissionStatus {
        let probe = "tell application \"System Events\" to return exists (processes where name is \"Music\")"
        var error: NSDictionary?
        if let script = NSAppleScript(source: probe) {
            _ = script.executeAndReturnError(&error)
            if error == nil {
                return .allowed
            } else if let code = error?[NSAppleScript.errorNumber] as? Int, code == -1743 {
                return .needsPermission
            }
        }
        return .allowed
    }

    // MARK: - Polling Engine (500ms for 10s upon Grant / Settings)

    public func startPolling(for targetKind: AppPermissionKind? = nil) {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.log("Starting 10-second polling session (500ms intervals) for \(targetKind?.displayName ?? "all permissions")")
            let startTime = CACurrentMediaTime()
            let timeout: Double = 10.0

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { break }

                let previousStatuses = self.statuses
                self.refreshAll(targetKind: targetKind)

                // If targeted permission flipped to .allowed, terminate polling early
                if let target = targetKind {
                    if previousStatuses[target] != .allowed && self.statuses[target] == .allowed {
                        self.log("Target permission \(target.displayName) successfully granted! Stopping polling session.")
                        break
                    }
                }

                if CACurrentMediaTime() - startTime >= timeout {
                    self.log("10-second polling session completed.")
                    break
                }
            }
        }
    }

    // MARK: - Actions

    public func requestPermission(for kind: AppPermissionKind) async {
        await request(kind: kind)
    }

    public func request(kind: AppPermissionKind) async {
        log("User requested permission for: \(kind.displayName)")
        switch kind {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
            // If still not trusted after prompt, guide user to System Settings
            if !AXIsProcessTrusted() {
                openSettings(for: .accessibility)
            }

        case .calendar:
            self.eventStore = EKEventStore()
            if #available(macOS 14.0, *) {
                _ = try? await eventStore.requestFullAccessToEvents()
            } else {
                _ = try? await eventStore.requestAccess(to: .event)
            }

        case .reminders:
            self.eventStore = EKEventStore()
            if #available(macOS 14.0, *) {
                _ = try? await eventStore.requestFullAccessToReminders()
            } else {
                _ = try? await eventStore.requestAccess(to: .reminder)
            }

        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)

        case .bluetooth:
            openSettings(for: .bluetooth)

        case .music:
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let triggerScript = "tell application \"Music\" to return player state"
                if let script = NSAppleScript(source: triggerScript) {
                    var err: NSDictionary?
                    _ = script.executeAndReturnError(&err)
                }
                DispatchQueue.main.async {
                    self?.refreshAll(targetKind: .music)
                }
            }
        }

        // Immediately refresh state and start the 500ms polling session for 10 seconds
        refreshAll(targetKind: kind)
        startPolling(for: kind)
    }

    public func openSettings(for kind: AppPermissionKind) {
        log("Opening System Settings for \(kind.displayName)")
        if let url = kind.systemSettingsURL {
            NSWorkspace.shared.open(url)
        }
        // Start 500ms polling so toggles in System Settings are detected immediately
        startPolling(for: kind)
    }

    private func log(_ message: String) {
        let time = dateFormatter.string(from: Date())
        print("🛡️ [PermissionManager] [\(time)] \(message)")
    }

    /// Determines the minimum set of permissions required by active module choices
    public func neededPermissions(forModuleKeys keys: Set<String>) -> [AppPermissionKind] {
        var needed: [AppPermissionKind] = []
        if keys.contains("media") {
            needed.append(.music)
            needed.append(.accessibility)
        }
        if keys.contains("calendar") {
            needed.append(.calendar)
            needed.append(.reminders)
        }
        if keys.contains("mirror") {
            needed.append(.camera)
        }
        return needed
    }
}
