//
//  ADBClient.swift
//  LiquidDynamo
//
//  Native, asynchronous, high-performance ADB client for Android file management.
//  Uses Foundation.Process with async/await, full Task cancellation, robust shell escaping,
//  and streaming stdout/stderr parsing.
//

import AppKit
import Foundation

// MARK: - ADB Connection State

public enum ADBConnectionState: Equatable, Sendable {
    case noAdb
    case noDevice
    case unauthorized(serial: String)
    case offline(serial: String)
    case multipleDevices(serials: [String])
    case ready(device: ADBDeviceInfo)
    case error(message: String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var displayText: String {
        switch self {
        case .noAdb:
            return "ADB not found"
        case .noDevice:
            return "No Android device detected"
        case .unauthorized:
            return "Unauthorized — unlock phone and allow USB debugging"
        case .offline:
            return "Device offline"
        case .multipleDevices(let serials):
            return "Multiple devices connected (\(serials.count))"
        case .ready(let dev):
            return dev.model.isEmpty ? dev.serial : dev.model
        case .error(let msg):
            return msg
        }
    }
}

// MARK: - ADB Device Info

public struct ADBDeviceInfo: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { serial }
    public let serial: String
    public let model: String
    public let product: String
    public let device: String
    public let state: String

    public init(serial: String, model: String = "", product: String = "", device: String = "", state: String = "device") {
        self.serial = serial
        self.model = model
        self.product = product
        self.device = device
        self.state = state
    }

    public var displayName: String {
        if !model.isEmpty { return model }
        if !product.isEmpty { return product }
        return serial
    }
}

// MARK: - ADB File Entry

public struct ADBFileEntry: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let symlinkTarget: String?
    public let size: Int64
    public let modificationDate: Date?
    public let permissions: String
    public let isRestrictedScopedStorage: Bool

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        isSymlink: Bool = false,
        symlinkTarget: String? = nil,
        size: Int64 = 0,
        modificationDate: Date? = nil,
        permissions: String = "",
        isRestrictedScopedStorage: Bool = false
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.symlinkTarget = symlinkTarget
        self.size = size
        self.modificationDate = modificationDate
        self.permissions = permissions
        self.isRestrictedScopedStorage = isRestrictedScopedStorage
    }

    public var fileExtension: String {
        guard !isDirectory else { return "" }
        return (name as NSString).pathExtension.lowercased()
    }

    public var isImage: Bool {
        ["jpg", "jpeg", "png", "heic", "webp", "gif", "bmp"].contains(fileExtension)
    }

    public var isVideo: Bool {
        ["mp4", "mkv", "mov", "webm", "avi", "3gp"].contains(fileExtension)
    }

    public var isAudio: Bool {
        ["mp3", "m4a", "flac", "wav", "ogg", "aac", "opus"].contains(fileExtension)
    }

    public var isDocument: Bool {
        ["pdf", "doc", "docx", "txt", "rtf", "xls", "xlsx", "ppt", "pptx", "csv", "json", "xml"].contains(fileExtension)
    }

    public var isApk: Bool {
        fileExtension == "apk"
    }

    public var iconSystemName: String {
        if isDirectory {
            if isRestrictedScopedStorage { return "folder.badge.gearshape" }
            return "folder.fill"
        }
        if isImage { return "photo.fill" }
        if isVideo { return "film.fill" }
        if isAudio { return "music.note" }
        if isDocument { return "doc.text.fill" }
        if isApk { return "shippingbox.fill" }
        return "doc.fill"
    }

    public var systemIconName: String { iconSystemName }
    public var modifiedDate: Date? { modificationDate }
    public var isHidden: Bool { name.hasPrefix(".") }
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Transfer Models

public struct ADBTransferProgress: Sendable {
    public let bytesTransferred: Int64
    public let totalBytes: Int64
    public let percentage: Double
    public let speedBytesPerSecond: Double
    public let currentItemName: String

    public init(
        bytesTransferred: Int64,
        totalBytes: Int64,
        percentage: Double,
        speedBytesPerSecond: Double = 0,
        currentItemName: String = ""
    ) {
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.percentage = percentage
        self.speedBytesPerSecond = speedBytesPerSecond
        self.currentItemName = currentItemName
    }
}

public enum ADBConflictPolicy: Sendable {
    case replace
    case keepBoth
    case skip
}

