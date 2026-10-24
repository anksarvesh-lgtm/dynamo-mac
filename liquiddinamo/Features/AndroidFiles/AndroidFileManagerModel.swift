//
//  AndroidFileManagerModel.swift
//  LiquidDynamo
//
//  Data models and state manager for the in-app Android File Manager.
//  Handles asynchronous folder loading, sorting, search, selection,
//  file transfer queues, and system integration (Quick Look & default app launches).
//

import AppKit
import Foundation
import SwiftUI

// MARK: - Sort Options

public enum AndroidSortField: String, CaseIterable, Identifiable, Sendable {
    case name = "Name"
    case size = "Size"
    case date = "Date"
    case kind = "Kind"

    public var id: String { rawValue }
}

// MARK: - Transfer Item

public struct AndroidFileTransfer: Identifiable, Sendable {
    public enum Status: String, Sendable {
        case pending = "Queued"
        case active = "Transferring"
        case completed = "Finished"
        case failed = "Failed"
        case cancelled = "Cancelled"
    }

    public let id: UUID
    public let filename: String
    public let remotePath: String
    public let localURL: URL
    public let isUpload: Bool
    public var bytesTransferred: Int64
    public var totalBytes: Int64
    public var percentage: Double
    public var speedBytesPerSec: Double
    public var status: Status
    public var errorMessage: String?
    public let dateStarted: Date

    public init(
        id: UUID = UUID(),
        filename: String,
        remotePath: String,
        localURL: URL,
        isUpload: Bool,
        bytesTransferred: Int64 = 0,
        totalBytes: Int64 = 0,
        percentage: Double = 0.0,
        speedBytesPerSec: Double = 0.0,
        status: Status = .pending,
        errorMessage: String? = nil,
        dateStarted: Date = Date()
    ) {
        self.id = id
        self.filename = filename
        self.remotePath = remotePath
        self.localURL = localURL
        self.isUpload = isUpload
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.percentage = percentage
        self.speedBytesPerSec = speedBytesPerSec
        self.status = status
        self.errorMessage = errorMessage
        self.dateStarted = dateStarted
    }
}

// MARK: - Quick Navigation Locations

public struct AndroidQuickLocation: Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let iconName: String
    public let tintColor: Color

    public static let standardLocations: [AndroidQuickLocation] = [
        AndroidQuickLocation(name: "Internal Storage", path: "/sdcard", iconName: "internaldrive.fill", tintColor: .green),
        AndroidQuickLocation(name: "Camera (DCIM)", path: "/sdcard/DCIM", iconName: "camera.fill", tintColor: .cyan),
        AndroidQuickLocation(name: "Pictures", path: "/sdcard/Pictures", iconName: "photo.on.rectangle.angled", tintColor: .indigo),
        AndroidQuickLocation(name: "Downloads", path: "/sdcard/Download", iconName: "arrow.down.circle.fill", tintColor: .blue),
        AndroidQuickLocation(name: "Documents", path: "/sdcard/Documents", iconName: "folder.fill", tintColor: .orange),
        AndroidQuickLocation(name: "Movies", path: "/sdcard/Movies", iconName: "film.fill", tintColor: .purple),
        AndroidQuickLocation(name: "Music", path: "/sdcard/Music", iconName: "music.note", tintColor: .pink),
        AndroidQuickLocation(name: "WhatsApp Media", path: "/sdcard/Android/media/com.whatsapp/WhatsApp/Media", iconName: "message.fill", tintColor: .mint)
    ]
}

// MARK: - View Model

@MainActor
public final class AndroidFileManagerViewModel: ObservableObject {
    public let deviceSerial: String
    public let deviceName: String
    public let deviceModel: String
    public let client: ADBClient

    // Navigation & State
    @Published public private(set) var currentPath: String = "/sdcard"
    @Published public private(set) var currentEntries: [ADBFileEntry] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public var searchQuery: String = ""
    @Published public var isGridView: Bool = false
    @Published public var sortField: AndroidSortField = .name
    @Published public var sortAscending: Bool = true
    @Published public var showHiddenFiles: Bool = false
    @Published public var selectedPaths: Set<String> = []

