//
//  KalamBridge.swift
//  LiquidDynamo
//
//  Native Swift C-FFI bridge to OpenMTP's high-performance Kalam MTP engine.
//  Directly interfaces with Android devices over USB MTP protocol without requiring
//  third-party drivers or ADB debugging.
//

import AppKit
import Darwin
import Foundation

public typealias KalamCallbackFn = @convention(c) (UnsafePointer<CChar>?) -> Void

// MARK: - Kalam Data Transfer Models

public struct KalamResponse<T: Codable>: Codable {
    public let errorType: String
    public let error: String
    public let data: T?
}

public struct KalamDeviceInfoData: Codable {
    public let mtpDeviceInfo: KalamMtpDeviceInfo?
    public let usbDeviceInfo: KalamUsbDeviceInfo?
}

public struct KalamMtpDeviceInfo: Codable {
    public let Manufacturer: String?
    public let Model: String?
    public let SerialNumber: String?
    public let DeviceVersion: String?
}

public struct KalamUsbDeviceInfo: Codable {
    public let IdVendor: UInt32?
    public let IdProduct: UInt32?
    public let Manufacturer: String?
    public let Product: String?
    public let SerialNumber: String?
}

public struct KalamStorageItem: Codable {
    public let Sid: UInt32
    public let Info: KalamStorageDetail
}

public struct KalamStorageDetail: Codable {
    public let StorageType: UInt16
    public let FilesystemType: UInt16
    public let AccessCapability: UInt16
    public let MaxCapability: UInt64
    public let FreeSpaceInBytes: UInt64
    public let StorageDescription: String
    public let VolumeLabel: String
}

public struct KalamWalkItem: Codable {
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

public struct KalamProgressPayload: Codable {
    public let percentage: Double?
    public let speed: Int64?
    public let activeFile: String?
    public let activeFileSize: Int64?
    public let currentFiles: Int?
    public let totalFiles: Int?
    public let bulkTotal: Int64?
    public let bulkTransferred: Int64?
}

// MARK: - Kalam Bridge Engine

public final class KalamBridge: @unchecked Sendable {
    public static let shared = KalamBridge()

    private let lock = NSLock()
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

    private static var activeDoneHandler: ((String) -> Void)?
    private static var activeProgressHandler: ((String) -> Void)?
    private static var activePreprocessHandler: ((String) -> Void)?

    private static let cDoneCallback: KalamCallbackFn = { jsonPtr in
        guard let jsonPtr = jsonPtr else { return }
        let str = String(cString: jsonPtr)
        activeDoneHandler?(str)
    }

    private static let cProgressCallback: KalamCallbackFn = { jsonPtr in
        guard let jsonPtr = jsonPtr else { return }
        let str = String(cString: jsonPtr)
        activeProgressHandler?(str)
    }

    private static let cPreprocessCallback: KalamCallbackFn = { jsonPtr in
        guard let jsonPtr = jsonPtr else { return }
        let str = String(cString: jsonPtr)
        activePreprocessHandler?(str)
    }

    public var isLoaded: Bool {
        return dylibHandle != nil
    }

    private init() {
        loadDylib()
    }

    public func loadDylib() {
        if dylibHandle != nil { return }

        let candidates = [
            Bundle.main.privateFrameworksPath.map { "\($0)/kalam.dylib" },
            Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/kalam.dylib").path,
            "/Applications/LiquidDynamo.app/Contents/Frameworks/kalam.dylib",
            "\(FileManager.default.currentDirectoryPath)/Frameworks/kalam.dylib",
            "/Users/sarvesh/Desktop/LiquidDynamo-1.9.2/Frameworks/kalam.dylib",
            "/Users/sarvesh/.gemini/antigravity-ide/brain/12c5ddfe-7ddb-4b55-9d33-7e51b20d493e/scratch/openmtp/build/mac/bin/arm64/kalam.dylib"
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                if let handle = dlopen(path, RTLD_NOW) {
                    self.dylibHandle = handle
                    bindSymbols(handle)
                    print("[KalamBridge] Successfully loaded kalam.dylib from: \(path)")
                    break
                }
            }
        }
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

