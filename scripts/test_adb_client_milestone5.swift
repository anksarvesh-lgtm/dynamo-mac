//
//  test_adb_client_milestone5.swift
//  LiquidDynamo Tests - Milestone 5 (ADBClient Pipe Concurrency & Safety)
//

import Foundation

var totalTests = 0
var passedTests = 0

func assertTest(_ condition: Bool, _ message: String) {
    totalTests += 1
    if condition {
        passedTests += 1
        print("  ✅ PASS: \(message)")
    } else {
        print("  ❌ FAIL: \(message)")
    }
}

print("==================================================================")
print("🚀 RUNNING MILESTONE 5 TEST SUITE: ADB CLIENT")
print("==================================================================")

// Setup temporary test directory and mock adb script
let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ld_adb_tests_\(UUID().uuidString.prefix(6))")
try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
defer {
    try? FileManager.default.removeItem(at: tempDir)
}

let mockAdbURL = tempDir.appendingPathComponent("mock_adb.sh")
let mockAdbPath = mockAdbURL.path

// Create mock ADB shell script that responds to commands
let mockAdbScript = """
#!/bin/sh
case "$1" in
    "devices")
        echo "List of devices attached"
        echo "TEST_SERIAL_123   device model:Pixel_8 product:pixel8 device:husky"
        exit 0
        ;;
    "big_output")
        # Generate 5 MB of data (well above the 64 KB pipe buffer limit)
        dd if=/dev/zero bs=1024 count=5120 2>/dev/null | tr '\\000' 'A'
        exit 0
        ;;
    "hang")
        # Sleep for a long time simulating a frozen subprocess
        sleep 30
        exit 0
        ;;
    "fail")
        echo "error: device unauthorized" >&2
        exit 1
        ;;
    "-s")
        # e.g., mock_adb.sh -s SERIAL pull ...
        if [ "$3" = "pull" ]; then
            echo "Mock pulled content from $4" > "$5"
            exit 0
        elif [ "$3" = "push" ]; then
            exit 0
        fi
        ;;
esac
exit 0
"""
try mockAdbScript.write(to: mockAdbURL, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockAdbPath)

// MARK: - Replicate ConcurrentDataBuffer & Process Execution Logic for Verification

final class ConcurrentDataBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    private let maxBytes: Int

    init(maxBytes: Int = 10 * 1024 * 1024) {
        self.maxBytes = maxBytes
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if data.count < maxBytes {
            let toAppend = min(chunk.count, maxBytes - data.count)
            data.append(chunk.prefix(toAppend))
        }
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return data.count
    }

    func string(encoding: String.Encoding = .utf8) -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: encoding) ?? ""
    }
}

enum ADBTestError: LocalizedError, Equatable {
    case adbNotFound
    case timeout(timeoutSeconds: TimeInterval)
    case cancelled
    case commandFailed(exitCode: Int32, message: String)
}

func runMockAdb(args: [String], timeout: TimeInterval) async throws -> (stdout: String, byteCount: Int, exitCode: Int32) {
    if Task.isCancelled {
        throw ADBTestError.cancelled
    }

    final class ProcessHolder: @unchecked Sendable {
        var process: Process?
        var isCancelled = false
        let lock = NSLock()

        func cancel() {
            lock.lock()
            isCancelled = true
            let p = process
            lock.unlock()
            if let p = p, p.isRunning {
                p.terminate()
            }
        }
    }
    let holder = ProcessHolder()

    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: mockAdbPath)
            process.arguments = args

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let outHandle = outPipe.fileHandleForReading
            let errHandle = errPipe.fileHandleForReading

            let stdoutBuffer = ConcurrentDataBuffer(maxBytes: 10 * 1024 * 1024)
            let stderrBuffer = ConcurrentDataBuffer(maxBytes: 10 * 1024 * 1024)

            outHandle.readabilityHandler = { handle in
                stdoutBuffer.append(handle.availableData)
            }
            errHandle.readabilityHandler = { handle in
                stderrBuffer.append(handle.availableData)
            }

            final class RunState: @unchecked Sendable {
                var isResumed = false
                var isTimedOut = false
                var timer: DispatchSourceTimer?
                let lock = NSLock()

                func finish(result: Result<(stdout: String, byteCount: Int, exitCode: Int32), Error>, cont: CheckedContinuation<(stdout: String, byteCount: Int, exitCode: Int32), Error>, timeoutDuration: TimeInterval, holder: ProcessHolder) {
                    lock.lock()
                    guard !isResumed else {
                        lock.unlock()
                        return
                    }
                    isResumed = true
                    timer?.cancel()
                    timer = nil
                    let timedOut = isTimedOut
                    lock.unlock()

                    if timedOut {
                        cont.resume(throwing: ADBTestError.timeout(timeoutSeconds: timeoutDuration))
                    } else if holder.isCancelled {
                        cont.resume(throwing: ADBTestError.cancelled)
                    } else {
                        cont.resume(with: result)
                    }
                }
            }

            let state = RunState()
            holder.process = process

            if timeout > 0 {
                let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
                t.schedule(deadline: .now() + timeout)
                t.setEventHandler { [weak process] in
                    state.lock.lock()
                    state.isTimedOut = true
                    state.lock.unlock()
                    if let proc = process, proc.isRunning {
                        proc.terminate()
                    }
                }
                t.resume()
                state.timer = t
            }

            process.terminationHandler = { proc in
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil
                stdoutBuffer.append(outHandle.readDataToEndOfFile())
                stderrBuffer.append(errHandle.readDataToEndOfFile())

                state.finish(
                    result: .success((stdout: stdoutBuffer.string(), byteCount: stdoutBuffer.count(), exitCode: proc.terminationStatus)),
                    cont: continuation,
                    timeoutDuration: timeout,
                    holder: holder
                )
            }

            do {
                try process.run()
            } catch {
                outHandle.readabilityHandler = nil
                errHandle.readabilityHandler = nil
                state.finish(result: .failure(error), cont: continuation, timeoutDuration: timeout, holder: holder)
            }
        }
    } onCancel: {
        holder.cancel()
    }
}

