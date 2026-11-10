//
//  PowerAssertionProviding.swift
//  LiquidDynamo
//
//  Cleanroom protocol abstraction for macOS IOKit power assertions.
//  Enables 100% isolated unit testing with mock assertion providers.
//

import Foundation
import IOKit.pwr_mgt

public protocol PowerAssertionProviding: AnyObject {
    /// Creates a power assertion with Apple IOKit.
    /// - Parameters:
    ///   - type: Assertion type constant (e.g. kIOPMAssertionTypePreventUserIdleSystemSleep)
    ///   - level: Assertion level (e.g. kIOPMAssertionLevelOn)
    ///   - name: Descriptive reason string displayed in `pmset -g assertions`
    /// - Returns: A tuple containing the created assertion ID and the IOReturn status code.
    func createAssertion(
        type: CFString,
        level: IOPMAssertionLevel,
        name: CFString
    ) -> (assertionID: IOPMAssertionID, result: IOReturn)

    /// Releases an active power assertion.
    /// - Parameter id: The IOPMAssertionID to release.
    /// - Returns: IOReturn status code (kIOReturnSuccess on success).
    func releaseAssertion(id: IOPMAssertionID) -> IOReturn
}
