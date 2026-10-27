//
//  MTPBridge.swift
//  LiquidDynamo
//
//  Native Swift C-FFI bridge to OpenMTP's high-performance Kalam MTP engine.
//  Uses an asynchronous FIFO stream queue with dynamic transfer timeouts,
//  thread-safe execution, strict Codable envelope validation,
//  robust dylib loading, process conflict resolution, and comprehensive error mapping.
//

import AppKit
import Darwin
import Foundation

public typealias MTPCallbackFn = @convention(c) (UnsafePointer<CChar>?) -> Void

// MARK: - OpenMTP Error Mapping

public enum MTPErrorMapper {
    public static func resolveMessage(error: String?, errorType: String?) -> String {
        if let errorType = errorType, !errorType.isEmpty {
            switch errorType {
            case "ErrorMtpDetectFailed":
                return "No Android MTP device found. Connect phone via USB and select 'File Transfer / Android Auto' on phone."
            case "ErrorDeviceLocked":
                return "Your phone screen is locked. Please unlock your phone and tap Refresh."
            case "ErrorAllowStorageAccess":
                return "Please tap 'Allow access to phone data' or 'Accept' on your Android screen."
            case "ErrorMtpLockExists":
                return "Android device is busy with another transfer. Please wait a moment."
            case "ErrorMultipleDevice":
                return "Multiple MTP devices found. Please disconnect extra phones."
            case "ErrorStorageFull":
                return "Device storage is full."
            case "ErrorNoStorage":
                return "Phone storage is inaccessible. Ensure phone is unlocked."
            case "ErrorStorageInfo":
                return "Unable to read phone storage info. Reconnect USB cable."
            case "ErrorDeviceInfo":
                return "Unable to read phone device info."
            case "ErrorListDirectory":
                return "Unable to read phone folder contents. Tap Refresh."
            case "ErrorFileNotFound":
                return "The requested file or folder was not found on device."
            case "ErrorFilePermission":
                return "Permission denied by Android system."
            case "ErrorFileTransfer":
                return "An error occurred during file transfer. Check USB cable."
            case "ErrorSendObject":
                return "Failed to send file object to Android device."
            case "ErrorFileObjectRead":
                return "Failed to read file from Android device."
            case "ErrorInvalidPath":
                return "Invalid remote directory path."
            case "ErrorDeviceSetup":
                return "Failed to configure MTP USB interface."
            case "ErrorDeviceChanged":
                return "USB connection changed. Reconnecting…"
            default:
                break
            }
        }
        if let err = error, !err.isEmpty {
            return err
        }
        if let errType = errorType, !errType.isEmpty {
            return errType
        }
        return "Unknown MTP communication error"
    }
}

// MARK: - OpenMTP USB Process Conflict Resolver

public enum MTPProcessConflictResolver {
    public static let conflictingProcessNames: [String] = [
        "Android File Transfer",
        "Android File Transfer Agent",
        "AndroidFileTransferAgent"
    ]

    public static func findRunningConflictingProcesses() -> [String] {
        var found: [String] = []
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            if let name = app.localizedName {
                for conflict in conflictingProcessNames {
                    if name.localizedCaseInsensitiveContains(conflict) {
                        found.append(name)
                    }
                }
            }
        }

        // Also check ps aux for background agents
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ax", "-o", "comm="]
        process.standardOutput = pipe
        process.standardError = Pipe()
        if (try? process.run()) != nil {
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lower = output.lowercased()
                if lower.contains("android file transfer") || lower.contains("androidfiletransferagent") {
                    if !found.contains("Android File Transfer Agent") {
                        found.append("Android File Transfer Agent")
                    }
                }
            }
        }
        return Array(Set(found))
    }

    @discardableResult
    public static func terminateConflictingProcesses() -> Bool {
        var killedAny = false
        for app in NSWorkspace.shared.runningApplications {
            guard let name = app.localizedName else { continue }
            if name.localizedCaseInsensitiveContains("Android File Transfer") {
                app.terminate()
                killedAny = true
            }
        }

        let targets = ["Android File Transfer", "Android File Transfer Agent", "AndroidFileTransferAgent"]
        for target in targets {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            proc.arguments = ["-9", target]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            if (try? proc.run()) != nil {
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    killedAny = true
                }
            }
        }
        return killedAny
    }
}

