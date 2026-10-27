//
//  AndroidTransferBackend.swift
//  LiquidDynamo
//
//  Protocol abstraction and native implementations for Android file transfers.
//  Provides unified backend architecture supporting both high-speed ADB protocol
//  and native OpenMTP (libmtp) device communication.
//

import AppKit
import Foundation

// MARK: - Backend Protocol

public protocol AndroidTransferBackend: AnyObject, Sendable {
    var backendType: PhoneBridgeConnectionType { get }
    var isAvailable: Bool { get }
    var availabilityHint: String? { get }
    
    func scanDevices() async -> [AndroidDevice]
    func queryStorageInfo(serial: String) async -> (total: UInt64, used: UInt64, free: UInt64)?
    func fetchDirectoryContents(serial: String, path: String, showHidden: Bool) async throws -> [AndroidFileItem]
    func createFolder(serial: String, remotePath: String) async throws
    func renameItem(serial: String, remotePath: String, newName: String) async throws
    func deleteItems(serial: String, remotePaths: [String]) async throws
    func pushFile(serial: String, localPath: String, remotePath: String, onProgress: (@Sendable (Int64, Int64) -> Void)?) async throws
    func pullFile(serial: String, remotePath: String, localPath: String, onProgress: (@Sendable (Int64, Int64) -> Void)?) async throws
}

// MARK: - ADB Transfer Backend

public final class AdbBackend: AndroidTransferBackend, @unchecked Sendable {
    public let backendType: PhoneBridgeConnectionType = .adb
    
    public var isAvailable: Bool {
        guard let path = effectiveAdbPath else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }
    
    public var availabilityHint: String? {
        if isAvailable { return nil }
        return "ADB platform-tools not found. Install via Homebrew: 'brew install android-platform-tools' or configure a custom path."
    }
    
    private static var cachedResolvedAdbPath: String? = nil

    public var effectiveAdbPath: String? {
        if let cached = Self.cachedResolvedAdbPath, FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }

        // 1. User custom setting
        let custom = UserDefaults.standard.string(forKey: "phonebridge_custom_adb_path")
            ?? UserDefaults.standard.string(forKey: "filedroid_custom_adb_path") ?? ""
        if !custom.isEmpty && FileManager.default.isExecutableFile(atPath: custom) {
            Self.cachedResolvedAdbPath = custom
            return custom
        }