    // Storage info
    @Published public private(set) var totalStorageBytes: Int64 = 0
    @Published public private(set) var freeStorageBytes: Int64 = 0

    // Alerts & Notifications
    @Published public var errorMessage: String? = nil
    @Published public var scopedStorageRestricted: Bool = false
    @Published public var isShowingNewFolderSheet: Bool = false
    @Published public var newFolderName: String = ""

    // Transfer Queue
    @Published public private(set) var transferQueue: [AndroidFileTransfer] = []
    @Published public var isTransferDrawerExpanded: Bool = false

    private var navigationHistory: [String] = ["/sdcard"]
    private var historyIndex: Int = 0
    private var activeTransferTasks: [UUID: Task<Void, Never>] = [:]

    public init(
        deviceSerial: String,
        deviceName: String,
        deviceModel: String = "",
        client: ADBClient? = nil
    ) {
        self.deviceSerial = deviceSerial
        self.deviceName = deviceName
        self.deviceModel = deviceModel
        self.client = client ?? LiveADBClient.shared
    }

    // MARK: - Navigation

    public var canGoBack: Bool { historyIndex > 0 }
    public var canGoForward: Bool { historyIndex < navigationHistory.count - 1 }
    public var canGoUp: Bool { currentPath != "/" && currentPath != "/sdcard" }

    public func navigate(to path: String) {
        let norm = ADBShellSecurity.normalizeRemotePath(path)
        guard norm != currentPath else { return }

        if historyIndex < navigationHistory.count - 1 {
            navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
        }
        navigationHistory.append(norm)
        historyIndex = navigationHistory.count - 1

        loadDirectory(path: norm)
    }

