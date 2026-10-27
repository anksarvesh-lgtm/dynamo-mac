//
//  PhoneBridgeEngine.swift
//  LiquidDynamo
//
//  Complete native Android ADB & MTP file transfer engine, Finder external
//  SSD storage volume mount emulation, and hardware telemetry service.
//  Merges Phone Bridge & OpenMTP architectures into high-performance Darwin engine.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

@MainActor
public final class PhoneBridgeEngine: ObservableObject {
    public static let shared = PhoneBridgeEngine()

    // MARK: - Backends (Option B: MTP Native & PhoneBridge ADB)

    public let adbBackend = AdbBackend()
    public let mtpBackend = MtpBackend()

    public func backend(for connectionType: PhoneBridgeConnectionType) -> AndroidTransferBackend {
        switch connectionType {
        case .mtp:
            return mtpBackend
        case .adb, .wireless:
            return adbBackend
        }
    }

    public var activeBackend: AndroidTransferBackend {
        if let dev = selectedDevice {
            return backend(for: dev.connectionType)
        }
        if Defaults[.phonebridgeBackendType] == "mtp" && mtpBackend.isAvailable {
            return mtpBackend
        }
        if mtpBackend.isAvailable {
            return mtpBackend
        }
        return adbBackend
    }

    // MARK: - Published State

    @Published public private(set) var connectedDevices: [AndroidDevice] = []
    @Published public private(set) var selectedDevice: AndroidDevice? = nil
    @Published public private(set) var currentRemotePath: String = "/sdcard"
    @Published public private(set) var currentFiles: [AndroidFileItem] = []
    @Published public private(set) var activeTransfers: [PhoneBridgeTransferItem] = []
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var isTransferring: Bool = false
    @Published public private(set) var isSyncingStorage: Bool = false
    @Published public private(set) var adbPath: String? = nil
    @Published public private(set) var isAdbAvailable: Bool = false
    @Published public var autoMountInFinder: Bool = true
    @Published public var autoRevealInFinder: Bool = false
    @Published public private(set) var lastErrorMessage: String? = nil

    // MARK: - Internal Subsystems

    private var scanTimer: Timer?
    private var activeTransferTasks: [UUID: Task<Void, Never>] = [:]
    private var fileWatchers: [String: DispatchSourceFileSystemObject] = [:]
    private var cancellables = Set<AnyCancellable>()

    // Standard Finder Mount Root
    public static let defaultMountRoot: URL = {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return desktop
    }()

    private init() {
        self.autoMountInFinder = Defaults[.phonebridgeAutoMountOnConnect]
        self.autoRevealInFinder = Defaults[.phonebridgeAutoRevealInFinder]
        resolveAdbPath()
        startPeriodicDeviceScanner()
        setupDeviceMonitorIntegration()
    }

    deinit {
        scanTimer?.invalidate()
        for (_, source) in fileWatchers {
            source.cancel()
        }
    }

    // MARK: - ADB Path Resolution

    public func resolveAdbPath() {
        adbBackend.effectiveAdbPath.map { _ in () }
        self.adbPath = adbBackend.effectiveAdbPath
        self.isAdbAvailable = adbBackend.isAvailable
        Defaults[.phonebridgeAdbPath] = self.adbPath ?? ""
    }

    public func setCustomAdbPath(_ path: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        UserDefaults.standard.set(path, forKey: "phonebridge_custom_adb_path")
        UserDefaults.standard.set(path, forKey: "filedroid_custom_adb_path")
        Defaults[.phonebridgeAdbPath] = path
        self.adbPath = path
        self.isAdbAvailable = true
        scanDevices()
        return true
    }

    // MARK: - Device Selection

    public func selectDevice(serial: String) {
        if let dev = connectedDevices.first(where: { $0.serial == serial }) {
            self.objectWillChange.send()
            self.selectedDevice = dev
            if dev.connectionType == .mtp && (self.currentRemotePath == "/sdcard" || !self.currentRemotePath.hasPrefix("/")) {
                self.currentRemotePath = "/"
            }
            fetchDirectoryContents(path: self.currentRemotePath)
            syncStorage(forced: true)
        }
    }

