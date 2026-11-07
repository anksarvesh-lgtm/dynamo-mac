//
//  KeepAwakeService.swift
//  LiquidDynamo
//
//  Clamshell mode & sleep prevention controller using IOKit power assertions.
//  Merged from Ledge.
//

import Combine
import Foundation
import IOKit.pwr_mgt

@MainActor
public final class KeepAwakeService: ObservableObject {
    public static let shared = KeepAwakeService()

    @Published public private(set) var isKeepAwakeActive: Bool = false
    private var assertionID: IOPMAssertionID = 0

    private init() {}

    public func toggleKeepAwake() {
        if isKeepAwakeActive {
            disableKeepAwake()
        } else {
            enableKeepAwake()
        }
    }

    public func enableKeepAwake() {
        guard !isKeepAwakeActive else { return }

        let reason = "LiquidDynamo Keep Awake Clamshell Mode" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )

        if result == kIOReturnSuccess {
            isKeepAwakeActive = true
        }
    }

    public func disableKeepAwake() {
        guard isKeepAwakeActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isKeepAwakeActive = false
    }

    deinit {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
        }
    }
}
