//
//  MockPowerAssertionProvider.swift
//  LiquidDynamo
//
//  Mock implementation of PowerAssertionProviding for unit testing and UI previews.
//  Records assertion creations, releases, and verifies assertions are released without leaks.
//

import Foundation
import IOKit.pwr_mgt

public final class MockPowerAssertionProvider: PowerAssertionProviding {
    public struct AssertionRecord: Equatable {
        public let id: IOPMAssertionID
        public let type: String
        public let level: IOPMAssertionLevel
        public let name: String
    }

    public var shouldFailCreation: Bool = false
    public var simulatedErrorCode: IOReturn = kIOReturnError

    public private(set) var activeAssertions: [IOPMAssertionID: AssertionRecord] = [:]
    public private(set) var createdRecords: [AssertionRecord] = []
    public private(set) var releasedIDs: [IOPMAssertionID] = []

    private var nextID: IOPMAssertionID = 1001

    public init() {}

    public func createAssertion(
        type: CFString,
        level: IOPMAssertionLevel,
        name: CFString
    ) -> (assertionID: IOPMAssertionID, result: IOReturn) {
        if shouldFailCreation {
            return (0, simulatedErrorCode)
        }

        let id = nextID
        nextID += 1

        let record = AssertionRecord(
            id: id,
            type: type as String,
            level: level,
            name: name as String
        )
        activeAssertions[id] = record
        createdRecords.append(record)

        return (id, kIOReturnSuccess)
    }

    public func releaseAssertion(id: IOPMAssertionID) -> IOReturn {
        guard activeAssertions.removeValue(forKey: id) != nil else {
            return kIOReturnNotFound
        }
        releasedIDs.append(id)
        return kIOReturnSuccess
    }

    /// Reset all records.
    public func reset() {
        activeAssertions.removeAll()
        createdRecords.removeAll()
        releasedIDs.removeAll()
        shouldFailCreation = false
    }

    /// Verifies all created assertions have been released.
    public var hasNoActiveLeaks: Bool {
        activeAssertions.isEmpty
    }
}
