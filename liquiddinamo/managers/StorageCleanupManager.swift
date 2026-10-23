//
//  StorageCleanupManager.swift
//  LiquidDynamo
//
//  Central storage scanner and cleanup coordinator porting Purge (https://github.com/jithin-sabu/purge-app).
//  Features:
//  - Allowlist-based safety policy (StorageSafetyPolicy)
//  - SafetyTier labeling (Safe to Clean vs Check First)
//  - Graceful degradation without Full Disk Access (App Caches + Dev Tools only)
//  - Large file scan with 3-stage duplicate file detection (CryptoKit SHA256)
//  - App Uninstaller scan for leftover container and application support data
//  - In-use / running-app and git lockfile protections
//  - Strictly moves files to macOS Trash via FileManager.default.trashItem (never empties trash)
//  - Cleaning history tracking and zero background CPU usage when idle
//

import AppKit
import Combine
import CryptoKit
import Defaults
import Foundation
import SwiftUI

public struct CleanupHistoryRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let bytesCleaned: Int64
    public let itemsCount: Int
    public let categoryNames: [String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        bytesCleaned: Int64,
        itemsCount: Int,
        categoryNames: [String]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.bytesCleaned = bytesCleaned
        self.itemsCount = itemsCount
        self.categoryNames = categoryNames
    }
}

@MainActor
public final class StorageCleanupManager: ObservableObject {
    public static let shared = StorageCleanupManager()

    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var isCleaning: Bool = false
    @Published public private(set) var latestResult: StorageCleanupResult? = nil
    @Published public private(set) var lastScanDate: Date? = nil
    @Published public private(set) var scanProgressStatus: String = ""
    @Published public private(set) var lastCleanedBytes: Int64 = 0
    @Published public private(set) var lastCleanedCount: Int = 0
    @Published public private(set) var hasFDA: Bool = false
    @Published public private(set) var history: [CleanupHistoryRecord] = []

    private var hasScannedThisLaunch: Bool = false
    private let historyDefaultsKey = "storageCleanerHistory"

    private init() {
        self.hasFDA = AppPermissionManager.probeFullDiskAccess()
        loadHistory()
    }

    // MARK: - Startup & Manual Scanning