    // MARK: - Storage Synchronization

    public func syncStorage(forced: Bool = false) {
        guard let dev = selectedDevice, dev.status == .connected else { return }
        guard !isSyncingStorage else { return }

        isSyncingStorage = true
        let serial = dev.serial
        let backend = activeBackend

        Task { [weak self] in
            guard let self = self else { return }
            var storageInfo = await backend.queryStorageInfo(serial: serial)
            if storageInfo == nil || storageInfo?.total == 0 {
                let fallback: AndroidTransferBackend = (backend.backendType == .adb) ? self.mtpBackend : self.adbBackend
                if fallback.isAvailable {
                    storageInfo = await fallback.queryStorageInfo(serial: serial)
                }
            }

            await MainActor.run {
                self.isSyncingStorage = false
                guard let (total, used, free) = storageInfo, total > 0 else {
                    if forced {
                        self.lastErrorMessage = "Storage stats currently unavailable for \(dev.displayName)"
                    }
                    return
                }

                self.objectWillChange.send()

                // Update selectedDevice
                if var sel = self.selectedDevice, sel.serial == serial {
                    sel.internalStorageTotal = total
                    sel.internalStorageUsed = used
                    sel.internalStorageFree = free
                    self.selectedDevice = sel
                }

                // Update connectedDevices list
                if let idx = self.connectedDevices.firstIndex(where: { $0.serial == serial }) {
                    self.connectedDevices[idx].internalStorageTotal = total
                    self.connectedDevices[idx].internalStorageUsed = used
                    self.connectedDevices[idx].internalStorageFree = free

                    if let mountPath = self.connectedDevices[idx].mountPath {
                        self.updateMountDeviceInfo(device: self.connectedDevices[idx], mountPath: mountPath)
                    }
                }
            }
        }
    }

