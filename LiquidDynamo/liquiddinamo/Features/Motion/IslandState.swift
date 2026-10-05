//
//  IslandState.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import Foundation
import SwiftUI

// MARK: - Island State Machine

/// The primary state machine governing notch geometry, physics, and content presentation.
public enum IslandState: Equatable, Hashable, Sendable {
    /// Exactly the hardware notch size, completely invisible with zero extra padding or shadow.
    case idle

    /// The notch widens at notch height with leading and trailing wings.
    case compact

    /// Two concurrent background activities: primary activity in compact pill, secondary in detached bubble.
    case minimal

    /// Opens downward and wider into the full interactive dashboard upon click or deliberate hover.
    case expanded

    /// A transient, high-priority announcement (peripheral connected, low battery, HUD feedback).
    case alertPop
}

// MARK: - Alert Kinds & Payload

public enum AlertKind: Equatable, Sendable {
    case deviceConnected(name: String, icon: String)
    case airPodsConnected(name: String, batteryLeft: Int?, batteryRight: Int?, batteryCase: Int?)
    case batteryLow(device: String, percentage: Int, isCritical: Bool)
    case chargingConnected(level: Double)
    case systemHUD(title: String, icon: String, value: Double)
    case musicTrackChange(title: String, artist: String)
    case downloadProgress(fileName: String, progress: Double, speed: String)
    case notification(appName: String, sender: String, message: String)
    case privacyIndicator(type: String, appName: String)
    case custom(title: String, subtitle: String?, icon: String?)
}

public struct AlertPayload: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: AlertKind
    public let title: String
    public let subtitle: String?
    public let iconName: String?
    public let iconColor: Color
    public let dwellDuration: TimeInterval
    public let customSize: CGSize?
    public let progress: Double?
    public let trailingText: String?
    public let action: (@MainActor @Sendable () -> Void)?

    public init(
        id: String = UUID().uuidString,
        kind: AlertKind,
        title: String,
        subtitle: String? = nil,
        iconName: String? = nil,
        iconColor: Color = .white,
        dwellDuration: TimeInterval = 3.5,
        customSize: CGSize? = nil,
        progress: Double? = nil,
        trailingText: String? = nil,
        action: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.iconColor = iconColor
        self.dwellDuration = dwellDuration
        self.customSize = customSize
        self.progress = progress
        self.trailingText = trailingText
        self.action = action
    }

    public static func == (lhs: AlertPayload, rhs: AlertPayload) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.title == rhs.title
    }
}

// MARK: - Background Activity Tracking

public enum ActivityKind: Equatable, Hashable, Sendable {
    case musicPlayback
    case timer
    case batteryLevel
    case systemStats
    case networkSpeed
    case bluetoothDevice
    case microphone
    case fileTransfer
    case custom(String)
}

public struct IslandActivity: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: ActivityKind
    public let priority: Int // higher number = higher priority
    public let leadingIcon: String?
    public let title: String?
    public let tintColor: Color
    public let trailingIcon: String?
    public let trailingText: String?

    public init(
        id: String,
        kind: ActivityKind,
        priority: Int,
        leadingIcon: String? = nil,
        title: String? = nil,
        tintColor: Color = .white,
        trailingIcon: String? = nil,
        trailingText: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.priority = priority
        self.leadingIcon = leadingIcon
        self.title = title
        self.tintColor = tintColor
        self.trailingIcon = trailingIcon
        self.trailingText = trailingText
    }
}