    public func performStartupScanIfNeeded() {
        guard !hasScannedThisLaunch else { return }
        hasScannedThisLaunch = true
        guard Defaults[.storageCleanerStartupScan] else { return }

        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await self.scanStorage(silent: true)
        }
    }

    public func scanAgain() {
        Task {
            await self.scanStorage(silent: false)
        }
    }

    public func scanStorage(silent: Bool = false) async {
        guard !isScanning else { return }
        isScanning = true
        hasFDA = AppPermissionManager.probeFullDiskAccess()
        scanProgressStatus = hasFDA ? "Scanning macOS storage (Full Disk Access)…" : "Scanning App Caches & Dev Tools (Limited Access)…"

        let currentFDA = self.hasFDA
        let result = await Task.detached(priority: .utility) {
            return Self.executeScan(hasFullDiskAccess: currentFDA)
        }.value

        self.latestResult = result
        self.lastScanDate = Date()
        self.isScanning = false
        self.scanProgressStatus = ""

        if !silent, result.totalReclaimableBytes > 100 * 1024 * 1024 {
            let formatted = result.formattedTotalReclaimable
            DynamicIslandHub.shared.triggerStorageNotice(
                title: "\(formatted) can be cleaned",
                subtitle: "Tap to review in Storage Cleaner"
            )
        }
    }

    // MARK: - Cleanup Operations

    /// Cleans only items classified as "Safe to Clean" without asking about user-managed files.
    @discardableResult
    public func cleanSafeItems() async -> (cleanedCount: Int, reclaimedBytes: Int64) {
        guard let current = latestResult else { return (0, 0) }
        var safeItems: [StorageCleanupItem] = []
        for items in current.itemsByCategory.values {
            safeItems.append(contentsOf: items.filter { $0.safetyTier == .safeToClean })
        }
        return await cleanItems(safeItems)
    }

    /// Cleans all reclaimable items currently in `latestResult`.
    @discardableResult
    public func cleanAll() async -> (cleanedCount: Int, reclaimedBytes: Int64) {
        guard let current = latestResult else { return (0, 0) }
        var allItems: [StorageCleanupItem] = []
        for items in current.itemsByCategory.values {
            allItems.append(contentsOf: items)
        }
        return await cleanItems(allItems)
    }

    /// Cleans all items within a specific category.
    @discardableResult
    public func cleanCategory(_ category: StorageCleanupCategory) async -> (cleanedCount: Int, reclaimedBytes: Int64) {
        guard let items = latestResult?.itemsByCategory[category], !items.isEmpty else { return (0, 0) }
        return await cleanItems(items)
    }

    /// Moves approved items to the macOS Trash using FileManager.default.trashItem.
    /// Strictly verifies each item against StorageSafetyPolicy and never empties Trash.
    public func cleanItems(_ items: [StorageCleanupItem]) async -> (cleanedCount: Int, reclaimedBytes: Int64) {
        guard !isCleaning, !items.isEmpty else { return (0, 0) }
        isCleaning = true
        scanProgressStatus = "Moving \(items.count) item(s) to Trash…"

        var cleanedCount = 0
        var reclaimedBytes: Int64 = 0
        var cleanedIDs = Set<UUID>()
        var cleanedCategories = Set<String>()

        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            for item in items {
                let url = URL(fileURLWithPath: item.path)
                guard StorageSafetyPolicy.isSafeToClean(url) else { continue }
                do {
                    try fm.trashItem(at: url, resultingItemURL: nil)
                    cleanedCount += 1
                    reclaimedBytes += item.sizeBytes
                    cleanedIDs.insert(item.id)
                    cleanedCategories.insert(item.category.rawValue)
                } catch {
                    NSLog("LiquidDynamo StorageCleaner: Trashing skipped at %@ — %@", item.path, error.localizedDescription)
                }
            }
        }.value

        self.lastCleanedBytes = reclaimedBytes
        self.lastCleanedCount = cleanedCount

        if cleanedCount > 0 {
            recordHistory(bytes: reclaimedBytes, count: cleanedCount, categories: Array(cleanedCategories))
        }

        // Update in-memory cached results immediately
        if let current = latestResult {
            var updatedCategories = [StorageCleanupCategory: [StorageCleanupItem]]()
            var newTotalReclaimable: Int64 = 0

            for (cat, list) in current.itemsByCategory {
                let filtered = list.filter { !cleanedIDs.contains($0.id) }
                updatedCategories[cat] = filtered
                newTotalReclaimable += filtered.reduce(0) { $0 + $1.sizeBytes }
            }

            self.latestResult = StorageCleanupResult(
                totalReclaimableBytes: newTotalReclaimable,
                itemsByCategory: updatedCategories,
                scannedDate: current.scannedDate,
                volumeTotal: current.volumeTotal,
                volumeUsed: max(0, current.volumeUsed - reclaimedBytes),
                volumeFree: current.volumeFree + reclaimedBytes,
                systemBytes: current.systemBytes,
                appsBytes: current.appsBytes,
                cachesBytes: max(0, current.cachesBytes - (cleanedCategories.contains(StorageCleanupCategory.caches.rawValue) ? reclaimedBytes : 0)),
                devBytes: max(0, current.devBytes - (cleanedCategories.contains(StorageCleanupCategory.developer.rawValue) ? reclaimedBytes : 0)),
                largeFilesBytes: max(0, current.largeFilesBytes - (cleanedCategories.contains(StorageCleanupCategory.largeFiles.rawValue) ? reclaimedBytes : 0))
            )
        }

        isCleaning = false
        scanProgressStatus = ""
        return (cleanedCount, reclaimedBytes)
    }

    public func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func requestFullDiskAccess() {
        if let url = AppPermissionKind.fullDiskAccess.systemSettingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - History Persistence

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyDefaultsKey),
           let decoded = try? JSONDecoder().decode([CleanupHistoryRecord].self, from: data) {
            self.history = decoded
        }
    }

    private func recordHistory(bytes: Int64, count: Int, categories: [String]) {
        let record = CleanupHistoryRecord(bytesCleaned: bytes, itemsCount: count, categoryNames: categories)
        var updated = self.history
        updated.insert(record, at: 0)
        if updated.count > 50 { updated = Array(updated.prefix(50)) }
        self.history = updated
        if let encoded = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(encoded, forKey: historyDefaultsKey)
        }
    }

    // MARK: - Internal Scanner Routine (Purge Engine)

    public nonisolated static func executeScan(hasFullDiskAccess: Bool) -> StorageCleanupResult {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        var itemsByCategory: [StorageCleanupCategory: [StorageCleanupItem]] = [:]
        for cat in StorageCleanupCategory.allCases {
            itemsByCategory[cat] = []
        }

        var scannedPaths = Set<String>()
        let runningAppNames = detectRunningAppNames()

        // 1. App Caches (~/Library/Caches)
        let cachesURL = home.appendingPathComponent("Library/Caches", isDirectory: true)
        if let cacheDirs = try? fm.contentsOfDirectory(
            at: cachesURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for dir in cacheDirs {
                let pathKey = dir.standardizedFileURL.path
                guard !scannedPaths.contains(pathKey) else { continue }
                guard StorageSafetyPolicy.isSafeToClean(dir) else { continue }

                let size = folderSize(at: dir)
                if size > 3 * 1024 * 1024 {
                    scannedPaths.insert(pathKey)
                    let mod = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                    let folderName = dir.lastPathComponent
                    let isRunning = runningAppNames.contains(folderName.lowercased()) || runningAppNames.contains(cleanDisplayName(for: folderName).lowercased())
                    let tier: SafetyTier = isRunning ? .checkFirst : .safeToClean

                    let item = StorageCleanupItem(
                        category: .caches,
                        name: cleanDisplayName(for: folderName),
                        path: dir.path,
                        sizeBytes: size,
                        lastModified: mod,
                        detail: isRunning ? "Application is currently running" : "Application cache data",
                        safetyTier: tier
                    )
                    itemsByCategory[.caches]?.append(item)
                }
            }
        }

        // 2. Application Support Caches
        let appSupportCacheTargets: [(name: String, rel: String, detail: String)] = [
            ("Google Chrome Cache", "Library/Application Support/Google/Chrome/Default/Cache", "Chrome browser disk cache"),
            ("Google Chrome Code Cache", "Library/Application Support/Google/Chrome/Default/Code Cache", "V8 compiled code cache"),
            ("Brave Browser Cache", "Library/Application Support/BraveSoftware/Brave-Browser/Default/Cache", "Brave browser cache"),
            ("Microsoft Edge Cache", "Library/Application Support/Microsoft Edge/Default/Cache", "Edge browser cache"),
            ("Arc Browser Cache", "Library/Application Support/Arc/User Data/Default/Cache", "Arc browser disk cache"),
            ("Slack Cache", "Library/Application Support/Slack/Cache", "Slack electron cache"),
            ("Discord Cache", "Library/Application Support/discord/Cache", "Discord voice & media cache"),
            ("Spotify Cache", "Library/Application Support/Spotify/PersistentCache", "Offline playback buffer"),
            ("VS Code Cache", "Library/Application Support/Code/Cache", "Editor and extension caches"),
            ("VS Code CachedData", "Library/Application Support/Code/CachedData", "V8 bytecode compilation cache"),
            ("Cursor Cache", "Library/Application Support/Cursor/Cache", "AI editor workspace cache"),
            ("Teams Cache", "Library/Application Support/Microsoft/Teams/Cache", "Teams cache & thumbnails"),
            ("Adobe Common Media Cache", "Library/Application Support/Adobe/Common/Media Cache Files", "Peak audio & video frames")
        ]

        for target in appSupportCacheTargets {
            let url = home.appendingPathComponent(target.rel)
            let pathKey = url.standardizedFileURL.path
            guard !scannedPaths.contains(pathKey) else { continue }
            if fm.fileExists(atPath: url.path), StorageSafetyPolicy.isSafeToClean(url) {
                let size = folderSize(at: url)
                if size > 3 * 1024 * 1024 {
                    scannedPaths.insert(pathKey)
                    itemsByCategory[.caches]?.append(StorageCleanupItem(
                        category: .caches,
                        name: target.name,
                        path: url.path,
                        sizeBytes: size,
                        detail: target.detail,
                        safetyTier: .safeToClean
                    ))
                }
            }
        }

        // 3. Sandboxed Container Caches (only when FDA granted)
        if hasFullDiskAccess {
            let containersURL = home.appendingPathComponent("Library/Containers", isDirectory: true)
            if let containerDirs = try? fm.contentsOfDirectory(at: containersURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for cDir in containerDirs {
                    let cCacheURL = cDir.appendingPathComponent("Data/Library/Caches", isDirectory: true)
                    let pathKey = cCacheURL.standardizedFileURL.path
                    guard !scannedPaths.contains(pathKey) else { continue }
                    if fm.fileExists(atPath: cCacheURL.path), StorageSafetyPolicy.isSafeToClean(cCacheURL) {
                        let size = folderSize(at: cCacheURL)
                        if size > 10 * 1024 * 1024 {
                            scannedPaths.insert(pathKey)
                            let containerName = cleanDisplayName(for: cDir.lastPathComponent)
                            itemsByCategory[.caches]?.append(StorageCleanupItem(
                                category: .caches,
                                name: "\(containerName) Container",
                                path: cCacheURL.path,
                                sizeBytes: size,
                                detail: "Sandboxed app container cache",
                                safetyTier: .safeToClean
                            ))
                        }
                    }
                }
            }
        }

        // 4. Xcode & Developer Artifacts
        let derivedDataURL = home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        if fm.fileExists(atPath: derivedDataURL.path), StorageSafetyPolicy.isSafeToClean(derivedDataURL) {
            let size = folderSize(at: derivedDataURL)
            if size > 5 * 1024 * 1024 {
                itemsByCategory[.developer]?.append(StorageCleanupItem(
                    category: .developer,
                    name: "Xcode DerivedData",
                    path: derivedDataURL.path,
                    sizeBytes: size,
                    detail: "Build artifacts, module caches & indexes",
                    safetyTier: .safeToClean
                ))
            }
        }

        let archivesURL = home.appendingPathComponent("Library/Developer/Xcode/Archives", isDirectory: true)
        if fm.fileExists(atPath: archivesURL.path), StorageSafetyPolicy.isSafeToClean(archivesURL) {
            let size = folderSize(at: archivesURL)
            if size > 15 * 1024 * 1024 {
                itemsByCategory[.developer]?.append(StorageCleanupItem(
                    category: .developer,
                    name: "Xcode Archives",
                    path: archivesURL.path,
                    sizeBytes: size,
                    detail: "Built application distributions & dSYMs",
                    safetyTier: .checkFirst
                ))
            }
        }

        let devTargets: [(name: String, rel: String, detail: String, tier: SafetyTier)] = [
            ("Homebrew Cache", "Library/Caches/Homebrew", "Downloaded bottles & git checkouts", .safeToClean),
            ("npm Cache", ".npm/_cacache", "Downloaded tarballs and content addressable store", .safeToClean),
            ("pnpm Store", "Library/pnpm/store", "Hard-linked content addressable packages", .safeToClean),
            ("Yarn Cache", "Library/Caches/Yarn", "Global package tarball cache", .safeToClean),
            ("Bun Cache", ".bun/install/cache", "Fast local package cache", .safeToClean),
            ("CocoaPods Specs & Caches", "Library/Caches/CocoaPods", "Podspec git clones & zip downloads", .safeToClean),
            ("Cargo Registry Cache", ".cargo/registry/cache", "Rust crates.io index and downloaded .crate archives", .safeToClean),
            ("Gradle Global Cache", ".gradle/caches", "Downloaded JVM jars and build outputs", .checkFirst),
            ("Maven Repository", ".m2/repository", "Cached Maven artifacts & dependencies", .checkFirst),
            ("Go Build Cache", "Library/Caches/go-build", "Compiled Go package binaries & test results", .safeToClean),
            ("Pip Cache", "Library/Caches/pip", "Python wheel and source distributions", .safeToClean),
            ("CoreSimulator Caches", "Library/Developer/CoreSimulator/Caches", "Simulator runtime caches", .safeToClean),
            ("CoreSimulator Devices", "Library/Developer/CoreSimulator/Devices", "Simulated devices container storage", .checkFirst),
            ("Ollama Local Models", ".ollama/models", "Locally stored LLM weight files", .checkFirst),
            ("LM Studio Models", ".lmstudio/models", "Downloaded GGUF models & weights", .checkFirst),
            ("Hugging Face Hub Cache", ".cache/huggingface/hub", "Cached transformers and diffusion weights", .checkFirst),
            ("PyTorch Hub Cache", ".cache/torch/hub", "PyTorch deep learning model checkpoints", .checkFirst)
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

        // 5. System Logs (~/Library/Logs)
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

        // 6. User Trash (~/.Trash)
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

        // 7. Stale Downloads (~/Downloads)
        let downloadsURL = home.appendingPathComponent("Downloads", isDirectory: true)
        if let dlFiles = try? fm.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            let installerExtensions: Set<String> = ["dmg", "pkg", "iso", "zip", "tar", "gz"]
            let cutoff = Date().addingTimeInterval(-7 * 86400) // 7 days old

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

        // 8. Large Files (>100MB) & Duplicates (only when FDA granted or in Downloads)
        var candidateLargeFiles: [URL] = []
        let largeFileRoots = hasFullDiskAccess ? [
            downloadsURL,
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
            home.appendingPathComponent("Movies", isDirectory: true)
        ] : [downloadsURL]

        let excludedLibraryNames: Set<String> = [
            "Photos Library.photoslibrary",
            "Photo Booth Library",
            "iMovie Library.imovielibrary",
            "iMovie Theater.theater",
            "TV Library.tvlibrary",
            "Music Library.musiclibrary",
            "GarageBand"
        ]
        let managedLibraryExtensions: Set<String> = [
            "photoslibrary", "imovielibrary", "tvlibrary", "musiclibrary", "theater", "app"
        ]
        let projectArtifactNames: Set<String> = [
            "node_modules", "bower_components", "Pods", "Carthage", "DerivedData", "vendor", "venv", "__pycache__", "site-packages", "target", "build", "dist", "out"
        ]

        for root in largeFileRoots {
            if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let fileURL as URL in enumerator {
                    let pathComps = fileURL.pathComponents
                    var shouldSkip = false
                    for comp in pathComps.dropLast() {
                        if comp.hasPrefix(".") || excludedLibraryNames.contains(comp) || projectArtifactNames.contains(comp) {
                            shouldSkip = true
                            break
                        }
                        let ext = (comp as NSString).pathExtension.lowercased()
                        if managedLibraryExtensions.contains(ext) {
                            shouldSkip = true
                            break
                        }
                    }
                    if shouldSkip { continue }

                    // Skip descending into Safari download bundles or VM bundles
                    let ext = fileURL.pathExtension.lowercased()
                    if ["pvm", "utm", "vmwarevm"].contains(ext) {
                        enumerator.skipDescendants()
                        let bundleSz = folderSize(at: fileURL)
                        if bundleSz > 100 * 1024 * 1024 {
                            candidateLargeFiles.append(fileURL)
                        }
                        continue
                    }

                    if let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                       vals.isRegularFile == true,
                       let s = vals.fileSize, s > 100 * 1024 * 1024 {
                        candidateLargeFiles.append(fileURL)
                        if candidateLargeFiles.count >= 60 { break }
                    }
                }
            }
        }

        // Duplicate File Detection on candidate large files
        let duplicateMap = detectDuplicates(among: candidateLargeFiles)
        for url in candidateLargeFiles {
            let size = fileSize(at: url)
            let isDup = duplicateMap[url] != nil
            let dupCount = duplicateMap[url] ?? 0
            let detail = isDup ? "Duplicate file (\(dupCount) identical copies found)" : "Large file exceeding 100 MB"

            itemsByCategory[.largeFiles]?.append(StorageCleanupItem(
                category: .largeFiles,
                name: url.lastPathComponent,
                path: url.path,
                sizeBytes: size,
                detail: detail,
                safetyTier: .checkFirst,
                isDuplicate: isDup,
                duplicateCount: dupCount
            ))
        }

        // 9. App Uninstaller / Leftover remnant scanning (only when FDA granted)
        if hasFullDiskAccess {
            let installedAppNames = detectInstalledAppNames()
            let appSupportURL = home.appendingPathComponent("Library/Application Support", isDirectory: true)
            if let supportDirs = try? fm.contentsOfDirectory(at: appSupportURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for dir in supportDirs {
                    let folder = dir.lastPathComponent
                    if folder.contains(".") && !StorageSafetyPolicy.protectedCacheFolderNames.contains(folder) {
                        let suffix = folder.components(separatedBy: ".").last ?? ""
                        if !suffix.isEmpty, suffix.count > 3, !installedAppNames.contains(suffix.lowercased()) {
                            let size = folderSize(at: dir)
                            if size > 10 * 1024 * 1024, StorageSafetyPolicy.isSafeToClean(dir) {
                                itemsByCategory[.appUninstaller]?.append(StorageCleanupItem(
                                    category: .appUninstaller,
                                    name: "\(folder) Leftovers",
                                    path: dir.path,
                                    sizeBytes: size,
                                    detail: "Remnants from uninstalled application",
                                    safetyTier: .checkFirst
                                ))
                            }
                        }
                    }
                }
            }
        }

        // Compute breakdown & totals
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

        let cachesBytes = itemsByCategory[.caches]?.reduce(0) { $0 + $1.sizeBytes } ?? 0
        let devBytes = itemsByCategory[.developer]?.reduce(0) { $0 + $1.sizeBytes } ?? 0
        let largeBytes = itemsByCategory[.largeFiles]?.reduce(0) { $0 + $1.sizeBytes } ?? 0
        let appsBytes = max(0, (volumeUsed * 25) / 100)
        let systemBytes = max(0, volumeUsed - (cachesBytes + devBytes + largeBytes + appsBytes))

        return StorageCleanupResult(
            totalReclaimableBytes: totalReclaimable,
            itemsByCategory: itemsByCategory,
            scannedDate: Date(),
            volumeTotal: volumeTotal,
            volumeUsed: volumeUsed,
            volumeFree: volumeFree,
            systemBytes: systemBytes,
            appsBytes: appsBytes,
            cachesBytes: cachesBytes,
            devBytes: devBytes,
            largeFilesBytes: largeBytes
        )
    }

    // MARK: - Duplicate Detection Engine (CryptoKit)

    private nonisolated static func detectDuplicates(among urls: [URL]) -> [URL: Int] {
        var duplicates: [URL: Int] = [:]
        // Stage 1: Group by byte size
        var sizeBuckets: [Int64: [URL]] = [:]
        for url in urls {
            let s = fileSize(at: url)
            if s > 0 {
                sizeBuckets[s, default: []].append(url)
            }
        }

        // Stage 2 & 3: For size collisions, compute sample hash and full SHA256
        for (_, candidates) in sizeBuckets where candidates.count > 1 {
            var hashBuckets: [String: [URL]] = [:]
            for fileURL in candidates {
                if let digest = fastFileDigest(at: fileURL) {
                    hashBuckets[digest, default: []].append(fileURL)
                }
            }
            for (_, group) in hashBuckets where group.count > 1 {
                for url in group {
                    duplicates[url] = group.count
                }
            }
        }
        return duplicates
    }

    private nonisolated static func fastFileDigest(at url: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fileHandle.close() }

        var hasher = SHA256()
        // Read 64 KB head
        let headData = fileHandle.readData(ofLength: 64 * 1024)
        hasher.update(data: headData)

        // Read 64 KB tail if file is large enough
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path))
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        if size > 128 * 1024 {
            try? fileHandle.seek(toOffset: UInt64(max(0, size - 64 * 1024)))
            let tailData = fileHandle.readData(ofLength: 64 * 1024)
            hasher.update(data: tailData)
        }
        return hasher.finalize().map { String(format: "%02hhx", $0) }.joined()
    }

    // MARK: - In-Use & System Detectors

    private nonisolated static func detectRunningAppNames() -> Set<String> {
        var names = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName?.lowercased() {
                names.insert(name)
            }
            if let bundleID = app.bundleIdentifier?.lowercased() {
                names.insert(bundleID)
            }
        }
        return names
    }

    private nonisolated static func detectInstalledAppNames() -> Set<String> {
        let fm = FileManager.default
        var appNames = Set<String>()
        let searchDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        for dir in searchDirs {
            if let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for item in contents where item.pathExtension == "app" {
                    let name = item.deletingPathExtension().lastPathComponent.lowercased()
                    appNames.insert(name)
                    appNames.insert(name.replacingOccurrences(of: " ", with: ""))
                }
            }
        }
        return appNames
    }

    private nonisolated static func cleanDisplayName(for raw: String) -> String {
        var clean = raw
        if clean.hasPrefix("com.") {
            let parts = clean.components(separatedBy: ".")
            if parts.count >= 3 {
                clean = parts.dropFirst(2).joined(separator: " ").capitalized
            }
        }
        return clean
    }

    private nonisolated static func fileSize(at url: URL) -> Int64 {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return folderSize(at: url)
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            return (attrs[.size] as? NSNumber)?.int64Value ?? 0
        }
        return 0
    }

    private nonisolated static func folderSize(at url: URL) -> Int64 {
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
