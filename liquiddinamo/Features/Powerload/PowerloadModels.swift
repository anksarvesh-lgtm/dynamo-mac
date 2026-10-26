//
//  PowerloadModels.swift
//  LiquidDynamo
//
//  Data models and types for Powerload Multi-Network Download Accelerator.
//  Rebranded and extended from Plexo (https://github.com/anmolkapil/plexo).
//  Supports multi-network interface bonding, parallel chunking, work stealing,
//  torrent/magnet link handling, bandwidth limits, and scheduling.
//

import AppKit
import Defaults
import Foundation
import SwiftUI

extension Defaults.Keys {
    public static let powerloadUseMeteredConnections = Key<Bool>("powerloadUseMeteredConnections", default: true)
}

public actor PowerloadDownloadWorkerPool {
    private var pendingChunkIndices: [Int] = []
    private var completedChunkIndices: Set<Int> = []
    private var inFlightChunkIndices: [Int: String] = [:]

    public init(chunks: [PowerloadChunk]) {
        self.pendingChunkIndices = chunks.filter { !$0.isCompleted }.map { $0.id }
        self.completedChunkIndices = Set(chunks.filter { $0.isCompleted }.map { $0.id })
    }

    public func claimNextChunk(interfaceId: String) -> Int? {
        guard !pendingChunkIndices.isEmpty else { return nil }
        let next = pendingChunkIndices.removeFirst()
        inFlightChunkIndices[next] = interfaceId
        return next
    }

    public func markCompleted(chunkIndex: Int) {
        inFlightChunkIndices.removeValue(forKey: chunkIndex)
        completedChunkIndices.insert(chunkIndex)
    }

    public func returnChunk(chunkIndex: Int) {
        inFlightChunkIndices.removeValue(forKey: chunkIndex)
        if !completedChunkIndices.contains(chunkIndex) && !pendingChunkIndices.contains(chunkIndex) {
            pendingChunkIndices.insert(chunkIndex, at: 0)
        }
    }

    public var isAllCompleted: Bool {
        pendingChunkIndices.isEmpty && inFlightChunkIndices.isEmpty
    }

    public var progressCount: (completed: Int, inFlight: Int, remaining: Int) {
        (completedChunkIndices.count, inFlightChunkIndices.count, pendingChunkIndices.count)
    }
}

public enum PowerloadInterfaceKind: String, Codable, CaseIterable, Sendable {
    case wifi
    case ethernet
    case usb // iPhone USB tethering, mobile hotspot, Android RNDIS
    case bridge
    case other

    public var displayName: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .usb: return "USB / Mobile"
        case .bridge: return "Thunderbolt Bridge"
        case .other: return "Network Adapter"
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

public enum PowerloadHealthState: Codable, Equatable, Sendable {
    case usable
    case degraded(reason: String)
    case unusable(reason: String)

    public var isUsable: Bool {
        if case .usable = self { return true }
        return false
    }

    public var reasonText: String {
        switch self {
        case .usable: return "Ready"
        case .degraded(let reason): return reason
        case .unusable(let reason): return reason
        }
    }

    public var statusText: String {
        switch self {
        case .usable: return "Usable"
        case .degraded(let reason): return "Degraded: \(reason)"
        case .unusable(let reason): return "Unusable: \(reason)"
        }
    }
}

public struct PowerloadInterface: Identifiable, Codable, Equatable, Sendable {
    public let id: String // e.g. "en0"
    public var bsdName: String // "en0"
    public var displayName: String // "Wi-Fi", "iPhone USB", "Ethernet Adapter"
    public var userNickname: String?
    public var kind: PowerloadInterfaceKind
    public var ipAddress: String?
    public var ipv6Address: String?
    public var macAddress: String?
    public var netmask: String?
    public var gatewayIP: String?
    public var isLinkActive: Bool // Physical carrier link active (cable plugged in / connected)
    public var isEnabled: Bool
    public var isMetered: Bool
    public var health: PowerloadHealthState
    public var consecutiveFailures: Int
    public var ewmaThroughput: Double // Exponentially Weighted Moving Average in bytes/sec
    public var linkSpeedMbps: Int?
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
        kind: PowerloadInterfaceKind,
        ipAddress: String? = nil,
        ipv6Address: String? = nil,
        macAddress: String? = nil,
        netmask: String? = nil,
        gatewayIP: String? = nil,
        isLinkActive: Bool = false,
        isEnabled: Bool = true,
        isMetered: Bool = false,
        health: PowerloadHealthState = .unusable(reason: "Initializing"),
        consecutiveFailures: Int = 0,
        ewmaThroughput: Double = 0,
        linkSpeedMbps: Int? = nil,
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
        self.gatewayIP = gatewayIP
        self.isLinkActive = isLinkActive
        self.isEnabled = isEnabled
        self.isMetered = isMetered
        self.health = health
        self.consecutiveFailures = consecutiveFailures
        self.ewmaThroughput = ewmaThroughput
        self.linkSpeedMbps = linkSpeedMbps
        self.colorHex = colorHex ?? kind.defaultColorHex
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.totalBytesDownloaded = totalBytesDownloaded
        self.speedLimitBytesPerSec = speedLimitBytesPerSec
        self.dataAllowanceBytes = dataAllowanceBytes
    }

    public var hasIP: Bool {
        (ipAddress != nil && !ipAddress!.isEmpty) || (ipv6Address != nil && !ipv6Address!.isEmpty)
    }

    public var isOnline: Bool {
        health.isUsable
    }

    public var statusDescription: String {
        if !isEnabled {
            return "Disabled"
        }
        switch health {
        case .usable:
            if let ip = ipAddress, !ip.isEmpty {
                return "\(ip) • Usable"
            }
            return "Usable"
        case .degraded(let reason):
            return "Degraded: \(reason)"
        case .unusable(let reason):
            return reason
        }
    }

