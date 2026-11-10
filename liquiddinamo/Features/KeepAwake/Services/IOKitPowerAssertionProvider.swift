//
//  IOKitPowerAssertionProvider.swift
//  LiquidDynamo
//
//  Production implementation of PowerAssertionProviding using macOS IOKit power management APIs.
//

import Foundation
import IOKit.pwr_mgt

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
        guard id != 0 else {
            return kIOReturnBadArgument
        }
        return IOPMAssertionRelease(id)
    }
}
