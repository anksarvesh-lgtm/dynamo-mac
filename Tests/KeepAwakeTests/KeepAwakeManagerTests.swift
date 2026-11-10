//
//  KeepAwakeManagerTests.swift
//  LiquidDynamoTests
//
//  Comprehensive test suite for KeepAwakeManager and MockPowerAssertionProvider.
//

import Foundation
import IOKit.pwr_mgt

#if canImport(LiquidDynamo)
@testable import LiquidDynamo
#endif

@MainActor
public final class KeepAwakeManagerTests {
    private var mockProvider: MockPowerAssertionProvider!
    private var manager: KeepAwakeManager!

    public init() {
        setUp()
    }

    public func setUp() {
        mockProvider = MockPowerAssertionProvider()
        manager = KeepAwakeManager(assertionProvider: mockProvider)
    }

    public func tearDown() {
        manager.stop()
        mockProvider.reset()
    }

    // MARK: - Test Cases

    /// Test 1: Starting session with each preset acquires correct assertion type, level, and calculates end date.
    public func testPresetsAndAssertionTypes() {
        let presets: [KeepAwakePreset] = [.m15, .m30, .h1, .h2, .h4, .h8]

        for preset in presets {
            setUp()
            let success = manager.start(mode: .displayAndSystem, duration: .preset(preset))
            assert(success, "Failed to start preset \(preset.rawValue)")
            assert(manager.isActive, "Manager should be active for preset \(preset.rawValue)")
            assert(!manager.isIndefinite, "Preset \(preset.rawValue) should not be indefinite")
            assert(manager.endDate != nil, "End date must be populated")

            let expectedSeconds = preset.durationSeconds!
            let delta = abs(manager.totalDurationSeconds - expectedSeconds)
            assert(delta < 1.0, "Expected duration \(expectedSeconds), got \(manager.totalDurationSeconds)")

            // Check provider records
            assert(mockProvider.createdRecords.count == 1, "Exactly one assertion should be created")
            let record = mockProvider.createdRecords[0]
            assert(record.type == (kIOPMAssertionTypePreventUserIdleDisplaySleep as String), "Type mismatch")
            assert(record.name.contains("Keep Awake active"), "Name must contain descriptive reason")

            manager.stop()
            assert(!manager.isActive, "Manager should be inactive after stop")
            assert(mockProvider.hasNoActiveLeaks, "Assertion leak detected for preset \(preset.rawValue)")
        }
    }

    /// Test 2: System-only mode uses kIOPMAssertionTypePreventUserIdleSystemSleep.
    public func testSystemOnlyModeAssertionType() {
        setUp()
        let success = manager.start(mode: .system, duration: .preset(.m30))
        assert(success, "Failed to start system mode")
        assert(mockProvider.createdRecords.count == 1)
        assert(mockProvider.createdRecords[0].type == (kIOPMAssertionTypePreventUserIdleSystemSleep as String))
        assert(mockProvider.activeAssertions.count == 1)

        manager.stop()
        assert(mockProvider.hasNoActiveLeaks, "Assertion leaked")
    }

    /// Test 3: Indefinite session sets isIndefinite = true and nil endDate.
    public func testIndefiniteDuration() {
        setUp()
        let success = manager.start(mode: .displayAndSystem, duration: .indefinite)
        assert(success)
        assert(manager.isActive)
        assert(manager.isIndefinite)
        assert(manager.endDate == nil, "Indefinite session must have nil endDate")
        assert(manager.remainingFormatted == "Indefinite")
        assert(manager.progress == 1.0)

        manager.stop()
        assert(mockProvider.hasNoActiveLeaks)
    }

    /// Test 4: Starting a new session while one is active cleanly replaces the assertion without leaks.
    public func testConsecutiveStartsCleanReplacement() {
        setUp()
        _ = manager.start(mode: .system, duration: .preset(.m15))
        assert(mockProvider.createdRecords.count == 1)
        assert(mockProvider.activeAssertions.count == 1)
        let firstID = mockProvider.createdRecords[0].id

        // Start another session immediately
        _ = manager.start(mode: .displayAndSystem, duration: .preset(.h1))
        assert(mockProvider.createdRecords.count == 2)
        assert(mockProvider.activeAssertions.count == 1, "Should only have 1 active assertion at any time")
        assert(mockProvider.releasedIDs.contains(firstID), "First assertion was not released")

        manager.stop()
        assert(mockProvider.hasNoActiveLeaks)
    }

    /// Test 5: Extending an active session pushes the end date forward and increases total duration.
    public func testExtendSession() {
        setUp()
        _ = manager.start(mode: .displayAndSystem, duration: .preset(.m15))
        let initialEndDate = manager.endDate!
        let initialTotal = manager.totalDurationSeconds

        // Extend by +15 min (900 seconds)
        manager.extend(by: 900)

        let newEndDate = manager.endDate!
        let addedInterval = newEndDate.timeIntervalSince(initialEndDate)
        assert(abs(addedInterval - 900) < 2.0, "End date should be extended by ~900s, got \(addedInterval)")
        assert(manager.totalDurationSeconds == initialTotal + 900, "Total duration must reflect extension")

        manager.stop()
        assert(mockProvider.hasNoActiveLeaks)
    }

