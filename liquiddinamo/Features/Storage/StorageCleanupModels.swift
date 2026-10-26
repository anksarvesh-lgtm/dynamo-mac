//
//  StorageCleanupModels.swift
//  LiquidDynamo
//
//  Models for storage scanning, breakdown categories, safety tiers, and item tracking.
//  Faithfully structures Scopa's categories, safety allowlist tiering, and breakdown models.
//

import AppKit
import Foundation
import SwiftUI

public enum SafetyTier: String, CaseIterable, Codable, Hashable, Sendable {
    case safeToClean = "Safe to Clean"
    case checkFirst = "Check First"

    public var displayName: String { rawValue }

    public var color: Color {
        switch self {
        case .safeToClean: return Color(red: 0.25, green: 0.82, blue: 0.45)
        case .checkFirst: return Color(red: 1.0, green: 0.65, blue: 0.15)
        }
    }

    public var symbolName: String {
        switch self {
        case .safeToClean: return "checkmark.shield.fill"
        case .checkFirst: return "exclamationmark.triangle.fill"
        }
    }
}

public enum StorageCleanupCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case caches = "App Caches"
    case developer = "Dev Tools"
    case largeFiles = "Large Files"
    case appUninstaller = "App Uninstaller"
    case logs = "System Logs"
    case downloads = "Stale Downloads"
    case trash = "Trash"
    case junk = "Junk Files"
    case simulators = "Simulator Data"
    case xcode = "Xcode Data"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .caches: return "archivebox.fill"
        case .developer: return "hammer.fill"
        case .largeFiles: return "film.fill"
        case .appUninstaller: return "app.dashed"
        case .logs: return "doc.text.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .trash: return "trash.fill"
        case .junk: return "trash"
        case .simulators: return "iphone"
        case .xcode: return "wrench.and.screwdriver.fill"
        }
    }

    public var color: Color {
        switch self {
        case .caches: return Color(red: 0.25, green: 0.65, blue: 0.98)
        case .developer: return Color(red: 0.30, green: 0.80, blue: 0.40)
        case .largeFiles: return Color(red: 1.0, green: 0.80, blue: 0.20)
        case .appUninstaller: return Color(red: 0.85, green: 0.35, blue: 0.95)
        case .logs: return Color(red: 1.0, green: 0.65, blue: 0.15)
        case .downloads: return Color(red: 0.15, green: 0.85, blue: 0.75)
        case .trash: return Color(red: 0.95, green: 0.30, blue: 0.30)
        case .junk: return Color(red: 0.85, green: 0.35, blue: 0.95)
        case .simulators: return Color(red: 0.55, green: 0.45, blue: 0.95)
        case .xcode: return Color(red: 0.20, green: 0.50, blue: 0.90)
        }
    }

    public var subtitle: String {
        switch self {
        case .caches: return "Application cache directories"
        case .developer: return "Build artifacts, simulators & package registries"
        case .largeFiles: return "Large files (>100MB) & duplicate copies"
        case .appUninstaller: return "Leftovers and support data from uninstalled apps"
        case .logs: return "Diagnostic reports & user logs"
        case .downloads: return "Old disk images, packages & archives"
        case .trash: return "Items currently in user Trash"
        case .junk: return "Temporary leftovers & orphan files"
        case .simulators: return "Unused CoreSimulator devices & runtimes"
        case .xcode: return "DerivedData & archive artifacts"
        }
    }

    /// Primary Scopa categories displayed in order
    public static var primaryCases: [StorageCleanupCategory] {
        [.caches, .developer, .largeFiles, .appUninstaller, .logs, .downloads, .trash]
    }
}

public struct StorageCleanupItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let category: StorageCleanupCategory
    public let name: String
    public let path: String
    public let sizeBytes: Int64
    public let lastModified: Date
    public let detail: String?
    public let safetyTier: SafetyTier
    public let isDuplicate: Bool
    public let duplicateCount: Int

    public init(
        id: UUID = UUID(),
        category: StorageCleanupCategory,
        name: String,
        path: String,
        sizeBytes: Int64,
        lastModified: Date = Date(),
        detail: String? = nil,
        safetyTier: SafetyTier = .safeToClean,
        isDuplicate: Bool = false,
        duplicateCount: Int = 0
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
        self.detail = detail
        self.safetyTier = safetyTier
        self.isDuplicate = isDuplicate
        self.duplicateCount = duplicateCount
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

public struct StorageCleanupResult: Sendable {
    public let totalReclaimableBytes: Int64
    public let itemsByCategory: [StorageCleanupCategory: [StorageCleanupItem]]
    public let scannedDate: Date
    public let volumeTotal: Int64
    public let volumeUsed: Int64
    public let volumeFree: Int64
    public let systemBytes: Int64
    public let appsBytes: Int64
    public let cachesBytes: Int64
    public let devBytes: Int64
    public let largeFilesBytes: Int64

    public init(
        totalReclaimableBytes: Int64,
        itemsByCategory: [StorageCleanupCategory: [StorageCleanupItem]],
        scannedDate: Date = Date(),
        volumeTotal: Int64,
        volumeUsed: Int64,
        volumeFree: Int64,
        systemBytes: Int64 = 0,
        appsBytes: Int64 = 0,
        cachesBytes: Int64 = 0,
        devBytes: Int64 = 0,
        largeFilesBytes: Int64 = 0
    ) {
        self.totalReclaimableBytes = totalReclaimableBytes
        self.itemsByCategory = itemsByCategory
        self.scannedDate = scannedDate
        self.volumeTotal = volumeTotal
        self.volumeUsed = volumeUsed
        self.volumeFree = volumeFree
        self.systemBytes = systemBytes
        self.appsBytes = appsBytes
        self.cachesBytes = cachesBytes
        self.devBytes = devBytes
        self.largeFilesBytes = largeFilesBytes
    }

    public var formattedTotalReclaimable: String {
        ByteCountFormatter.string(fromByteCount: totalReclaimableBytes, countStyle: .file)
    }

    public var formattedVolumeTotal: String {
        ByteCountFormatter.string(fromByteCount: volumeTotal, countStyle: .file)
    }

    public var formattedVolumeUsed: String {
        ByteCountFormatter.string(fromByteCount: volumeUsed, countStyle: .file)
    }

    public var formattedVolumeFree: String {
        ByteCountFormatter.string(fromByteCount: volumeFree, countStyle: .file)
    }

    public var usedPercentage: Double {
        guard volumeTotal > 0 else { return 0 }
        return Double(volumeUsed) / Double(volumeTotal)
    }

    public var reclaimablePercentage: Double {
        guard volumeTotal > 0 else { return 0 }
        return Double(totalReclaimableBytes) / Double(volumeTotal)
    }

    public var freePercentage: Double {
        guard volumeTotal > 0 else { return 0 }
        return Double(volumeFree) / Double(volumeTotal)
    }

    public func totalBytes(for category: StorageCleanupCategory) -> Int64 {
        itemsByCategory[category]?.reduce(0) { $0 + $1.sizeBytes } ?? 0
    }

    public func formattedTotal(for category: StorageCleanupCategory) -> String {
        ByteCountFormatter.string(fromByteCount: totalBytes(for: category), countStyle: .file)
    }

    public func itemCount(for category: StorageCleanupCategory) -> Int {
        itemsByCategory[category]?.count ?? 0
    }

    public var categoriesWithReclaimableItems: [StorageCleanupCategory] {
        StorageCleanupCategory.allCases.filter { (itemsByCategory[$0]?.isEmpty == false) }
            .sorted { totalBytes(for: $0) > totalBytes(for: $1) }
    }
}
