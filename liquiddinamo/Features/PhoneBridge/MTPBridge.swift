//
//  MTPBridge.swift
//  LiquidDynamo
//
//  Native Swift C-FFI bridge to OpenMTP's high-performance Kalam MTP engine.
//  Uses an asynchronous FIFO stream queue with per-call 15-second timeouts,
//  thread-safe execution without lock deadlocks, strict Codable envelope validation,
//  secure bundle-only dylib loading, and Intel architecture detection.
//

import AppKit
import Darwin
import Foundation

public typealias MTPCallbackFn = @convention(c) (UnsafePointer<CChar>?) -> Void

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
        if let err = error, !err.isEmpty { return err }
        if let errType = errorType, !errType.isEmpty { return errType }
        return "Unknown MTP error"
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

public struct MTPStorageItem: Codable {
    public let Sid: UInt32
    public let Info: MTPStorageDetail
}

public struct MTPStorageDetail: Codable {
    public let StorageType: UInt16
    public let FilesystemType: UInt16
    public let AccessCapability: UInt16
    public let MaxCapability: UInt64
    public let FreeSpaceInBytes: UInt64
    public let StorageDescription: String
    public let VolumeLabel: String
}

public struct MTPWalkItem: Codable {
    public let size: Int64
    public let isFolder: Bool
    public let dateAdded: String
    public let name: String
    public let path: String
    public let parentPath: String
    public let `extension`: String
    public let parentId: UInt32
    public let objectId: UInt32
}

public struct MTPProgressPayload: Codable {
    public let percentage: Double?
    public let speed: Int64?
    public let activeFile: String?
    public let activeFileSize: Int64?
    public let currentFiles: Int?
    public let totalFiles: Int?
    public let bulkTotal: Int64?
    public let bulkTransferred: Int64?
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
            return "MTP operation timed out after 15 seconds."
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
            callbackLock.unlock()

            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(op.timeoutSeconds * 1_000_000_000))
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

    private static var activeProgressHandler: (@Sendable (Int64, Int64) -> Void)?
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
        if let data = try? JSONDecoder().decode(MTPResponse<MTPProgressPayload>.self, from: Data(str.utf8)),
           let payload = data.data {
            let total = payload.bulkTotal ?? payload.activeFileSize ?? 0
            let current = payload.bulkTransferred ?? (Int64((payload.percentage ?? 0) / 100.0 * Double(total)))
            progressLock.lock()
            let handler = activeProgressHandler
            progressLock.unlock()
            handler?(current, total)
        }
    }

    private static let cPreprocessCallback: MTPCallbackFn = { _ in }

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

        // Restrict dylib loading exclusively to application private frameworks and @rpath
        let candidates: [String] = [
            Bundle.main.privateFrameworksURL?.appendingPathComponent("kalam.dylib").path,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/kalam.dylib").path,
            "/Applications/LiquidDynamo.app/Contents/Frameworks/kalam.dylib"
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                if let handle = dlopen(path, RTLD_NOW) {
                    self.dylibHandle = handle
                    bindSymbols(handle)
                    print("[MTPBridge] Successfully loaded kalam.dylib from bundle: \(path)")
                    return
                }
            }
        }

        // Fallback for development/testing: @rpath
        if let handle = dlopen("@rpath/kalam.dylib", RTLD_NOW) {
            self.dylibHandle = handle
            bindSymbols(handle)
            print("[MTPBridge] Successfully loaded kalam.dylib via @rpath")
            return
        }

        print("[MTPBridge] Notice: kalam.dylib not found in Frameworks bundle.")
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

        let rawResult = await queue.execute(timeoutSeconds: 15.0) {
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
                let decoded = try JSONDecoder().decode(MTPResponse<MTPEmptyData>.self, from: Data(json.utf8))
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
                let decoded = try JSONDecoder().decode(MTPResponse<MTPEmptyData>.self, from: Data(json.utf8))
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
            "Files": files
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
                let decoded = try JSONDecoder().decode(MTPResponse<MTPEmptyData>.self, from: Data(json.utf8))
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
        onProgress: (@Sendable (Int64, Int64) -> Void)? = nil
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

        let rawResult = await queue.execute(timeoutSeconds: 15.0) {
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
                let decoded = try JSONDecoder().decode(MTPResponse<MTPEmptyData>.self, from: Data(json.utf8))
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
        onProgress: (@Sendable (Int64, Int64) -> Void)? = nil
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

        let rawResult = await queue.execute(timeoutSeconds: 15.0) {
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
                let decoded = try JSONDecoder().decode(MTPResponse<MTPEmptyData>.self, from: Data(json.utf8))
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