// MARK: - MTP Data Transfer Models & Envelopes

public struct MTPResponse<T: Codable>: Codable {
    public let errorType: String?
    public let error: String?
    public let data: T?

    public var hasError: Bool {
        if let err = error, !err.isEmpty { return true }
        if let errType = errorType, !errType.isEmpty { return true }
        return false
    }

    public var resolvedErrorMessage: String {
        MTPErrorMapper.resolveMessage(error: error, errorType: errorType)
    }
}

public struct MTPBoolResponse: Codable {
    public let errorType: String?
    public let error: String?
    public let data: Bool?

    public var hasError: Bool {
        if let err = error, !err.isEmpty { return true }
        if let errType = errorType, !errType.isEmpty { return true }
        return false
    }

    public var resolvedErrorMessage: String {
        MTPErrorMapper.resolveMessage(error: error, errorType: errorType)
    }
}

public struct MTPEmptyData: Codable {}

public struct MTPDeviceInfoData: Codable {
    public let mtpDeviceInfo: MTPMtpDeviceInfo?
    public let usbDeviceInfo: MTPUsbDeviceInfo?
}

public struct MTPMtpDeviceInfo: Codable {
    public let Manufacturer: String?
    public let Model: String?
    public let SerialNumber: String?
    public let DeviceVersion: String?
}

public struct MTPUsbDeviceInfo: Codable {
    public let IdVendor: UInt32?
    public let IdProduct: UInt32?
    public let Manufacturer: String?
    public let Product: String?
    public let SerialNumber: String?
}

public struct MTPStorageItem: Codable, Identifiable {
    public var id: UInt32 { Sid }
    public let Sid: UInt32
    public let Info: MTPStorageDetail
}

public struct MTPStorageDetail: Codable {
    public let StorageType: UInt16?
    public let FilesystemType: UInt16?
    public let AccessCapability: UInt16?
    public let MaxCapability: UInt64?
    public let FreeSpaceInBytes: UInt64?
    public let StorageDescription: String?
    public let VolumeLabel: String?

    public var effectiveDescription: String {
        if let desc = StorageDescription, !desc.isEmpty { return desc }
        if let label = VolumeLabel, !label.isEmpty { return label }
        return "Internal Storage"
    }

    public var safeMaxCapability: UInt64 { MaxCapability ?? 0 }
    public var safeFreeSpace: UInt64 { FreeSpaceInBytes ?? 0 }
}

public struct MTPWalkItem: Codable, Identifiable {
    public var id: String { path }
    public let size: Int64
    public let isFolder: Bool
    public let dateAdded: String?
    public let name: String
    public let path: String
    public let parentPath: String?
    public let `extension`: String?
    public let parentId: UInt32?
    public let objectId: UInt32?
}

public struct MTPFileExistsItem: Codable {
    public let fullpath: String
    public let exists: Bool
}

public struct MTPTransferSizeInfo: Codable {
    public let total: Int64?
    public let sent: Int64?
    public let progress: Double?
}

public struct MTPProgressPayload: Codable {
    public let fullPath: String?
    public let name: String?
    public let elapsedTime: Int64?
    public let speed: Double?
    public let totalFiles: Int64?
    public let totalDirectories: Int64?
    public let filesSent: Int64?
    public let filesSentProgress: Double?
    public let activeFileSize: MTPTransferSizeInfo?
    public let bulkFileSize: MTPTransferSizeInfo?
    public let status: Int?
}

public enum MTPError: LocalizedError, Equatable {
    case dylibNotLoaded
    case unsupportedArchitecture
    case timeout
    case bridgeError(String)
    case invalidArguments
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .dylibNotLoaded:
            return "Native OpenMTP kalam.dylib is not loaded."
        case .unsupportedArchitecture:
            return "Native MTP bridge is unavailable on Intel Macs (Apple Silicon required)."
        case .timeout:
            return "MTP operation timed out."
        case .bridgeError(let msg):
            return msg
        case .invalidArguments:
            return "Invalid MTP request arguments."
        case .decodingFailed(let msg):
            return "Failed to decode MTP engine response: \(msg)"
        }
    }
}