    public var isWifi: Bool {
        kind == .wifi
    }

    public var type: PowerloadInterfaceKind {
        kind
    }

    public var name: String {
        bsdName
    }

    public var speedMbps: Int {
        if let link = linkSpeedMbps, link > 0 {
            return link
        }
        if downloadSpeed > 1024 {
            return Int((downloadSpeed * 8) / (1024 * 1024))
        }
        return kind == .wifi ? 866 : 1000
    }

    public var isDefaultRoute: Bool {
        kind == .wifi || kind == .ethernet
    }

    public var effectiveName: String {
        userNickname?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? userNickname! : displayName
    }

    public var color: Color {
        Color(hex: colorHex) ?? .cyan
    }
}

// MARK: - Color Hex Initializer
extension Color {
    public init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        guard let intVal = UInt64(cleanHex, radix: 16) else { return nil }
        let r, g, b, a: Double
        if cleanHex.count == 6 {
            r = Double((intVal >> 16) & 0xFF) / 255.0
            g = Double((intVal >> 8) & 0xFF) / 255.0
            b = Double(intVal & 0xFF) / 255.0
            a = 1.0
        } else if cleanHex.count == 8 {
            r = Double((intVal >> 24) & 0xFF) / 255.0
            g = Double((intVal >> 16) & 0xFF) / 255.0
            b = Double((intVal >> 8) & 0xFF) / 255.0
            a = Double(intVal & 0xFF) / 255.0
        } else {
            return nil
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

public enum PowerloadDownloadState: Codable, Equatable, Sendable {
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

public struct PowerloadChunk: Identifiable, Codable, Equatable, Sendable {
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

    public var totalBytes: Int64 {
        size
    }

    public var progress: Double {
        guard size > 0 else { return 0 }
        return Double(downloadedBytes) / Double(size)
    }
}

public struct PowerloadDownloadTask: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var urlString: String
    public var fileName: String
    public var destinationDirectory: String
    public var totalBytes: Int64
    public var downloadedBytes: Int64
    public var state: PowerloadDownloadState
    public var speed: Double // bytes/sec
    public var perInterfaceBytes: [String: Int64] // interfaceId -> bytes
    public var perInterfaceSpeeds: [String: Double] // interfaceId -> bytes/sec
    public var supportsRange: Bool
    public var isTorrent: Bool
    public var torrentInfoHash: String?
    public var torrentPeersCount: Int
    public var chunks: [PowerloadChunk]
    public var dateAdded: Date
    public var dateCompleted: Date?

    public init(
        id: UUID = UUID(),
        urlString: String,
        fileName: String,
        destinationDirectory: String,
        totalBytes: Int64 = 0,
        downloadedBytes: Int64 = 0,
        state: PowerloadDownloadState = .queued,
        speed: Double = 0,
        perInterfaceBytes: [String: Int64] = [:],
        perInterfaceSpeeds: [String: Double] = [:],
        supportsRange: Bool = true,
        isTorrent: Bool = false,
        torrentInfoHash: String? = nil,
        torrentPeersCount: Int = 0,
        chunks: [PowerloadChunk] = [],
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
        PowerloadFormatting.formatSpeed(speed)
    }

    public var formattedTotalSize: String {
        PowerloadFormatting.formatBytes(totalBytes)
    }

    public var formattedDownloadedSize: String {
        PowerloadFormatting.formatBytes(downloadedBytes)
    }

    public var destinationFilePath: String {
        (destinationDirectory as NSString).appendingPathComponent(fileName)
    }

    public var timeRemainingString: String {
        guard speed > 1024, totalBytes > downloadedBytes else { return "—" }
        let remainingBytes = totalBytes - downloadedBytes
        return PowerloadFormatting.formatTimeRemaining(bytesLeft: remainingBytes, speedBytesPerSec: speed)
    }
}

public struct PowerloadTorrentInfo: Codable, Equatable, Sendable {
    public var infoHashHex: String
    public var displayName: String
    public var trackers: [String]
    public var piecesCount: Int
    public var pieceLength: Int64
    public var totalSize: Int64

    public init(infoHashHex: String, displayName: String, trackers: [String] = [], piecesCount: Int = 0, pieceLength: Int64 = 0, totalSize: Int64 = 0) {
        self.infoHashHex = infoHashHex
        self.displayName = displayName
        self.trackers = trackers
        self.piecesCount = piecesCount
        self.pieceLength = pieceLength
        self.totalSize = totalSize
    }
}

public struct PowerloadBandwidthSettings: Codable, Equatable, Sendable {
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

public enum PowerloadFormatting {
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

    public static func formatTimeRemaining(bytesLeft: Int64, speedBytesPerSec: Double) -> String {
        guard speedBytesPerSec > 1024, bytesLeft > 0 else { return "—" }
        let seconds = Double(bytesLeft) / speedBytesPerSec
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else if seconds < 3600 {
            return String(format: "%.0fm %.0fs", seconds / 60, seconds.truncatingRemainder(dividingBy: 60))
        } else {
            return String(format: "%.1fh", seconds / 3600)
        }
    }
}

// MARK: - Backward Compatibility Typealiases
public typealias PlexoInterfaceKind = PowerloadInterfaceKind
public typealias PlexoInterface = PowerloadInterface
public typealias PlexoDownloadState = PowerloadDownloadState
public typealias PlexoChunk = PowerloadChunk
public typealias PlexoDownloadTask = PowerloadDownloadTask
public typealias PlexoTorrentInfo = PowerloadTorrentInfo
public typealias PlexoFormatting = PowerloadFormatting
public typealias PlexoBandwidthSettings = PowerloadBandwidthSettings
