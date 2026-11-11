// SPDX-License-Identifier: MIT
import Foundation
import IOKit.pwr_mgt

public protocol PowerAssertionProviding: AnyObject {
    func createAssertion(
        type: CFString,
        level: IOPMAssertionLevel,
        name: CFString
    ) -> (assertionID: IOPMAssertionID, result: IOReturn)

    func releaseAssertion(id: IOPMAssertionID) -> IOReturn
}

public final class IOKitPowerAssertionProvider: PowerAssertionProviding {
    public init() {}

    public func createAssertion(
        type: CFString,
        level: IOPMAssertionLevel,
        name: CFString
    ) -> (assertionID: IOPMAssertionID, result: IOReturn) {
        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type,
            level,
            name,
            &assertionID
        )
        return (assertionID, result)
    }

    public func releaseAssertion(id: IOPMAssertionID) -> IOReturn {
        guard id != 0 else { return kIOReturnBadArgument }
        return IOPMAssertionRelease(id)
    }
}

public final class MockPowerAssertionProvider: PowerAssertionProviding {
    public var createdAssertions: [(type: CFString, level: IOPMAssertionLevel, name: CFString)] = []
    public var releasedIDs: [IOPMAssertionID] = []
    private var nextID: IOPMAssertionID = 100

    public init() {}

    public func createAssertion(
        type: CFString,
        level: IOPMAssertionLevel,
        name: CFString
    ) -> (assertionID: IOPMAssertionID, result: IOReturn) {
        let id = nextID
        nextID += 1
        createdAssertions.append((type, level, name))
        return (id, kIOReturnSuccess)
    }

    public func releaseAssertion(id: IOPMAssertionID) -> IOReturn {
        releasedIDs.append(id)
        return kIOReturnSuccess
    }

    public func reset() {
        createdAssertions.removeAll()
        releasedIDs.removeAll()
        nextID = 100
    }
}
