//
//  AirPodsTypes.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import Foundation
import SwiftUI

// MARK: - Noise Control Modes

public enum AirPodsNoiseMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case off = "Off"
    case noiseCancellation = "Noise Cancellation"
    case transparency = "Transparency"
    case adaptive = "Adaptive"

    public var id: String { rawValue }

    public var systemImageName: String {
        switch self {
        case .off:
            return "circle.slash"
        case .noiseCancellation:
            return "earbuds.waveform"
        case .transparency:
            return "earbuds"
        case .adaptive:
            return "sparkles"
        }
    }
}

// MARK: - Capabilities

/// Flags defining what the current connection and hardware model actually support.
public struct AirPodsCapabilities: Equatable, Sendable {
    public var supportsBatteryParts: Bool // Left, Right, Case individual tracking
    public var supportsEarDetection: Bool
    public var supportsCaseLid: Bool
    public var supportsNoiseControl: Bool // ANC / Transparency
    public var supportsAdaptiveAudio: Bool
    public var supportsConversationAwareness: Bool
    public var supportsOneBudANC: Bool
    public var supportsHeadMotion: Bool

    public init(
        supportsBatteryParts: Bool = false,
        supportsEarDetection: Bool = false,
        supportsCaseLid: Bool = false,
        supportsNoiseControl: Bool = false,
        supportsAdaptiveAudio: Bool = false,
        supportsConversationAwareness: Bool = false,
        supportsOneBudANC: Bool = false,
        supportsHeadMotion: Bool = false
    ) {
        self.supportsBatteryParts = supportsBatteryParts
        self.supportsEarDetection = supportsEarDetection
        self.supportsCaseLid = supportsCaseLid
        self.supportsNoiseControl = supportsNoiseControl
        self.supportsAdaptiveAudio = supportsAdaptiveAudio
        self.supportsConversationAwareness = supportsConversationAwareness
        self.supportsOneBudANC = supportsOneBudANC
        self.supportsHeadMotion = supportsHeadMotion
    }

    public static let none = AirPodsCapabilities()

    /// Resolves capabilities from Apple Product ID / Model Name
    public static func forModel(modelID: UInt16) -> AirPodsCapabilities {
        switch modelID {
        case 0x2002, 0x200F: // AirPods 1st & 2nd Gen
            return AirPodsCapabilities(
                supportsBatteryParts: true,
                supportsEarDetection: true,
                supportsCaseLid: true,
                supportsNoiseControl: false,
                supportsAdaptiveAudio: false,
                supportsConversationAwareness: false,
                supportsOneBudANC: false,
                supportsHeadMotion: false
            )
        case 0x2013: // AirPods 3rd Gen
            return AirPodsCapabilities(
                supportsBatteryParts: true,
                supportsEarDetection: true,
                supportsCaseLid: true,
                supportsNoiseControl: false,
                supportsAdaptiveAudio: false,
                supportsConversationAwareness: false,
                supportsOneBudANC: false,
                supportsHeadMotion: true
            )
        case 0x2018: // AirPods 4th Gen (standard / ANC variants)
            return AirPodsCapabilities(
                supportsBatteryParts: true,
                supportsEarDetection: true,
                supportsCaseLid: true,
                supportsNoiseControl: true,
                supportsAdaptiveAudio: true,
                supportsConversationAwareness: true,
                supportsOneBudANC: false,
                supportsHeadMotion: true
            )
        case 0x200E, 0x2014: // AirPods Pro 1st & 2nd Gen
            return AirPodsCapabilities(
                supportsBatteryParts: true,
                supportsEarDetection: true,
                supportsCaseLid: true,
                supportsNoiseControl: true,
                supportsAdaptiveAudio: modelID == 0x2014,
                supportsConversationAwareness: modelID == 0x2014,
                supportsOneBudANC: true,
                supportsHeadMotion: true
            )
        case 0x200A: // AirPods Max
            return AirPodsCapabilities(
                supportsBatteryParts: false, // Single headphone unit
                supportsEarDetection: true,  // On-head detection
                supportsCaseLid: false,      // Smart case
                supportsNoiseControl: true,
                supportsAdaptiveAudio: false,
                supportsConversationAwareness: false,
                supportsOneBudANC: false,
                supportsHeadMotion: true
            )
        default:
            // Fallback for standard AirPods-like devices
            return AirPodsCapabilities(
                supportsBatteryParts: true,
                supportsEarDetection: true,
                supportsCaseLid: true,
                supportsNoiseControl: false,
                supportsAdaptiveAudio: false,
                supportsConversationAwareness: false,
                supportsOneBudANC: false,
                supportsHeadMotion: false
            )
        }
    }
}

