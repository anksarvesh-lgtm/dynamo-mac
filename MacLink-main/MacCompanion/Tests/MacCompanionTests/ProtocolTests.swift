// SPDX-License-Identifier: MIT
import Foundation
import MacCompanionKit

@main
struct ProtocolTestMain {
    static func main() throws {
        print("Running Protocol Tests...")
        try testEnvelopeSerializationRoundTrip()
        testSequenceManagerEnforcesMonotonicOrdering()
        testValidatorRejectsIncompatibleVersion()
        print("All Protocol Tests passed successfully!")

        InputEngineTests.runAll()
        RemoteInputTests.runAll()
        KeepAwakeTests.runAll()
    }

    static func testEnvelopeSerializationRoundTrip() throws {
        let payload: [String: AnyCodableValue] = [
            "deltaX": AnyCodableValue(.double(12.5)),
            "deltaY": AnyCodableValue(.double(-8.0))
        ]
        let envelope = TouchpadEnvelope(
            version: 1,
            sessionId: "test-session-12345678",
            sequence: 42,
            timestamp: 1793658000000,
            eventType: .pointerMove,
            payload: payload
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(envelope)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TouchpadEnvelope.self, from: data)

        assert(decoded.version == 1, "Version must be 1")
        assert(decoded.sessionId == "test-session-12345678", "SessionId must match")
        assert(decoded.sequence == 42, "Sequence must be 42")
        assert(decoded.eventType == .pointerMove, "EventType must be pointerMove")

        let movePayload = EventValidator.extractPointerMove(decoded)
        assert(movePayload != nil, "PointerMovePayload should be parsed")
        assert(movePayload?.deltaX == 12.5, "deltaX should match")
        assert(movePayload?.deltaY == -8.0, "deltaY should match")
        print("✓ Envelope round-trip test passed")
    }

    static func testSequenceManagerEnforcesMonotonicOrdering() {
        let seq = SequenceManager()
        if case .failure = seq.validateAndAdvance(sequence: 10) { fatalError("First sequence should succeed") }
        if case .failure = seq.validateAndAdvance(sequence: 11) { fatalError("Monotonic advance should succeed") }
        if case .failure = seq.validateAndAdvance(sequence: 15) { fatalError("Monotonic jump should succeed") }

        // Out-of-order / replay must fail
        let replayResult = seq.validateAndAdvance(sequence: 12)
        if case .failure(let err) = replayResult {
            assert(err == .sequenceViolation(expected: 16, received: 12), "Expected sequence violation")
        } else {
            fatalError("Replayed sequence should be rejected")
        }

        // Heartbeats are permitted
        if case .failure = seq.validateAndAdvance(sequence: 15, isHeartbeat: true) {
            fatalError("Heartbeat replay should succeed")
        }
        print("✓ Sequence manager monotonic order test passed")
    }

    static func testValidatorRejectsIncompatibleVersion() {
        let badEnvelope = TouchpadEnvelope(
            version: 2,
            sessionId: "test-session-12345678",
            sequence: 1,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            eventType: .pointerMove,
            payload: [:]
        )
        let result = EventValidator.validateEnvelope(badEnvelope)
        assert(result == .failure(.unsupportedVersion(2)), "Incompatible version should be rejected")
        print("✓ Version validation test passed")
    }
}


