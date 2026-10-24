//
//  AndroidThumbnailCache.swift
//  LiquidDynamo
//
//  Size-capped LRU disk & memory cache for Android image and video thumbnails.
//  Pulls small previews rather than entire multi-gigabyte media files,
//  and evicts old entries when exceeding cache capacity (default 200 MB).
//

import AppKit
import Foundation

@MainActor
public final class AndroidThumbnailCache: ObservableObject {
    public static let shared = AndroidThumbnailCache()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let cacheDirectory: URL
    private let maxDiskBytes: Int64 = 200 * 1024 * 1024 // 200 MB default
    private var activeTasks: [String: Task<NSImage?, Never>] = [:]

    private init() {
        memoryCache.countLimit = 300
        let temp = FileManager.default.temporaryDirectory
        self.cacheDirectory = temp.appendingPathComponent("com.liquiddynamo.android.thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        pruneDiskCacheIfNeeded()
    }

    public func cachedImage(for key: String) -> NSImage? {
        if let mem = memoryCache.object(forKey: key as NSString) {
            return mem
        }
        let fileURL = cacheDirectory.appendingPathComponent(Self.sanitizedKey(key))
        if let data = try? Data(contentsOf: fileURL), let img = NSImage(data: data) {
            memoryCache.setObject(img, forKey: key as NSString)
            return img
        }
        return nil
    }

    public func storeImage(_ image: NSImage, for key: String) {
        memoryCache.setObject(image, forKey: key as NSString)
        let dir = self.cacheDirectory
        let safeKey = Self.sanitizedKey(key)
        let maxDisk = self.maxDiskBytes

        Task.detached(priority: .background) {
            let fileURL = dir.appendingPathComponent(safeKey)
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) {
                try? data.write(to: fileURL)
            }
            Self.pruneDiskDirectory(dir, maxDiskBytes: maxDisk)
        }
    }

    public func loadThumbnail(
        for item: ADBFileEntry,
        serial: String,
        client: ADBClient
    ) async -> NSImage? {
        guard item.isImage || item.isVideo else { return nil }
        let key = "\(serial)_\(item.path)_\(item.size)"

        if let existing = cachedImage(for: key) {
            return existing
        }

        if let inFlight = activeTasks[key] {
            return await inFlight.value
        }

        let task = Task<NSImage?, Never> { [weak self] () -> NSImage? in
            defer {
                Task { @MainActor [weak self] in
                    self?.activeTasks.removeValue(forKey: key)
                }
            }

            guard let self = self else { return nil }

            // Pull file to a temporary location to extract thumbnail
            let tempFile = self.cacheDirectory.appendingPathComponent("fetch_\(UUID().uuidString).\(item.fileExtension)")
            defer { try? FileManager.default.removeItem(at: tempFile) }

            do {
                try await client.pullFile(serial: serial, remotePath: item.path, localURL: tempFile, onProgress: nil)
                guard let image = NSImage(contentsOf: tempFile) else { return nil }

                // Downscale to max 128x128 for crisp, low-memory thumbnail display
                let thumb = self.createThumbnail(from: image, targetSize: CGSize(width: 128, height: 128))
                await MainActor.run {
                    self.storeImage(thumb, for: key)
                }
                return thumb
            } catch {
                return nil
            }
        }

        activeTasks[key] = task
        return await task.value
    }

    public func cancelAllPending() {
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
    }

    public func clearAllCache() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func createThumbnail(from original: NSImage, targetSize: CGSize) -> NSImage {
        let originalSize = original.size
        guard originalSize.width > 0 && originalSize.height > 0 else { return original }

        let widthRatio = targetSize.width / originalSize.width
        let heightRatio = targetSize.height / originalSize.height
        let scale = min(widthRatio, heightRatio)

        let newSize = CGSize(width: max(1, originalSize.width * scale), height: max(1, originalSize.height * scale))
        let newImage = NSImage(size: newSize)

        newImage.lockFocus()
        original.draw(in: NSRect(origin: .zero, size: newSize),
                      from: NSRect(origin: .zero, size: originalSize),
                      operation: .copy,
                      fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    nonisolated static func sanitizedKey(_ key: String) -> String {
        key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
    }

    private func pruneDiskCacheIfNeeded() {
        Self.pruneDiskDirectory(cacheDirectory, maxDiskBytes: maxDiskBytes)
    }

    nonisolated static func pruneDiskDirectory(_ dir: URL, maxDiskBytes: Int64) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        var totalSize: Int64 = 0
        var fileStats: [(url: URL, size: Int64, date: Date)] = []

        for file in files {
            guard let vals = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let sz = vals.fileSize,
                  let date = vals.contentModificationDate else { continue }
            let s = Int64(sz)
            totalSize += s
            fileStats.append((url: file, size: s, date: date))
        }

        if totalSize > maxDiskBytes {
            // Sort oldest first
            fileStats.sort { $0.date < $1.date }
            for stat in fileStats {
                try? FileManager.default.removeItem(at: stat.url)
                totalSize -= stat.size
                if totalSize <= Int64(Double(maxDiskBytes) * 0.75) {
                    break
                }
            }
        }
    }
}