        // 2. Check PhoneBridge / FileDroid app config if previously configured
        let userHome = "/Users/\(NSUserName())"
        let phonebridgeConfig = "\(userHome)/Library/Application Support/com.phonebridge/adb_path.txt"
        let filedroidConfig = "\(userHome)/Library/Application Support/com.filedroid/adb_path.txt"
        let configPath = FileManager.default.fileExists(atPath: phonebridgeConfig) ? phonebridgeConfig : filedroidConfig
        if let saved = try? String(contentsOfFile: configPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty, FileManager.default.isExecutableFile(atPath: saved) {
            Self.cachedResolvedAdbPath = saved
            return saved
        }

        // 3. Fast check common paths
        let candidates = [
            "\(userHome)/.local/bin/adb",
            "\(userHome)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "/Applications/Android Studio.app/Contents/platform-tools/adb",
            "/opt/android-sdk/platform-tools/adb",
            "/usr/bin/adb"
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            Self.cachedResolvedAdbPath = found
            return found
        }

        // 4. Login shell resolution ('which adb')
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which adb"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                    Self.cachedResolvedAdbPath = path
                    return path
                }
            }
        } catch {}

        return nil
    }
    
    public init() {}
    
    // MARK: - Device Discovery
    
    public func scanDevices() async -> [AndroidDevice] {
        guard let adb = effectiveAdbPath else { return [] }
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
            
            var status: PhoneBridgeDeviceStatus = .connected
            if stateStr == "unauthorized" {
                status = .unauthorized
            } else if stateStr == "offline" {
                status = .offline
            }
            
            var model = "Android"
            for part in parts.dropFirst(2) {
                if part.hasPrefix("model:") {
                    model = part.replacingOccurrences(of: "model:", with: "").replacingOccurrences(of: "_", with: " ")
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
                
                let battOut = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "dumpsys", "battery"])
                dev.batteryLevel = Self.extractInt(from: battOut, key: "level:")
                dev.isCharging = (Self.extractInt(from: battOut, key: "status:") ?? 0) == 2 || (Self.extractInt(from: battOut, key: "AC powered:") ?? 0) == 1
                if let tempRaw = Self.extractInt(from: battOut, key: "temperature:") {
                    dev.batteryTemperature = Double(tempRaw) / 10.0
                }
                if let healthCode = Self.extractInt(from: battOut, key: "health:") {
                    dev.batteryHealth = (healthCode == 2) ? "Good" : "Normal"
                }
                
                if let storage = await queryStorageInfo(serial: serial) {
                    dev.internalStorageTotal = storage.total
                    dev.internalStorageUsed = storage.used
                    dev.internalStorageFree = storage.free
                }
            }
            
            discovered.append(dev)
        }
        return discovered
    }
    
    // MARK: - Directory Browsing
    
    public func fetchDirectoryContents(serial: String, path: String, showHidden: Bool) async throws -> [AndroidFileItem] {
        guard let adb = effectiveAdbPath else {
            throw NSError(domain: "AdbBackend", code: 1, userInfo: [NSLocalizedDescriptionKey: "ADB executable not found"])
        }
        
        // Escape single quotes safely for the shell command
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
        let script = "for f in '\(escapedPath)'/*; do [ -e \"$f\" ] && stat -c '%n|%s|%Y|%F' \"$f\"; done"
        
        let statOut = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", script])
        var parsed: [AndroidFileItem] = []
        let lines = statOut.components(separatedBy: "\n")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains("No such file"), !trimmed.contains("Permission denied") else { continue }
            
            let tokens = trimmed.components(separatedBy: "|")
            guard tokens.count >= 4 else { continue }
            
            let fullPath = tokens[0]
            let name = (fullPath as NSString).lastPathComponent
            guard !name.isEmpty else { continue }
            
            let isHidden = name.hasPrefix(".")
            if isHidden && !showHidden { continue }
            
            let size = UInt64(tokens[1]) ?? 0
            let timeSec = Double(tokens[2]) ?? 0
            let date = Date(timeIntervalSince1970: timeSec)
            let typeStr = tokens[3].lowercased()
            let isDir = typeStr.contains("directory")
            
            parsed.append(AndroidFileItem(
                name: name,
                remotePath: fullPath,
                sizeBytes: size,
                modificationDate: date,
                isDirectory: isDir,
                isHidden: isHidden
            ))
        }
        
        parsed.sort {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory && !$1.isDirectory
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return parsed
    }
    
    // MARK: - File Mutations
    
    public func createFolder(serial: String, remotePath: String) async throws {
        guard let adb = effectiveAdbPath else { throw NSError(domain: "AdbBackend", code: 1, userInfo: [NSLocalizedDescriptionKey: "ADB missing"]) }
        let out = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "mkdir", "-p", remotePath])
        if out.contains("Permission denied") || out.contains("Read-only file system") {
            throw NSError(domain: "AdbBackend", code: 2, userInfo: [NSLocalizedDescriptionKey: out])
        }
    }
    
    public func renameItem(serial: String, remotePath: String, newName: String) async throws {
        guard let adb = effectiveAdbPath else { throw NSError(domain: "AdbBackend", code: 1, userInfo: [NSLocalizedDescriptionKey: "ADB missing"]) }
        let parent = (remotePath as NSString).deletingLastPathComponent
        let target = (parent as NSString).appendingPathComponent(newName)
        let out = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "mv", remotePath, target])
        if out.contains("failed") || out.contains("Permission denied") {
            throw NSError(domain: "AdbBackend", code: 3, userInfo: [NSLocalizedDescriptionKey: out])
        }
    }
    
    public func deleteItems(serial: String, remotePaths: [String]) async throws {
        guard let adb = effectiveAdbPath else { throw NSError(domain: "AdbBackend", code: 1, userInfo: [NSLocalizedDescriptionKey: "ADB missing"]) }
        for path in remotePaths {
            _ = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "rm", "-rf", path])
        }
    }
    
    public func pushFile(serial: String, localPath: String, remotePath: String, onProgress: (@Sendable (Int64, Int64) -> Void)?) async throws {
        guard let adb = effectiveAdbPath else { throw NSError(domain: "AdbBackend", code: 1, userInfo: [NSLocalizedDescriptionKey: "ADB missing"]) }
        guard FileManager.default.fileExists(atPath: localPath) else {
            throw NSError(domain: "AdbBackend", code: 4, userInfo: [NSLocalizedDescriptionKey: "Local file does not exist: \(localPath)"])
        }
        let totalSize = (try? FileManager.default.attributesOfItem(atPath: localPath)[.size] as? Int64) ?? 0
        onProgress?(0, totalSize)
        
        let output = await Self.runProcess(executable: adb, arguments: ["-s", serial, "push", localPath, remotePath])
        if output.contains("device offline") || output.contains("device not found") {
            throw NSError(domain: "AdbBackend", code: 5, userInfo: [NSLocalizedDescriptionKey: "Device disconnected mid-transfer"])
        }
        if output.contains("No space left on device") {
            throw NSError(domain: "AdbBackend", code: 6, userInfo: [NSLocalizedDescriptionKey: "Storage full on Android device"])
        }
        if output.contains("failed") || output.contains("error:") {
            throw NSError(domain: "AdbBackend", code: 7, userInfo: [NSLocalizedDescriptionKey: output])
        }
        onProgress?(totalSize, totalSize)
    }
    
    public func pullFile(serial: String, remotePath: String, localPath: String, onProgress: (@Sendable (Int64, Int64) -> Void)?) async throws {
        guard let adb = effectiveAdbPath else { throw NSError(domain: "AdbBackend", code: 1, userInfo: [NSLocalizedDescriptionKey: "ADB missing"]) }
        
        // Ensure local parent directory exists
        let localDir = (localPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: localDir, withIntermediateDirectories: true)
        
        let output = await Self.runProcess(executable: adb, arguments: ["-s", serial, "pull", remotePath, localPath])
        if output.contains("device offline") || output.contains("device not found") {
            throw NSError(domain: "AdbBackend", code: 5, userInfo: [NSLocalizedDescriptionKey: "Device disconnected mid-transfer"])
        }
        if output.contains("failed") || output.contains("error:") {
            throw NSError(domain: "AdbBackend", code: 7, userInfo: [NSLocalizedDescriptionKey: output])
        }
        let finalSize = (try? FileManager.default.attributesOfItem(atPath: localPath)[.size] as? Int64) ?? 0
        onProgress?(finalSize, finalSize)
    }
    
    // MARK: - Process Execution Helpers
    
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
    
    // MARK: - Storage Query
    
    public func queryStorageInfo(serial: String) async -> (total: UInt64, used: UInt64, free: UInt64)? {
        guard let adb = effectiveAdbPath else { return nil }
        
        // Strategy 1: dumpsys diskstats (system service, unrestricted across Android 4 - 15)
        let diskstatsOut = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "dumpsys", "diskstats"])
        if let res = Self.parseDiskstatsOutput(diskstatsOut) {
            return res
        }
        
        // Strategy 2: Global df -k (reads /proc/mounts without path permissions)
        let globalDfOut = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "df", "-k"])
        if let res = Self.parseDfMounts(globalDfOut) {
            return res
        }
        
        // Strategy 3: Target path df -k (without invalid POSIX -P flag which breaks toybox)
        let candidatePaths = ["/data", "/storage/emulated/0", "/sdcard", "/storage/self/primary"]
        for path in candidatePaths {
            let dfOut = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "df", "-k", path])
            if let res = Self.parseDfMounts(dfOut) ?? Self.parseDfOutput(dfOut) {
                return res
            }
        }
        
        // Strategy 4: stat -f -c %a %b %s (unquoted format specifier for toybox stat)
        for path in candidatePaths {
            let statOut = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "stat", "-f", "-c", "%a %b %s", path])
            let cleaned = statOut.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 3,
               let freeBlocks = UInt64(parts[0]),
               let totalBlocks = UInt64(parts[1]),
               let blockSize = UInt64(parts[2]),
               totalBlocks > 0, blockSize > 0 {
                let total = totalBlocks * blockSize
                let free = freeBlocks * blockSize
                let used = total > free ? (total - free) : 0
                return (total, used, free)
            }
        }
        
        return nil
    }
    
    public static func parseDiskstatsOutput(_ text: String) -> (total: UInt64, used: UInt64, free: UInt64)? {
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("Data-Free:") else { continue }
            let parts = trimmed.replacingOccurrences(of: "Data-Free:", with: "")
                .components(separatedBy: "/")
            guard parts.count >= 2 else { continue }
            
            let freeStr = parts[0].trimmingCharacters(in: .whitespaces)
            let totalPart = parts[1].components(separatedBy: "total")[0].trimmingCharacters(in: .whitespaces)
            
            if let freeBytes = parseByteToken(freeStr),
               let totalBytes = parseByteToken(totalPart),
               totalBytes > 0 {
                let usedBytes = totalBytes > freeBytes ? (totalBytes - freeBytes) : 0
                return (totalBytes, usedBytes, freeBytes)
            }
        }
        return nil
    }
    
    private static func parseByteToken(_ str: String) -> UInt64? {
        let clean = str.trimmingCharacters(in: .whitespaces).uppercased()
        if clean.hasSuffix("K") {
            let numStr = String(clean.dropLast()).trimmingCharacters(in: .whitespaces)
            return UInt64(numStr).map { $0 * 1024 }
        } else if clean.hasSuffix("M") {
            let numStr = String(clean.dropLast()).trimmingCharacters(in: .whitespaces)
            return UInt64(numStr).map { $0 * 1024 * 1024 }
        } else if clean.hasSuffix("G") {
            let numStr = String(clean.dropLast()).trimmingCharacters(in: .whitespaces)
            return UInt64(numStr).map { $0 * 1024 * 1024 * 1024 }
        } else if let val = UInt64(clean) {
            return val * 1024
        }
        return nil
    }

    public static func parseDfMounts(_ text: String) -> (total: UInt64, used: UInt64, free: UInt64)? {
        let lines = text.components(separatedBy: "\n")
        var bestCandidate: (total: UInt64, used: UInt64, free: UInt64)? = nil
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lower = trimmed.lowercased()
            if lower.contains("filesystem") || lower.contains("1k-blocks") || lower.contains("1024-blocks") || lower.contains("mounted on") {
                continue
            }
            
            let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard tokens.count >= 4 else { continue }
            
            let mount = tokens.last ?? ""
            let isDataPartition = mount == "/data" || mount == "/storage/emulated" || mount == "/storage/emulated/0" || mount == "/sdcard" || mount == "/storage/self/primary"
            
            var numbers: [UInt64] = []
            for token in tokens.dropFirst() {
                if let val = UInt64(token) {
                    numbers.append(val)
                }
            }
            
            if numbers.count >= 3, numbers[0] > 0 {
                let total = numbers[0] * 1024
                let used = numbers[1] * 1024
                let free = numbers[2] * 1024
                
                if isDataPartition {
                    return (total, used, free)
                }
                
                if mount.hasSuffix("/data") || mount.contains("emulated") {
                    bestCandidate = (total, used, free)
                }
            }
        }
        
        return bestCandidate
    }
    
    public static func parseDfOutput(_ text: String) -> (total: UInt64, used: UInt64, free: UInt64)? {
        let lines = text.components(separatedBy: "\n")
        var dataTokens: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lower = trimmed.lowercased()
            if lower.contains("filesystem") || lower.contains("1k-blocks") || lower.contains("1024-blocks") || lower.contains("mounted on") {
                continue
            }
            let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            dataTokens.append(contentsOf: tokens)
        }
        
        // Locate 3 consecutive numeric columns (total 1K, used 1K, free 1K)
        for i in 0..<dataTokens.count {
            if i + 2 < dataTokens.count,
               let totalK = UInt64(dataTokens[i]),
               let usedK = UInt64(dataTokens[i+1]),
               let freeK = UInt64(dataTokens[i+2]),
               totalK > 0 {
                return (totalK * 1024, usedK * 1024, freeK * 1024)
            }
        }
        return nil
    }
}

