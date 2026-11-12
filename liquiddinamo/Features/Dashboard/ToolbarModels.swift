//
//  ToolbarModels.swift
//  LiquidDynamo
//
//  Feature registry, persistent configuration, and categories for the
//  expanded Dynamic Island Liquid Glass Toolbar.
//

import AppKit
import Defaults
import Foundation
import SwiftUI

// MARK: - Toolbar Categories

public enum ToolbarCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case core = "Core"
    case hardware = "Hardware & Telephony"
    case system = "System & Utility"
    case productivity = "Productivity & Shelf"
    case media = "Media & Audio"
    case privacy = "Privacy & Safety"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .core: return "square.grid.2x2.fill"
        case .hardware: return "iphone.gen3"
        case .system: return "gauge.with.needle.fill"
        case .productivity: return "tray.full.fill"
        case .media: return "music.note"
        case .privacy: return "hand.raised.fill"
        }
    }
}

// MARK: - Toolbar Feature Identifier

public enum ToolbarFeatureID: String, Codable, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    // Section A: Home (Always permanent first icon)
    case home = "home"

    // Section B: 23 Verified Implemented Tools
    case colorDropper = "colorDropper"
    case keepAwake = "keepAwake"
    case phoneBridge = "phoneBridge"
    case powerload = "powerload"
    case watcher = "watcher"
    case nowPlaying = "nowPlaying"
    case deviceUniverse = "deviceUniverse"
    case systemStats = "systemStats"
    case shelf = "shelf"
    case timer = "timer"
    case stopwatch = "stopwatch"
    case privacyGuard = "privacyGuard"
    case webcamMonitor = "webcamMonitor"
    case micMonitor = "micMonitor"
    case downloads = "downloads"
    case clipboard = "clipboard"
    case audioControls = "audioControls"
    case volumeControl = "volumeControl"
    case brightnessControl = "brightnessControl"
    case calendar = "calendar"
    case reminders = "reminders"
    case liveActivities = "liveActivities"
    case externalDisplay = "externalDisplay"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .home: return "Home"
        case .colorDropper: return "Color Dropper"
        case .keepAwake: return "Sleep Prevent"
        case .phoneBridge: return "Phone Bridge"
        case .powerload: return "Powerload Turbo"
        case .watcher: return "Watcher AI"
        case .nowPlaying: return "Now Playing"
        case .deviceUniverse: return "3D Devices"
        case .systemStats: return "System Stats"
        case .shelf: return "Notch Shelf"
        case .timer: return "Timer"
        case .stopwatch: return "Stopwatch"
        case .privacyGuard: return "Privacy Guard"
        case .webcamMonitor: return "Webcam"
        case .micMonitor: return "Microphone"
        case .downloads: return "Downloads"
        case .clipboard: return "Clipboard"
        case .audioControls: return "Audio Controls"
        case .volumeControl: return "Volume"
        case .brightnessControl: return "Brightness"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .liveActivities: return "Live Activities"
        case .externalDisplay: return "External Display"
        }
    }

    public var systemImage: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .colorDropper: return "eyedropper.halffull"
        case .keepAwake: return "bolt.shield.fill"
        case .phoneBridge: return "iphone.gen3"
        case .powerload: return "bolt.horizontal.fill"
        case .watcher: return "eye.fill"
        case .nowPlaying: return "music.note"
        case .deviceUniverse: return "cube.fill"
        case .systemStats: return "gauge.with.needle.fill"
        case .shelf: return "tray.full.fill"
        case .timer: return "timer"
        case .stopwatch: return "stopwatch.fill"
        case .privacyGuard: return "hand.raised.fill"
        case .webcamMonitor: return "web.camera.fill"
        case .micMonitor: return "mic.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .audioControls: return "waveform"
        case .volumeControl: return "speaker.wave.3.fill"
        case .brightnessControl: return "sun.max.fill"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .liveActivities: return "bell.badge.fill"
        case .externalDisplay: return "display.2"
        }
    }

    public var category: ToolbarCategory {
        switch self {
        case .home:
            return .core
        case .phoneBridge, .deviceUniverse, .externalDisplay:
            return .hardware
        case .colorDropper, .keepAwake, .powerload, .watcher, .systemStats:
            return .system
        case .shelf, .timer, .stopwatch, .downloads, .clipboard, .calendar, .reminders:
            return .productivity
        case .nowPlaying, .audioControls, .volumeControl, .brightnessControl:
            return .media
        case .privacyGuard, .webcamMonitor, .micMonitor, .liveActivities:
            return .privacy
        }
    }

    public var helpText: String {
        switch self {
        case .home: return "Home Dashboard: Devices, Clipboard, Scopa & Pinned"
        case .colorDropper: return "Color Dropper: Sample pixel colors on screen"
        case .keepAwake: return "Sleep Prevent / Caffeinate: Keep Mac awake"
        case .phoneBridge: return "Phone Bridge: Mirror and manage paired Android devices"
        case .powerload: return "Powerload Turbo: Multi-connection high-speed downloader"
        case .watcher: return "Watcher AI: Real-time autonomous agent monitoring"
        case .nowPlaying: return "Now Playing: Music player controls and artwork"
        case .deviceUniverse: return "3D Device Universe: Bluetooth and connected peripherals"
        case .systemStats: return "System Statistics: CPU, GPU, RAM, thermals and power"
        case .shelf: return "Notch Shelf: Drop zone for files, links, and snippets"
        case .timer: return "Timer: Quick focus countdown"
        case .stopwatch: return "Stopwatch: High precision lap timer"
        case .privacyGuard: return "Privacy Guard: Camera and mic shield status"
        case .webcamMonitor: return "Webcam Monitor: Active camera feeds"
        case .micMonitor: return "Microphone Monitor: Live input audio levels"
        case .downloads: return "Downloads: Active file downloads and recent arrivals"
        case .clipboard: return "Clipboard History: Search and reuse copied clips"
        case .audioControls: return "Audio Controls: Spectral equalizer and sound routing"
        case .volumeControl: return "Volume Control: Master audio output slider"
        case .brightnessControl: return "Brightness Control: Display backlights and DDC"
        case .calendar: return "Calendar: Upcoming events and meeting flight deck"
        case .reminders: return "Reminders: Scheduled tasks and checklists"
        case .liveActivities: return "Live Activities: Alerts, flight progress, delivery status"
        case .externalDisplay: return "External Display Island: Companion notch on secondary monitors"
        }
    }

    /// Whether this icon is permanently fixed (e.g. Home is always 1st).
    public var isFixed: Bool {
        self == .home
    }
}

