// SPDX-License-Identifier: MIT
import Foundation

public enum ValidationError: Error, Sendable, Equatable {
    case unsupportedVersion(Int)
    case invalidSessionId(String)
    case invalidTimestamp(UInt64)
    case sequenceViolation(expected: UInt64, received: UInt64)
    case malformedPayload(String)
    case unknownEventType(String)
}

public final class SequenceManager: @unchecked Sendable {
    private let lock = NSLock()
    private var lastSequence: UInt64 = 0
    private var isInitialized = false

    public init() {}

    public func reset(initialSequence: UInt64 = 0) {
        lock.lock()
        defer { lock.unlock() }
        lastSequence = initialSequence
        isInitialized = initialSequence > 0
    }

    public func validateAndAdvance(sequence: UInt64, isHeartbeat: Bool = false) -> Result<Void, ValidationError> {
        lock.lock()
        defer { lock.unlock() }

        if !isInitialized {
            lastSequence = sequence
            isInitialized = true
            return .success(())
        }

        // Heartbeats are allowed to have out-of-band sequence or repeat if needed,
        // but input events must be strictly monotonically increasing.
        if sequence <= lastSequence && !isHeartbeat {
            return .failure(.sequenceViolation(expected: lastSequence + 1, received: sequence))
        }

        lastSequence = max(lastSequence, sequence)
        return .success(())
    }

    public var currentSequence: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return lastSequence
    }
}

public struct EventValidator: Sendable {
    public static let supportedVersion = 1
    public static let maxClockDriftMs: UInt64 = 60_000 // 60s tolerance

    public static func validateEnvelope(
        _ envelope: TouchpadEnvelope,
        expectedSessionId: String? = nil,
        sequenceManager: SequenceManager? = nil
    ) -> Result<TouchpadEnvelope, ValidationError> {
        // 1. Version check
        guard envelope.version == supportedVersion else {
            return .failure(.unsupportedVersion(envelope.version))
        }

        // 2. Session ID check
        guard envelope.sessionId.count >= 8 && envelope.sessionId.count <= 128 else {
            return .failure(.invalidSessionId(envelope.sessionId))
        }
        if let expected = expectedSessionId, envelope.sessionId != expected {
            return .failure(.invalidSessionId("Session mismatch: expected \(expected), got \(envelope.sessionId)"))
        }

        // 3. Timestamp drift check
        let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let drift = nowMs > envelope.timestamp ? (nowMs - envelope.timestamp) : (envelope.timestamp - nowMs)
        if drift > maxClockDriftMs {
            return .failure(.invalidTimestamp(envelope.timestamp))
        }

        // 4. Monotonic sequence check
        if let seqMgr = sequenceManager {
            let isHeartbeat = envelope.eventType == .connectionPing || envelope.eventType == .connectionPong
            let seqResult = seqMgr.validateAndAdvance(sequence: envelope.sequence, isHeartbeat: isHeartbeat)
            if case .failure(let err) = seqResult {
                return .failure(err)
            }
        }

        return .success(envelope)
    }

    public static func extractPointerMove(_ envelope: TouchpadEnvelope) -> PointerMovePayload? {
        guard envelope.eventType == .pointerMove,
              let dx = envelope.payload["deltaX"]?.asDouble,
              let dy = envelope.payload["deltaY"]?.asDouble else {
            return nil
        }
        return PointerMovePayload(deltaX: dx, deltaY: dy)
    }

    public static func extractScroll(_ envelope: TouchpadEnvelope) -> ScrollPayload? {
        guard envelope.eventType == .scroll,
              let dx = envelope.payload["deltaX"]?.asDouble,
              let dy = envelope.payload["deltaY"]?.asDouble else {
            return nil
        }
        let continuous = envelope.payload["isContinuous"]?.asBool ?? true
        let phaseStr = envelope.payload["phase"]?.asString ?? "changed"
        let phase = ScrollPayload.Phase(rawValue: phaseStr) ?? .changed
        return ScrollPayload(deltaX: dx, deltaY: dy, isContinuous: continuous, phase: phase)
    }
}

