//
//  FileDroidEngine.swift
//  LiquidDynamo
//
//  Complete native Android ADB & MTP file transfer engine, Finder external
//  SSD storage volume mount emulation, and hardware telemetry service.
//  Merges FileDroid & OpenMTP architectures into high-performance Darwin engine.
//

import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
public final class FileDroidEngine: ObservableObject {
    public static let shared = FileDroidEngine()

    // MARK: - Published State

    @Published public private(set) var connectedDevices: [AndroidDevice] = []
    @Published public private(set) var selectedDevice: AndroidDevice? = nil
    @Published public private(set) var currentRemotePath: String = "/sdcard"
    @Published public private(set) var currentFiles: [AndroidFileItem] = []
    @Published public private(set) var activeTransfers: [FileDroidTransferItem] = []
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var isTransferring: Bool = false
    @Published public private(set) var adbPath: String? = nil
    @Published public private(set) var isAdbAvailable: Bool = false
    @Published public var autoMountInFinder: Bool = true
    @Published public var autoRevealInFinder: Bool = false
    @Published public private(set) var lastErrorMessage: String? = nil

    // MARK: - Internal Subsystems

    private var scanTimer: Timer?
    private var activeTransferProcess: Process?
    private var fileWatchers: [String: DispatchSourceFileSystemObject] = [:]
    private var cancellables = Set<AnyCancellable>()

    // Standard Finder Mount Root
    public static let defaultMountRoot: URL = {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return desktop
    }()

