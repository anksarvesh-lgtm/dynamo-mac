//
//  FileDroidModels.swift
//  LiquidDynamo
//
//  Data models for FileDroid & OpenMTP unified Android file management,
//  Finder external SSD mount emulation, and hardware telemetry.
//

import AppKit
import Foundation
import SwiftUI

public enum FileDroidConnectionType: String, Codable, CaseIterable {
    case adb = "ADB High-Speed"
    case mtp = "MTP Protocol"
    case wireless = "Wireless ADB"

    public var iconName: String {
        switch self {
        case .adb: return "bolt.fill"
        case .mtp: return "cable.connector"
        case .wireless: return "wifi"
        }
    }
}

public enum FileDroidDeviceStatus: String, Codable, CaseIterable {
    case connected = "Connected"
    case unauthorized = "Device Locked / Allow USB Debugging"
    case offline = "Offline"
    case connecting = "Connecting…"

    public var statusColor: Color {
        switch self {
        case .connected: return .green
        case .unauthorized: return .orange
        case .offline: return .secondary
        case .connecting: return .cyan
        }
    }
}

public struct AndroidDevice: Identifiable, Equatable, Hashable {
    public var id: String { serial }
    public let serial: String
    public var model: String
    public var manufacturer: String
    public var marketName: String
    public var androidVersion: String
    public var apiLevel: Int
    public var batteryLevel: Int?
    public var batteryTemperature: Double?
    public var batteryHealth: String?
    public var isCharging: Bool
    public var internalStorageTotal: UInt64
    public var internalStorageUsed: UInt64
    public var internalStorageFree: UInt64
    public var sdCardTotal: UInt64?
    public var sdCardUsed: UInt64?
    public var sdCardFree: UInt64?
    public var connectionType: FileDroidConnectionType
    public var status: FileDroidDeviceStatus
    public var mountPath: String?

    public init(
        serial: String,
        model: String = "Android Device",
        manufacturer: String = "Generic",
        marketName: String = "",
        androidVersion: String = "Android",
        apiLevel: Int = 34,
        batteryLevel: Int? = nil,
        batteryTemperature: Double? = nil,
        batteryHealth: String? = nil,
        isCharging: Bool = false,
        internalStorageTotal: UInt64 = 0,
        internalStorageUsed: UInt64 = 0,
        internalStorageFree: UInt64 = 0,
        sdCardTotal: UInt64? = nil,
        sdCardUsed: UInt64? = nil,
        sdCardFree: UInt64? = nil,
        connectionType: FileDroidConnectionType = .adb,
        status: FileDroidDeviceStatus = .connected,
        mountPath: String? = nil
    ) {
        self.serial = serial
        self.model = model
        self.manufacturer = manufacturer
        self.marketName = marketName.isEmpty ? model : marketName
        self.androidVersion = androidVersion
        self.apiLevel = apiLevel
        self.batteryLevel = batteryLevel
        self.batteryTemperature = batteryTemperature
        self.batteryHealth = batteryHealth
        self.isCharging = isCharging
        self.internalStorageTotal = internalStorageTotal
        self.internalStorageUsed = internalStorageUsed
        self.internalStorageFree = internalStorageFree
        self.sdCardTotal = sdCardTotal
        self.sdCardUsed = sdCardUsed
        self.sdCardFree = sdCardFree
        self.connectionType = connectionType
        self.status = status
        self.mountPath = mountPath
    }

    public var displayName: String {
        if !marketName.isEmpty && marketName != "Android Device" {
            return marketName
        }
        if !model.isEmpty && model != "Android Device" {
            let mfg = manufacturer.capitalized
            if model.lowercased().hasPrefix(mfg.lowercased()) {
                return model
            }
            return "\(mfg) \(model)"
        }
        return "Android Phone"
    }

    public var storageUsedPercentage: Double {
        guard internalStorageTotal > 0 else { return 0 }
        return Double(internalStorageUsed) / Double(internalStorageTotal)
    }

    public var sdCardUsedPercentage: Double {
        guard let total = sdCardTotal, total > 0, let used = sdCardUsed else { return 0 }
        return Double(used) / Double(total)
    }

    public var formattedInternalStorage: String {
        let used = FileDroidFormatting.formatBytes(internalStorageUsed)
        let total = FileDroidFormatting.formatBytes(internalStorageTotal)
        let free = FileDroidFormatting.formatBytes(internalStorageFree)
        return "\(free) free of \(total) (\(used) used)"
    }

    public var brandIconName: String {
        let m = manufacturer.lowercased()
        let mod = model.lowercased()
        if m.contains("google") || mod.contains("pixel") {
            return "phone.fill"
        } else if m.contains("samsung") || mod.contains("galaxy") {
            return "phone.fill"
        } else if m.contains("xiaomi") || m.contains("redmi") {
            return "phone.fill"
        } else if m.contains("oneplus") || m.contains("oppo") || m.contains("vivo") {
            return "phone.fill"
        }
        return "phone.fill"
    }
}

public struct AndroidFileItem: Identifiable, Equatable, Hashable {
    public var id: String { remotePath }
    public let name: String
    public let remotePath: String
    public let sizeBytes: UInt64
    public let modificationDate: Date
    public let isDirectory: Bool
    public let isHidden: Bool

