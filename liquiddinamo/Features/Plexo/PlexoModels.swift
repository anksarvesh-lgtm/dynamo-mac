//
//  PlexoModels.swift
//  LiquidDynamo
//
//  Data models and types for Plexo Multi-Network Download Accelerator.
//  Faithfully ported from Plexo (https://github.com/anmolkapil/plexo).
//  Supports multi-network interface bonding, parallel chunking, work stealing,
//  torrent/magnet link handling, bandwidth limits, and scheduling.
//

import AppKit
import Foundation
import SwiftUI

public enum PlexoInterfaceKind: String, Codable, CaseIterable, Sendable {
    case wifi
    case ethernet
    case usb // iPhone USB tethering, mobile hotspot
    case bridge
    case other

    public var displayName: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .usb: return "USB / Mobile"
        case .bridge: return "Bridge"
        case .other: return "Network"
        }
    }

    public var iconName: String {
        switch self {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .usb: return "iphone"
        case .bridge: return "point.3.filled.connected.trianglepath.dotted"
        case .other: return "network"
        }
    }

    public var defaultColorHex: String {
        switch self {
        case .wifi: return "#00E5FF" // Neon Cyan
        case .ethernet: return "#00E676" // Neon Emerald
        case .usb: return "#FF9100" // Neon Amber
        case .bridge: return "#D500F9" // Neon Purple
        case .other: return "#2979FF" // Neon Blue
        }
    }
}

public struct PlexoInterface: Identifiable, Codable, Equatable, Sendable {
    public let id: String // e.g. "en0"
    public var bsdName: String // "en0"
    public var displayName: String // "Wi-Fi", "iPhone USB"
    public var userNickname: String?
    public var kind: PlexoInterfaceKind
    public var ipAddress: String?
    public var ipv6Address: String?
    public var macAddress: String?
    public var netmask: String?
    public var isEnabled: Bool
    public var colorHex: String
    public var downloadSpeed: Double // bytes/sec
    public var uploadSpeed: Double // bytes/sec
    public var totalBytesDownloaded: Int64
    public var speedLimitBytesPerSec: Double?
    public var dataAllowanceBytes: Int64?

    public init(
        id: String,
        bsdName: String,
        displayName: String,
        userNickname: String? = nil,
        kind: PlexoInterfaceKind,
        ipAddress: String? = nil,
        ipv6Address: String? = nil,
        macAddress: String? = nil,
        netmask: String? = nil,
        isEnabled: Bool = true,
        colorHex: String? = nil,
        downloadSpeed: Double = 0,
        uploadSpeed: Double = 0,
        totalBytesDownloaded: Int64 = 0,
        speedLimitBytesPerSec: Double? = nil,
        dataAllowanceBytes: Int64? = nil
    ) {
        self.id = id
        self.bsdName = bsdName
        self.displayName = displayName
        self.userNickname = userNickname
        self.kind = kind
        self.ipAddress = ipAddress
        self.ipv6Address = ipv6Address
        self.macAddress = macAddress
        self.netmask = netmask
        self.isEnabled = isEnabled
        self.colorHex = colorHex ?? kind.defaultColorHex
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.totalBytesDownloaded = totalBytesDownloaded
        self.speedLimitBytesPerSec = speedLimitBytesPerSec
        self.dataAllowanceBytes = dataAllowanceBytes
    }

    public var isOnline: Bool {
        ipAddress != nil && !ipAddress!.isEmpty
    }

    public var statusDescription: String {
        if let ip = ipAddress, !ip.isEmpty {
            return ip
        } else if isEnabled {
            return "Not Connected"
        } else {
            return "Disabled"
        }
    }

    public var effectiveName: String {
        userNickname?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? userNickname! : displayName
    }

    public var color: Color {
        Color(hex: colorHex) ?? .cyan
    }
}

public enum PlexoDownloadState: Codable, Equatable, Sendable {
    case queued
    case probing
    case downloading
    case paused
    case completed
    case failed(String)

    public var displayText: String {
        switch self {
        case .queued: return "Queued"
        case .probing: return "Probing Server…"
        case .downloading: return "Turbo Downloading"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed(let err): return "Failed: \(err)"
        }
    }
}

public struct PlexoChunk: Identifiable, Codable, Equatable, Sendable {
    public let id: Int
    public let rangeStart: Int64
    public let rangeEnd: Int64
    public var downloadedBytes: Int64
    public var assignedInterfaceId: String?
    public var isCompleted: Bool

    public init(
        id: Int,
        rangeStart: Int64,
        rangeEnd: Int64,
        downloadedBytes: Int64 = 0,
        assignedInterfaceId: String? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.downloadedBytes = downloadedBytes
        self.assignedInterfaceId = assignedInterfaceId
        self.isCompleted = isCompleted
    }

    public var size: Int64 {
        max(0, rangeEnd - rangeStart + 1)
    }