    /// Test 6: Extending an indefinite session is a no-op.
    public func testExtendIndefiniteIsNoOp() {
        setUp()
        _ = manager.start(mode: .displayAndSystem, duration: .indefinite)
        manager.extend(by: 900)
        assert(manager.isIndefinite)
        assert(manager.endDate == nil)

        manager.stop()
        assert(mockProvider.hasNoActiveLeaks)
    }

    /// Test 7: Changing mode mid-session re-creates assertion with new type and preserves remaining duration.
    public func testChangeModeMidSession() {
        setUp()
        _ = manager.start(mode: .system, duration: .preset(.h1))
        assert(mockProvider.createdRecords.last?.type == (kIOPMAssertionTypePreventUserIdleSystemSleep as String))

        manager.changeMode(to: .displayAndSystem)
        assert(manager.mode == .displayAndSystem)
        assert(manager.isActive)
        assert(mockProvider.activeAssertions.count == 1, "Only 1 active assertion should exist")
        assert(mockProvider.createdRecords.last?.type == (kIOPMAssertionTypePreventUserIdleDisplaySleep as String))
        assert(manager.remainingSeconds > 0, "Remaining seconds must be preserved")

        manager.stop()
        assert(mockProvider.hasNoActiveLeaks)
    }

    /// Test 8: Custom duration validation enforces min 1 min, max 24 hours, rejects negatives.
    public func testCustomDurationValidation() {
        // Negative hours or minutes
        assert(KeepAwakeDuration.validate(hours: -1, minutes: 10) == .failure(.negativeDuration))
        assert(KeepAwakeDuration.validate(hours: 1, minutes: -5) == .failure(.negativeDuration))

        // 0 duration (< 60s)
        assert(KeepAwakeDuration.validate(hours: 0, minutes: 0) == .failure(.tooShort))

        // > 24 hours (25 hours)
        assert(KeepAwakeDuration.validate(hours: 24, minutes: 1) == .failure(.tooLong))
        assert(KeepAwakeDuration.validate(hours: 25, minutes: 0) == .failure(.tooLong))

        // Valid boundary: 1 minute
        if case .success(let secs) = KeepAwakeDuration.validate(hours: 0, minutes: 1) {
            assert(secs == 60)
        } else {
            assertionFailure("1 min should be valid")
        }

        // Valid boundary: 24 hours
        if case .success(let secs) = KeepAwakeDuration.validate(hours: 24, minutes: 0) {
            assert(secs == 86400)
        } else {
            assertionFailure("24 hours should be valid")
        }

        // Valid: 2 hours 45 mins
        if case .success(let secs) = KeepAwakeDuration.validate(hours: 2, minutes: 45) {
            assert(secs == (2 * 3600 + 45 * 60))
        } else {
            assertionFailure("2h 45m should be valid")
        }
    }

    /// Test 9: Failure in power assertion creation gracefully reports error and does not activate.
    public func testAssertionCreationFailure() {
        setUp()
        mockProvider.shouldFailCreation = true
        let success = manager.start(mode: .system, duration: .preset(.m15))
        assert(!success, "Start should return false on assertion failure")
        assert(!manager.isActive, "Manager must not be active")
        assert(manager.lastErrorMessage != nil, "Error message must be set")
        assert(mockProvider.hasNoActiveLeaks)
    }

    /// Run all unit tests and print results.
    public static func runAll() {
        let suite = KeepAwakeManagerTests()
        print("▶ Running KeepAwakeManagerTests...")
        suite.testPresetsAndAssertionTypes()
        print("  ✓ testPresetsAndAssertionTypes passed")
        suite.testSystemOnlyModeAssertionType()
        print("  ✓ testSystemOnlyModeAssertionType passed")
        suite.testIndefiniteDuration()
        print("  ✓ testIndefiniteDuration passed")
        suite.testConsecutiveStartsCleanReplacement()
        print("  ✓ testConsecutiveStartsCleanReplacement passed")
        suite.testExtendSession()
        print("  ✓ testExtendSession passed")
        suite.testExtendIndefiniteIsNoOp()
        print("  ✓ testExtendIndefiniteIsNoOp passed")
        suite.testChangeModeMidSession()
        print("  ✓ testChangeModeMidSession passed")
        suite.testCustomDurationValidation()
        print("  ✓ testCustomDurationValidation passed")
        suite.testAssertionCreationFailure()
        print("  ✓ testAssertionCreationFailure passed")
        print("🎉 All 9 KeepAwakeManager tests PASSED with zero leaks!")
    }
}
