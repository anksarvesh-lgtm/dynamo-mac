// SPDX-License-Identifier: MIT
import Foundation
@testable import MacCompanionKit

public struct KeepAwakeTests {
    @MainActor
    public static func runAll() {
        print("Running Keep Awake Tests...")
        testAssertionCreationAndReleaseWithMock()
        testDurationPresetsAndValidation()
        testSessionExtension()
        testReplacesExistingAssertionCleanly()
        testModeSwitchPreservesRemainingTime()
        print("All Keep Awake Tests passed successfully!")
    }

    @MainActor
    public static func testAssertionCreationAndReleaseWithMock() {
        let mock = MockPowerAssertionProvider()
        let manager = KeepAwakeManager(assertionProvider: mock)

        let started = manager.start(mode: .displayAndSystem, duration: .preset(.m15))
        assert(started, "Keep Awake session should start successfully")
        assert(manager.isActive, "Manager state should be active")
        assert(mock.createdAssertions.count == 1, "Expected 1 assertion created")
        assert(mock.releasedIDs.isEmpty, "No assertions should be released yet")

        manager.stop()
        assert(!manager.isActive, "Manager state should be inactive after stop")
        assert(mock.releasedIDs.count == 1, "Expected 1 assertion released")
        print("✓ Mock power assertion lifecycle verified")
    }

    public static func testDurationPresetsAndValidation() {
        assert(KeepAwakePreset.m15.durationSeconds == 900, "15m should be 900s")
        assert(KeepAwakePreset.h1.durationSeconds == 3600, "1h should be 3600s")
        assert(KeepAwakePreset.h8.durationSeconds == 28800, "8h should be 28800s")
        assert(KeepAwakePreset.indefinite.durationSeconds == nil, "Indefinite should be nil")

        // Validation bounds: min 1 min (60s), max 24 hours (86400s)
        let tooShort = KeepAwakeDuration.validate(hours: 0, minutes: 0)
        assert(tooShort == .failure(.tooShort), "0 minutes should fail tooShort")

        let negative = KeepAwakeDuration.validate(hours: -1, minutes: 30)
        assert(negative == .failure(.negativeDuration), "Negative should fail negativeDuration")

        let tooLong = KeepAwakeDuration.validate(hours: 25, minutes: 0)
        assert(tooLong == .failure(.tooLong), "25 hours should fail tooLong")

        let valid = KeepAwakeDuration.validate(hours: 2, minutes: 30)
        if case .success(let seconds) = valid {
            assert(seconds == 9000, "2h30m should be 9000s")
        } else {
            fatalError("Valid duration failed validation")
        }
        print("✓ Presets and duration bounds validation verified")
    }

    @MainActor
    public static func testSessionExtension() {
        let mock = MockPowerAssertionProvider()
        let manager = KeepAwakeManager(assertionProvider: mock)

        manager.start(mode: .system, duration: .preset(.m15))
        let initialRemaining = manager.remainingSeconds

        manager.extend(by: 15 * 60)
        assert(manager.remainingSeconds >= initialRemaining + 890, "Remaining seconds should increase by ~900s")
        assert(mock.createdAssertions.count == 1, "No extra assertion should be created on extend")

        manager.stop()
        print("✓ Session extension (+15m) verified")
    }

    @MainActor
    public static func testReplacesExistingAssertionCleanly() {
        let mock = MockPowerAssertionProvider()
        let manager = KeepAwakeManager(assertionProvider: mock)

        manager.start(mode: .system, duration: .preset(.m15))
        assert(mock.createdAssertions.count == 1)

        // Start new session while one is active
        manager.start(mode: .displayAndSystem, duration: .preset(.h1))
        assert(mock.releasedIDs.count == 1, "First assertion should be released before creating second")
        assert(mock.createdAssertions.count == 2, "Second assertion created")

        manager.stop()
        assert(mock.releasedIDs.count == 2, "Both assertions released cleanly")
        print("✓ Clean assertion replacement verified without leaks")
    }

    @MainActor
    public static func testModeSwitchPreservesRemainingTime() {
        let mock = MockPowerAssertionProvider()
        let manager = KeepAwakeManager(assertionProvider: mock)

        manager.start(mode: .system, duration: .preset(.h1))
        manager.changeMode(to: .displayAndSystem)

        assert(manager.mode == .displayAndSystem, "Mode should be updated to displayAndSystem")
        assert(manager.isActive, "Session should remain active")
        assert(manager.remainingSeconds > 3500, "Remaining seconds should be preserved across mode change")

        manager.stop()
        print("✓ Mode change time preservation verified")
    }
}