    public func updateMountDeviceInfo(device: AndroidDevice, mountPath: String) {
        let mountURL = URL(fileURLWithPath: mountPath)
        let infoURL = mountURL.appendingPathComponent("Device Info & Storage Specs.txt")
        let infoContent = """
        ========================================================================
        Phone Bridge — Phone Storage Volume
        ========================================================================
        Device Name:       \(device.displayName)
        Manufacturer:      \(device.manufacturer)
        Model:             \(device.model)
        Android OS:        \(device.androidVersion) (API Level \(device.apiLevel))
        Serial Number:     \(device.serial)
        Connection:        \(device.connectionType.rawValue)
        Battery Level:     \(device.batteryLevel.map { "\($0)%" } ?? "Unknown") \(device.isCharging ? "(Charging)" : "")
        Battery Health:    \(device.batteryHealth ?? "Normal") (\(device.batteryTemperature.map { String(format: "%.1f°C", $0) } ?? ""))
        Internal Storage:  \(device.formattedInternalStorage)
        Finder Mount:      \(mountPath)
        Last Synced:       \(Date().formatted(date: .abbreviated, time: .standard))
        ========================================================================
        INSTRUCTIONS:
        - Drag & drop files from your Mac into any 'Internal Storage' folder.
        - Phone Bridge will automatically sync and upload them directly to your phone.
        - To manage or browse all files, use Phone Bridge in the LiquidDynamo Island.
        ========================================================================
        """
        try? infoContent.write(to: infoURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Integration with DeviceMonitor

    private func setupDeviceMonitorIntegration() {
        DeviceMonitor.shared.$activeDevices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                guard let self = self else { return }
                let hasAndroidUsb = devices.values.contains { $0.kind == .androidPhone }
                if hasAndroidUsb && self.connectedDevices.isEmpty {
                    self.scanDevices(forced: true)
                } else if !hasAndroidUsb && !self.connectedDevices.isEmpty {
                    // Check if any ADB wireless or remaining devices exist
                    Task { [weak self] in
                        guard let self = self else { return }
                        let adbDevs = await self.adbBackend.scanDevices()
                        await MainActor.run {
                            if adbDevs.isEmpty {
                                self.connectedDevices = []
                                self.selectedDevice = nil
                                self.stopPeriodicDeviceScanner()
                            } else {
                                self.connectedDevices = adbDevs
                            }
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Device Polling & Hardware Telemetry

    public func startPeriodicDeviceScanner() {
        scanTimer?.invalidate()
        scanTimer = nil
        // Only run periodic polling when a device is actually connected, avoiding waking CPU & libusb in background
        guard !connectedDevices.isEmpty else { return }
        scanTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scanDevices(forced: false)
            }
        }
    }

    public func stopPeriodicDeviceScanner() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    public var availableMtpStorages: [MTPStorageItem] {
        mtpBackend.availableStorages
    }

    public func selectMtpStorage(storageId: UInt32) {
        mtpBackend.setTargetStorageId(storageId)
        self.currentRemotePath = "/"
        fetchDirectoryContents(path: "/")
        syncStorage(forced: true)
    }

    public func terminateUsbConflicts() -> Bool {
        let killed = MTPProcessConflictResolver.terminateConflictingProcesses()
        if killed {
            scanDevices(forced: true)
        }
        return killed
    }

    public func scanDevices(forced: Bool = false) {
        guard !isScanning else { return }
        let hasAndroidUsb = DeviceMonitor.shared.activeDevices.values.contains { $0.kind == .androidPhone }
        
        // Skip background probe only if no Android USB device is detected, no active devices, and neither backend is available
        if !hasAndroidUsb && !forced && connectedDevices.isEmpty && !adbBackend.isAvailable && !mtpBackend.isAvailable {
            return
        }

        isScanning = true
        resolveAdbPath()

        Task { [weak self] in
            guard let self = self else { return }

            // Probe ADB backend (if not strictly set to mtp only)
            var adbDevices: [AndroidDevice] = []
            if Defaults[.phonebridgeBackendType] != "mtp" && self.adbBackend.isAvailable {
                adbDevices = await self.adbBackend.scanDevices()
            }

            // Probe OpenMTP native MTP backend (if not strictly set to adb only)
            var mtpDevices: [AndroidDevice] = []
            if Defaults[.phonebridgeBackendType] != "adb" && self.mtpBackend.isAvailable {
                mtpDevices = await self.mtpBackend.scanDevices(force: forced)
            }

            var discovered: [AndroidDevice] = mtpDevices
            for adbDev in adbDevices {
                if !discovered.contains(where: { $0.serial == adbDev.serial || $0.model == adbDev.model }) {
                    discovered.append(adbDev)
                }
            }

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.objectWillChange.send()
                self.isScanning = false
                let previousDevices = self.connectedDevices
                self.connectedDevices = discovered

                if !discovered.isEmpty {
                    self.startPeriodicDeviceScanner()
                } else {
                    self.stopPeriodicDeviceScanner()
                }

                // Preserve and refresh current selected device
                if let currentSel = self.selectedDevice,
                   let updated = discovered.first(where: { $0.serial == currentSel.serial }) {
                    self.selectedDevice = updated
                } else {
                    self.selectedDevice = discovered.first
                    if let sel = self.selectedDevice {
                        if sel.connectionType == .mtp && self.currentRemotePath == "/sdcard" {
                            self.currentRemotePath = "/"
                        }
                        self.fetchDirectoryContents(path: self.currentRemotePath)
                    }
                }

                // Auto-sync storage if device is connected and storage is 0 or newly connected
                if let sel = self.selectedDevice, sel.status == .connected {
                    if sel.internalStorageTotal == 0 || previousDevices.isEmpty {
                        self.syncStorage(forced: forced)
                    }
                }

                // If newly connected device detected, trigger island alert
                for dev in discovered where !previousDevices.contains(where: { $0.serial == dev.serial }) {
                    if Defaults[.phonebridgeNotifications] {
                        DynamicIslandHub.shared.triggerCustomAlert(
                            title: "Android Connected",
                            subtitle: "\(dev.displayName) Ready",
                            iconName: "phone.fill",
                            tint: Color.green
                        )
                    }
                }

                // Auto-mount in Finder if enabled
                if self.autoMountInFinder || Defaults[.phonebridgeAutoMountOnConnect] {
                    for dev in discovered where dev.status == .connected {
                        self.mountDeviceInFinder(device: dev)
                    }
                }
            }
        }
    }

    // MARK: - Finder SSD Storage Mount Emulation

    public func mountDeviceInFinder(device: AndroidDevice) {
        let safeName = device.displayName.replacingOccurrences(of: "/", with: "-")
        let mountURL = Self.defaultMountRoot.appendingPathComponent(safeName)
        let mountPath = mountURL.path

        do {
            try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)

            let internalStorageURL = mountURL.appendingPathComponent("Internal Storage")
            let standardDirs = ["DCIM", "Download", "Documents", "Music", "Pictures", "Movies", "Podcasts"]
            for dir in standardDirs {
                try FileManager.default.createDirectory(at: internalStorageURL.appendingPathComponent(dir), withIntermediateDirectories: true)
            }

            let infoURL = mountURL.appendingPathComponent("Device Info & Storage Specs.txt")
            let infoContent = """
            ========================================================================
            Phone Bridge — Phone Storage Volume
            ========================================================================
            Device Name:       \(device.displayName)
            Manufacturer:      \(device.manufacturer)
            Model:             \(device.model)
            Android OS:        \(device.androidVersion) (API Level \(device.apiLevel))
            Serial Number:     \(device.serial)
            Connection:        \(device.connectionType.rawValue)
            Battery Level:     \(device.batteryLevel.map { "\($0)%" } ?? "Unknown") \(device.isCharging ? "(Charging)" : "")
            Battery Health:    \(device.batteryHealth ?? "Normal") (\(device.batteryTemperature.map { String(format: "%.1f°C", $0) } ?? ""))
            Internal Storage:  \(device.formattedInternalStorage)
            Finder Mount:      \(mountPath)
            Mounted At:        \(Date().formatted(date: .abbreviated, time: .standard))
            ========================================================================
            INSTRUCTIONS:
            - Drag & drop files from your Mac into any 'Internal Storage' folder.
            - Phone Bridge will automatically sync and upload them directly to your phone.
            - To manage or browse all files, use Phone Bridge in the LiquidDynamo Island.
            ========================================================================
            """
            try infoContent.write(to: infoURL, atomically: true, encoding: .utf8)

            let appIconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns")
            if let icns = appIconPath {
                let volIconURL = mountURL.appendingPathComponent(".VolumeIcon.icns")
                if !FileManager.default.fileExists(atPath: volIconURL.path) {
                    try? FileManager.default.copyItem(atPath: icns, toPath: volIconURL.path)
                }
                Task.detached(priority: .background) {
                    let setFile = "/usr/bin/SetFile"
                    if FileManager.default.isExecutableFile(atPath: setFile) {
                        let proc1 = Process()
                        proc1.executableURL = URL(fileURLWithPath: setFile)
                        proc1.arguments = ["-a", "C", mountPath]
                        try? proc1.run()
                        proc1.waitUntilExit()

                        let proc2 = Process()
                        proc2.executableURL = URL(fileURLWithPath: setFile)
                        proc2.arguments = ["-c", "icnC", volIconURL.path]
                        try? proc2.run()
                        proc2.waitUntilExit()
                    }
                }
            }

            if let idx = self.connectedDevices.firstIndex(where: { $0.serial == device.serial }) {
                self.connectedDevices[idx].mountPath = mountPath
            }
            if self.selectedDevice?.serial == device.serial {
                self.selectedDevice?.mountPath = mountPath
            }

            setupFinderDropWatcher(for: device, mountURL: internalStorageURL)

            if autoRevealInFinder || Defaults[.phonebridgeAutoRevealInFinder] {
                openMountInFinder(device: device)
            }
        } catch {
            print("[PhoneBridge] Error creating Finder mount: \(error)")
        }
    }

    private func setupFinderDropWatcher(for device: AndroidDevice, mountURL: URL) {
        let fd = open(mountURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        fileWatchers[device.serial]?.cancel()
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .link], queue: .global(qos: .utility))

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleFinderDropDetected(for: device, mountURL: mountURL)
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fileWatchers[device.serial] = source
    }

    private func handleFinderDropDetected(for device: AndroidDevice, mountURL: URL) {
        guard let subdirs = try? FileManager.default.contentsOfDirectory(at: mountURL, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        for sub in subdirs where (try? sub.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            guard let files = try? FileManager.default.contentsOfDirectory(at: sub, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for f in files {
                let name = f.lastPathComponent
                guard !name.hasPrefix("."), !name.hasSuffix(".txt") else { continue }
                self.uploadFiles(localURLs: [f], destinationRemotePath: "/sdcard/\(sub.lastPathComponent)")
            }
        }
    }

    public func openMountInFinder(device: AndroidDevice? = nil) {
        guard let dev = device ?? selectedDevice, let path = dev.mountPath else { return }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public static var defaultDownloadFolder: String {
        let saved = Defaults[.phonebridgeDefaultMacFolder]
        let baseDownloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? (NSHomeDirectory() + "/Downloads")
        let androidFolder = (baseDownloads as NSString).appendingPathComponent("Android")

        let target = (saved.isEmpty || saved == baseDownloads || saved == (baseDownloads + "/")) ? androidFolder : saved
        if !FileManager.default.fileExists(atPath: target) {
            try? FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
        }
        return target
    }

    public func openMacDownloadsFolder() {
        let dest = Self.defaultDownloadFolder
        if !FileManager.default.fileExists(atPath: dest) {
            try? FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
        }
        let url = URL(fileURLWithPath: dest)
        NSWorkspace.shared.open(url)
    }

    public func openPhoneDownloadsFolder() {
        if selectedDevice?.connectionType == .mtp {
            navigateTo(path: "/Download")
        } else {
            navigateTo(path: "/sdcard/Download")
        }
    }

    // MARK: - Remote File Browsing

    public func navigateTo(path: String) {
        self.currentRemotePath = path
        fetchDirectoryContents(path: path)
    }

    public func navigateUp() {
        if selectedDevice?.connectionType == .mtp {
            guard currentRemotePath != "/" else { return }
        } else {
            guard currentRemotePath != "/" && currentRemotePath != "/sdcard" else { return }
        }
        let parent = (currentRemotePath as NSString).deletingLastPathComponent
        navigateTo(path: parent.isEmpty ? "/" : parent)
    }

    public func fetchDirectoryContents(path: String) {
        guard let dev = selectedDevice, dev.status == .connected else {
            self.currentFiles = []
            return
        }

        let backend = activeBackend
        let showHidden = Defaults[.phonebridgeShowHiddenFiles]

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let files = try await backend.fetchDirectoryContents(serial: dev.serial, path: path, showHidden: showHidden)
                await MainActor.run {
                    self.currentFiles = files
                    self.lastErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - File Operations (Create, Rename, Delete)

    public func createFolder(named folderName: String) {
        guard let dev = selectedDevice, dev.status == .connected else { return }
        let cleanName = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let target = (currentRemotePath as NSString).appendingPathComponent(cleanName)
        let backend = activeBackend

        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await backend.createFolder(serial: dev.serial, remotePath: target)
                await MainActor.run {
                    self.fetchDirectoryContents(path: self.currentRemotePath)
                }
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    public func renameItem(from remotePath: String, to newName: String) {
        guard let dev = selectedDevice, dev.status == .connected else { return }
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let backend = activeBackend

        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await backend.renameItem(serial: dev.serial, remotePath: remotePath, newName: cleanName)
                await MainActor.run {
                    self.fetchDirectoryContents(path: self.currentRemotePath)
                }
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    public func deleteItems(paths: [String]) {
        guard let dev = selectedDevice, dev.status == .connected, !paths.isEmpty else { return }
        let backend = activeBackend

        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await backend.deleteItems(serial: dev.serial, remotePaths: paths)
                await MainActor.run {
                    self.fetchDirectoryContents(path: self.currentRemotePath)
                }
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Upload & Download with Progress & Collapsed Live Activity

    public func uploadFiles(localURLs: [URL], destinationRemotePath: String, conflictResolution: FileConflictResolution = .replace) {
        guard let dev = selectedDevice, dev.status == .connected else { return }

        for url in localURLs {
            let fileName = url.lastPathComponent
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            var targetRemote = (destinationRemotePath as NSString).appendingPathComponent(fileName)

            if conflictResolution == .keepBoth && currentFiles.contains(where: { $0.name == fileName }) {
                let ext = (fileName as NSString).pathExtension
                let base = (fileName as NSString).deletingPathExtension
                let newName = ext.isEmpty ? "\(base)_1" : "\(base)_1.\(ext)"
                targetRemote = (destinationRemotePath as NSString).appendingPathComponent(newName)
            } else if conflictResolution == .skip && currentFiles.contains(where: { $0.name == fileName }) {
                continue
            }

            let item = PhoneBridgeTransferItem(
                fileName: fileName,
                direction: .uploadToAndroid,
                localPath: url.path,
                remotePath: targetRemote,
                totalBytes: size,
                status: .queued
            )
            self.activeTransfers.append(item)
            dispatchTransfer(item: item, serial: dev.serial)
        }
    }

    public func downloadFiles(remoteFiles: [AndroidFileItem], destinationLocalURL: URL? = nil, conflictResolution: FileConflictResolution = .replace) {
        guard let dev = selectedDevice, dev.status == .connected else { return }
        let destFolder = destinationLocalURL?.path ?? Self.defaultDownloadFolder
        if !FileManager.default.fileExists(atPath: destFolder) {
            try? FileManager.default.createDirectory(atPath: destFolder, withIntermediateDirectories: true)
        }

        // Disk space check
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: destFolder),
           let freeSpace = attrs[.systemFreeSize] as? UInt64 {
            let totalNeeded = remoteFiles.reduce(0) { $0 + $1.sizeBytes }
            if totalNeeded > freeSpace {
                self.lastErrorMessage = "Not enough disk space on Mac (\(PhoneBridgeFormatting.formatBytes(totalNeeded)) required, \(PhoneBridgeFormatting.formatBytes(freeSpace)) free)"
                return
            }
        }

        for file in remoteFiles {
            var targetLocal = (destFolder as NSString).appendingPathComponent(file.name)

            if FileManager.default.fileExists(atPath: targetLocal) {
                if conflictResolution == .keepBoth {
                    let ext = (file.name as NSString).pathExtension
                    let base = (file.name as NSString).deletingPathExtension
                    let newName = ext.isEmpty ? "\(base)_1" : "\(base)_1.\(ext)"
                    targetLocal = (destFolder as NSString).appendingPathComponent(newName)
                } else if conflictResolution == .skip {
                    continue
                }
            }

            let item = PhoneBridgeTransferItem(
                fileName: file.name,
                direction: .downloadToMac,
                localPath: targetLocal,
                remotePath: file.remotePath,
                totalBytes: file.sizeBytes,
                status: .queued
            )
            self.activeTransfers.append(item)
            dispatchTransfer(item: item, serial: dev.serial)
        }
    }

    private func dispatchTransfer(item: PhoneBridgeTransferItem, serial: String) {
        self.isTransferring = true
        let itemId = item.id
        let backend = activeBackend

        let job = Task { [weak self] in
            await MainActor.run {
                if let idx = self?.activeTransfers.firstIndex(where: { $0.id == itemId }) {
                    self?.activeTransfers[idx].status = .inProgress
                }
                self?.updateLiveActivity()
            }

            let start = Date()
            var speed: Double = 0
            do {
                if item.direction == .uploadToAndroid {
                    try await backend.pushFile(serial: serial, localPath: item.localPath, remotePath: item.remotePath) { [weak self] transferred, total in
                        Task { @MainActor [weak self] in
                            if let idx = self?.activeTransfers.firstIndex(where: { $0.id == itemId }) {
                                self?.activeTransfers[idx].transferredBytes = UInt64(max(0, transferred))
                                if total > 0 { self?.activeTransfers[idx].totalBytes = UInt64(total) }
                                let elapsed = max(0.1, Date().timeIntervalSince(start))
                                speed = Double(transferred) / elapsed
                                self?.activeTransfers[idx].speedBytesPerSec = speed
                                self?.updateLiveActivity()
                            }
                        }
                    }
                } else {
                    try await backend.pullFile(serial: serial, remotePath: item.remotePath, localPath: item.localPath) { [weak self] transferred, total in
                        Task { @MainActor [weak self] in
                            if let idx = self?.activeTransfers.firstIndex(where: { $0.id == itemId }) {
                                self?.activeTransfers[idx].transferredBytes = UInt64(max(0, transferred))
                                if total > 0 { self?.activeTransfers[idx].totalBytes = UInt64(total) }
                                let elapsed = max(0.1, Date().timeIntervalSince(start))
                                speed = Double(transferred) / elapsed
                                self?.activeTransfers[idx].speedBytesPerSec = speed
                                self?.updateLiveActivity()
                            }
                        }
                    }
                }

                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    if let idx = self.activeTransfers.firstIndex(where: { $0.id == itemId }) {
                        self.activeTransfers[idx].transferredBytes = self.activeTransfers[idx].totalBytes
                        self.activeTransfers[idx].status = .completed
                    }
                    self.activeTransferTasks.removeValue(forKey: itemId)
                    self.isTransferring = self.activeTransfers.contains { $0.status == .inProgress }
                    self.updateLiveActivity()
                    self.fetchDirectoryContents(path: self.currentRemotePath)
                    self.syncStorage()

                    if Defaults[.phonebridgeNotifications] {
                        DynamicIslandHub.shared.triggerCustomAlert(
                            title: item.direction == .uploadToAndroid ? "Upload Completed" : "Download Completed",
                            subtitle: "\(item.fileName) (\(PhoneBridgeFormatting.formatBytes(item.totalBytes)))",
                            iconName: "checkmark.circle.fill",
                            tint: Color.green
                        )
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    if let idx = self.activeTransfers.firstIndex(where: { $0.id == itemId }) {
                        self.activeTransfers[idx].status = .failed
                        self.activeTransfers[idx].errorMessage = error.localizedDescription
                    }
                    self.activeTransferTasks.removeValue(forKey: itemId)
                    self.isTransferring = self.activeTransfers.contains { $0.status == .inProgress }
                    self.updateLiveActivity()
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
        activeTransferTasks[itemId] = job
    }

    public func retryTransfer(id: UUID) {
        guard let idx = activeTransfers.firstIndex(where: { $0.id == id }), let dev = selectedDevice else { return }
        activeTransfers[idx].status = .queued
        activeTransfers[idx].errorMessage = nil
        dispatchTransfer(item: activeTransfers[idx], serial: dev.serial)
    }

    public func cancelTransfer(id: UUID) {
        activeTransferTasks[id]?.cancel()
        activeTransferTasks.removeValue(forKey: id)
        if let idx = activeTransfers.firstIndex(where: { $0.id == id }) {
            activeTransfers[idx].status = .cancelled
        }
        isTransferring = activeTransfers.contains { $0.status == .inProgress }
        updateLiveActivity()
    }

    public func clearFinishedTransfers() {
        activeTransfers.removeAll { $0.status == .completed || $0.status == .cancelled }
        updateLiveActivity()
    }

    // MARK: - Collapsed Live Activity Registration

    private func updateLiveActivity() {
        if let active = activeTransfers.first(where: { $0.status == .inProgress }) {
            IslandController.shared.registerActivity(IslandActivity(
                id: "phonebridge_transfer",
                kind: .fileTransfer,
                priority: 85,
                leadingIcon: active.direction == .uploadToAndroid ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
                title: active.fileName,
                tintColor: Color.green,
                trailingText: "\(Int(active.progressFraction * 100))% • \(active.formattedSpeed)"
            ))
        } else {
            IslandController.shared.removeActivity(id: "phonebridge_transfer")
            IslandController.shared.removeActivity(id: "filedroid_transfer")
        }
    }
}

// MARK: - Backward Compatibility Aliases
public typealias FileDroidEngine = PhoneBridgeEngine