// MARK: - Serial AsyncStream FIFO Request Queue

public final class MTPRequestQueue: @unchecked Sendable {
    private struct Operation: Sendable {
        let timeoutSeconds: TimeInterval
        let invoking: @Sendable () -> Void
        let completion: @Sendable (Result<String, Error>) -> Void
    }

    private let streamContinuation: AsyncStream<Operation>.Continuation
    private static var activeCallback: (@Sendable (String) -> Void)?
    private static var lastProgressTimestamp: Date = Date()
    private static let callbackLock = NSLock()

    public init() {
        var capturedContinuation: AsyncStream<Operation>.Continuation!
        let stream = AsyncStream<Operation> { continuation in
            capturedContinuation = continuation
        }
        self.streamContinuation = capturedContinuation

        Task.detached(priority: .userInitiated) {
            for await op in stream {
                await Self.processOperation(op)
            }
        }
    }

    public static func reportProgressActivity() {
        callbackLock.lock()
        lastProgressTimestamp = Date()
        callbackLock.unlock()
    }

    private static func processOperation(_ op: Operation) async {
        await withCheckedContinuation { (stepDone: CheckedContinuation<Void, Never>) in
            var hasResumed = false
            let resumeLock = NSLock()
            var timeoutTask: Task<Void, Never>? = nil

            let finishOnce: @Sendable (Result<String, Error>) -> Void = { result in
                resumeLock.lock()
                guard !hasResumed else {
                    resumeLock.unlock()
                    return
                }
                hasResumed = true
                timeoutTask?.cancel()

                callbackLock.lock()
                activeCallback = nil
                callbackLock.unlock()
                resumeLock.unlock()

                op.completion(result)
                stepDone.resume()
            }

            callbackLock.lock()
            activeCallback = { json in
                finishOnce(.success(json))
            }
            lastProgressTimestamp = Date()
            callbackLock.unlock()

            timeoutTask = Task {
                let start = Date()
                let totalAllowed = op.timeoutSeconds
                while Date().timeIntervalSince(start) < totalAllowed && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)

                    // If progress was active recently (within 20s), keep alive
                    callbackLock.lock()
                    let recentProgress = Date().timeIntervalSince(lastProgressTimestamp) < 20.0
                    callbackLock.unlock()

                    if recentProgress && totalAllowed > 30.0 {
                        // Transfer is actively moving, continue waiting
                        continue
                    }
                }
                if !Task.isCancelled {
                    finishOnce(.failure(MTPError.timeout))
                }
            }

            op.invoking()
        }
    }

    public static func handleCCallback(json: String) {
        callbackLock.lock()
        let cb = activeCallback
        callbackLock.unlock()
        cb?(json)
    }

    public func execute(
        timeoutSeconds: TimeInterval = 15.0,
        invoking: @Sendable @escaping () -> Void
    ) async -> Result<String, Error> {
        await withCheckedContinuation { (callerContinuation: CheckedContinuation<Result<String, Error>, Never>) in
            let op = Operation(
                timeoutSeconds: timeoutSeconds,
                invoking: invoking,
                completion: { result in
                    callerContinuation.resume(returning: result)
                }
            )
            self.streamContinuation.yield(op)
        }
    }
}

// MARK: - MTP Bridge Engine

public final class MTPBridge: @unchecked Sendable {
    public static let shared = MTPBridge()

    #if arch(x86_64)
    public static let isSupportedArchitecture = false
    #else
    public static let isSupportedArchitecture = true
    #endif

    public let queue = MTPRequestQueue()
    private var dylibHandle: UnsafeMutableRawPointer?