// MARK: - MTP Transfer Backend (Native MTPBridge & OpenMTP Engine)

public final class MtpBackend: AndroidTransferBackend, @unchecked Sendable {
    public let backendType: PhoneBridgeConnectionType = .mtp
    public private(set) var cachedStorageId: UInt32 = 65537
    public private(set) var availableStorages: [MTPStorageItem] = []
    private var isSessionActive: Bool = false
    private let sessionLock = NSLock()

    public var isAvailable: Bool {
        return MTPBridge.isSupportedArchitecture && MTPBridge.shared.isLoaded
    }

    public var availabilityHint: String? {
        if !MTPBridge.isSupportedArchitecture {
            return "Native MTP bridge is unavailable on Intel Macs (Apple Silicon required)."
        }
        if isAvailable { return nil }
        return "Native OpenMTP engine dylib is initializing or missing from Frameworks."
    }

    public init() {
        MTPBridge.shared.loadDylib()
    }

    public func ensureSession() async throws {
        let bridge = MTPBridge.shared
        if !bridge.isLoaded {
            bridge.loadDylib()
        }
        guard bridge.isLoaded else {
            throw MTPError.dylibNotLoaded
        }

        sessionLock.lock()
        let active = isSessionActive
        sessionLock.unlock()

        if active {
            return
        }

        let initRes = await bridge.initialize()
        switch initRes {
        case .success:
            sessionLock.lock()
            isSessionActive = true
            sessionLock.unlock()

            let storagesRes = await bridge.fetchStorages()
            if case .success(let storages) = storagesRes, !storages.isEmpty {
                self.availableStorages = storages
                if let first = storages.first {
                    self.cachedStorageId = first.Sid
                }
            }
        case .failure(let err):
            sessionLock.lock()
            isSessionActive = false
            sessionLock.unlock()
            throw err
        }
    }