// MARK: - ADB Client Protocol

public protocol ADBClient: AnyObject, Sendable {
    var adbPath: String? { get }
    var connectionState: ADBConnectionState { get }

    func resolveAdbPath() -> String?
    func refreshConnectionState(targetSerial: String?) async -> ADBConnectionState
    func listDevices() async throws -> [ADBDeviceInfo]
    func listDirectory(serial: String, path: String, showHidden: Bool) async throws -> [ADBFileEntry]
    func makeDirectory(serial: String, path: String) async throws
    func rename(serial: String, oldPath: String, newPath: String) async throws
    func delete(serial: String, path: String) async throws
    func getStorageInfo(serial: String, path: String) async throws -> (total: Int64, free: Int64)
    func pullFile(
        serial: String,
        remotePath: String,
        localURL: URL,
        onProgress: (@Sendable (ADBTransferProgress) -> Void)?
    ) async throws
    func pushFile(
        serial: String,
        localURL: URL,
        remotePath: String,
        conflictPolicy: ADBConflictPolicy,
        onProgress: (@Sendable (ADBTransferProgress) -> Void)?
    ) async throws
}

// MARK: - Shell Safety Utilities

public enum ADBShellSecurity {
    /// Strictly quotes and escapes an untrusted string for execution in POSIX sh / toybox shell.
    /// Uses single-quote encapsulation: enclosing in `'...'` and escaping internal single quotes as `'\''`.
    /// Handles spaces, quotes, unicode, emoji, leading dashes, newlines, semicolons, backticks, dollar signs safely.
    public static func escape(_ string: String) -> String {
        if string.isEmpty {
            return "''"
        }
        let escaped = string.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// Normalizes an Android remote path, removing redundant slashes, trailing slashes,
    /// and standardizing symlinks like /sdcard to /storage/emulated/0 when appropriate.
    public static func normalizeRemotePath(_ path: String) -> String {
        var p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return "/" }
        if !p.hasPrefix("/") { p = "/" + p }

        // Remove duplicate slashes
        while p.contains("//") {
            p = p.replacingOccurrences(of: "//", with: "/")
        }

        if p.count > 1 && p.hasSuffix("/") {
            p = String(p.dropLast())
        }
        return p
    }

    /// Checks if a remote path is under restricted scoped storage on Android 11+
    public static func isScopedStorageRestricted(path: String) -> Bool {
        let norm = normalizeRemotePath(path)
        let restricted = [
            "/Android/data",
            "/Android/obb",
            "/sdcard/Android/data",
            "/sdcard/Android/obb",
            "/storage/emulated/0/Android/data",
            "/storage/emulated/0/Android/obb"
        ]
        return restricted.contains(where: { norm == $0 || norm.hasPrefix($0 + "/") })
    }
}

// MARK: - Robust LS -lA Parser

public enum ADBDirectoryParser {
    private static let monthMap: [String: Int] = [
        "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
        "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12
    ]

    /// Parses output of `ls -lA` across various Android toybox, toolbox, and busybox implementations.
    public static func parseListing(_ output: String, parentPath: String, showHidden: Bool) -> [ADBFileEntry] {
        var entries: [ADBFileEntry] = []
        let lines = output.components(separatedBy: .newlines)
        let normalizedParent = ADBShellSecurity.normalizeRemotePath(parentPath)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("total ") || line.contains("Permission denied") {
                continue
            }

            // Standard toybox `ls -lA` line format:
            // drwxrwx--x  4 root sdcard_rw     4096 2026-10-24 12:30 DCIM
            // -rw-rw----  1 root sdcard_rw 12345678 2026-10-24 12:30 Photo.jpg
            // lrwxrwxrwx  1 root root            21 2026-10-24 12:30 sdcard -> /storage/emulated/0
            // or BSD / older toybox:
            // drwxr-xr-x 2 root root 4096 Oct 24 12:30 Music
            let tokens = line.split(whereSeparator: { $0.isWhitespace })
            guard tokens.count >= 6 else { continue }

            let permissions = String(tokens[0])
            let firstChar = permissions.first ?? "-"
            let isDir = firstChar == "d"
            let isSymlink = firstChar == "l"

            // Look for date tokens (YYYY-MM-DD or Month Day) and size token
            var size: Int64 = 0
            var dateIndex = -1
            var parsedDate: Date? = nil

            for i in 1..<tokens.count {
                let token = String(tokens[i])
                // Match ISO date YYYY-MM-DD
                if token.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
                    dateIndex = i
                    if i > 1, let parsedSize = Int64(tokens[i - 1]) {
                        size = parsedSize
                    }
                    if i + 1 < tokens.count {
                        let timeToken = String(tokens[i + 1])
                        parsedDate = parseISODate(dateStr: token, timeStr: timeToken)
                    }
                    break
                }
                // Match Month name (Jan, Feb, ...)
                if monthMap[token] != nil && i + 1 < tokens.count {
                    dateIndex = i
                    if i > 1, let parsedSize = Int64(tokens[i - 1]) {
                        size = parsedSize
                    }
                    break
                }
            }

