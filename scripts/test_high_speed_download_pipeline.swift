#!/usr/bin/env swift
import Foundation

print("=== Testing High-Speed Download & Verification Pipeline ===")

let targetURL = URL(string: "https://github.com/anksarvesh-lgtm/dynamo-mac/releases/download/v2.0.7/liquiddynamo.zip")!

private final class DownloadLockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var isResumed = false
    func resumeOnce(continuation: CheckedContinuation<URL, Error>, result: Result<URL, Error>) {
        lock.lock()
        defer { lock.unlock() }
        if !isResumed {
            isResumed = true
            continuation.resume(with: result)
        }
    }
}

private final class HighSpeedDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double, Int64, Int64) -> Void
    private let onFinish: @Sendable (Result<URL, Error>) -> Void
    private let lastUpdateLock = NSLock()
    private var lastUpdateTime = Date.distantPast

    init(
        onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void,
        onFinish: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        self.onProgress = onProgress
        self.onFinish = onFinish
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = Date()
        lastUpdateLock.lock()
        let shouldUpdate = now.timeIntervalSince(lastUpdateTime) >= 0.1 || totalBytesWritten == totalBytesExpectedToWrite
        if shouldUpdate {
            lastUpdateTime = now
        }
        lastUpdateLock.unlock()

        if shouldUpdate {
            let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
            onProgress(progress, totalBytesWritten, totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tempTarget = FileManager.default.temporaryDirectory.appendingPathComponent("test_high_speed_\(UUID().uuidString).zip")
        do {
            try FileManager.default.moveItem(at: location, to: tempTarget)
            onFinish(.success(tempTarget))
        } catch {
            onFinish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onFinish(.failure(error))
        }
    }
}

func runTest() async throws {
    let startTime = Date()
    print("Initiating high-speed streaming download from:")
    print("  \(targetURL.absoluteString)")

    var request = URLRequest(url: targetURL)
    request.timeoutInterval = 60
    request.setValue("LiquidDynamo-HighSpeedTest", forHTTPHeaderField: "User-Agent")

    let lockBox = DownloadLockBox()
    let downloadedURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
        let delegate = HighSpeedDownloadDelegate(
            onProgress: { progress, downloaded, total in
                let pct = Int(progress * 100)
                let mbDownloaded = Double(downloaded) / (1024 * 1024)
                let mbTotal = Double(total) / (1024 * 1024)
                print(String(format: "  ↳ Progress: %3d%% (%.2f MB / %.2f MB)", pct, mbDownloaded, mbTotal))
            },
            onFinish: { result in
                lockBox.resumeOnce(continuation: continuation, result: result)
            }
        )

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 20
        sessionConfig.timeoutIntervalForResource = 300
        sessionConfig.waitsForConnectivity = true
        sessionConfig.httpMaximumConnectionsPerHost = 8
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData

        let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
        let downloadTask = session.downloadTask(with: request)
        downloadTask.resume()
    }

    defer { try? FileManager.default.removeItem(at: downloadedURL) }

    let duration = Date().timeIntervalSince(startTime)
    let fileSize = (try? FileManager.default.attributesOfItem(atPath: downloadedURL.path)[.size] as? Int64) ?? 0
    let fileSizeMB = Double(fileSize) / (1024 * 1024)
    let speedMBps = fileSizeMB / duration

    print(String(format: "\n⚡ Download Completed in %.2f seconds!", duration))
    print(String(format: "   File Size: %.2f MB", fileSizeMB))
    print(String(format: "   Average Throughput: %.2f MB/s (%.1f Mbps)", speedMBps, speedMBps * 8))

    assert(fileSize > 20 * 1024 * 1024, "Payload must be at least 20MB")

    // Test extraction via ditto
    print("\nVerifying extraction with ditto...")
    let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_extract_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: stagingDir) }

    let ditto = Process()
    ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    ditto.arguments = ["-x", "-k", downloadedURL.path, stagingDir.path]
    try ditto.run()
    ditto.waitUntilExit()

    assert(ditto.terminationStatus == 0, "ditto extraction must succeed")

    let contents = (try? FileManager.default.contentsOfDirectory(atPath: stagingDir.path)) ?? []
    guard let appBundle = contents.first(where: { $0.hasSuffix(".app") }) else {
        fatalError("No .app bundle extracted")
    }

    let stagedAppPath = stagingDir.appendingPathComponent(appBundle).path
    print("✓ Successfully extracted: \(appBundle)")

    // Verify bundle binary
    let binaryPath = "\(stagedAppPath)/Contents/MacOS/LiquidDynamo"
    assert(FileManager.default.fileExists(atPath: binaryPath), "Application binary must exist")
    print("✓ Binary confirmed at: \(binaryPath)")

    print("\n🎉 ALL TESTS PASSED: High-speed download pipeline is verified and fully operational!")
}

let sema = DispatchSemaphore(value: 0)
Task {
    do {
        try await runTest()
    } catch {
        print("❌ Test failed: \(error)")
        exit(1)
    }
    sema.signal()
}
sema.wait()