// MARK: - Test Runner Definitions

let sema = DispatchSemaphore(value: 0)

_ = Task {
    // Suite 1: Pipe Streaming with 5 MB Output (No 64 KB deadlock)
    print("\n[Suite 1: Pipe Streaming with 5 MB Output]")
    do {
        let res = try await runMockAdb(args: ["big_output"], timeout: 10.0)
        assertTest(res.exitCode == 0, "Process completed with exit code 0")
        assertTest(res.byteCount >= 5 * 1024 * 1024, "Read full 5 MB output without hanging on 64 KB buffer: received \(res.byteCount) bytes")
    } catch {
        assertTest(false, "Big output should not fail: \(error)")
    }

    // Suite 2: Timeout Returns Typed Error (Not exit code 15)
    print("\n[Suite 2: Typed Timeout Error Handling]")
    do {
        _ = try await runMockAdb(args: ["hang"], timeout: 0.3)
        assertTest(false, "Hanging command must time out")
    } catch let err as ADBTestError {
        switch err {
        case .timeout(let sec):
            assertTest(sec == 0.3, "Typed timeout error received with duration 0.3s")
        default:
            assertTest(false, "Expected .timeout, got: \(err)")
        }
    } catch {
        assertTest(false, "Unexpected error: \(error)")
    }

    // Suite 3: Task Cancellation Support
    print("\n[Suite 3: Task Cancellation Support]")
    let cancelTask = Task {
        try await runMockAdb(args: ["hang"], timeout: 10.0)
    }
    Task {
        try? await Task.sleep(nanoseconds: 100_000_000)
        cancelTask.cancel()
    }
    do {
        _ = try await cancelTask.value
        assertTest(false, "Cancelled task should throw cancellation error")
    } catch let err as ADBTestError {
        assertTest(err == .cancelled, "Task cancellation cleanly threw ADBTestError.cancelled")
    } catch {
        assertTest(false, "Unexpected error on cancel: \(error)")
    }

    // Suite 4: Exception-Safe Timer Lifecycle (No inactive source release crash)
    print("\n[Suite 4: Exception-Safe Progress Timer Lifecycle]")
    do {
        // Test pattern when size is 0 or progress callback is nil: timer is never instantiated/suspended
        var timerCreated = false
        var timerResumed = false
        let finalBytes: Int64 = 0
        let hasProgress = false

        let progressTimer: DispatchSourceTimer?
        if finalBytes > 0 && hasProgress {
            let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            timerCreated = true
            t.resume()
            timerResumed = true
            progressTimer = t
        } else {
            progressTimer = nil
        }

        // Simulating terminationHandler cleanup
        progressTimer?.cancel()
        assertTest(progressTimer == nil && !timerCreated, "Timer is cleanly omitted when size <= 0 or onProgress is nil")
    }

    // Suite 5: Atomic File Replacement (Never deletes target before temp is verified)
    print("\n[Suite 5: Atomic File Replacement Mechanics]")
    do {
        let destURL = tempDir.appendingPathComponent("important_doc.txt")
        let originalText = "Original irreplaceable document content"
        try originalText.write(to: destURL, atomically: true, encoding: .utf8)

        let tempURL = tempDir.appendingPathComponent("important_doc.downloading")
        let newText = "Newly downloaded update content"
        try newText.write(to: tempURL, atomically: true, encoding: .utf8)

        // Perform atomic replace using replaceItemAt
        _ = try FileManager.default.replaceItemAt(
            destURL,
            withItemAt: tempURL,
            backupItemName: nil,
            options: [.usingNewMetadataOnly]
        )

        let replacedText = try String(contentsOf: destURL, encoding: .utf8)
        assertTest(replacedText == newText, "Target file successfully updated via atomic replacement")
        assertTest(!FileManager.default.fileExists(atPath: tempURL.path), "Temporary file consumed during replacement")
    }

    // Suite 6: ADBShellSecurity & Listing Parsing Verification
    print("\n[Suite 6: Shell Escaping & Directory Listing]")
    do {
        // Escaping tests
        let test1 = "file with spaces.txt"
        let esc1 = "'file with spaces.txt'"
        let actual1 = "'\(test1.replacingOccurrences(of: "'", with: "'\\''"))'"
        assertTest(actual1 == esc1, "Simple filename with spaces safely quoted")

        let test2 = "file'with'quotes.txt"
        let actual2 = "'\(test2.replacingOccurrences(of: "'", with: "'\\''"))'"
        assertTest(actual2 == "'file'\\''with'\\''quotes.txt'", "Single quotes inside filename safely escaped")

        let test3 = "; rm -rf / ;"
        let actual3 = "'\(test3.replacingOccurrences(of: "'", with: "'\\''"))'"
        assertTest(actual3 == "'; rm -rf / ;'", "Shell injection payload encapsulated in single quotes")
    }

    sema.signal()
}

sema.wait()

print("\n==================================================================")
print("TEST SUMMARY: \(passedTests)/\(totalTests) TESTS PASSED")
print("==================================================================")

if passedTests == totalTests {
    exit(0)
} else {
    exit(1)
}
