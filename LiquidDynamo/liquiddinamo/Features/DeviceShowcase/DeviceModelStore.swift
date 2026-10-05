//
//  DeviceModelStore.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Defaults
import Foundation

// MARK: - Model Source Tier

public enum ModelSourceTier: String, Codable {
    case cached = "cached"
    case categoryStandIn = "category_stand_in"
    case aiGenerated = "ai_generated"
    case custom = "custom"
}

// MARK: - Device Model Metadata

public struct DeviceModelMetadata: Codable, Equatable, Identifiable {
    public var id: String { deviceKey }
    public let deviceKey: String
    public var deviceName: String
    public var kind: String
    public var sourceTier: ModelSourceTier
    public var provider: String?
    public var sourceURL: String?
    public var createdAt: Date
    public var lastSeenAt: Date
    public var fileSizeBytes: Int64
    public var polygonCount: Int?
    public var isPinned: Bool

    public init(
        deviceKey: String,
        deviceName: String,
        kind: String,
        sourceTier: ModelSourceTier = .cached,
        provider: String? = nil,
        sourceURL: String? = nil,
        createdAt: Date = Date(),
        lastSeenAt: Date = Date(),
        fileSizeBytes: Int64 = 0,
        polygonCount: Int? = nil,
        isPinned: Bool = false
    ) {
        self.deviceKey = deviceKey
        self.deviceName = deviceName
        self.kind = kind
        self.sourceTier = sourceTier
        self.provider = provider
        self.sourceURL = sourceURL
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.fileSizeBytes = fileSizeBytes
        self.polygonCount = polygonCount
        self.isPinned = isPinned
    }
}

// MARK: - Device Model Store Actor

