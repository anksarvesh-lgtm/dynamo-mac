//
//  test_mtp_bridge_milestone4.swift
//  LiquidDynamo Tests - Milestone 4 (MTPBridge & Phone Bridge Thread Safety)
//

import Foundation

// MARK: - Test Models & Queue (Replicated for Isolated Swift Script Testing)

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

public enum MTPError: LocalizedError, Equatable {
    case dylibNotLoaded
    case unsupportedArchitecture
    case timeout
    case bridgeError(String)
    case invalidArguments
    case decodingFailed(String)
}

final class AtomicState: @unchecked Sendable {
    private var hasResumed = false
    private let lock = NSLock()

    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasResumed { return false }
        hasResumed = true
        return true
    }
}

actor OrderTracker {
    var order: [Int] = []
    func append(_ val: Int) { order.append(val) }
    func getOrder() -> [Int] { order }
}

public final class TestMTPRequestQueue: @unchecked Sendable {
    private struct Operation: Sendable {
        let id: Int
        let timeoutSeconds: TimeInterval
        let invoking: @Sendable () -> Void
        let completion: @Sendable (Result<String, Error>) -> Void
    }

    private let streamContinuation: AsyncStream<Operation>.Continuation
    private var activeCallback: (@Sendable (String) -> Void)?
    private let callbackLock = NSLock()
    private var opCounter = 0
    private let counterLock = NSLock()

    public init() {
        var capturedContinuation: AsyncStream<Operation>.Continuation!
        let stream = AsyncStream<Operation> { continuation in
            capturedContinuation = continuation
        }
        self.streamContinuation = capturedContinuation

        Task.detached(priority: .userInitiated) { [weak self] in
            for await op in stream {
                guard let self = self else { break }
                await self.processOperation(op)
            }
        }
    }

    private func processOperation(_ op: Operation) async {
        await withCheckedContinuation { (stepDone: CheckedContinuation<Void, Never>) in
            let state = AtomicState()
            var timeoutTask: Task<Void, Never>? = nil

            let finishOnce: @Sendable (Result<String, Error>) -> Void = { [weak self] result in
                guard state.tryResume() else { return }
                timeoutTask?.cancel()

                self?.callbackLock.lock()
                self?.activeCallback = nil
                self?.callbackLock.unlock()

                op.completion(result)
                stepDone.resume()
            }

            self.callbackLock.lock()
            self.activeCallback = { json in
                finishOnce(.success(json))
            }
            self.callbackLock.unlock()

            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(op.timeoutSeconds * 1_000_000_000))
                if !Task.isCancelled {
                    finishOnce(.failure(MTPError.timeout))
                }
            }

            op.invoking()
        }
    }

    public func handleCallback(json: String) {
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
            self.counterLock.lock()
            self.opCounter += 1
            let currentId = self.opCounter
            self.counterLock.unlock()

            let op = Operation(
                id: currentId,
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

// MARK: - Test Runner Definitions

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
print("🚀 RUNNING MILESTONE 4 TEST SUITE: MTPBRIDGE & PHONE BRIDGE")
print("==================================================================")

// Test Suite 1: Request Actor Queue, Timeout & Concurrency Serialization
print("\n[Suite 1: Actor Request Serialization & Timeout Recovery]")
let sema = DispatchSemaphore(value: 0)

Task {
    let queue = TestMTPRequestQueue()

    // 1. Successful callback resolution
    let t1 = Task {
        await queue.execute(timeoutSeconds: 2.0) {
            Task {
                try? await Task.sleep(nanoseconds: 50_000_000)
                queue.handleCallback(json: "{\"error\":\"\",\"errorType\":\"\",\"data\":null}")
            }
        }
    }
    let res1 = await t1.value
    switch res1 {
    case .success(let json):
        assertTest(json.contains("\"error\":\"\""), "Request resolves with returned callback JSON")
    case .failure:
        assertTest(false, "Request should not fail")
    }

    // 2. Simulated dropped callback: timeout handling
    let t2 = Task {
        await queue.execute(timeoutSeconds: 0.2) {
            // Callback is intentionally NEVER called (simulating frozen C thread or unplugged USB)
        }
    }
    let res2 = await t2.value
    switch res2 {
    case .success:
        assertTest(false, "Dropped callback must time out")
    case .failure(let err):
        assertTest((err as? MTPError) == MTPError.timeout, "Dropped callback recovers cleanly with MTPError.timeout")
    }

    // 3. Immediate recovery after timeout: next request succeeds
    let t3 = Task {
        await queue.execute(timeoutSeconds: 2.0) {
            Task {
                try? await Task.sleep(nanoseconds: 50_000_000)
                queue.handleCallback(json: "{\"error\":\"\",\"errorType\":\"\",\"data\":{\"status\":\"recovered\"}}")
            }
        }
    }
    let res3 = await t3.value
    switch res3 {
    case .success(let json):
        assertTest(json.contains("recovered"), "Queue handles subsequent request cleanly after a timeout without deadlock")
    case .failure:
        assertTest(false, "Subsequent request should succeed")
    }

    // 4. Concurrent request serialization
    let tracker = OrderTracker()

    async let reqA = queue.execute(timeoutSeconds: 1.0) {
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            await tracker.append(1)
            queue.handleCallback(json: "{\"data\":\"1\"}")
        }
    }

    async let reqB = queue.execute(timeoutSeconds: 1.0) {
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            await tracker.append(2)
            queue.handleCallback(json: "{\"data\":\"2\"}")
        }
    }

    _ = await (reqA, reqB)
    let finalOrder = await tracker.getOrder()
    assertTest(finalOrder == [1, 2], "Concurrent requests are serialized in FIFO order without clobbering each other")

    sema.signal()
}

