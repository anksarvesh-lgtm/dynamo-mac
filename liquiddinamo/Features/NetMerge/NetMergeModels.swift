//
//  NetMergeModels.swift
//  LiquidDynamo
//
//  Data structures and models for NetMerge multi-network link bonding.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import Foundation

/// Represents the real-time operational metrics of a single physical or tethered network interface.
public struct NetMergeAdapterMetric: Identifiable, Equatable, Hashable {
    public var id: String { name }
    public let name: String
    public var ipv4: String?
    public var ipv6: String?
    public var isUsable: Bool
    public var isChecking: Bool
    public var downloadSpeedMbps: Double
    public var uploadSpeedMbps: Double
    public var weight: Double
    public var activeFlows: Int
    public var totalFlows: Int
    public var failedCount: Int

    public init(
        name: String,
        ipv4: String? = nil,
        ipv6: String? = nil,
        isUsable: Bool = true,
        isChecking: Bool = false,
        downloadSpeedMbps: Double = 0.0,
        uploadSpeedMbps: Double = 0.0,
        weight: Double = 1.0,
        activeFlows: Int = 0,
        totalFlows: Int = 0,
        failedCount: Int = 0
    ) {
        self.name = name
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.isUsable = isUsable
        self.isChecking = isChecking
        self.downloadSpeedMbps = downloadSpeedMbps
        self.uploadSpeedMbps = uploadSpeedMbps
        self.weight = weight
        self.activeFlows = activeFlows
        self.totalFlows = totalFlows
        self.failedCount = failedCount
    }

    /// User-friendly label for interface type.
    public var interfaceTypeDisplayName: String {
        if name.starts(with: "en0") {
            return "Wi-Fi (en0)"
        } else if name.starts(with: "en") {
            return "Ethernet / Adapter (\(name))"
        } else if name.starts(with: "feth") || name.starts(with: "bridge") {
            return "Tether / Mobile Hotspot (\(name))"
        } else {
            return "Interface (\(name))"
        }
    }

    public var systemSymbolName: String {
        if name.starts(with: "en0") {
            return "wifi"
        } else if name.starts(with: "feth") {
            return "iphone.and.arrow.forward"
        } else {
            return "cable.connector.horizontal"
        }
    }
}

/// Operational state of the NetMerge daemon and bonding service.
public enum NetMergeServiceState: String, Equatable {
    case stopped = "Stopped"
    case starting = "Starting..."
    case active = "Bonding Active"
    case degraded = "Single Link (Waiting for 2nd connection)"
    case error = "Error"
}

/// IPv6 routing preference for NetMerge.
public enum NetMergeIPv6Mode: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case on = "Always On"
    case off = "Off"

    public var id: String { rawValue }

    public var flagValue: String {
        switch self {
        case .auto: return "auto"
        case .on: return "on"
        case .off: return "off"
        }
    }
}