/// Thread-safe, non-blocking persistent store for 3D device models and previews.
/// Stores models under `~/Library/Application Support/com.agrigence.liquiddynamo/DeviceModels/<deviceKey>/`
/// Enforces LRU cache eviction based on user-configured cache size limits.
public actor DeviceModelStore {
    public static let shared = DeviceModelStore()

    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    public init(customBaseDirectory: URL? = nil) {
        if let customDir = customBaseDirectory {
            self.baseDirectory = customDir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let bundleID = Bundle.main.bundleIdentifier ?? "com.agrigence.liquiddynamo"
            self.baseDirectory = appSupport
                .appendingPathComponent(bundleID, isDirectory: true)
                .appendingPathComponent("DeviceModels", isDirectory: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.jsonEncoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.jsonDecoder = decoder

        createBaseDirectoryIfNeeded()
    }

    // MARK: - Path Helpers

    public func sanitize(key: String) -> String {
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<> ")
        let components = key.components(separatedBy: invalidChars)
        let filtered = components.filter { !$0.isEmpty }.joined(separator: "_")
        return filtered.isEmpty ? "device_unknown" : filtered
    }

    public func deviceDirectory(for deviceKey: String) -> URL {
        let safeKey = sanitize(key: deviceKey)
        return baseDirectory.appendingPathComponent(safeKey, isDirectory: true)
    }

    public func modelFileURL(for deviceKey: String) -> URL {
        return deviceDirectory(for: deviceKey).appendingPathComponent("model.usdz")
    }

    public func previewFileURL(for deviceKey: String) -> URL {
        return deviceDirectory(for: deviceKey).appendingPathComponent("preview.png")
    }

    public func metadataFileURL(for deviceKey: String) -> URL {
        return deviceDirectory(for: deviceKey).appendingPathComponent("meta.json")
    }

    // MARK: - Existence & Retrieval

    public func hasModel(for deviceKey: String) -> Bool {
        let url = modelFileURL(for: deviceKey)
        return fileManager.fileExists(atPath: url.path)
    }

    public func getModelURL(for deviceKey: String) -> URL? {
        let url = modelFileURL(for: deviceKey)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        touchDevice(deviceKey: deviceKey)
        return url
    }

    public func getPreviewImage(for deviceKey: String) -> NSImage? {
        let url = previewFileURL(for: deviceKey)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    public func getMetadata(for deviceKey: String) -> DeviceModelMetadata? {
        let url = metadataFileURL(for: deviceKey)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let meta = try? jsonDecoder.decode(DeviceModelMetadata.self, from: data) else {
            return nil
        }
        return meta
    }

    // MARK: - Saving

    @discardableResult
    public func saveModel(
        deviceKey: String,
        modelData: Data,
        previewImage: NSImage? = nil,
        previewData: Data? = nil,
        metadata: DeviceModelMetadata
    ) throws -> URL {
        let dir = deviceDirectory(for: deviceKey)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let modelURL = modelFileURL(for: deviceKey)
        try modelData.write(to: modelURL, options: .atomic)

        // Save preview PNG if provided
        let previewURL = previewFileURL(for: deviceKey)
        if let previewData = previewData {
            try? previewData.write(to: previewURL, options: .atomic)
        } else if let previewImage = previewImage,
                  let tiff = previewImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: previewURL, options: .atomic)
        }

        // Save metadata
        var updatedMeta = metadata
        updatedMeta.fileSizeBytes = Int64(modelData.count)
        updatedMeta.lastSeenAt = Date()
        let metaURL = metadataFileURL(for: deviceKey)
        let encoded = try jsonEncoder.encode(updatedMeta)
        try encoded.write(to: metaURL, options: .atomic)

        // Enforce cache size limits asynchronously
        enforceSizeCap()

        return modelURL
    }

    @discardableResult
    public func saveModelFile(
        deviceKey: String,
        from sourceURL: URL,
        previewImage: NSImage? = nil,
        metadata: DeviceModelMetadata
    ) throws -> URL {
        let data = try Data(contentsOf: sourceURL)
        return try saveModel(
            deviceKey: deviceKey,
            modelData: data,
            previewImage: previewImage,
            metadata: metadata
        )
    }

    /// Saves a processed 1024px transparent product preview PNG and updates meta.json with sourceURL.
    public func saveProductImage(
        deviceKey: String,
        pngData: Data,
        sourceURL: String?,
        deviceName: String,
        kind: String
    ) throws {
        let dir = deviceDirectory(for: deviceKey)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Save preview.png
        let previewURL = previewFileURL(for: deviceKey)
        try pngData.write(to: previewURL, options: .atomic)

        // Load existing metadata or create fresh entry
        var meta: DeviceModelMetadata
        if let existing = getMetadata(for: deviceKey) {
            meta = existing
            meta.sourceURL = sourceURL
            meta.lastSeenAt = Date()
        } else {
            meta = DeviceModelMetadata(
                deviceKey: deviceKey,
                deviceName: deviceName,
                kind: kind,
                sourceTier: .custom,
                provider: "vision_foreground_cutout",
                sourceURL: sourceURL,
                createdAt: Date(),
                lastSeenAt: Date(),
                fileSizeBytes: Int64(pngData.count),
                polygonCount: nil,
                isPinned: false
            )
        }

        let metaURL = metadataFileURL(for: deviceKey)
        let encoded = try jsonEncoder.encode(meta)
        try encoded.write(to: metaURL, options: .atomic)
    }

    public func touchDevice(deviceKey: String) {
        let dir = deviceDirectory(for: deviceKey)
        guard fileManager.fileExists(atPath: dir.path) else { return }

        // Update modification date of directory for filesystem-level fallback
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: dir.path)

        // Update lastSeenAt in meta.json
        let metaURL = metadataFileURL(for: deviceKey)
        if let data = try? Data(contentsOf: metaURL),
           var meta = try? jsonDecoder.decode(DeviceModelMetadata.self, from: data) {
            meta.lastSeenAt = Date()
            if let updatedData = try? jsonEncoder.encode(meta) {
                try? updatedData.write(to: metaURL, options: .atomic)
            }
        }
    }

    public func calculateTotalCacheSize() -> Int64 {
        guard let subdirs = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.totalFileSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalBytes: Int64 = 0
        for dir in subdirs {
            guard let enumerator = fileManager.enumerator(
                at: dir,
                includingPropertiesForKeys: [.totalFileSizeKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.totalFileSizeKey, .fileSizeKey]) {
                    let size = resourceValues.totalFileSize ?? resourceValues.fileSize ?? 0
                    totalBytes += Int64(size)
                }
            }
        }
        return totalBytes
    }

    /// Enforces the size limit by evicting the least-recently-used models.
    /// Pinned models (`isPinned == true`) are preserved whenever possible.
    public func enforceSizeCap(customLimitMB: Int? = nil) {
        let defaultLimit = (UserDefaults.standard.object(forKey: "deviceModelCacheLimitMB") as? Int) ?? 150
        let limitMB = customLimitMB ?? defaultLimit
        let maxBytes = Int64(limitMB) * 1024 * 1024

        guard let subdirs = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        struct CacheEntry {
            let directoryURL: URL
            let key: String
            let sizeBytes: Int64
            let lastSeen: Date
            let isPinned: Bool
        }

        var entries: [CacheEntry] = []
        var totalBytes: Int64 = 0

        for dir in subdirs {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let key = dir.lastPathComponent
            let metaURL = dir.appendingPathComponent("meta.json")
            var lastSeen = Date.distantPast
            var isPinned = false
            var entrySize: Int64 = 0

            // Try reading meta.json
            if let data = try? Data(contentsOf: metaURL),
               let meta = try? jsonDecoder.decode(DeviceModelMetadata.self, from: data) {
                lastSeen = meta.lastSeenAt
                isPinned = meta.isPinned
                entrySize = meta.fileSizeBytes
            } else if let attrs = try? fileManager.attributesOfItem(atPath: dir.path),
                      let modDate = attrs[.modificationDate] as? Date {
                lastSeen = modDate
            }

            // Calculate actual on-disk size for accuracy
            if let enumerator = fileManager.enumerator(
                at: dir,
                includingPropertiesForKeys: [.totalFileSizeKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) {
                var dirBytes: Int64 = 0
                for case let fileURL as URL in enumerator {
                    if let res = try? fileURL.resourceValues(forKeys: [.totalFileSizeKey, .fileSizeKey]) {
                        dirBytes += Int64(res.totalFileSize ?? res.fileSize ?? 0)
                    }
                }
                if dirBytes > 0 { entrySize = dirBytes }
            }

            totalBytes += entrySize
            entries.append(CacheEntry(
                directoryURL: dir,
                key: key,
                sizeBytes: entrySize,
                lastSeen: lastSeen,
                isPinned: isPinned
            ))
        }

        guard totalBytes > maxBytes else { return }

        // Sort by pinned status (unpinned first) and then by lastSeen ascending (oldest first = LRU)
        entries.sort { a, b in
            if a.isPinned != b.isPinned {
                return !a.isPinned && b.isPinned
            }
            return a.lastSeen < b.lastSeen
        }

        // Evict until within bounds
        for entry in entries {
            if totalBytes <= maxBytes { break }
            do {
                try fileManager.removeItem(at: entry.directoryURL)
                totalBytes -= entry.sizeBytes
            } catch {
                // Continue to next entry on error
            }
        }
    }

    // MARK: - Deletion & Listing

    public func deleteModel(for deviceKey: String) throws {
        let dir = deviceDirectory(for: deviceKey)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }

    public func clearAllCache() throws {
        guard let subdirs = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for dir in subdirs {
            try? fileManager.removeItem(at: dir)
        }
    }

    public func allCachedDevices() -> [DeviceModelMetadata] {
        guard let subdirs = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var list: [DeviceModelMetadata] = []
        for dir in subdirs {
            let metaURL = dir.appendingPathComponent("meta.json")
            if let data = try? Data(contentsOf: metaURL),
               let meta = try? jsonDecoder.decode(DeviceModelMetadata.self, from: data) {
                list.append(meta)
            }
        }
        return list.sorted { $0.lastSeenAt > $1.lastSeenAt }
    }

    // MARK: - Private Helpers

    nonisolated private func createBaseDirectoryIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: baseDirectory.path) {
            try? fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }
}
