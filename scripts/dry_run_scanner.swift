import AppKit
import CryptoKit
import Foundation

@main
struct DryRunScanner {
    static func main() {
        print("Starting dry-run storage scan on Mac...")

        // Probe Full Disk Access
        let home = FileManager.default.homeDirectoryForCurrentUser
        let probes: [URL] = [
            home.appendingPathComponent("Library/Safari", isDirectory: true),
            home.appendingPathComponent("Library/Containers", isDirectory: true),
            home.appendingPathComponent("Library/Application Support", isDirectory: true)
        ]
        var hasFDA = true
        for url in probes {
            do {
                _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants])
            } catch {
                hasFDA = false
                break
            }
        }
        print("Full Disk Access: \(hasFDA ? "Granted (Deep scan enabled)" : "Not Granted (Limited scan: App Caches & Dev Tools only)")")

        let startTime = Date()
        let fm = FileManager.default

        var itemsByCategory: [StorageCleanupCategory: [StorageCleanupItem]] = [:]
        for cat in StorageCleanupCategory.allCases {
            itemsByCategory[cat] = []
        }
        var scannedPaths = Set<String>()

        // 1. App Caches
        let cachesURL = home.appendingPathComponent("Library/Caches", isDirectory: true)
        if let cacheDirs = try? fm.contentsOfDirectory(at: cachesURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            for dir in cacheDirs {
                let pathKey = dir.standardizedFileURL.path
                guard !scannedPaths.contains(pathKey) else { continue }
                guard StorageSafetyPolicy.isSafeToClean(dir) else { continue }
                let size = folderSize(at: dir)
                if size > 3 * 1024 * 1024 {
                    scannedPaths.insert(pathKey)
                    let mod = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                    let item = StorageCleanupItem(
                        category: .caches,
                        name: cleanDisplayName(for: dir.lastPathComponent),
                        path: dir.path,
                        sizeBytes: size,
                        lastModified: mod,
                        detail: "Application cache data",
                        safetyTier: .safeToClean
                    )
                    itemsByCategory[.caches]?.append(item)
                }
            }
        }

        // 2. Dev Tools
        let devTargets: [(name: String, rel: String, detail: String, tier: SafetyTier)] = [
            ("Xcode DerivedData", "Library/Developer/Xcode/DerivedData", "Xcode build artifacts and module cache", .safeToClean),
            ("Xcode Archives", "Library/Developer/Xcode/Archives", "Built application archives", .checkFirst),
            ("Homebrew Cache", "Library/Caches/Homebrew", "Downloaded formula bottles", .safeToClean),
            ("npm Cache", ".npm/_cacache", "Node package manager cache", .safeToClean),
            ("pnpm Store", "Library/pnpm/store", "Hard-linked package store", .safeToClean),
            ("Yarn Cache", "Library/Caches/Yarn", "Yarn global tarball cache", .safeToClean),
            ("Bun Cache", ".bun/install/cache", "Fast Bun package cache", .safeToClean),
            ("Cargo Registry", ".cargo/registry/cache", "Rust crates.io index cache", .safeToClean),
            ("Go Build Cache", "Library/Caches/go-build", "Compiled Go package cache", .safeToClean),
            ("CoreSimulator Caches", "Library/Developer/CoreSimulator/Caches", "Simulator runtime caches", .safeToClean),
            ("CoreSimulator Devices", "Library/Developer/CoreSimulator/Devices", "Simulated devices container storage", .checkFirst)
        ]
        for target in devTargets {
            let url = home.appendingPathComponent(target.rel)
            if fm.fileExists(atPath: url.path), StorageSafetyPolicy.isSafeToClean(url) {
                let size = folderSize(at: url)
                if size > 5 * 1024 * 1024 {
                    itemsByCategory[.developer]?.append(StorageCleanupItem(
                        category: .developer,
                        name: target.name,
                        path: url.path,
                        sizeBytes: size,
                        detail: target.detail,
                        safetyTier: target.tier
                    ))
                }
            }
        }

        // 3. System Logs
        let logsURL = home.appendingPathComponent("Library/Logs", isDirectory: true)
        if let logEntries = try? fm.contentsOfDirectory(at: logsURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for entry in logEntries {
                guard StorageSafetyPolicy.isSafeToClean(entry) else { continue }
                let size = folderSize(at: entry)
                if size > 500 * 1024 {
                    itemsByCategory[.logs]?.append(StorageCleanupItem(
                        category: .logs,
                        name: entry.lastPathComponent,
                        path: entry.path,
                        sizeBytes: size,
                        detail: "Application activity and diagnostic log files",
                        safetyTier: .safeToClean
                    ))
                }
            }
        }

        // 4. Trash
        let trashURL = home.appendingPathComponent(".Trash", isDirectory: true)
        if fm.fileExists(atPath: trashURL.path) {
            if let entries = try? fm.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: [.fileSizeKey], options: []) {
                for entry in entries {
                    let size = folderSize(at: entry)
                    if size > 500 * 1024 {
                        itemsByCategory[.trash]?.append(StorageCleanupItem(
                            category: .trash,
                            name: entry.lastPathComponent,
                            path: entry.path,
                            sizeBytes: size,
                            detail: "Item already in macOS Trash",
                            safetyTier: .safeToClean
                        ))
                    }
                }
            }
        }

        // 5. Stale Downloads
        let downloadsURL = home.appendingPathComponent("Downloads", isDirectory: true)
        if let dlFiles = try? fm.contentsOfDirectory(at: downloadsURL, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) {
            let installerExtensions: Set<String> = ["dmg", "pkg", "iso", "zip", "tar", "gz"]
            let cutoff = Date().addingTimeInterval(-7 * 86400)
            for file in dlFiles {
                let ext = file.pathExtension.lowercased()
                if installerExtensions.contains(ext) {
                    let size = fileSize(at: file)
                    if size > 25 * 1024 * 1024 {
                        let mod = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                        if mod < cutoff {
                            itemsByCategory[.downloads]?.append(StorageCleanupItem(
                                category: .downloads,
                                name: file.lastPathComponent,
                                path: file.path,
                                sizeBytes: size,
                                lastModified: mod,
                                detail: "Downloaded archive or installer (>7 days old)",
                                safetyTier: .checkFirst
                            ))
                        }
                    }
                }
            }
        }

        // Totals
        var totalReclaimable: Int64 = 0
        for list in itemsByCategory.values {
            totalReclaimable += list.reduce(0) { $0 + $1.sizeBytes }
        }

        var volumeTotal: Int64 = 500 * 1024 * 1024 * 1024
        var volumeFree: Int64 = 150 * 1024 * 1024 * 1024
        let rootURL = URL(fileURLWithPath: "/")
        if let vals = try? rootURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]) {
            if let t = vals.volumeTotalCapacity { volumeTotal = Int64(t) }
            if let f = vals.volumeAvailableCapacity { volumeFree = Int64(f) }
        }
        let volumeUsed = max(0, volumeTotal - volumeFree)

        let result = StorageCleanupResult(
            totalReclaimableBytes: totalReclaimable,
            itemsByCategory: itemsByCategory,
            volumeTotal: volumeTotal,
            volumeUsed: volumeUsed,
            volumeFree: volumeFree
        )

        let elapsed = Date().timeIntervalSince(startTime)

        print("\n=== STORAGE CLEANUP DRY-RUN SCAN REPORT ===")
        print(String(format: "Scan Duration: %.2f seconds", elapsed))
        print("Total Volume Size: \(result.formattedVolumeTotal)")
        print("Total Volume Used: \(result.formattedVolumeUsed) (\(String(format: "%.1f", result.usedPercentage * 100))%)")
        print("Total Volume Free: \(result.formattedVolumeFree) (\(String(format: "%.1f", result.freePercentage * 100))%)")
        print("Total Cleanable:   \(result.formattedTotalReclaimable) (\(String(format: "%.2f", result.reclaimablePercentage * 100))%)")

        print("\n--- CATEGORY BREAKDOWN ---")
        for cat in StorageCleanupCategory.primaryCases {
            let items = result.itemsByCategory[cat] ?? []
            if !items.isEmpty {
                let totalBytes = result.totalBytes(for: cat)
                let formatted = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
                print("• \(cat.rawValue): \(formatted) (\(items.count) item\(items.count == 1 ? "" : "s"))")
                for item in items.prefix(4) {
                    print("   - [\(item.safetyTier.displayName)] \(item.name): \(item.formattedSize)")
                }
                if items.count > 4 {
                    print("   ... and \(items.count - 4) more items")
                }
            }
        }
        print("===========================================\n")
    }

    private static func cleanDisplayName(for raw: String) -> String {
        var clean = raw
        if clean.hasPrefix("com.") {
            let parts = clean.components(separatedBy: ".")
            if parts.count >= 3 {
                clean = parts.dropFirst(2).joined(separator: " ").capitalized
            }
        }
        return clean
    }

    private static func fileSize(at url: URL) -> Int64 {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return folderSize(at: url)
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            return (attrs[.size] as? NSNumber)?.int64Value ?? 0
        }
        return 0
    }

    private static func folderSize(at url: URL) -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]) {
            for case let fileURL as URL in enumerator {
                if let vals = try? fileURL.resourceValues(forKeys: keys), vals.isRegularFile == true {
                    total += Int64(vals.fileSize ?? 0)
                }
            }
        }
        return total
    }
}