    public init(
        name: String,
        remotePath: String,
        sizeBytes: UInt64,
        modificationDate: Date = Date(),
        isDirectory: Bool,
        isHidden: Bool = false
    ) {
        self.name = name
        self.remotePath = remotePath
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
        self.isHidden = isHidden
    }

    public var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    public var iconSymbol: String {
        if isDirectory {
            let lower = name.lowercased()
            if lower == "dcim" || lower == "camera" { return "camera.fill" }
            if lower == "download" || lower == "downloads" { return "arrow.down.circle.fill" }
            if lower == "pictures" || lower == "photos" { return "photo.stack.fill" }
            if lower == "music" || lower == "audio" { return "music.note.list" }
            if lower == "documents" || lower == "docs" { return "doc.fill" }
            if lower == "movies" || lower == "video" || lower == "videos" { return "film.fill" }
            if lower == "android" { return "gearshape.2.fill" }
            return "folder.fill"
        }

        switch fileExtension {
        case "jpg", "jpeg", "png", "webp", "gif", "heic", "raw", "dng", "bmp":
            return "photo.fill"
        case "mp4", "mkv", "mov", "avi", "webm", "3gp", "ts":
            return "film.fill"
        case "mp3", "m4a", "flac", "wav", "aac", "ogg", "opus":
            return "music.note"
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "tar", "gz", "7z", "rar", "tgz":
            return "doc.zipper"
        case "apk", "xapk", "apks":
            return "cube.box.fill"
        case "txt", "md", "json", "xml", "log", "csv":
            return "doc.text.fill"
        default:
            return "doc.fill"
        }
    }

    public var iconColor: Color {
        if isDirectory {
            let lower = name.lowercased()
            if lower == "dcim" || lower == "camera" { return .pink }
            if lower == "download" { return .blue }
            if lower == "pictures" { return .purple }
            if lower == "music" { return .red }
            if lower == "documents" { return .orange }
            if lower == "movies" { return .indigo }
            return .accentColor
        }

        switch fileExtension {
        case "jpg", "jpeg", "png", "webp", "gif", "heic": return .purple
        case "mp4", "mkv", "mov", "avi": return .indigo
        case "mp3", "m4a", "flac", "wav": return .red
        case "pdf": return .orange
        case "zip", "tar", "gz", "7z": return .yellow
        case "apk": return .green
        default: return .secondary
        }
    }

    public var formattedSize: String {
        if isDirectory { return "--" }
        return FileDroidFormatting.formatBytes(sizeBytes)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modificationDate)
    }
}

public enum FileDroidTransferDirection: String, Codable {
    case uploadToAndroid = "Upload to Phone"
    case downloadToMac = "Download to Mac"
}

public enum FileDroidTransferStatus: String, Codable {
    case queued = "Queued"
    case inProgress = "Transferring"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

public struct FileDroidTransferItem: Identifiable, Equatable {
    public let id: UUID
    public let fileName: String
    public let direction: FileDroidTransferDirection
    public let localPath: String
    public let remotePath: String
    public var totalBytes: UInt64
    public var transferredBytes: UInt64
    public var speedBytesPerSec: Double
    public var status: FileDroidTransferStatus
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        fileName: String,
        direction: FileDroidTransferDirection,
        localPath: String,
        remotePath: String,
        totalBytes: UInt64 = 0,
        transferredBytes: UInt64 = 0,
        speedBytesPerSec: Double = 0,
        status: FileDroidTransferStatus = .queued,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.direction = direction
        self.localPath = localPath
        self.remotePath = remotePath
        self.totalBytes = totalBytes
        self.transferredBytes = transferredBytes
        self.speedBytesPerSec = speedBytesPerSec
        self.status = status
        self.errorMessage = errorMessage
    }

    public var progressFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, Double(transferredBytes) / Double(totalBytes))
    }

    public var formattedSpeed: String {
        FileDroidFormatting.formatSpeed(speedBytesPerSec)
    }

    public var formattedProgress: String {
        let cur = FileDroidFormatting.formatBytes(transferredBytes)
        let tot = FileDroidFormatting.formatBytes(totalBytes)
        return "\(cur) of \(tot) (\(Int(progressFraction * 100))%)"
    }
}

public enum FileDroidFormatting {
    public static func formatBytes(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        if b < 1024 { return "\(bytes) B" }
        if b < 1024 * 1024 { return String(format: "%.1f KB", b / 1024.0) }
        if b < 1024 * 1024 * 1024 { return String(format: "%.1f MB", b / (1024.0 * 1024.0)) }
        return String(format: "%.1f GB", b / (1024.0 * 1024.0 * 1024.0))
    }

    public static func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec <= 0 { return "0 KB/s" }
        if bytesPerSec < 1024 { return String(format: "%.0f B/s", bytesPerSec) }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.1f KB/s", bytesPerSec / 1024.0) }
        return String(format: "%.1f MB/s", bytesPerSec / (1024.0 * 1024.0))
    }
}

public enum FileConflictResolution: String, CaseIterable, Identifiable {
    case replace = "Replace"
    case keepBoth = "Keep Both"
    case skip = "Skip"
    
    public var id: String { rawValue }
}