// MARK: - Toolbar Configuration

public struct ToolbarConfig: Codable, Defaults.Serializable, Equatable, Sendable {
    public var version: Int
    public var featureOrder: [ToolbarFeatureID]
    public var enabledFeatureIDs: Set<ToolbarFeatureID>
    public var pinnedFeatureIDs: Set<ToolbarFeatureID>

    public init(
        version: Int = 1,
        featureOrder: [ToolbarFeatureID] = ToolbarConfig.defaultFeatureOrder,
        enabledFeatureIDs: Set<ToolbarFeatureID> = ToolbarConfig.defaultEnabledIDs,
        pinnedFeatureIDs: Set<ToolbarFeatureID> = ToolbarConfig.defaultPinnedIDs
    ) {
        self.version = version
        self.featureOrder = featureOrder
        self.enabledFeatureIDs = enabledFeatureIDs
        self.pinnedFeatureIDs = pinnedFeatureIDs
    }

    /// Factory default ordering (Home first, followed by default shortcuts).
    public static let defaultFeatureOrder: [ToolbarFeatureID] = [
        .home,
        .phoneBridge,
        .calendar,
        .shelf,
        .nowPlaying,
        .systemStats,
        .keepAwake,
        .clipboard,
        .volumeControl,
        .brightnessControl,
        .colorDropper,
        .powerload,
        .watcher,
        .deviceUniverse,
        .timer,
        .stopwatch,
        .privacyGuard,
        .webcamMonitor,
        .micMonitor,
        .downloads,
        .audioControls,
        .reminders,
        .liveActivities,
        .externalDisplay
    ]

    /// Default enabled tools.
    public static let defaultEnabledIDs: Set<ToolbarFeatureID> = [
        .home,
        .phoneBridge,
        .calendar,
        .shelf,
        .nowPlaying,
        .systemStats,
        .keepAwake,
        .clipboard,
        .volumeControl,
        .brightnessControl
    ]

    /// Default pinned tools (high priority).
    public static let defaultPinnedIDs: Set<ToolbarFeatureID> = [
        .home,
        .phoneBridge,
        .calendar,
        .shelf
    ]

    /// Sanitized list of enabled items in user-configured order, guaranteeing Home is always 1st.
    public var activeOrderedFeatures: [ToolbarFeatureID] {
        var items: [ToolbarFeatureID] = [.home]
        for feature in featureOrder where feature != .home {
            if enabledFeatureIDs.contains(feature) {
                items.append(feature)
            }
        }
        return items
    }
}

// MARK: - Defaults Keys

extension Defaults.Keys {
    public static let toolbarConfig = Key<ToolbarConfig>(
        "toolbarConfig_v1",
        default: ToolbarConfig()
    )
}