    public var progress: Double {
        guard size > 0 else { return 0 }
        return Double(downloadedBytes) / Double(size)
    }
}

public struct PlexoDownloadTask: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var urlString: String
    public var fileName: String
    public var destinationDirectory: String
    public var totalBytes: Int64
    public var downloadedBytes: Int64
    public var state: PlexoDownloadState
    public var speed: Double // bytes/sec
    public var perInterfaceBytes: [String: Int64] // interfaceId -> bytes
    public var perInterfaceSpeeds: [String: Double] // interfaceId -> bytes/sec
    public var supportsRange: Bool
    public var isTorrent: Bool
    public var torrentInfoHash: String?
    public var torrentPeersCount: Int
    public var chunks: [PlexoChunk]
    public var dateAdded: Date
    public var dateCompleted: Date?

    public init(
        id: UUID = UUID(),
        urlString: String,
        fileName: String,
        destinationDirectory: String,
        totalBytes: Int64 = 0,
        downloadedBytes: Int64 = 0,
        state: PlexoDownloadState = .queued,
        speed: Double = 0,
        perInterfaceBytes: [String: Int64] = [:],
        perInterfaceSpeeds: [String: Double] = [:],
        supportsRange: Bool = true,
        isTorrent: Bool = false,
        torrentInfoHash: String? = nil,
        torrentPeersCount: Int = 0,
        chunks: [PlexoChunk] = [],
        dateAdded: Date = Date(),
        dateCompleted: Date? = nil
    ) {
        self.id = id
        self.urlString = urlString
        self.fileName = fileName
        self.destinationDirectory = destinationDirectory
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.state = state
        self.speed = speed
        self.perInterfaceBytes = perInterfaceBytes
        self.perInterfaceSpeeds = perInterfaceSpeeds
        self.supportsRange = supportsRange
        self.isTorrent = isTorrent
        self.torrentInfoHash = torrentInfoHash
        self.torrentPeersCount = torrentPeersCount
        self.chunks = chunks
        self.dateAdded = dateAdded
        self.dateCompleted = dateCompleted
    }

    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(downloadedBytes) / Double(totalBytes)))
    }

    public var progressFraction: Double {
        progress
    }

    public var formattedSpeed: String {
        PlexoFormatting.formatSpeed(speed)
    }

    public var formattedTotalSize: String {
        PlexoFormatting.formatBytes(totalBytes)
    }

    public var formattedDownloadedSize: String {
        PlexoFormatting.formatBytes(downloadedBytes)
    }

    public var destinationFilePath: String {
        (destinationDirectory as NSString).appendingPathComponent(fileName)
    }

    public var timeRemainingString: String {
        guard speed > 1024, totalBytes > downloadedBytes else { return "—" }
        let remainingBytes = totalBytes - downloadedBytes
        let seconds = Double(remainingBytes) / speed
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else if seconds < 3600 {
            return String(format: "%.0fm %.0fs", seconds / 60, seconds.truncatingRemainder(dividingBy: 60))
        } else {
            return String(format: "%.1fh", seconds / 3600)
        }
    }
}

public struct PlexoBandwidthSettings: Codable, Equatable, Sendable {
    public var globalSpeedLimitBytesPerSec: Double?
    public var isSlowModeActive: Bool
    public var slowModeSpeedLimitBytesPerSec: Double
    public var isScheduleActive: Bool
    public var scheduleStartHour: Int
    public var scheduleEndHour: Int
    public var maxConcurrentDownloads: Int

    public init(
        globalSpeedLimitBytesPerSec: Double? = nil,
        isSlowModeActive: Bool = false,
        slowModeSpeedLimitBytesPerSec: Double = 1024 * 1024, // 1 MB/s
        isScheduleActive: Bool = false,
        scheduleStartHour: Int = 1, // 1 AM
        scheduleEndHour: Int = 7, // 7 AM
        maxConcurrentDownloads: Int = 3
    ) {
        self.globalSpeedLimitBytesPerSec = globalSpeedLimitBytesPerSec
        self.isSlowModeActive = isSlowModeActive
        self.slowModeSpeedLimitBytesPerSec = slowModeSpeedLimitBytesPerSec
        self.isScheduleActive = isScheduleActive
        self.scheduleStartHour = scheduleStartHour
        self.scheduleEndHour = scheduleEndHour
        self.maxConcurrentDownloads = maxConcurrentDownloads
    }
}

// MARK: - Utilities & Color Extension

public enum PlexoFormatting {
    public static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    public static func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec <= 0 { return "0 KB/s" }
        let kb = bytesPerSec / 1024.0
        if kb < 1024.0 {
            return String(format: "%.1f KB/s", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024.0 {
            return String(format: "%.1f MB/s", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.2f GB/s", gb)
    }
}

extension Color {
    public init?(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let rgbValue = UInt64(clean, radix: 16) else { return nil }
        self.init(
            red: Double((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: Double((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgbValue & 0x0000FF) / 255.0
        )
    }
}