    public func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        loadDirectory(path: navigationHistory[historyIndex])
    }

    public func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        loadDirectory(path: navigationHistory[historyIndex])
    }

    public func goUp() {
        guard canGoUp else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        navigate(to: parent.isEmpty ? "/" : parent)
    }

    public func refresh() {
        loadDirectory(path: currentPath)
        updateStorageInfo()
    }

    // MARK: - Breadcrumb Components

    public var breadcrumbs: [(title: String, path: String)] {
        let clean = ADBShellSecurity.normalizeRemotePath(currentPath)
        if clean == "/" { return [("Root", "/")] }

        var crumbs: [(title: String, path: String)] = []
        var builtPath = ""
        let components = clean.split(separator: "/")

        for (idx, comp) in components.enumerated() {
            builtPath += "/" + comp
            let displayTitle: String
            if idx == 0 && comp == "sdcard" {
                displayTitle = "Internal Storage"
            } else if idx == 2 && comp == "0" && builtPath.hasPrefix("/storage/emulated/0") {
                displayTitle = "Internal Storage"
            } else {
                displayTitle = String(comp)
            }
            crumbs.append((title: displayTitle, path: builtPath))
        }
        return crumbs
    }

    // MARK: - Filtered & Sorted Display Items

    public var displayEntries: [ADBFileEntry] {
        var items = currentEntries

        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchQuery.lowercased()
            items = items.filter { $0.name.lowercased().contains(q) }
        }

        items.sort { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            switch sortField {
            case .name:
                let comp = a.name.localizedStandardCompare(b.name)
                return sortAscending ? comp == .orderedAscending : comp == .orderedDescending
            case .size:
                return sortAscending ? a.size < b.size : a.size > b.size
            case .date:
                let d1 = a.modificationDate ?? Date.distantPast
                let d2 = b.modificationDate ?? Date.distantPast
                return sortAscending ? d1 < d2 : d1 > d2
            case .kind:
                let comp = a.fileExtension.localizedCaseInsensitiveCompare(b.fileExtension)
                return sortAscending ? comp == .orderedAscending : comp == .orderedDescending
            }
        }

        return items
    }

    // MARK: - Loading Contents

    public func loadDirectory(path: String) {
        let target = ADBShellSecurity.normalizeRemotePath(path)
        self.currentPath = target
        self.selectedPaths.removeAll()
        self.scopedStorageRestricted = ADBShellSecurity.isScopedStorageRestricted(path: target)
        self.isLoading = true
        self.errorMessage = nil

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let items = try await self.client.listDirectory(serial: self.deviceSerial, path: target, showHidden: self.showHiddenFiles)
                await MainActor.run {
                    self.currentEntries = items
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.currentEntries = []
                }
            }
        }
    }

    public func updateStorageInfo() {
        Task { [weak self] in
            guard let self = self else { return }
            let info = try? await self.client.getStorageInfo(serial: self.deviceSerial, path: self.currentPath)
            if let (tot, fr) = info, tot > 0 {
                await MainActor.run {
                    self.totalStorageBytes = tot
                    self.freeStorageBytes = fr
                }
            }
        }
    }

    // MARK: - Item Interactions & Quick Look

    public func openEntry(_ item: ADBFileEntry) {
        if item.isDirectory {
            navigate(to: item.path)
        } else {
            // Pull to temporary preview cache and open with macOS default handler
            previewFile(item)
        }
    }

    public func previewFile(_ item: ADBFileEntry) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("com.liquiddynamo.previewCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let localURL = tempDir.appendingPathComponent(item.name)

        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.client.pullFile(serial: self.deviceSerial, remotePath: item.path, localURL: localURL, onProgress: nil)
                await MainActor.run {
                    NSWorkspace.shared.open(localURL)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to preview file: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Operations: Create, Delete, Rename

    public func createFolder(named name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let fullPath = currentPath == "/" ? "/\(clean)" : "\(currentPath)/\(clean)"

        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.client.makeDirectory(serial: self.deviceSerial, path: fullPath)
                await MainActor.run {
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to create folder: \(error.localizedDescription)"
                }
            }
        }
    }

    public func deleteSelected() {
        guard !selectedPaths.isEmpty else { return }
        let targets = Array(selectedPaths)

        let alert = NSAlert()
        alert.messageText = "Delete \(targets.count) item(s)?"
        alert.informativeText = "Are you sure you want to permanently delete these items from \(deviceName)? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { [weak self] in
            guard let self = self else { return }
            for p in targets {
                try? await self.client.delete(serial: self.deviceSerial, path: p)
            }
            await MainActor.run {
                self.selectedPaths.removeAll()
                self.refresh()
            }
        }
    }

    public func renameItem(_ item: ADBFileEntry, to newName: String) {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty && clean != item.name else { return }
        let parent = (item.path as NSString).deletingLastPathComponent
        let target = parent == "/" ? "/\(clean)" : "\(parent)/\(clean)"

        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await self.client.rename(serial: self.deviceSerial, oldPath: item.path, newPath: target)
                await MainActor.run {
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Rename failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - File Transfers (Upload / Download)

    public func downloadSelectedItems() {
        guard !selectedPaths.isEmpty else { return }
        let items = currentEntries.filter { selectedPaths.contains($0.path) }

        // Default download location: ~/Downloads/<deviceName>
        let downloadsFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let deviceFolder = downloadsFolder.appendingPathComponent(deviceName.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
        try? FileManager.default.createDirectory(at: deviceFolder, withIntermediateDirectories: true)

        for item in items {
            let destURL = deviceFolder.appendingPathComponent(item.name)
            queueDownload(item: item, destinationURL: destURL)
        }
        self.isTransferDrawerExpanded = true
    }

    public func promptUploadFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload to Android"

        if panel.runModal() == .OK {
            uploadFiles(urls: panel.urls, targetRemoteDir: currentPath)
        }
    }

    public func uploadFiles(urls: [URL], targetRemoteDir: String) {
        for url in urls {
            let destRemotePath = targetRemoteDir == "/" ? "/\(url.lastPathComponent)" : "\(targetRemoteDir)/\(url.lastPathComponent)"
            queueUpload(localURL: url, remotePath: destRemotePath)
        }
        self.isTransferDrawerExpanded = true
    }

    private func queueDownload(item: ADBFileEntry, destinationURL: URL) {
        let transferId = UUID()
        var transfer = AndroidFileTransfer(
            id: transferId,
            filename: item.name,
            remotePath: item.path,
            localURL: destinationURL,
            isUpload: false,
            totalBytes: item.size,
            status: .pending
        )
        transferQueue.append(transfer)

        let task = Task { [weak self] in
            guard let self = self else { return }
            await MainActor.run {
                if let idx = self.transferQueue.firstIndex(where: { $0.id == transferId }) {
                    self.transferQueue[idx].status = .active
                }
            }

            do {
                try await self.client.pullFile(
                    serial: self.deviceSerial,
                    remotePath: item.path,
                    localURL: destinationURL
                ) { [weak self] prog in
                    Task { @MainActor [weak self] in
                        guard let self = self,
                              let idx = self.transferQueue.firstIndex(where: { $0.id == transferId }) else { return }
                        self.transferQueue[idx].bytesTransferred = prog.bytesTransferred
                        self.transferQueue[idx].totalBytes = prog.totalBytes
                        self.transferQueue[idx].percentage = prog.percentage
                        self.transferQueue[idx].speedBytesPerSec = prog.speedBytesPerSecond
                    }
                }

                await MainActor.run {
                    if let idx = self.transferQueue.firstIndex(where: { $0.id == transferId }) {
                        self.transferQueue[idx].status = .completed
                        self.transferQueue[idx].percentage = 1.0
                    }
                }
            } catch {
                await MainActor.run {
                    if let idx = self.transferQueue.firstIndex(where: { $0.id == transferId }) {
                        self.transferQueue[idx].status = .failed
                        self.transferQueue[idx].errorMessage = error.localizedDescription
                    }
                }
            }
        }

        activeTransferTasks[transferId] = task
    }

    private func queueUpload(localURL: URL, remotePath: String) {
        let transferId = UUID()
        let attrs = try? FileManager.default.attributesOfItem(atPath: localURL.path)
        let fSize = (attrs?[.size] as? Int64) ?? 0

        var transfer = AndroidFileTransfer(
            id: transferId,
            filename: localURL.lastPathComponent,
            remotePath: remotePath,
            localURL: localURL,
            isUpload: true,
            totalBytes: fSize,
            status: .pending
        )
        transferQueue.append(transfer)

        let task = Task { [weak self] in
            guard let self = self else { return }
            await MainActor.run {
                if let idx = self.transferQueue.firstIndex(where: { $0.id == transferId }) {
                    self.transferQueue[idx].status = .active
                }
            }

            do {
                try await self.client.pushFile(
                    serial: self.deviceSerial,
                    localURL: localURL,
                    remotePath: remotePath,
                    conflictPolicy: .keepBoth
                ) { [weak self] prog in
                    Task { @MainActor [weak self] in
                        guard let self = self,
                              let idx = self.transferQueue.firstIndex(where: { $0.id == transferId }) else { return }
                        self.transferQueue[idx].bytesTransferred = prog.bytesTransferred
                        self.transferQueue[idx].totalBytes = prog.totalBytes
                        self.transferQueue[idx].percentage = prog.percentage
                        self.transferQueue[idx].speedBytesPerSec = prog.speedBytesPerSecond
                    }
                }

                await MainActor.run {
                    if let idx = self.transferQueue.firstIndex(where: { $0.id == transferId }) {
                        self.transferQueue[idx].status = .completed
                        self.transferQueue[idx].percentage = 1.0
                    }
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    if let idx = self.transferQueue.firstIndex(where: { $0.id == transferId }) {
                        self.transferQueue[idx].status = .failed
                        self.transferQueue[idx].errorMessage = error.localizedDescription
                    }
                }
            }
        }

        activeTransferTasks[transferId] = task
    }

    public func cancelTransfer(_ id: UUID) {
        activeTransferTasks[id]?.cancel()
        activeTransferTasks.removeValue(forKey: id)
        if let idx = transferQueue.firstIndex(where: { $0.id == id }) {
            transferQueue[idx].status = .cancelled
        }
    }

    public func revealInFinder(localURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([localURL])
    }

    public func clearCompletedTransfers() {
        transferQueue.removeAll(where: { $0.status == .completed || $0.status == .cancelled })
    }
}