    // MARK: - Synchronized Operations

    public func initialize() async -> Result<KalamDeviceInfoData, Error> {
        guard let initFn = initFn else {
            return .failure(NSError(domain: "KalamBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "kalam.dylib not loaded"]))
        }

        return await withCheckedContinuation { continuation in
            lock.lock()
            Self.activeDoneHandler = { json in
                Self.activeDoneHandler = nil
                self.lock.unlock()

                do {
                    let decoded = try JSONDecoder().decode(KalamResponse<KalamDeviceInfoData>.self, from: Data(json.utf8))
                    if !decoded.error.isEmpty {
                        continuation.resume(returning: .failure(NSError(domain: "KalamBridge", code: 2, userInfo: [NSLocalizedDescriptionKey: decoded.error])))
                    } else if let data = decoded.data {
                        continuation.resume(returning: .success(data))
                    } else {
                        continuation.resume(returning: .failure(NSError(domain: "KalamBridge", code: 3, userInfo: [NSLocalizedDescriptionKey: "Empty device payload"])))
                    }
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }

            let ptr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            initFn(ptr)
        }
    }

    public func fetchStorages() async -> Result<[KalamStorageItem], Error> {
        guard let fetchStoragesFn = fetchStoragesFn else {
            return .failure(NSError(domain: "KalamBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "kalam.dylib not loaded"]))
        }

        return await withCheckedContinuation { continuation in
            lock.lock()
            Self.activeDoneHandler = { json in
                Self.activeDoneHandler = nil
                self.lock.unlock()

                do {
                    let decoded = try JSONDecoder().decode(KalamResponse<[KalamStorageItem]>.self, from: Data(json.utf8))
                    if !decoded.error.isEmpty {
                        continuation.resume(returning: .failure(NSError(domain: "KalamBridge", code: 2, userInfo: [NSLocalizedDescriptionKey: decoded.error])))
                    } else if let data = decoded.data {
                        continuation.resume(returning: .success(data))
                    } else {
                        continuation.resume(returning: .success([]))
                    }
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }

            let ptr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            fetchStoragesFn(ptr)
        }
    }

    public func walk(storageId: UInt32, fullPath: String, recursive: Bool = false, skipHidden: Bool = false) async -> Result<[KalamWalkItem], Error> {
        guard let walkFn = walkFn else {
            return .failure(NSError(domain: "KalamBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "kalam.dylib not loaded"]))
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
            return .failure(NSError(domain: "KalamBridge", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid walk arguments"]))
        }

        return await withCheckedContinuation { continuation in
            lock.lock()
            Self.activeDoneHandler = { json in
                Self.activeDoneHandler = nil
                self.lock.unlock()

                do {
                    let decoded = try JSONDecoder().decode(KalamResponse<[KalamWalkItem]>.self, from: Data(json.utf8))
                    if !decoded.error.isEmpty {
                        continuation.resume(returning: .failure(NSError(domain: "KalamBridge", code: 2, userInfo: [NSLocalizedDescriptionKey: decoded.error])))
                    } else if let data = decoded.data {
                        continuation.resume(returning: .success(data))
                    } else {
                        continuation.resume(returning: .success([]))
                    }
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }

            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            jsonString.withCString { cstr in
                walkFn(cstr, donePtr)
            }
        }
    }

    public func makeDirectory(storageId: UInt32, fullPath: String) async -> Result<Bool, Error> {
        guard let makeDirectoryFn = makeDirectoryFn else {
            return .failure(NSError(domain: "KalamBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "kalam.dylib not loaded"]))
        }

        let inputDict: [String: Any] = [
            "storageId": storageId,
            "fullPath": fullPath
        ]
        guard let inputData = try? JSONSerialization.data(withJSONObject: inputDict),
              let jsonString = String(data: inputData, encoding: .utf8) else {
            return .failure(NSError(domain: "KalamBridge", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid arguments"]))
        }

        return await withCheckedContinuation { continuation in
            lock.lock()
            Self.activeDoneHandler = { json in
                Self.activeDoneHandler = nil
                self.lock.unlock()

                if json.contains("\"error\":\"\"") || !json.contains("errorType") {
                    continuation.resume(returning: .success(true))
                } else {
                    continuation.resume(returning: .failure(NSError(domain: "KalamBridge", code: 5, userInfo: [NSLocalizedDescriptionKey: json])))
                }
            }

            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            jsonString.withCString { cstr in
                makeDirectoryFn(cstr, donePtr)
            }
        }
    }

    public func renameFile(storageId: UInt32, fullPath: String, newFileName: String) async -> Result<Bool, Error> {
        guard let renameFileFn = renameFileFn else {
            return .failure(NSError(domain: "KalamBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "kalam.dylib not loaded"]))
        }

        let inputDict: [String: Any] = [
            "storageId": storageId,
            "fullPath": fullPath,
            "newFileName": newFileName
        ]
        guard let inputData = try? JSONSerialization.data(withJSONObject: inputDict),
              let jsonString = String(data: inputData, encoding: .utf8) else {
            return .failure(NSError(domain: "KalamBridge", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid arguments"]))
        }

        return await withCheckedContinuation { continuation in
            lock.lock()
            Self.activeDoneHandler = { json in
                Self.activeDoneHandler = nil
                self.lock.unlock()

                if json.contains("\"error\":\"\"") || !json.contains("errorType") {
                    continuation.resume(returning: .success(true))
                } else {
                    continuation.resume(returning: .failure(NSError(domain: "KalamBridge", code: 6, userInfo: [NSLocalizedDescriptionKey: json])))
                }
            }

            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            jsonString.withCString { cstr in
                renameFileFn(cstr, donePtr)
            }
        }
    }

    public func deleteFiles(storageId: UInt32, files: [String]) async -> Result<Bool, Error> {
        guard let deleteFileFn = deleteFileFn else {
            return .failure(NSError(domain: "KalamBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "kalam.dylib not loaded"]))
        }

        let inputDict: [String: Any] = [
            "storageId": storageId,
            "Files": files
        ]
        guard let inputData = try? JSONSerialization.data(withJSONObject: inputDict),
              let jsonString = String(data: inputData, encoding: .utf8) else {
            return .failure(NSError(domain: "KalamBridge", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid arguments"]))
        }

        return await withCheckedContinuation { continuation in
            lock.lock()
            Self.activeDoneHandler = { json in
                Self.activeDoneHandler = nil
                self.lock.unlock()

                if json.contains("\"error\":\"\"") || !json.contains("errorType") {
                    continuation.resume(returning: .success(true))
                } else {
                    continuation.resume(returning: .failure(NSError(domain: "KalamBridge", code: 7, userInfo: [NSLocalizedDescriptionKey: json])))
                }
            }

            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            jsonString.withCString { cstr in
                deleteFileFn(cstr, donePtr)
            }
        }
    }

    public func downloadFiles(
        storageId: UInt32,
        sources: [String],
        destination: String,
        onProgress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async -> Result<Bool, Error> {
        guard let downloadFilesFn = downloadFilesFn else {
            return .failure(NSError(domain: "KalamBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "kalam.dylib not loaded"]))
        }

        let inputDict: [String: Any] = [
            "storageId": storageId,
            "sources": sources,
            "destination": destination,
            "preprocessFiles": false
        ]
        guard let inputData = try? JSONSerialization.data(withJSONObject: inputDict),
              let jsonString = String(data: inputData, encoding: .utf8) else {
            return .failure(NSError(domain: "KalamBridge", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid arguments"]))
        }

        return await withCheckedContinuation { continuation in
            lock.lock()

            Self.activeProgressHandler = { json in
                if let data = try? JSONDecoder().decode(KalamResponse<KalamProgressPayload>.self, from: Data(json.utf8)),
                   let payload = data.data {
                    let total = payload.bulkTotal ?? payload.activeFileSize ?? 0
                    let current = payload.bulkTransferred ?? (Int64((payload.percentage ?? 0) / 100.0 * Double(total)))
                    onProgress?(current, total)
                }
            }

            Self.activeDoneHandler = { json in
                Self.activeDoneHandler = nil
                Self.activeProgressHandler = nil
                self.lock.unlock()

                if json.contains("\"error\":\"\"") || !json.contains("errorType") {
                    continuation.resume(returning: .success(true))
                } else {
                    continuation.resume(returning: .failure(NSError(domain: "KalamBridge", code: 8, userInfo: [NSLocalizedDescriptionKey: json])))
                }
            }

            let prepPtr = unsafeBitCast(Self.cPreprocessCallback, to: UnsafeRawPointer.self)
            let progPtr = unsafeBitCast(Self.cProgressCallback, to: UnsafeRawPointer.self)
            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)

            jsonString.withCString { cstr in
                downloadFilesFn(cstr, prepPtr, progPtr, donePtr)
            }
        }
    }

    public func uploadFiles(
        storageId: UInt32,
        sources: [String],
        destination: String,
        onProgress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async -> Result<Bool, Error> {
        guard let uploadFilesFn = uploadFilesFn else {
            return .failure(NSError(domain: "KalamBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "kalam.dylib not loaded"]))
        }

        let inputDict: [String: Any] = [
            "storageId": storageId,
            "sources": sources,
            "destination": destination,
            "preprocessFiles": false
        ]
        guard let inputData = try? JSONSerialization.data(withJSONObject: inputDict),
              let jsonString = String(data: inputData, encoding: .utf8) else {
            return .failure(NSError(domain: "KalamBridge", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid arguments"]))
        }

        return await withCheckedContinuation { continuation in
            lock.lock()

            Self.activeProgressHandler = { json in
                if let data = try? JSONDecoder().decode(KalamResponse<KalamProgressPayload>.self, from: Data(json.utf8)),
                   let payload = data.data {
                    let total = payload.bulkTotal ?? payload.activeFileSize ?? 0
                    let current = payload.bulkTransferred ?? (Int64((payload.percentage ?? 0) / 100.0 * Double(total)))
                    onProgress?(current, total)
                }
            }

            Self.activeDoneHandler = { json in
                Self.activeDoneHandler = nil
                Self.activeProgressHandler = nil
                self.lock.unlock()

                if json.contains("\"error\":\"\"") || !json.contains("errorType") {
                    continuation.resume(returning: .success(true))
                } else {
                    continuation.resume(returning: .failure(NSError(domain: "KalamBridge", code: 9, userInfo: [NSLocalizedDescriptionKey: json])))
                }
            }

            let prepPtr = unsafeBitCast(Self.cPreprocessCallback, to: UnsafeRawPointer.self)
            let progPtr = unsafeBitCast(Self.cProgressCallback, to: UnsafeRawPointer.self)
            let donePtr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)

            jsonString.withCString { cstr in
                uploadFilesFn(cstr, prepPtr, progPtr, donePtr)
            }
        }
    }

    public func dispose() async {
        guard let disposeFn = disposeFn else { return }

        await withCheckedContinuation { continuation in
            lock.lock()
            Self.activeDoneHandler = { _ in
                Self.activeDoneHandler = nil
                self.lock.unlock()
                continuation.resume()
            }

            let ptr = unsafeBitCast(Self.cDoneCallback, to: UnsafeRawPointer.self)
            disposeFn(ptr)
        }
    }
}