    public func invalidateSession() async {
        sessionLock.lock()
        isSessionActive = false
        sessionLock.unlock()
        await MTPBridge.shared.dispose()
    }

    public func setTargetStorageId(_ sid: UInt32) {
        self.cachedStorageId = sid
    }

    public func scanDevices() async -> [AndroidDevice] {
        return await scanDevices(force: false)
    }

    public func scanDevices(force: Bool) async -> [AndroidDevice] {
        let hasAndroidUsb = await MainActor.run {
            DeviceMonitor.shared.activeDevices.values.contains { $0.kind == .androidPhone }
        }
        let allowProbe = hasAndroidUsb || force || Defaults[.phonebridgeBackendType] == "mtp" || Defaults[.phonebridgeBackendType] == "auto"
        guard allowProbe else { return [] }

        let bridge = MTPBridge.shared
        if !bridge.isLoaded {
            bridge.loadDylib()
        }
        guard bridge.isLoaded else { return [] }

        let initRes = await bridge.initialize()
        switch initRes {
        case .success(let info):
            sessionLock.lock()
            isSessionActive = true
            sessionLock.unlock()

            let model = info.mtpDeviceInfo?.Model ?? info.usbDeviceInfo?.Product ?? "Android Device"
            let manufacturer = info.mtpDeviceInfo?.Manufacturer ?? info.usbDeviceInfo?.Manufacturer ?? "Android"
            let serial = info.mtpDeviceInfo?.SerialNumber ?? info.usbDeviceInfo?.SerialNumber ?? "MTP-\(abs(model.hashValue))"

            var totalBytes: UInt64 = 0
            var freeBytes: UInt64 = 0
            var usedBytes: UInt64 = 0
            var sdTotal: UInt64? = nil
            var sdFree: UInt64? = nil
            var sdUsed: UInt64? = nil

            let storagesRes = await bridge.fetchStorages()
            if case .success(let storages) = storagesRes, !storages.isEmpty {
                self.availableStorages = storages
                if let first = storages.first {
                    self.cachedStorageId = first.Sid
                    totalBytes = first.Info.safeMaxCapability
                    freeBytes = first.Info.safeFreeSpace
                    usedBytes = totalBytes > freeBytes ? (totalBytes - freeBytes) : 0
                }
                if storages.count > 1 {
                    let second = storages[1]
                    sdTotal = second.Info.safeMaxCapability
                    sdFree = second.Info.safeFreeSpace
                    sdUsed = (sdTotal ?? 0) > (sdFree ?? 0) ? ((sdTotal ?? 0) - (sdFree ?? 0)) : 0
                }
            }

            let dev = AndroidDevice(
                serial: serial,
                model: model,
                manufacturer: manufacturer,
                marketName: model,
                androidVersion: "MTP Media Bridge",
                apiLevel: 34,
                batteryLevel: nil,
                batteryTemperature: nil,
                batteryHealth: nil,
                isCharging: true,
                internalStorageTotal: totalBytes,
                internalStorageUsed: usedBytes,
                internalStorageFree: freeBytes,
                sdCardTotal: sdTotal,
                sdCardUsed: sdUsed,
                sdCardFree: sdFree,
                connectionType: .mtp,
                status: .connected
            )
            return [dev]

        case .failure:
            await invalidateSession()
            return []
        }
    }