    private var initFn: (@convention(c) (UnsafeRawPointer) -> Void)?
    private var fetchDeviceInfoFn: (@convention(c) (UnsafeRawPointer) -> Void)?
    private var fetchStoragesFn: (@convention(c) (UnsafeRawPointer) -> Void)?
    private var makeDirectoryFn: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer) -> Void)?
    private var fileExistsFn: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer) -> Void)?
    private var deleteFileFn: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer) -> Void)?
    private var renameFileFn: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer) -> Void)?
    private var walkFn: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer) -> Void)?
    private var uploadFilesFn: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer, UnsafeRawPointer, UnsafeRawPointer) -> Void)?
    private var downloadFilesFn: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer, UnsafeRawPointer, UnsafeRawPointer) -> Void)?
    private var disposeFn: (@convention(c) (UnsafeRawPointer) -> Void)?

    private static var activeProgressHandler: (@Sendable (Int64, Int64, Double) -> Void)?
    private static let progressLock = NSLock()

    private static let cDoneCallback: MTPCallbackFn = { jsonPtr in
        guard let jsonPtr = jsonPtr else {
            MTPRequestQueue.handleCCallback(json: "{\"error\":\"Null pointer from Kalam C engine\"}")
            return
        }
        let str = String(cString: jsonPtr)
        MTPRequestQueue.handleCCallback(json: str)
    }

    private static let cProgressCallback: MTPCallbackFn = { jsonPtr in
        guard let jsonPtr = jsonPtr else { return }
        let str = String(cString: jsonPtr)
        MTPRequestQueue.reportProgressActivity()

        if let data = try? JSONDecoder().decode(MTPResponse<MTPProgressPayload>.self, from: Data(str.utf8)),
           let payload = data.data {
            let sent = payload.bulkFileSize?.sent ?? payload.activeFileSize?.sent ?? 0
            let total = payload.bulkFileSize?.total ?? payload.activeFileSize?.total ?? 0
            let speed = payload.speed ?? 0

            progressLock.lock()
            let handler = activeProgressHandler
            progressLock.unlock()

            handler?(sent, total, speed)
        }
    }

    private static let cPreprocessCallback: MTPCallbackFn = { _ in
        MTPRequestQueue.reportProgressActivity()
    }

    public var isLoaded: Bool {
        return dylibHandle != nil
    }

    private init() {
        loadDylib()
    }

    public func loadDylib() {
        if dylibHandle != nil { return }
        guard Self.isSupportedArchitecture else {
            print("[MTPBridge] Native MTP engine is unsupported on Intel x86_64.")
            return
        }

        let candidates: [String] = [
            Bundle.main.privateFrameworksURL?.appendingPathComponent("kalam.dylib").path,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/kalam.dylib").path,
            Bundle.main.bundleURL.appendingPathComponent("Frameworks/kalam.dylib").path,
            Bundle.main.resourceURL?.appendingPathComponent("kalam.dylib").path,
            "/Applications/LiquidDynamo.app/Contents/Frameworks/kalam.dylib",
            FileManager.default.currentDirectoryPath + "/Frameworks/kalam.dylib",
            (NSHomeDirectory() + "/Desktop/LiquidDynamo-1.9.2/Frameworks/kalam.dylib")
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                if let handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL) {
                    self.dylibHandle = handle
                    bindSymbols(handle)
                    print("[MTPBridge] Successfully loaded kalam.dylib from: \(path)")
                    return
                }
            }
        }

        if let handle = dlopen("@rpath/kalam.dylib", RTLD_NOW | RTLD_GLOBAL) {
            self.dylibHandle = handle
            bindSymbols(handle)
            print("[MTPBridge] Successfully loaded kalam.dylib via @rpath")
            return
        }

        print("[MTPBridge] Notice: kalam.dylib not found in candidate paths.")
    }

    private func bindSymbols(_ handle: UnsafeMutableRawPointer) {
        if let s = dlsym(handle, "Initialize") {
            initFn = unsafeBitCast(s, to: (@convention(c) (UnsafeRawPointer) -> Void).self)
        }
        if let s = dlsym(handle, "FetchDeviceInfo") {
            fetchDeviceInfoFn = unsafeBitCast(s, to: (@convention(c) (UnsafeRawPointer) -> Void).self)
        }
        if let s = dlsym(handle, "FetchStorages") {
            fetchStoragesFn = unsafeBitCast(s, to: (@convention(c) (UnsafeRawPointer) -> Void).self)
        }
        if let s = dlsym(handle, "MakeDirectory") {
            makeDirectoryFn = unsafeBitCast(s, to: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer) -> Void).self)
        }
        if let s = dlsym(handle, "FileExists") {
            fileExistsFn = unsafeBitCast(s, to: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer) -> Void).self)
        }
        if let s = dlsym(handle, "DeleteFile") {
            deleteFileFn = unsafeBitCast(s, to: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer) -> Void).self)
        }
        if let s = dlsym(handle, "RenameFile") {
            renameFileFn = unsafeBitCast(s, to: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer) -> Void).self)
        }
        if let s = dlsym(handle, "Walk") {
            walkFn = unsafeBitCast(s, to: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer) -> Void).self)
        }
        if let s = dlsym(handle, "UploadFiles") {
            uploadFilesFn = unsafeBitCast(s, to: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer, UnsafeRawPointer, UnsafeRawPointer) -> Void).self)
        }
        if let s = dlsym(handle, "DownloadFiles") {
            downloadFilesFn = unsafeBitCast(s, to: (@convention(c) (UnsafePointer<CChar>, UnsafeRawPointer, UnsafeRawPointer, UnsafeRawPointer) -> Void).self)
        }
        if let s = dlsym(handle, "Dispose") {
            disposeFn = unsafeBitCast(s, to: (@convention(c) (UnsafeRawPointer) -> Void).self)
        }
    }

    // MARK: - Synchronized Operations via FIFO Stream Queue

    public func initialize() async -> Result<MTPDeviceInfoData, Error> {
        guard Self.isSupportedArchitecture else {
            return .failure(MTPError.unsupportedArchitecture)
        }
        guard let initFn = initFn else {
            return .failure(MTPError.dylibNotLoaded)
        }

        // Before initializing MTP, terminate conflicting AFT daemons if running
        MTPProcessConflictResolver.terminateConflictingProcesses()

        let rawResult = await queue.execute(timeoutSeconds: 15.0) {
            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            initFn(donePtr)
        }

        switch rawResult {
        case .success(let json):
            do {
                let decoded = try JSONDecoder().decode(MTPResponse<MTPDeviceInfoData>.self, from: Data(json.utf8))
                if decoded.hasError {
                    return .failure(MTPError.bridgeError(decoded.resolvedErrorMessage))
                } else if let data = decoded.data {
                    return .success(data)
                } else {
                    return .failure(MTPError.bridgeError("Empty device info payload from MTP engine."))
                }
            } catch {
                return .failure(MTPError.decodingFailed(error.localizedDescription))
            }
        case .failure(let err):
            return .failure(err)
        }
    }

    public func fetchDeviceInfo() async -> Result<MTPDeviceInfoData, Error> {
        guard Self.isSupportedArchitecture else {
            return .failure(MTPError.unsupportedArchitecture)
        }
        guard let fetchDeviceInfoFn = fetchDeviceInfoFn else {
            return .failure(MTPError.dylibNotLoaded)
        }

        let rawResult = await queue.execute(timeoutSeconds: 15.0) {
            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            fetchDeviceInfoFn(donePtr)
        }

        switch rawResult {
        case .success(let json):
            do {
                let decoded = try JSONDecoder().decode(MTPResponse<MTPDeviceInfoData>.self, from: Data(json.utf8))
                if decoded.hasError {
                    return .failure(MTPError.bridgeError(decoded.resolvedErrorMessage))
                } else if let data = decoded.data {
                    return .success(data)
                } else {
                    return .failure(MTPError.bridgeError("Empty device info payload from MTP engine."))
                }
            } catch {
                return .failure(MTPError.decodingFailed(error.localizedDescription))
            }
        case .failure(let err):
            return .failure(err)
        }
    }

    public func fetchStorages() async -> Result<[MTPStorageItem], Error> {
        guard Self.isSupportedArchitecture else {
            return .failure(MTPError.unsupportedArchitecture)
        }
        guard let fetchStoragesFn = fetchStoragesFn else {
            return .failure(MTPError.dylibNotLoaded)
        }

        let rawResult = await queue.execute(timeoutSeconds: 15.0) {
            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            fetchStoragesFn(donePtr)
        }

        switch rawResult {
        case .success(let json):
            do {
                let decoded = try JSONDecoder().decode(MTPResponse<[MTPStorageItem]>.self, from: Data(json.utf8))
                if decoded.hasError {
                    return .failure(MTPError.bridgeError(decoded.resolvedErrorMessage))
                } else if let data = decoded.data {
                    return .success(data)
                } else {
                    return .success([])
                }
            } catch {
                return .failure(MTPError.decodingFailed(error.localizedDescription))
            }
        case .failure(let err):
            return .failure(err)
        }
    }

    public func walk(storageId: UInt32, fullPath: String, recursive: Bool = false, skipHidden: Bool = false) async -> Result<[MTPWalkItem], Error> {
        guard Self.isSupportedArchitecture else {
            return .failure(MTPError.unsupportedArchitecture)
        }
        guard let walkFn = walkFn else {
            return .failure(MTPError.dylibNotLoaded)
        }

        let inputDict: [String: Any] = [
            "storageId": storageId,
            "fullPath": fullPath,
            "recursive": recursive,
            "skipDisallowedFiles": true,
            "skipHiddenFiles": skipHidden
        ]
        guard let inputData = try? JSONSerialization.data(withJSONObject: inputDict),
              let jsonString = String(data: inputData, encoding: .utf8) else {
            return .failure(MTPError.invalidArguments)
        }

        let rawResult = await queue.execute(timeoutSeconds: 20.0) {
            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            jsonString.withCString { cstr in
                walkFn(cstr, donePtr)
            }
        }

        switch rawResult {
        case .success(let json):
            do {
                let decoded = try JSONDecoder().decode(MTPResponse<[MTPWalkItem]>.self, from: Data(json.utf8))
                if decoded.hasError {
                    return .failure(MTPError.bridgeError(decoded.resolvedErrorMessage))
                } else if let data = decoded.data {
                    return .success(data)
                } else {
                    return .success([])
                }
            } catch {
                return .failure(MTPError.decodingFailed(error.localizedDescription))
            }
        case .failure(let err):
            return .failure(err)
        }
    }

    public func makeDirectory(storageId: UInt32, fullPath: String) async -> Result<Bool, Error> {
        guard Self.isSupportedArchitecture else {
            return .failure(MTPError.unsupportedArchitecture)
        }
        guard let makeDirectoryFn = makeDirectoryFn else {
            return .failure(MTPError.dylibNotLoaded)
        }

        let inputDict: [String: Any] = [
            "storageId": storageId,
            "fullPath": fullPath
        ]
        guard let inputData = try? JSONSerialization.data(withJSONObject: inputDict),
              let jsonString = String(data: inputData, encoding: .utf8) else {
            return .failure(MTPError.invalidArguments)
        }

        let rawResult = await queue.execute(timeoutSeconds: 15.0) {
            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            jsonString.withCString { cstr in
                makeDirectoryFn(cstr, donePtr)
            }
        }

        switch rawResult {
        case .success(let json):
            do {
                let decoded = try JSONDecoder().decode(MTPBoolResponse.self, from: Data(json.utf8))
                if decoded.hasError {
                    return .failure(MTPError.bridgeError(decoded.resolvedErrorMessage))
                }
                return .success(true)
            } catch {
                return .failure(MTPError.decodingFailed(error.localizedDescription))
            }
        case .failure(let err):
            return .failure(err)
        }
    }

    public func fileExists(storageId: UInt32, files: [String]) async -> Result<[MTPFileExistsItem], Error> {
        guard Self.isSupportedArchitecture else {
            return .failure(MTPError.unsupportedArchitecture)
        }
        guard let fileExistsFn = fileExistsFn else {
            return .failure(MTPError.dylibNotLoaded)
        }

        let inputDict: [String: Any] = [
            "storageId": storageId,
            "files": files
        ]
        guard let inputData = try? JSONSerialization.data(withJSONObject: inputDict),
              let jsonString = String(data: inputData, encoding: .utf8) else {
            return .failure(MTPError.invalidArguments)
        }

        let rawResult = await queue.execute(timeoutSeconds: 15.0) {
            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            jsonString.withCString { cstr in
                fileExistsFn(cstr, donePtr)
            }
        }

        switch rawResult {
        case .success(let json):
            do {
                let decoded = try JSONDecoder().decode(MTPResponse<[MTPFileExistsItem]>.self, from: Data(json.utf8))
                if decoded.hasError {
                    return .failure(MTPError.bridgeError(decoded.resolvedErrorMessage))
                } else if let data = decoded.data {
                    return .success(data)
                } else {
                    return .success([])
                }
            } catch {
                return .failure(MTPError.decodingFailed(error.localizedDescription))
            }
        case .failure(let err):
            return .failure(err)
        }
    }

    public func renameFile(storageId: UInt32, fullPath: String, newFileName: String) async -> Result<Bool, Error> {
        guard Self.isSupportedArchitecture else {
            return .failure(MTPError.unsupportedArchitecture)
        }
        guard let renameFileFn = renameFileFn else {
            return .failure(MTPError.dylibNotLoaded)
        }

        let inputDict: [String: Any] = [
            "storageId": storageId,
            "fullPath": fullPath,
            "newFileName": newFileName
        ]
        guard let inputData = try? JSONSerialization.data(withJSONObject: inputDict),
              let jsonString = String(data: inputData, encoding: .utf8) else {
            return .failure(MTPError.invalidArguments)
        }

        let rawResult = await queue.execute(timeoutSeconds: 15.0) {
            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            jsonString.withCString { cstr in
                renameFileFn(cstr, donePtr)
            }
        }

        switch rawResult {
        case .success(let json):
            do {
                let decoded = try JSONDecoder().decode(MTPBoolResponse.self, from: Data(json.utf8))
                if decoded.hasError {
                    return .failure(MTPError.bridgeError(decoded.resolvedErrorMessage))
                }
                return .success(true)
            } catch {
                return .failure(MTPError.decodingFailed(error.localizedDescription))
            }
        case .failure(let err):
            return .failure(err)
        }
    }

    public func deleteFiles(storageId: UInt32, files: [String]) async -> Result<Bool, Error> {
        guard Self.isSupportedArchitecture else {
            return .failure(MTPError.unsupportedArchitecture)
        }
        guard let deleteFileFn = deleteFileFn else {
            return .failure(MTPError.dylibNotLoaded)
        }

        let inputDict: [String: Any] = [
            "storageId": storageId,
            "files": files
        ]
        guard let inputData = try? JSONSerialization.data(withJSONObject: inputDict),
              let jsonString = String(data: inputData, encoding: .utf8) else {
            return .failure(MTPError.invalidArguments)
        }

        let rawResult = await queue.execute(timeoutSeconds: 15.0) {
            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            jsonString.withCString { cstr in
                deleteFileFn(cstr, donePtr)
            }
        }

        switch rawResult {
        case .success(let json):
            do {
                let decoded = try JSONDecoder().decode(MTPBoolResponse.self, from: Data(json.utf8))
                if decoded.hasError {
                    return .failure(MTPError.bridgeError(decoded.resolvedErrorMessage))
                }
                return .success(true)
            } catch {
                return .failure(MTPError.decodingFailed(error.localizedDescription))
            }
        case .failure(let err):
            return .failure(err)
        }
    }

    public func downloadFiles(
        storageId: UInt32,
        sources: [String],
        destination: String,
        onProgress: (@Sendable (Int64, Int64, Double) -> Void)? = nil
    ) async -> Result<Bool, Error> {
        guard Self.isSupportedArchitecture else {
            return .failure(MTPError.unsupportedArchitecture)
        }
        guard let downloadFilesFn = downloadFilesFn else {
            return .failure(MTPError.dylibNotLoaded)
        }

        let inputDict: [String: Any] = [
            "storageId": storageId,
            "sources": sources,
            "destination": destination,
            "preprocessFiles": false
        ]
        guard let inputData = try? JSONSerialization.data(withJSONObject: inputDict),
              let jsonString = String(data: inputData, encoding: .utf8) else {
            return .failure(MTPError.invalidArguments)
        }

        Self.progressLock.lock()
        Self.activeProgressHandler = onProgress
        Self.progressLock.unlock()

        let rawResult = await queue.execute(timeoutSeconds: 1800.0) {
            let prepPtr = unsafeBitCast(Self.cPreprocessCallback, to: UnsafeRawPointer.self)
            let progPtr = unsafeBitCast(Self.cProgressCallback, to: UnsafeRawPointer.self)
            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            jsonString.withCString { cstr in
                downloadFilesFn(cstr, prepPtr, progPtr, donePtr)
            }
        }

        Self.progressLock.lock()
        Self.activeProgressHandler = nil
        Self.progressLock.unlock()

        switch rawResult {
        case .success(let json):
            do {
                let decoded = try JSONDecoder().decode(MTPBoolResponse.self, from: Data(json.utf8))
                if decoded.hasError {
                    return .failure(MTPError.bridgeError(decoded.resolvedErrorMessage))
                }
                return .success(true)
            } catch {
                return .failure(MTPError.decodingFailed(error.localizedDescription))
            }
        case .failure(let err):
            return .failure(err)
        }
    }

    public func uploadFiles(
        storageId: UInt32,
        sources: [String],
        destination: String,
        onProgress: (@Sendable (Int64, Int64, Double) -> Void)? = nil
    ) async -> Result<Bool, Error> {
        guard Self.isSupportedArchitecture else {
            return .failure(MTPError.unsupportedArchitecture)
        }
        guard let uploadFilesFn = uploadFilesFn else {
            return .failure(MTPError.dylibNotLoaded)
        }

        let inputDict: [String: Any] = [
            "storageId": storageId,
            "sources": sources,
            "destination": destination,
            "preprocessFiles": false
        ]
        guard let inputData = try? JSONSerialization.data(withJSONObject: inputDict),
              let jsonString = String(data: inputData, encoding: .utf8) else {
            return .failure(MTPError.invalidArguments)
        }

        Self.progressLock.lock()
        Self.activeProgressHandler = onProgress
        Self.progressLock.unlock()

        let rawResult = await queue.execute(timeoutSeconds: 1800.0) {
            let prepPtr = unsafeBitCast(Self.cPreprocessCallback, to: UnsafeRawPointer.self)
            let progPtr = unsafeBitCast(Self.cProgressCallback, to: UnsafeRawPointer.self)
            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            jsonString.withCString { cstr in
                uploadFilesFn(cstr, prepPtr, progPtr, donePtr)
            }
        }

        Self.progressLock.lock()
        Self.activeProgressHandler = nil
        Self.progressLock.unlock()

        switch rawResult {
        case .success(let json):
            do {
                let decoded = try JSONDecoder().decode(MTPBoolResponse.self, from: Data(json.utf8))
                if decoded.hasError {
                    return .failure(MTPError.bridgeError(decoded.resolvedErrorMessage))
                }
                return .success(true)
            } catch {
                return .failure(MTPError.decodingFailed(error.localizedDescription))
            }
        case .failure(let err):
            return .failure(err)
        }
    }

    public func dispose() async {
        guard let disposeFn = disposeFn else { return }

        _ = await queue.execute(timeoutSeconds: 5.0) {
            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            disposeFn(donePtr)
        }
    }
}

// MARK: - Backward Compatibility Typealiases
public typealias KalamBridge = MTPBridge
public typealias KalamCallbackFn = MTPCallbackFn
public typealias KalamResponse<T: Codable> = MTPResponse<T>
public typealias KalamEmptyData = MTPEmptyData
public typealias KalamDeviceInfoData = MTPDeviceInfoData
public typealias KalamMtpDeviceInfo = MTPMtpDeviceInfo
public typealias KalamUsbDeviceInfo = MTPUsbDeviceInfo
public typealias KalamStorageItem = MTPStorageItem
public typealias KalamStorageDetail = MTPStorageDetail
public typealias KalamWalkItem = MTPWalkItem
public typealias KalamProgressPayload = MTPProgressPayload
public typealias KalamError = MTPError
public typealias KalamRequestQueue = MTPRequestQueue