            // Extract file name
            var name = ""
            var symlinkTarget: String? = nil

            if dateIndex != -1 && dateIndex + 2 < tokens.count {
                // Name starts after date and time
                let nameStartIndex = (tokens[dateIndex].contains("-")) ? dateIndex + 2 : dateIndex + 3
                if nameStartIndex < tokens.count {
                    let rawNameAndTarget = tokens[nameStartIndex...].joined(separator: " ")
                    if isSymlink && rawNameAndTarget.contains(" -> ") {
                        let parts = rawNameAndTarget.components(separatedBy: " -> ")
                        name = parts[0].trimmingCharacters(in: .whitespaces)
                        symlinkTarget = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
                    } else {
                        name = rawNameAndTarget.trimmingCharacters(in: .whitespaces)
                    }
                }
            } else {
                // Fallback: take last token as name
                name = String(tokens.last!)
            }

            guard !name.isEmpty && name != "." && name != ".." else { continue }
            if !showHidden && name.hasPrefix(".") {
                continue
            }

            let fullRemotePath = normalizedParent == "/" ? "/\(name)" : "\(normalizedParent)/\(name)"
            let isRestricted = ADBShellSecurity.isScopedStorageRestricted(path: fullRemotePath)

            entries.append(ADBFileEntry(
                name: name,
                path: fullRemotePath,
                isDirectory: isDir,
                isSymlink: isSymlink,
                symlinkTarget: symlinkTarget,
                size: size,
                modificationDate: parsedDate,
                permissions: permissions,
                isRestrictedScopedStorage: isRestricted
            ))
        }

        return entries.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private static func parseISODate(dateStr: String, timeStr: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: "\(dateStr) \(timeStr)")
    }
}

// MARK: - Live ADB Client Implementation

public final class LiveADBClient: ADBClient, @unchecked Sendable {
    public static let shared = LiveADBClient()

    private let lock = NSLock()
    private var _adbPath: String? = nil
    private var _connectionState: ADBConnectionState = .noAdb

    public var adbPath: String? {
        lock.lock()
        defer { lock.unlock() }
        return _adbPath
    }

    public var connectionState: ADBConnectionState {
        lock.lock()
        defer { lock.unlock() }
        return _connectionState
    }

    public init() {
        _ = resolveAdbPath()
    }

    // MARK: - ADB Resolution Order (D3)

    public func resolveAdbPath() -> String? {
        lock.lock()
        defer { lock.unlock() }

        // 1. User custom setting override
        let custom = UserDefaults.standard.string(forKey: "android_files_custom_adb_path") ?? ""
        if !custom.isEmpty && FileManager.default.isExecutableFile(atPath: custom) {
            _adbPath = custom
            return custom
        }

        // 2. Setting from FileDroid if configured
        let filedroidPath = UserDefaults.standard.string(forKey: "filedroid_custom_adb_path") ?? ""
        if !filedroidPath.isEmpty && FileManager.default.isExecutableFile(atPath: filedroidPath) {
            _adbPath = filedroidPath
            return filedroidPath
        }

        // 3. Bundled binary inside App bundle
        if let bundlePath = Bundle.main.path(forResource: "adb", ofType: nil),
           FileManager.default.isExecutableFile(atPath: bundlePath) {
            _adbPath = bundlePath
            return bundlePath
        }

        // 4. Standard system & developer tool candidates
        let userHome = NSHomeDirectory()
        let candidates = [
            "\(userHome)/.local/bin/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(userHome)/Library/Android/sdk/platform-tools/adb",
            "/Applications/Android Studio.app/Contents/platform-tools/adb",
            "/opt/android-sdk/platform-tools/adb",
            "/usr/bin/adb"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                _adbPath = path
                return path
            }
        }

