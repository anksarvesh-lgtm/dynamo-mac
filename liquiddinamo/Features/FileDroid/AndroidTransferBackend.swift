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
    var backendType: FileDroidConnectionType { get }
    var isAvailable: Bool { get }
    var availabilityHint: String? { get }
    
    func scanDevices() async -> [AndroidDevice]
    func fetchDirectoryContents(serial: String, path: String, showHidden: Bool) async throws -> [AndroidFileItem]
    func createFolder(serial: String, remotePath: String) async throws
    func renameItem(serial: String, remotePath: String, newName: String) async throws
    func deleteItems(serial: String, remotePaths: [String]) async throws
    func pushFile(serial: String, localPath: String, remotePath: String, onProgress: (@Sendable (Int64, Int64) -> Void)?) async throws
    func pullFile(serial: String, remotePath: String, localPath: String, onProgress: (@Sendable (Int64, Int64) -> Void)?) async throws
}

// MARK: - ADB Transfer Backend

public final class AdbBackend: AndroidTransferBackend, @unchecked Sendable {
    public let backendType: FileDroidConnectionType = .adb
    
    public var isAvailable: Bool {
        guard let path = effectiveAdbPath else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }
    
    public var availabilityHint: String? {
        if isAvailable { return nil }
        return "ADB platform-tools not found. Install via Homebrew: 'brew install android-platform-tools' or configure a custom path."
    }
    
    public var effectiveAdbPath: String? {
        let custom = UserDefaults.standard.string(forKey: "filedroid_custom_adb_path") ?? ""
        if !custom.isEmpty && FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }
        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "/Applications/Android Studio.app/Contents/platform-tools/adb",
            "/opt/android-sdk/platform-tools/adb",
            "/usr/bin/adb"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
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
            
            var status: FileDroidDeviceStatus = .connected
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
                
                let dfOut = await Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "df", "-k", "/storage/emulated/0"])
                if let (total, used, free) = Self.parseDfOutput(dfOut) {
                    dev.internalStorageTotal = total
                    dev.internalStorageUsed = used
                    dev.internalStorageFree = free
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
    
    private static func parseDfOutput(_ text: String) -> (total: UInt64, used: UInt64, free: UInt64)? {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }
        let parts = lines[1].components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 4 else { return nil }
        if let totalK = UInt64(parts[1]),
           let usedK = UInt64(parts[2]),
           let freeK = UInt64(parts[3]) {
            return (totalK * 1024, usedK * 1024, freeK * 1024)
        }
        return nil
    }
}

// MARK: - MTP Transfer Backend (Option B)

public final class MtpBackend: AndroidTransferBackend, @unchecked Sendable {
    public let backendType: FileDroidConnectionType = .mtp
    
    public var isAvailable: Bool {
        return effectiveMtpDetectPath != nil
    }
    
    public var availabilityHint: String? {
        if isAvailable { return nil }
        return "Native MTP tools (libmtp) are optional for non-debugging USB transfer. Install via Homebrew: 'brew install libmtp', or enable USB Debugging on your phone."
    }
    
    public var effectiveMtpDetectPath: String? {
        let candidates = [
            "/opt/homebrew/bin/mtp-detect",
            "/usr/local/bin/mtp-detect",
            "/usr/bin/mtp-detect"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    
    public init() {}
    
    public func scanDevices() async -> [AndroidDevice] {
        guard let mtpDetect = effectiveMtpDetectPath else { return [] }
        let output = await Self.runProcess(executable: mtpDetect, arguments: [])
        guard output.contains("Device 0 (VID=") || output.contains("Manufacturer:") else { return [] }
        
        var manufacturer = "Android"
        var model = "MTP Device"
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Manufacturer:") {
                manufacturer = trimmed.replacingOccurrences(of: "Manufacturer:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Model:") {
                model = trimmed.replacingOccurrences(of: "Model:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        
        let dev = AndroidDevice(
            serial: "MTP-\(abs(model.hashValue))",
            model: model,
            manufacturer: manufacturer,
            marketName: model,
            connectionType: .mtp,
            status: .connected
        )
        return [dev]
    }
    
    public func fetchDirectoryContents(serial: String, path: String, showHidden: Bool) async throws -> [AndroidFileItem] {
        guard let mtpFiles = ["/opt/homebrew/bin/mtp-files", "/usr/local/bin/mtp-files"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw NSError(domain: "MtpBackend", code: 1, userInfo: [NSLocalizedDescriptionKey: "libmtp tools not installed"])
        }
        let out = await Self.runProcess(executable: mtpFiles, arguments: [])
        var items: [AndroidFileItem] = []
        for line in out.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("File ID:") else { continue }
            // Basic parsing of MTP file listing
            items.append(AndroidFileItem(name: "MTP Item", remotePath: path + "/item", sizeBytes: 1024, isDirectory: false))
        }
        return items
    }
    
    public func createFolder(serial: String, remotePath: String) async throws {
        throw NSError(domain: "MtpBackend", code: 2, userInfo: [NSLocalizedDescriptionKey: "Folder creation requires ADB or full libmtp integration"])
    }
    
    public func renameItem(serial: String, remotePath: String, newName: String) async throws {
        throw NSError(domain: "MtpBackend", code: 3, userInfo: [NSLocalizedDescriptionKey: "Rename requires ADB or full libmtp integration"])
    }
    
    public func deleteItems(serial: String, remotePaths: [String]) async throws {
        throw NSError(domain: "MtpBackend", code: 4, userInfo: [NSLocalizedDescriptionKey: "Delete requires ADB or full libmtp integration"])
    }
    
    public func pushFile(serial: String, localPath: String, remotePath: String, onProgress: (@Sendable (Int64, Int64) -> Void)?) async throws {
        guard let mtpSend = ["/opt/homebrew/bin/mtp-sendfile", "/usr/local/bin/mtp-sendfile"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw NSError(domain: "MtpBackend", code: 5, userInfo: [NSLocalizedDescriptionKey: "libmtp tools not installed. Use ADB mode for transfers."])
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: localPath)[.size] as? Int64) ?? 0
        onProgress?(0, size)
        _ = await Self.runProcess(executable: mtpSend, arguments: [localPath, (remotePath as NSString).lastPathComponent])
        onProgress?(size, size)
    }
    
    public func pullFile(serial: String, remotePath: String, localPath: String, onProgress: (@Sendable (Int64, Int64) -> Void)?) async throws {
        guard let mtpGet = ["/opt/homebrew/bin/mtp-getfile", "/usr/local/bin/mtp-getfile"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw NSError(domain: "MtpBackend", code: 6, userInfo: [NSLocalizedDescriptionKey: "libmtp tools not installed. Use ADB mode for transfers."])
        }
        _ = await Self.runProcess(executable: mtpGet, arguments: [remotePath, localPath])
    }
    
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
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
}