    public func queryStorageInfo(serial: String) async -> (total: UInt64, used: UInt64, free: UInt64)? {
        let bridge = MTPBridge.shared
        do {
            try await ensureSession()
        } catch {
            return nil
        }

        let storagesRes = await bridge.fetchStorages()
        if case .success(let storages) = storagesRes, let first = storages.first {
            self.availableStorages = storages
            let total = first.Info.safeMaxCapability
            let free = first.Info.safeFreeSpace
            let used = total > free ? (total - free) : 0
            if total > 0 {
                return (total, used, free)
            }
        }
        return nil
    }

    public func fetchDirectoryContents(serial: String, path: String, showHidden: Bool) async throws -> [AndroidFileItem] {
        let bridge = MTPBridge.shared
        try await ensureSession()

        let normalizedPath = path.isEmpty ? "/" : path
        let walkRes = await bridge.walk(storageId: self.cachedStorageId, fullPath: normalizedPath, recursive: false, skipHidden: !showHidden)

        switch walkRes {
        case .success(let items):
            let isoFormatter = ISO8601DateFormatter()
            return items.map { item in
                let modDate = item.dateAdded.flatMap { isoFormatter.date(from: $0) } ?? Date()
                return AndroidFileItem(
                    name: item.name,
                    remotePath: item.path,
                    sizeBytes: UInt64(max(0, item.size)),
                    modificationDate: modDate,
                    isDirectory: item.isFolder,
                    isHidden: item.name.hasPrefix(".")
                )
            }.sorted {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory && !$1.isDirectory
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }

        case .failure(let error):
            await invalidateSession()
            throw error
        }
    }