// MARK: - Battery Part Model

public struct AirPodsBatteryPart: Equatable, Sendable {
    public var level: Int? // 0...100, nil if disconnected/unknown
    public var isCharging: Bool
    public var isConnected: Bool

    public init(level: Int? = nil, isCharging: Bool = false, isConnected: Bool = false) {
        self.level = level
        self.isCharging = isCharging
        self.isConnected = isConnected
    }
}

// MARK: - AirPods State

public struct AirPodsState: Equatable, Sendable {
    public var isConnected: Bool
    public var deviceID: String?
    public var modelName: String
    public var leftBattery: AirPodsBatteryPart
    public var rightBattery: AirPodsBatteryPart
    public var caseBattery: AirPodsBatteryPart
    public var leftInEar: Bool?
    public var rightInEar: Bool?
    public var lidOpen: Bool?
    public var noiseMode: AirPodsNoiseMode?
    public var adaptiveLevel: Double? // 0.0 ... 1.0
    public var conversationAwarenessEnabled: Bool?
    public var oneBudANCEnabled: Bool?
    public var headMotionAvailable: Bool
    public var roll: Double?
    public var pitch: Double?
    public var yaw: Double?

    public init(
        isConnected: Bool = false,
        deviceID: String? = nil,
        modelName: String = "AirPods",
        leftBattery: AirPodsBatteryPart = .init(),
        rightBattery: AirPodsBatteryPart = .init(),
        caseBattery: AirPodsBatteryPart = .init(),
        leftInEar: Bool? = nil,
        rightInEar: Bool? = nil,
        lidOpen: Bool? = nil,
        noiseMode: AirPodsNoiseMode? = nil,
        adaptiveLevel: Double? = nil,
        conversationAwarenessEnabled: Bool? = nil,
        oneBudANCEnabled: Bool? = nil,
        headMotionAvailable: Bool = false,
        roll: Double? = nil,
        pitch: Double? = nil,
        yaw: Double? = nil
    ) {
        self.isConnected = isConnected
        self.deviceID = deviceID
        self.modelName = modelName
        self.leftBattery = leftBattery
        self.rightBattery = rightBattery
        self.caseBattery = caseBattery
        self.leftInEar = leftInEar
        self.rightInEar = rightInEar
        self.lidOpen = lidOpen
        self.noiseMode = noiseMode
        self.adaptiveLevel = adaptiveLevel
        self.conversationAwarenessEnabled = conversationAwarenessEnabled
        self.oneBudANCEnabled = oneBudANCEnabled
        self.headMotionAvailable = headMotionAvailable
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
    }

    public static let disconnected = AirPodsState(
        isConnected: false,
        modelName: "AirPods"
    )
}

// MARK: - Write Commands & Control Errors

public enum AirPodsCommand: Equatable, Sendable {
    case setNoiseMode(AirPodsNoiseMode)
    case setAdaptiveLevel(Double)
    case setConversationAwareness(Bool)
    case setOneBudANC(Bool)
    case setVolume(Double)
}

public enum AirPodsControlError: LocalizedError, Equatable, Sendable {
    case deviceNotConnected
    case unsupportedOnModel(String)
    case aapUnavailable(String)
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .deviceNotConnected:
            return "AirPods are not connected."
        case .unsupportedOnModel(let reason):
            return reason
        case .aapUnavailable(let reason):
            return reason
        case .executionFailed(let reason):
            return reason
        }
    }
}
