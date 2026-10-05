//
//  ModuleCatalog.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import Combine
import Defaults
import Foundation
import SwiftUI

// MARK: - Module Item Definition

public struct ModuleSourceItem: Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public let subtitle: String
    public let iconName: String
    public let defaultKind: LiveActivityKind
    public let defaultPriority: Int
    public let defaultSeverity: LiveActivitySeverity
    public let defaultDuration: TimeInterval
    public let defaultsKey: String
    public let isExperimental: Bool

    public init(
        id: String,
        displayName: String,
        subtitle: String = "",
        iconName: String,
        defaultKind: LiveActivityKind,
        defaultPriority: Int,
        defaultSeverity: LiveActivitySeverity = .info,
        defaultDuration: TimeInterval = 2.5,
        defaultsKey: String,
        isExperimental: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.subtitle = subtitle
        self.iconName = iconName
        self.defaultKind = defaultKind
        self.defaultPriority = defaultPriority
        self.defaultSeverity = defaultSeverity
        self.defaultDuration = defaultDuration
        self.defaultsKey = defaultsKey
        self.isExperimental = isExperimental
    }
}

// MARK: - Module Catalog

@MainActor
public final class ModuleCatalog: ObservableObject {
    public static let shared = ModuleCatalog()

    @Published public private(set) var modules: [ModuleSourceItem] = []

    public static let hideSystemHUDKey = "liveActivity_hide_system_hud"

    private init() {
        registerDefaultModules()
    }

    private func registerDefaultModules() {
        modules = [
            ModuleSourceItem(
                id: "volume",
                displayName: String(localized: "Volume & Mute"),
                subtitle: String(localized: "System volume level, hardware mute, and quick slider"),
                iconName: "speaker.wave.3.fill",
                defaultKind: .hud,
                defaultPriority: LiveActivityPriority.hud,
                defaultSeverity: .info,
                defaultDuration: 1.5,
                defaultsKey: "liveActivity_source_volume"
            ),
            ModuleSourceItem(
                id: "audio_output",
                displayName: String(localized: "Audio Output Device"),
                subtitle: String(localized: "Switches to AirPods, speakers, and external headphones"),
                iconName: "headphones",
                defaultKind: .alert,
                defaultPriority: LiveActivityPriority.alert,
                defaultSeverity: .info,
                defaultDuration: 2.5,
                defaultsKey: "liveActivity_source_audio_output"
            ),
            ModuleSourceItem(
                id: "brightness",
                displayName: String(localized: "Display Brightness"),
                subtitle: String(localized: "Brightness for all built-in and external DDC displays"),
                iconName: "sun.max.fill",
                defaultKind: .hud,
                defaultPriority: LiveActivityPriority.hud,
                defaultSeverity: .info,
                defaultDuration: 1.5,
                defaultsKey: "liveActivity_source_brightness"
            ),
            ModuleSourceItem(
                id: "keyboard_brightness",
                displayName: String(localized: "Keyboard Backlight"),
                subtitle: String(localized: "Illumination level for Apple and supported keyboards"),
                iconName: "keyboard",
                defaultKind: .hud,
                defaultPriority: LiveActivityPriority.hud,
                defaultSeverity: .info,
                defaultDuration: 1.5,
                defaultsKey: "liveActivity_source_keyboard_brightness"
            ),
            ModuleSourceItem(
                id: "microphone",
                displayName: String(localized: "Microphone In-Use & Mute"),
                subtitle: String(localized: "Detects apps actively recording audio and mic mute state"),
                iconName: "mic.fill",
                defaultKind: .alert,
                defaultPriority: LiveActivityPriority.alert,
                defaultSeverity: .warning,
                defaultDuration: 3.0,
                defaultsKey: "liveActivity_source_microphone"
            ),
            ModuleSourceItem(
                id: "camera",
                displayName: String(localized: "Camera In-Use"),
                subtitle: String(localized: "Alerts when FaceTime, Zoom, or webcams start streaming"),
                iconName: "camera.fill",
                defaultKind: .alert,
                defaultPriority: LiveActivityPriority.alert,
                defaultSeverity: .warning,
                defaultDuration: 3.0,
                defaultsKey: "liveActivity_source_camera"
            ),
            ModuleSourceItem(
                id: "battery",
                displayName: String(localized: "Battery & Charging"),
                subtitle: String(localized: "Plugged in, charging started/stopped, 15% low, and 5% critical alerts"),
                iconName: "battery.100.bolt",
                defaultKind: .alert,
                defaultPriority: LiveActivityPriority.alert,
                defaultSeverity: .warning,
                defaultDuration: 3.5,
                defaultsKey: "liveActivity_source_battery"
            ),
            ModuleSourceItem(
                id: "caps_lock",
                displayName: String(localized: "Caps Lock Status"),
                subtitle: String(localized: "Instant alert when Caps Lock is toggled ON or OFF"),
                iconName: "capslock.fill",
                defaultKind: .alert,
                defaultPriority: LiveActivityPriority.alert,
                defaultSeverity: .info,
                defaultDuration: 2.0,
                defaultsKey: "liveActivity_source_caps_lock"
            ),
            ModuleSourceItem(
                id: "timer",
                displayName: String(localized: "Timers & Pomodoro"),
                subtitle: String(localized: "Ongoing countdown rings, focus sessions, and completion chimes"),
                iconName: "timer",
                defaultKind: .ongoing,
                defaultPriority: LiveActivityPriority.alert,
                defaultSeverity: .info,
                defaultDuration: 4.0,
                defaultsKey: "liveActivity_source_timer"
            ),
            ModuleSourceItem(
                id: "calendar_events",
                displayName: String(localized: "Upcoming Calendar Events"),
                subtitle: String(localized: "Meeting reminders 5 to 15 minutes before scheduled start"),
                iconName: "calendar",
                defaultKind: .alert,
                defaultPriority: LiveActivityPriority.alert,
                defaultSeverity: .info,
                defaultDuration: 5.0,
                defaultsKey: "liveActivity_source_calendar_events"
            ),
            ModuleSourceItem(
                id: "network",
                displayName: String(localized: "Network & VPN Status"),
                subtitle: String(localized: "Wi-Fi, Ethernet, offline alerts, and VPN connections"),
                iconName: "wifi",
                defaultKind: .alert,
                defaultPriority: LiveActivityPriority.alert,
                defaultSeverity: .info,
                defaultDuration: 3.0,
                defaultsKey: "liveActivity_source_network"
            ),
            ModuleSourceItem(
                id: "focus_mode",
                displayName: String(localized: "Focus Mode (Experimental)"),
                subtitle: String(localized: "Alerts when Do Not Disturb or Focus mode activates"),
                iconName: "moon.fill",
                defaultKind: .alert,
                defaultPriority: LiveActivityPriority.alert,
                defaultSeverity: .info,
                defaultDuration: 2.5,
                defaultsKey: "liveActivity_source_focus_mode",
                isExperimental: true
            ),
            ModuleSourceItem(
                id: "bluetooth",
                displayName: String(localized: "Bluetooth Accessories"),
                subtitle: String(localized: "Mouse, keyboard, and trackpad connection banners"),
                iconName: "bolt.horizontal.fill",
                defaultKind: .alert,
                defaultPriority: LiveActivityPriority.alert,
                defaultSeverity: .info,
                defaultDuration: 3.0,
                defaultsKey: "liveActivity_source_bluetooth"
            ),
            ModuleSourceItem(
                id: "airpods",
                displayName: String(localized: "AirPods Case & Buds"),
                subtitle: String(localized: "Battery pods and spatial audio connection alert"),
                iconName: "headphones",
                defaultKind: .alert,
                defaultPriority: LiveActivityPriority.alert,
                defaultSeverity: .info,
                defaultDuration: 3.5,
                defaultsKey: "liveActivity_source_airpods"
            ),
            ModuleSourceItem(
                id: "music",
                displayName: String(localized: "Media Playback Wing"),
                subtitle: String(localized: "Now playing title, artist, and playback controls"),
                iconName: "music.note",
                defaultKind: .ongoing,
                defaultPriority: LiveActivityPriority.ongoing,
                defaultSeverity: .info,
                defaultDuration: 3.0,
                defaultsKey: "liveActivity_source_music"
            )
        ]
    }