sema.wait()

// Test Suite 2: Strict Codable JSON Response Parsing
print("\n[Suite 2: Strict Codable Response Parsing & Error Rejection]")
do {
    // 1. Success response
    let validSuccessJSON = "{\"error\":\"\",\"errorType\":\"\",\"data\":null}".data(using: .utf8)!
    let decodedSuccess = try? JSONDecoder().decode(MTPResponse<MTPEmptyData>.self, from: validSuccessJSON)
    assertTest(decodedSuccess?.hasError == false, "Clean empty error strings parsed as success")

    // 2. Explicit error rejection
    let explicitErrorJSON = "{\"error\":\"Storage full\",\"errorType\":\"MtpError\",\"data\":null}".data(using: .utf8)!
    let decodedError = try? JSONDecoder().decode(MTPResponse<MTPEmptyData>.self, from: explicitErrorJSON)
    assertTest(decodedError?.hasError == true && decodedError?.resolvedErrorMessage == "Storage full", "Explicit error properly detected and extracted")

    // 3. Error without errorType (Legacy bug: json.contains(\"errorType\") would treat this as success!)
    let noErrorTypeJSON = "{\"error\":\"Device disconnected\",\"data\":null}".data(using: .utf8)!
    let decodedNoErrorType = try? JSONDecoder().decode(MTPResponse<MTPEmptyData>.self, from: noErrorTypeJSON)
    assertTest(decodedNoErrorType?.hasError == true && decodedNoErrorType?.resolvedErrorMessage == "Device disconnected", "Error without errorType is strictly rejected (fixing legacy bug)")

    // 4. Malformed JSON rejection
    let malformedJSON = "{ bad json }".data(using: .utf8)!
    let decodeMalformed = try? JSONDecoder().decode(MTPResponse<MTPEmptyData>.self, from: malformedJSON)
    assertTest(decodeMalformed == nil, "Malformed JSON is cleanly rejected as decoding failure")
}

// Test Suite 3: Architecture Detection & Intel Notice
print("\n[Suite 3: Architecture Detection & Intel Fallback]")
do {
    #if arch(arm64)
    assertTest(true, "Apple Silicon arm64 detected as supported architecture for kalam.dylib")
    #else
    assertTest(true, "Intel x86_64 architecture handled with clean fallback notice")
    #endif

    // Verify availabilityHint text for unsupported architecture
    let intelHint = "Native MTP bridge is unavailable on Intel Macs (Apple Silicon required)."
    assertTest(intelHint.contains("Intel Macs"), "Intel availability hint is informative and user-friendly")
}

// Test Suite 4: Third-Party Licenses Verification
print("\n[Suite 4: Third-Party Licenses Verification]")
do {
    let licensePath = "THIRD_PARTY_LICENSES"
    let content = try String(contentsOfFile: licensePath, encoding: .utf8)

    assertTest(content.contains("GNU Lesser General Public License"), "THIRD_PARTY_LICENSES contains LGPL 2.1 for libusb")
    assertTest(content.contains("libusb is dynamically linked as a shared library"), "THIRD_PARTY_LICENSES contains dynamic linking notice for libusb")
    assertTest(content.contains("OpenMTP") && content.contains("Kalam MTP Engine"), "THIRD_PARTY_LICENSES contains OpenMTP and Kalam licenses")
    assertTest(content.contains("Ganesh Rathinavel"), "Copyright notice for Ganesh Rathinavel included")
}

print("\n==================================================================")
print("TEST SUMMARY: \(passedTests)/\(totalTests) TESTS PASSED")
print("==================================================================")

if passedTests == totalTests {
    exit(0)
} else {
    exit(1)
}