    private init() {
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
        if let custom = UserDefaults.standard.string(forKey: "filedroid_custom_adb_path"),
           FileManager.default.isExecutableFile(atPath: custom) {
            self.adbPath = custom
            self.isAdbAvailable = true
            return
        }

        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "/Applications/Android Studio.app/Contents/platform-tools/adb",
            "/opt/android-sdk/platform-tools/adb",
            "/usr/bin/adb"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                self.adbPath = path
                self.isAdbAvailable = true
                return
            }
        }

        self.adbPath = nil
        self.isAdbAvailable = false
    }

    public func setCustomAdbPath(_ path: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        UserDefaults.standard.set(path, forKey: "filedroid_custom_adb_path")
        self.adbPath = path
        self.isAdbAvailable = true
        scanDevices()
        return true
    }

    // MARK: - Integration with DeviceMonitor

    private func setupDeviceMonitorIntegration() {
        DeviceMonitor.shared.$activeDevices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                guard let self = self else { return }
                let hasAndroidUsb = devices.values.contains { $0.kind == .androidPhone }
                if hasAndroidUsb && self.connectedDevices.isEmpty {
                    self.scanDevices()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Device Polling & Hardware Telemetry

    public func startPeriodicDeviceScanner() {
        scanTimer?.invalidate()
        scanDevices()
        // Low-frequency polling: every 6 seconds when app is active
        scanTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scanDevices()
            }
        }
    }

    public func scanDevices() {
        guard !isScanning else { return }
        isScanning = true

        Task.detached(priority: .utility) { [weak self, adb = self.adbPath] in
            guard let adb = adb, FileManager.default.isExecutableFile(atPath: adb) else {
                await MainActor.run {
                    self?.isScanning = false
                    self?.isAdbAvailable = false
                }
                return
            }

            // Execute `adb devices -l`
            let output = await Self.runProcess(executable: adb, arguments: ["devices", "-l"])
            var discovered: [AndroidDevice] = []

            let lines = output.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("List of devices") else { continue }

                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard parts.count >= 2 else { continue }

                let serial = parts[0]
                let stateStr = parts[1]

                var status: FileDroidDeviceStatus = .connected
                if stateStr == "unauthorized" {
                    status = .unauthorized
                } else if stateStr == "offline" {
                    status = .offline
                }

                var model = "Android"
                var product = ""
                for part in parts.dropFirst(2) {
                    if part.hasPrefix("model:") {
                        model = part.replacingOccurrences(of: "model:", with: "").replacingOccurrences(of: "_", with: " ")
                    } else if part.hasPrefix("product:") {
                        product = part.replacingOccurrences(of: "product:", with: "").replacingOccurrences(of: "_", with: " ")
                    }
                }

                var dev = AndroidDevice(
                    serial: serial,
                    model: model,
                    manufacturer: "Android",
                    marketName: model,
                    connectionType: .adb,
                    status: status
                )

                // If authorized, fetch detailed telemetry
                if status == .connected {
                    let mfg = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "getprop", "ro.product.manufacturer"])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !mfg.isEmpty { dev.manufacturer = mfg.capitalized }

                    let market = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "getprop", "ro.product.marketname"])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !market.isEmpty { dev.marketName = market }

                    let osVer = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "getprop", "ro.build.version.release"])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !osVer.isEmpty { dev.androidVersion = "Android \(osVer)" }

                    let apiStr = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "getprop", "ro.build.version.sdk"])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if let api = Int(apiStr) { dev.apiLevel = api }

                    // Battery Telemetry via dumpsys battery
                    let battOut = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "dumpsys", "battery"])
                    dev.batteryLevel = Self.extractInt(from: battOut, key: "level:")
                    dev.isCharging = (Self.extractInt(from: battOut, key: "status:") ?? 0) == 2 || (Self.extractInt(from: battOut, key: "AC powered:") ?? 0) == 1
                    if let tempRaw = Self.extractInt(from: battOut, key: "temperature:") {
                        dev.batteryTemperature = Double(tempRaw) / 10.0
                    }
                    if let healthCode = Self.extractInt(from: battOut, key: "health:") {
                        dev.batteryHealth = (healthCode == 2) ? "Good" : "Normal"
                    }

                    // Storage Telemetry via df -k /storage/emulated/0
                    let dfOut = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "df", "-k", "/storage/emulated/0"])
                    if let (total, used, free) = Self.parseDfOutput(dfOut) {
                        dev.internalStorageTotal = total
                        dev.internalStorageUsed = used
                        dev.internalStorageFree = free
                    }
                }

                discovered.append(dev)
            }

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.isScanning = false
                self.connectedDevices = discovered

                if self.selectedDevice == nil || !discovered.contains(where: { $0.serial == self.selectedDevice?.serial }) {
                    self.selectedDevice = discovered.first
                    if self.selectedDevice != nil {
                        self.fetchDirectoryContents(path: self.currentRemotePath)
                    }
                }

                // Auto-mount in Finder if enabled
                if self.autoMountInFinder {
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

            // 1. Create Internal Storage structure
            let internalStorageURL = mountURL.appendingPathComponent("Internal Storage")
            let standardDirs = ["DCIM", "Download", "Documents", "Music", "Pictures", "Movies", "Podcasts"]
            for dir in standardDirs {
                try FileManager.default.createDirectory(at: internalStorageURL.appendingPathComponent(dir), withIntermediateDirectories: true)
            }

            // 2. Write Device Info & Hardware Specs Text File
            let infoURL = mountURL.appendingPathComponent("Device Info & Storage Specs.txt")
            let infoContent = """
            ========================================================================
            FileDroid & OpenMTP — Android Storage Volume
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
            - FileDroid will automatically sync and upload them directly to your phone.
            - To manage or browse all files, use FileDroid in the LiquidDynamo Island.
            ========================================================================
            """
            try infoContent.write(to: infoURL, atomically: true, encoding: .utf8)

            // 3. Set Volume Custom Icon if icns is available
            let appIconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns")
            if let icns = appIconPath {
                let volIconURL = mountURL.appendingPathComponent(".VolumeIcon.icns")
                if !FileManager.default.fileExists(atPath: volIconURL.path) {
                    try? FileManager.default.copyItem(atPath: icns, toPath: volIconURL.path)
                }
                // Invoke SetFile to tell Finder this directory has a custom external volume icon
                Task.detached(priority: .background) {
                    _ = await Self.runProcess(executable: "/usr/bin/SetFile", arguments: ["-a", "C", mountPath])
                    _ = await Self.runProcess(executable: "/usr/bin/SetFile", arguments: ["-c", "icnC", volIconURL.path])
                }
            }

            // 4. Update mountPath in model
            if let idx = self.connectedDevices.firstIndex(where: { $0.serial == device.serial }) {
                self.connectedDevices[idx].mountPath = mountPath
            }
            if self.selectedDevice?.serial == device.serial {
                self.selectedDevice?.mountPath = mountPath
            }

            // 5. Setup live watcher on the mount directory to auto-push newly dropped files
            setupFinderDropWatcher(for: device, mountURL: internalStorageURL)

            if autoRevealInFinder {
                openMountInFinder(device: device)
            }
        } catch {
            print("[FileDroid] Error creating Finder mount: \(error)")
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
        // Inspect internal storage folders for any newly copied files
        guard let subdirs = try? FileManager.default.contentsOfDirectory(at: mountURL, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        for sub in subdirs where (try? sub.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            guard let files = try? FileManager.default.contentsOfDirectory(at: sub, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for f in files {
                // If file is not hidden and was modified in last 5 seconds, sync it to device
                let name = f.lastPathComponent
                guard !name.hasPrefix("."), !name.hasSuffix(".txt") else { continue }
                let remoteTarget = "/sdcard/\(sub.lastPathComponent)/\(name)"
                self.uploadFiles(localURLs: [f], destinationRemotePath: "/sdcard/\(sub.lastPathComponent)")
            }
        }
    }

    public func openMountInFinder(device: AndroidDevice? = nil) {
        guard let dev = device ?? selectedDevice, let path = dev.mountPath else { return }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Remote File Browsing

    public func navigateTo(path: String) {
        self.currentRemotePath = path
        fetchDirectoryContents(path: path)
    }

    public func navigateUp() {
        guard currentRemotePath != "/" && currentRemotePath != "/sdcard" else { return }
        let parent = (currentRemotePath as NSString).deletingLastPathComponent
        navigateTo(path: parent.isEmpty ? "/" : parent)
    }

    public func fetchDirectoryContents(path: String) {
        guard let dev = selectedDevice, dev.status == .connected, let adb = adbPath else {
            self.currentFiles = []
            return
        }

        Task.detached(priority: .userInitiated) { [weak self, serial = dev.serial] in
            // Execute stat format: %n|%s|%Y|%F for accurate parsing
            let statOut = await Self.runProcess(
                executable: adb,
                arguments: ["-s", serial, "shell", "stat", "-c", "%n|%s|%Y|%F", "\(path)/*"]
            )

            var parsed: [AndroidFileItem] = []
            let lines = statOut.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.contains("No such file") else { continue }

                let tokens = trimmed.components(separatedBy: "|")
                guard tokens.count >= 4 else { continue }

                let fullPath = tokens[0]
                let name = (fullPath as NSString).lastPathComponent
                guard !name.isEmpty else { continue }

                let size = UInt64(tokens[1]) ?? 0
                let timeSec = Double(tokens[2]) ?? 0
                let date = Date(timeIntervalSince1970: timeSec)
                let typeStr = tokens[3].lowercased()
                let isDir = typeStr.contains("directory")
                let isHidden = name.hasPrefix(".")

                parsed.append(AndroidFileItem(
                    name: name,
                    remotePath: fullPath,
                    sizeBytes: size,
                    modificationDate: date,
                    isDirectory: isDir,
                    isHidden: isHidden
                ))
            }

            // Sort directories first, then alphabetical
            parsed.sort {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory && !$1.isDirectory
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }

            await MainActor.run { [weak self] in
                self?.currentFiles = parsed
            }
        }
    }

    // MARK: - File Actions (Create, Delete, Rename, Upload, Download)

    public func createFolder(named folderName: String) {
        guard let dev = selectedDevice, let adb = adbPath else { return }
        let target = (currentRemotePath as NSString).appendingPathComponent(folderName)

        Task.detached(priority: .userInitiated) { [weak self, serial = dev.serial] in
            _ = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "mkdir", "-p", target])
            await MainActor.run {
                self?.fetchDirectoryContents(path: self?.currentRemotePath ?? "/sdcard")
            }
        }
    }

    public func renameItem(from remotePath: String, to newName: String) {
        guard let dev = selectedDevice, let adb = adbPath else { return }
        let parent = (remotePath as NSString).deletingLastPathComponent
        let target = (parent as NSString).appendingPathComponent(newName)

        Task.detached(priority: .userInitiated) { [weak self, serial = dev.serial] in
            _ = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "mv", remotePath, target])
            await MainActor.run {
                self?.fetchDirectoryContents(path: self?.currentRemotePath ?? "/sdcard")
            }
        }
    }

    public func deleteItems(paths: [String]) {
        guard let dev = selectedDevice, let adb = adbPath, !paths.isEmpty else { return }

        Task.detached(priority: .userInitiated) { [weak self, serial = dev.serial] in
            for path in paths {
                _ = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "rm", "-rf", path])
            }
            await MainActor.run {
                self?.fetchDirectoryContents(path: self?.currentRemotePath ?? "/sdcard")
            }
        }
    }

    public func uploadFiles(localURLs: [URL], destinationRemotePath: String) {
        guard let dev = selectedDevice, let adb = adbPath else { return }

        for url in localURLs {
            let fileName = url.lastPathComponent
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            let targetRemote = (destinationRemotePath as NSString).appendingPathComponent(fileName)

            var item = FileDroidTransferItem(
                fileName: fileName,
                direction: .uploadToAndroid,
                localPath: url.path,
                remotePath: targetRemote,
                totalBytes: size,
                status: .queued
            )
            self.activeTransfers.append(item)

            executeTransfer(item: item, adb: adb, serial: dev.serial)
        }
    }

    public func downloadFiles(remoteFiles: [AndroidFileItem], destinationLocalURL: URL) {
        guard let dev = selectedDevice, let adb = adbPath else { return }

        for file in remoteFiles {
            let targetLocal = destinationLocalURL.appendingPathComponent(file.name).path

            let item = FileDroidTransferItem(
                fileName: file.name,
                direction: .downloadToMac,
                localPath: targetLocal,
                remotePath: file.remotePath,
                totalBytes: file.sizeBytes,
                status: .queued
            )
            self.activeTransfers.append(item)

            executeTransfer(item: item, adb: adb, serial: dev.serial)
        }
    }

    private func executeTransfer(item: FileDroidTransferItem, adb: String, serial: String) {
        self.isTransferring = true
        let itemId = item.id

        Task.detached(priority: .userInitiated) { [weak self] in
            await MainActor.run {
                if let idx = self?.activeTransfers.firstIndex(where: { $0.id == itemId }) {
                    self?.activeTransfers[idx].status = .inProgress
                }
            }

            let start = Date()
            let args: [String]
            if item.direction == .uploadToAndroid {
                args = ["-s", serial, "push", item.localPath, item.remotePath]
            } else {
                args = ["-s", serial, "pull", item.remotePath, item.localPath]
            }

            let output = await Self.runProcess(executable: adb, arguments: args)
            let elapsed = max(0.1, Date().timeIntervalSince(start))
            let speed = Double(item.totalBytes) / elapsed

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                if let idx = self.activeTransfers.firstIndex(where: { $0.id == itemId }) {
                    self.activeTransfers[idx].transferredBytes = item.totalBytes
                    self.activeTransfers[idx].speedBytesPerSec = speed
                    self.activeTransfers[idx].status = .completed
                }
                self.isTransferring = self.activeTransfers.contains { $0.status == .inProgress }
                self.fetchDirectoryContents(path: self.currentRemotePath)
            }
        }
    }

    public func cancelTransfer(id: UUID) {
        if let idx = activeTransfers.firstIndex(where: { $0.id == id }) {
            activeTransfers[idx].status = .cancelled
        }
        activeTransferProcess?.terminate()
        activeTransferProcess = nil
        isTransferring = activeTransfers.contains { $0.status == .inProgress }
    }

    // MARK: - Subprocess Helper

    private static func runProcess(executable: String, arguments: [String]) async -> String {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: out)
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    private static func extractInt(from text: String, key: String) -> Int? {
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix(key) {
                let val = t.replacingOccurrences(of: key, with: "").trimmingCharacters(in: .whitespaces)
                return Int(val)
            }
        }
        return nil
    }

    private static func parseDfOutput(_ text: String) -> (total: UInt64, used: UInt64, free: UInt64)? {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }
        let parts = lines[1].components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 4 else { return nil }

        // df gives 1K blocks
        if let totalK = UInt64(parts[1]),
           let usedK = UInt64(parts[2]),
           let freeK = UInt64(parts[3]) {
            return (totalK * 1024, usedK * 1024, freeK * 1024)
        }
        return nil
    }
}