    // MARK: - Enabled State

    public func isSourceEnabled(_ identifier: String) -> Bool {
        guard let module = modules.first(where: { $0.id == identifier }) else {
            return true // Allow custom unlisted sources by default
        }
        if UserDefaults.standard.object(forKey: module.defaultsKey) == nil {
            // Experimental modules default to OFF; all standard modules default to ON
            return !module.isExperimental
        }
        return UserDefaults.standard.bool(forKey: module.defaultsKey)
    }

    public func setSourceEnabled(_ identifier: String, enabled: Bool) {
        guard let module = modules.first(where: { $0.id == identifier }) else { return }
        UserDefaults.standard.set(enabled, forKey: module.defaultsKey)
        objectWillChange.send()
    }

    // MARK: - Severity Customization

    public func sourceSeverity(for identifier: String) -> LiveActivitySeverity {
        let key = "liveActivity_severity_\(identifier)"
        if let raw = UserDefaults.standard.string(forKey: key),
           let severity = LiveActivitySeverity(rawValue: raw) {
            return severity
        }
        return modules.first(where: { $0.id == identifier })?.defaultSeverity ?? .info
    }

    public func setSourceSeverity(for identifier: String, severity: LiveActivitySeverity) {
        let key = "liveActivity_severity_\(identifier)"
        UserDefaults.standard.set(severity.rawValue, forKey: key)
        objectWillChange.send()
    }

    // MARK: - Duration Customization

    public func sourceDuration(for identifier: String) -> TimeInterval {
        let key = "liveActivity_duration_\(identifier)"
        if let stored = UserDefaults.standard.object(forKey: key) as? Double, stored > 0 {
            return stored
        }
        return modules.first(where: { $0.id == identifier })?.defaultDuration ?? 2.5
    }

    public func setSourceDuration(for identifier: String, duration: TimeInterval) {
        let key = "liveActivity_duration_\(identifier)"
        UserDefaults.standard.set(duration, forKey: key)
        objectWillChange.send()
    }

    // MARK: - Hide Native System HUD

    public var hideSystemHUD: Bool {
        get {
            return Defaults[.hideSystemOSD] || Defaults[.hudReplacement]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.hideSystemHUDKey)
            Defaults[.hideSystemOSD] = newValue
            Defaults[.hudReplacement] = newValue
            objectWillChange.send()
        }
    }
}
