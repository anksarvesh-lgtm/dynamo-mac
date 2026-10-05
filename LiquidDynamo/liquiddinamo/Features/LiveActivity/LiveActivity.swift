//
//  LiveActivity.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Live Activity Kind

public enum LiveActivityKind: String, Codable, CaseIterable, Sendable {
    case hud           // Icon + slider or level bar (e.g. Volume, Brightness)
    case alert         // Liquid-drop popup (e.g. AirPods, Bluetooth connect, Low battery)
    case ongoing       // Continuous background activity (e.g. Timer, Music, Call, Recording)
    case progress      // Task or download progress (e.g. Ring or Bar)
    case notification  // App or system message with body, action, and swipe dismiss
}

// MARK: - Severity & Standard Tints

public enum LiveActivitySeverity: String, Codable, CaseIterable, Sendable {
    case info          // Emerald
    case warning       // Amber
    case critical      // Red

    public var color: Color {
        switch self {
        case .info:
            return Color(red: 0.06, green: 0.78, blue: 0.48) // Emerald
        case .warning:
            return Color(red: 1.00, green: 0.65, blue: 0.00) // Amber
        case .critical:
            return Color(red: 0.95, green: 0.22, blue: 0.23) // Crimson Red
        }
    }
}

// MARK: - Standard Priorities

public enum LiveActivityPriority {
    public static let critical: Int = 100
    public static let alert: Int = 80
    public static let hud: Int = 60
    public static let progress: Int = 50
    public static let notification: Int = 40
    public static let ongoing: Int = 20
    public static let idle: Int = 0
}

// MARK: - Payload

public struct LiveActivityPayload: @unchecked Sendable {
    public var title: String
    public var subtitle: String?
    public var body: String?
    public var iconName: String?
    public var iconColor: Color?
    public var value: Double?            // 0.0 ... 1.0 (for sliders, level bars, or progress)
    public var progressTotal: Double?    // Optional max value
    public var progressCurrent: Double?  // Optional current value
    public var isDraggable: Bool         // For interactive HUD sliders
    public var actionTitle: String?      // Primary action label
    public var action: (() -> Void)?     // Action to execute on click
    public var secondaryActionTitle: String?
    public var secondaryAction: (() -> Void)?
    public var auxData: [String: Any]?

    public init(
        title: String,
        subtitle: String? = nil,
        iconName: String? = nil,
        body: String? = nil,
        iconColor: Color? = nil,
        value: Double? = nil,
        progressTotal: Double? = nil,
        progressCurrent: Double? = nil,
        isDraggable: Bool = false,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        auxData: [String: Any]? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.body = body
        self.iconColor = iconColor
        self.value = value
        self.progressTotal = progressTotal
        self.progressCurrent = progressCurrent
        self.isDraggable = isDraggable
        self.actionTitle = actionTitle
        self.action = action
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
        self.auxData = auxData
    }
}

// MARK: - Live Activity Model

public struct LiveActivity: Identifiable, @unchecked Sendable {
    public let id: String
    public let source: String
    public let kind: LiveActivityKind
    public var priority: Int
    public var tint: Color
    public var duration: TimeInterval?   // nil means ongoing; positive number = auto-dismiss seconds
    public var coalescingKey: String?    // If set, subsequent updates with this key mutate in-place
    public var payload: LiveActivityPayload
    public var pauseDismissalOnHover: Bool
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        source: String,
        kind: LiveActivityKind,
        priority: Int,
        tint: Color = LiveActivitySeverity.info.color,
        duration: TimeInterval? = nil,
        coalescingKey: String? = nil,
        payload: LiveActivityPayload,
        pauseDismissalOnHover: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.kind = kind
        self.priority = priority
        self.tint = tint
        self.duration = duration
        self.coalescingKey = coalescingKey
        self.payload = payload
        self.pauseDismissalOnHover = pauseDismissalOnHover
        self.createdAt = createdAt
    }
}

// MARK: - Live Activity Source Protocol

/// Protocol implemented by modules emitting LiveActivity events into the centralized hub.
@MainActor
public protocol LiveActivitySource: AnyObject {
    var identifier: String { get }
    var activityPublisher: AnyPublisher<LiveActivity, Never> { get }
    func start()
    func stop()
}