    public func createFolder(serial: String, remotePath: String) async throws {
        let bridge = MTPBridge.shared
        try await ensureSession()

        let res = await bridge.makeDirectory(storageId: self.cachedStorageId, fullPath: remotePath)
        switch res {
        case .success:
            break
        case .failure(let err):
            await invalidateSession()
            throw err
        }
    }

    public func renameItem(serial: String, remotePath: String, newName: String) async throws {
        let bridge = MTPBridge.shared
        try await ensureSession()

        let res = await bridge.renameFile(storageId: self.cachedStorageId, fullPath: remotePath, newFileName: newName)
        switch res {
        case .success:
            break
        case .failure(let err):
            await invalidateSession()
            throw err
        }
    }

    public func deleteItems(serial: String, remotePaths: [String]) async throws {
        let bridge = MTPBridge.shared
        try await ensureSession()

        let res = await bridge.deleteFiles(storageId: self.cachedStorageId, files: remotePaths)
        switch res {
        case .success:
            break
        case .failure(let err):
            await invalidateSession()
            throw err
        }
    }

    public func pushFile(serial: String, localPath: String, remotePath: String, onProgress: (@Sendable (Int64, Int64) -> Void)?) async throws {
        let bridge = MTPBridge.shared
        try await ensureSession()

        let destinationDir = (remotePath as NSString).deletingLastPathComponent
        let targetDir = destinationDir.isEmpty ? "/" : destinationDir

        let res = await bridge.uploadFiles(
            storageId: self.cachedStorageId,
            sources: [localPath],
            destination: targetDir,
            onProgress: { sent, total, _ in
                onProgress?(sent, total)
            }
        )
        switch res {
        case .success:
            break
        case .failure(let err):
            await invalidateSession()
            throw err
        }
    }

    public func pullFile(serial: String, remotePath: String, localPath: String, onProgress: (@Sendable (Int64, Int64) -> Void)?) async throws {
        let bridge = MTPBridge.shared
        try await ensureSession()

        let localDir = (localPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: localDir, withIntermediateDirectories: true)

        let res = await bridge.downloadFiles(
            storageId: self.cachedStorageId,
            sources: [remotePath],
            destination: localDir,
            onProgress: { sent, total, _ in
                onProgress?(sent, total)
            }
        )
        switch res {
        case .success:
            break
        case .failure(let err):
            await invalidateSession()
            throw err
        }
    }
}