        // 5. Environment variable candidate
        if let envSdk = ProcessInfo.processInfo.environment["ANDROID_HOME"] ?? ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"] {
            let p = "\(envSdk)/platform-tools/adb"
            if FileManager.default.isExecutableFile(atPath: p) {
                _adbPath = p
                return p
            }
        }

        _adbPath = nil
        return nil
    }

    // MARK: - Connection State Machine

    @discardableResult
    public func refreshConnectionState(targetSerial: String? = nil) async -> ADBConnectionState {
        guard resolveAdbPath() != nil else {
            let state: ADBConnectionState = .noAdb
            setConnectionState(state)
            return state
        }

        do {
            let devices = try await listDevices()
            if devices.isEmpty {
                let state: ADBConnectionState = .noDevice
                setConnectionState(state)
                return state
            }

            let activeDev: ADBDeviceInfo
            if let target = targetSerial, let found = devices.first(where: { $0.serial == target }) {
                activeDev = found
            } else if let firstDevice = devices.first(where: { $0.state == "device" }) {
                activeDev = firstDevice
            } else {
                activeDev = devices.first!
            }

            let state: ADBConnectionState
            switch activeDev.state {
            case "device":
                state = .ready(device: activeDev)
            case "unauthorized":
                state = .unauthorized(serial: activeDev.serial)
            case "offline":
                state = .offline(serial: activeDev.serial)
            default:
                state = .error(message: "Device in state: \(activeDev.state)")
            }

            setConnectionState(state)
            return state
        } catch {
            let state: ADBConnectionState = .error(message: error.localizedDescription)
            setConnectionState(state)
            return state
        }
    }

    private func setConnectionState(_ state: ADBConnectionState) {
        lock.lock()
        _connectionState = state
        lock.unlock()
    }

    // MARK: - Process Execution Engine

    public func runAdbCommand(arguments: [String], timeout: TimeInterval = 30.0) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        guard let executablePath = resolveAdbPath() else {
            throw NSError(domain: "ADBClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "ADB executable not found."])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            final class TimerBox: @unchecked Sendable {
                var timer: DispatchSourceTimer?
            }
            let box = TimerBox()

            if timeout > 0 {
                let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
                t.schedule(deadline: .now() + timeout)
                t.setEventHandler { [weak process] in
                    process?.terminate()
                }
                t.resume()
                box.timer = t
            }

            process.terminationHandler = { proc in
                box.timer?.cancel()
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""

                continuation.resume(returning: (stdout: outStr, stderr: errStr, exitCode: proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                box.timer?.cancel()
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Device Listing

    public func listDevices() async throws -> [ADBDeviceInfo] {
        let result = try await runAdbCommand(arguments: ["devices", "-l"], timeout: 10.0)
        var devices: [ADBDeviceInfo] = []

        let lines = result.stdout.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("List of devices") || trimmed.hasPrefix("* daemon") {
                continue
            }

            let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 2 else { continue }

            let serial = String(parts[0])
            let state = String(parts[1])

            var model = ""
            var product = ""
            var device = ""

            for part in parts.dropFirst(2) {
                let token = String(part)
                if token.hasPrefix("model:") {
                    model = String(token.dropFirst("model:".count)).replacingOccurrences(of: "_", with: " ")
                } else if token.hasPrefix("product:") {
                    product = String(token.dropFirst("product:".count))
                } else if token.hasPrefix("device:") {
                    device = String(token.dropFirst("device:".count))
                }
            }

            devices.append(ADBDeviceInfo(
                serial: serial,
                model: model,
                product: product,
                device: device,
                state: state
            ))
        }

        return devices
    }

    // MARK: - Directory Listing

    public func listDirectory(serial: String, path: String, showHidden: Bool) async throws -> [ADBFileEntry] {
        let normPath = ADBShellSecurity.normalizeRemotePath(path)
        let escapedPath = ADBShellSecurity.escape(normPath)

        let result = try await runAdbCommand(arguments: ["-s", serial, "shell", "ls -lA \(escapedPath)"], timeout: 25.0)

        if result.exitCode != 0 {
            if result.stderr.contains("Permission denied") || result.stdout.contains("Permission denied") {
                if ADBShellSecurity.isScopedStorageRestricted(path: normPath) {
                    throw NSError(
                        domain: "ADBClient",
                        code: 403,
                        userInfo: [NSLocalizedDescriptionKey: "Access to '\(normPath)' is restricted by Android 11+ scoped storage."]
                    )
                }
                throw NSError(domain: "ADBClient", code: 403, userInfo: [NSLocalizedDescriptionKey: "Permission denied accessing folder."])
            }
            if result.stderr.contains("No such file") {
                throw NSError(domain: "ADBClient", code: 404, userInfo: [NSLocalizedDescriptionKey: "Directory does not exist."])
            }
        }

        return ADBDirectoryParser.parseListing(result.stdout, parentPath: normPath, showHidden: showHidden)
    }

    // MARK: - File Operations

    public func makeDirectory(serial: String, path: String) async throws {
        let escaped = ADBShellSecurity.escape(ADBShellSecurity.normalizeRemotePath(path))
        let res = try await runAdbCommand(arguments: ["-s", serial, "shell", "mkdir -p \(escaped)"], timeout: 15.0)
        guard res.exitCode == 0 else {
            throw NSError(domain: "ADBClient", code: Int(res.exitCode), userInfo: [NSLocalizedDescriptionKey: res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
    }

    public func rename(serial: String, oldPath: String, newPath: String) async throws {
        let escOld = ADBShellSecurity.escape(ADBShellSecurity.normalizeRemotePath(oldPath))
        let escNew = ADBShellSecurity.escape(ADBShellSecurity.normalizeRemotePath(newPath))
        let res = try await runAdbCommand(arguments: ["-s", serial, "shell", "mv \(escOld) \(escNew)"], timeout: 15.0)
        guard res.exitCode == 0 else {
            throw NSError(domain: "ADBClient", code: Int(res.exitCode), userInfo: [NSLocalizedDescriptionKey: res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
    }

    public func delete(serial: String, path: String) async throws {
        let escaped = ADBShellSecurity.escape(ADBShellSecurity.normalizeRemotePath(path))
        let res = try await runAdbCommand(arguments: ["-s", serial, "shell", "rm -rf \(escaped)"], timeout: 20.0)
        guard res.exitCode == 0 else {
            throw NSError(domain: "ADBClient", code: Int(res.exitCode), userInfo: [NSLocalizedDescriptionKey: res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
    }

    public func getStorageInfo(serial: String, path: String = "/sdcard") async throws -> (total: Int64, free: Int64) {
        let escaped = ADBShellSecurity.escape(ADBShellSecurity.normalizeRemotePath(path))
        let res = try await runAdbCommand(arguments: ["-s", serial, "shell", "df -k \(escaped)"], timeout: 10.0)
        guard res.exitCode == 0 else {
            return (0, 0)
        }

        let lines = res.stdout.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return (0, 0) }

        // Format: Filesystem 1K-blocks Used Available Use% Mounted on
        let parts = lines[1].split(whereSeparator: { $0.isWhitespace })
        if parts.count >= 4,
           let totalKb = Int64(parts[1]),
           let availKb = Int64(parts[3]) {
            return (totalKb * 1024, availKb * 1024)
        }

        return (0, 0)
    }

    // MARK: - Pull & Push File Transfers with Progress Monitoring

    public func pullFile(
        serial: String,
        remotePath: String,
        localURL: URL,
        onProgress: (@Sendable (ADBTransferProgress) -> Void)?
    ) async throws {
        let remoteNorm = ADBShellSecurity.normalizeRemotePath(remotePath)
        let localPath = localURL.path

        // Check remote file size first for progress calculation
        var expectedBytes: Int64 = 0
        let statRes = try? await runAdbCommand(arguments: ["-s", serial, "shell", "stat -c %s \(ADBShellSecurity.escape(remoteNorm))"], timeout: 5.0)
        if let s = statRes?.stdout.trimmingCharacters(in: .whitespacesAndNewlines), let b = Int64(s) {
            expectedBytes = b
        }

        // Temporary download file for atomic completion
        let tempDownloadURL = localURL.appendingPathExtension("downloading_\(UUID().uuidString.prefix(6))")
        defer {
            try? FileManager.default.removeItem(at: tempDownloadURL)
        }

        let finalBytes = expectedBytes
        guard let executablePath = resolveAdbPath() else {
            throw NSError(domain: "ADBClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "ADB not found."])
        }

        let startTime = Date()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["-s", serial, "pull", remoteNorm, tempDownloadURL.path]

            let errPipe = Pipe()
            process.standardError = errPipe

            let progressTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            if finalBytes > 0 && onProgress != nil {
                progressTimer.schedule(deadline: .now() + 0.25, repeating: 0.25)
                progressTimer.setEventHandler {
                    guard let attrs = try? FileManager.default.attributesOfItem(atPath: tempDownloadURL.path),
                          let currentSize = attrs[.size] as? Int64 else { return }

                    let elapsed = max(0.1, Date().timeIntervalSince(startTime))
                    let speed = Double(currentSize) / elapsed
                    let pct = min(1.0, Double(currentSize) / Double(finalBytes))

                    onProgress?(ADBTransferProgress(
                        bytesTransferred: currentSize,
                        totalBytes: finalBytes,
                        percentage: pct,
                        speedBytesPerSecond: speed,
                        currentItemName: (remoteNorm as NSString).lastPathComponent
                    ))
                }
                progressTimer.resume()
            }

            process.terminationHandler = { proc in
                progressTimer.cancel()

                if proc.terminationStatus == 0 {
                    do {
                        if FileManager.default.fileExists(atPath: localPath) {
                            try FileManager.default.removeItem(at: localURL)
                        }
                        try FileManager.default.moveItem(at: tempDownloadURL, to: localURL)
                        onProgress?(ADBTransferProgress(
                            bytesTransferred: finalBytes,
                            totalBytes: finalBytes,
                            percentage: 1.0,
                            speedBytesPerSecond: 0,
                            currentItemName: (remoteNorm as NSString).lastPathComponent
                        ))
                        continuation.resume(returning: ())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? "Transfer failed"
                    continuation.resume(throwing: NSError(domain: "ADBClient", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errStr]))
                }
            }

            do {
                try process.run()
            } catch {
                progressTimer.cancel()
                continuation.resume(throwing: error)
            }
        }
    }

    public func pushFile(
        serial: String,
        localURL: URL,
        remotePath: String,
        conflictPolicy: ADBConflictPolicy = .replace,
        onProgress: (@Sendable (ADBTransferProgress) -> Void)?
    ) async throws {
        var remoteNorm = ADBShellSecurity.normalizeRemotePath(remotePath)
        let localPath = localURL.path

        guard FileManager.default.fileExists(atPath: localPath) else {
            throw NSError(domain: "ADBClient", code: 404, userInfo: [NSLocalizedDescriptionKey: "Local file does not exist."])
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: localPath)
        let fileSize = (attrs?[.size] as? Int64) ?? 0

        // Handle conflict policy
        if conflictPolicy == .skip {
            let checkRes = try? await runAdbCommand(arguments: ["-s", serial, "shell", "test -e \(ADBShellSecurity.escape(remoteNorm)) && echo EXISTS"], timeout: 5.0)
            if checkRes?.stdout.contains("EXISTS") == true {
                return
            }
        } else if conflictPolicy == .keepBoth {
            let checkRes = try? await runAdbCommand(arguments: ["-s", serial, "shell", "test -e \(ADBShellSecurity.escape(remoteNorm)) && echo EXISTS"], timeout: 5.0)
            if checkRes?.stdout.contains("EXISTS") == true {
                let dir = (remoteNorm as NSString).deletingLastPathComponent
                let filename = (remoteNorm as NSString).lastPathComponent
                let ext = (filename as NSString).pathExtension
                let base = (filename as NSString).deletingPathExtension
                let newName = "\(base) (1)\(ext.isEmpty ? "" : ".\(ext)")"
                remoteNorm = dir == "/" ? "/\(newName)" : "\(dir)/\(newName)"
            }
        }

        guard let executablePath = resolveAdbPath() else {
            throw NSError(domain: "ADBClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "ADB not found."])
        }

        let startTime = Date()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["-s", serial, "push", localPath, remoteNorm]

            let errPipe = Pipe()
            process.standardError = errPipe

            let progressTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            if fileSize > 0 && onProgress != nil {
                progressTimer.schedule(deadline: .now() + 0.3, repeating: 0.3)
                progressTimer.setEventHandler {
                    // Estimate upload progress over time based on duration
                    let elapsed = max(0.1, Date().timeIntervalSince(startTime))
                    let estBytes = min(fileSize, Int64(Double(fileSize) * min(0.95, elapsed / max(1.0, Double(fileSize) / 25_000_000.0))))
                    let speed = Double(estBytes) / elapsed
                    let pct = Double(estBytes) / Double(fileSize)

                    onProgress?(ADBTransferProgress(
                        bytesTransferred: estBytes,
                        totalBytes: fileSize,
                        percentage: pct,
                        speedBytesPerSecond: speed,
                        currentItemName: localURL.lastPathComponent
                    ))
                }
                progressTimer.resume()
            }

            process.terminationHandler = { proc in
                progressTimer.cancel()

                if proc.terminationStatus == 0 {
                    onProgress?(ADBTransferProgress(
                        bytesTransferred: fileSize,
                        totalBytes: fileSize,
                        percentage: 1.0,
                        speedBytesPerSecond: 0,
                        currentItemName: localURL.lastPathComponent
                    ))
                    continuation.resume(returning: ())
                } else {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? "Upload failed"
                    continuation.resume(throwing: NSError(domain: "ADBClient", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errStr]))
                }
            }

            do {
                try process.run()
            } catch {
                progressTimer.cancel()
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - In-Memory Fake ADB Client (for Tests & Previewing)

public final class FakeADBClient: ADBClient, @unchecked Sendable {
    public var adbPath: String? = "/fake/bin/adb"
    public var connectionState: ADBConnectionState

    private var virtualFileSystem: [String: [ADBFileEntry]] = [:]
    private let queue = DispatchQueue(label: "com.liquiddynamo.fakeadb", attributes: .concurrent)

    public init(initialState: ADBConnectionState? = nil) {
        if let st = initialState {
            self.connectionState = st
        } else {
            let dev = ADBDeviceInfo(serial: "ZY22G8K99L", model: "motorola edge 50", product: "motorola", device: "edge50", state: "device")
            self.connectionState = .ready(device: dev)
        }
        setupMockHierarchy()
    }

    private func setupMockHierarchy() {
        let rootItems: [ADBFileEntry] = [
            ADBFileEntry(name: "DCIM", path: "/sdcard/DCIM", isDirectory: true),
            ADBFileEntry(name: "Pictures", path: "/sdcard/Pictures", isDirectory: true),
            ADBFileEntry(name: "Download", path: "/sdcard/Download", isDirectory: true),
            ADBFileEntry(name: "Documents", path: "/sdcard/Documents", isDirectory: true),
            ADBFileEntry(name: "Movies", path: "/sdcard/Movies", isDirectory: true),
            ADBFileEntry(name: "Music", path: "/sdcard/Music", isDirectory: true),
            ADBFileEntry(name: "WhatsApp", path: "/sdcard/WhatsApp", isDirectory: true),
            ADBFileEntry(name: "Android", path: "/sdcard/Android", isDirectory: true)
        ]
        virtualFileSystem["/sdcard"] = rootItems
        virtualFileSystem["/storage/emulated/0"] = rootItems

        let dcimItems: [ADBFileEntry] = [
            ADBFileEntry(name: "Camera", path: "/sdcard/DCIM/Camera", isDirectory: true),
            ADBFileEntry(name: "Screenshots", path: "/sdcard/DCIM/Screenshots", isDirectory: true),
            ADBFileEntry(name: "IMG_20261024_001.jpg", path: "/sdcard/DCIM/IMG_20261024_001.jpg", isDirectory: false, size: 4_250_000),
            ADBFileEntry(name: "VID_20261024_002.mp4", path: "/sdcard/DCIM/VID_20261024_002.mp4", isDirectory: false, size: 45_800_000)
        ]
        virtualFileSystem["/sdcard/DCIM"] = dcimItems

        let downloadItems: [ADBFileEntry] = [
            ADBFileEntry(name: "Specification_v2.pdf", path: "/sdcard/Download/Specification_v2.pdf", isDirectory: false, size: 1_250_000),
            ADBFileEntry(name: "App_Release.apk", path: "/sdcard/Download/App_Release.apk", isDirectory: false, size: 18_400_000),
            ADBFileEntry(name: "archive.zip", path: "/sdcard/Download/archive.zip", isDirectory: false, size: 8_100_000)
        ]
        virtualFileSystem["/sdcard/Download"] = downloadItems
    }

    public func resolveAdbPath() -> String? { adbPath }

    public func refreshConnectionState(targetSerial: String?) async -> ADBConnectionState {
        return connectionState
    }

    public func listDevices() async throws -> [ADBDeviceInfo] {
        if case .ready(let dev) = connectionState {
            return [dev]
        }
        return []
    }

    public func listDirectory(serial: String, path: String, showHidden: Bool) async throws -> [ADBFileEntry] {
        let norm = ADBShellSecurity.normalizeRemotePath(path)
        if ADBShellSecurity.isScopedStorageRestricted(path: norm) {
            throw NSError(domain: "FakeADBClient", code: 403, userInfo: [NSLocalizedDescriptionKey: "Restricted by Android 11+ scoped storage."])
        }

        return queue.sync {
            let items = virtualFileSystem[norm] ?? []
            return showHidden ? items : items.filter { !$0.name.hasPrefix(".") }
        }
    }

    public func makeDirectory(serial: String, path: String) async throws {
        let norm = ADBShellSecurity.normalizeRemotePath(path)
        let parent = (norm as NSString).deletingLastPathComponent
        let name = (norm as NSString).lastPathComponent
        let newEntry = ADBFileEntry(name: name, path: norm, isDirectory: true)

        queue.sync(flags: .barrier) {
            var list = virtualFileSystem[parent] ?? []
            list.append(newEntry)
            virtualFileSystem[parent] = list
            virtualFileSystem[norm] = []
        }
    }

    public func rename(serial: String, oldPath: String, newPath: String) async throws {
        let oldNorm = ADBShellSecurity.normalizeRemotePath(oldPath)
        let newNorm = ADBShellSecurity.normalizeRemotePath(newPath)
        let parent = (oldNorm as NSString).deletingLastPathComponent
        let newName = (newNorm as NSString).lastPathComponent

        queue.sync(flags: .barrier) {
            if var list = virtualFileSystem[parent] {
                if let idx = list.firstIndex(where: { $0.path == oldNorm }) {
                    let old = list[idx]
                    list[idx] = ADBFileEntry(name: newName, path: newNorm, isDirectory: old.isDirectory, size: old.size)
                    virtualFileSystem[parent] = list
                }
            }
        }
    }

    public func delete(serial: String, path: String) async throws {
        let norm = ADBShellSecurity.normalizeRemotePath(path)
        let parent = (norm as NSString).deletingLastPathComponent
        queue.sync(flags: .barrier) {
            if var list = virtualFileSystem[parent] {
                list.removeAll(where: { $0.path == norm })
                virtualFileSystem[parent] = list
            }
            virtualFileSystem.removeValue(forKey: norm)
        }
    }

    public func getStorageInfo(serial: String, path: String) async throws -> (total: Int64, free: Int64) {
        return (256_000_000_000, 118_400_000_000)
    }

    public func pullFile(
        serial: String,
        remotePath: String,
        localURL: URL,
        onProgress: (@Sendable (ADBTransferProgress) -> Void)?
    ) async throws {
        try? "Fake downloaded content from \(remotePath)".write(to: localURL, atomically: true, encoding: .utf8)
        onProgress?(ADBTransferProgress(bytesTransferred: 100, totalBytes: 100, percentage: 1.0, currentItemName: localURL.lastPathComponent))
    }

    public func pushFile(
        serial: String,
        localURL: URL,
        remotePath: String,
        conflictPolicy: ADBConflictPolicy,
        onProgress: (@Sendable (ADBTransferProgress) -> Void)?
    ) async throws {
        let norm = ADBShellSecurity.normalizeRemotePath(remotePath)
        let parent = (norm as NSString).deletingLastPathComponent
        let name = (norm as NSString).lastPathComponent
        let entry = ADBFileEntry(name: name, path: norm, isDirectory: false, size: 50_000)

        queue.sync(flags: .barrier) {
            var list = virtualFileSystem[parent] ?? []
            list.append(entry)
            virtualFileSystem[parent] = list
        }

        onProgress?(ADBTransferProgress(bytesTransferred: 50_000, totalBytes: 50_000, percentage: 1.0, currentItemName: name))
    }
}
