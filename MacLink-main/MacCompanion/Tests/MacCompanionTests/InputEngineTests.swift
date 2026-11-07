// SPDX-License-Identifier: MIT
import Foundation
import MacCompanionKit

struct InputEngineTests {
    static func runAll() {
        print("Running Input Engine Tests...")
        testForceTouchMonitorStages()
        testMagicMouseCapabilities()
        testTrackpadMonitorState()
        print("All Input Engine Tests passed successfully!")
    }

    private static func testForceTouchMonitorStages() {
        let monitor = ForceTouchMonitor()
        monitor.isHapticFeedbackEnabled = false // headless test

        var lastRecordedStage: ForceTouchStage = .resting
        var lastPressure: Float = 0.0

        final class TestDelegate: ForceTouchDelegate, @unchecked Sendable {
            var onStageChanged: ((ForceTouchStage, Float) -> Void)?
            func didChangeForceTouchStage(stage: ForceTouchStage, pressure: Float) {
                onStageChanged?(stage, pressure)
            }
        }

        let delegate = TestDelegate()
        delegate.onStageChanged = { stage, pressure in
            lastRecordedStage = stage
            lastPressure = pressure
        }
        monitor.delegate = delegate

        // Process stage 1 (Click)
        monitor.processPressureEvent(stage: 1, pressure: 0.6)
        assert(lastRecordedStage == .normalClick, "Should transition to normalClick")
        assert(lastPressure == 0.6, "Pressure should match")

        // Process stage 2 (Force Click)
        monitor.processPressureEvent(stage: 2, pressure: 0.95)
        assert(lastRecordedStage == .forceClick, "Should transition to forceClick")

        // Release
        monitor.processPressureEvent(stage: 0, pressure: 0.0)
        assert(lastRecordedStage == .resting, "Should return to resting")
        print("✓ ForceTouchMonitor stages verified")
    }

    private static func testMagicMouseCapabilities() {
        let monitor = MagicMouseMonitor()
        assert(!monitor.state.isForceTouchSupported, "Magic Mouse must never claim Force Touch support")

        monitor.recordScroll(deltaX: 10.0, deltaY: -5.0, momentum: false)
        assert(monitor.state.lastScrollDeltaX == 10.0, "DeltaX should be recorded")
        assert(monitor.state.lastScrollDeltaY == -5.0, "DeltaY should be recorded")
        assert(!monitor.state.isMomentumActive, "Momentum should be false")

        monitor.recordSwipe(direction: "left")
        assert(monitor.state.lastSwipeDirection == "left", "Swipe direction should be recorded")
        print("✓ MagicMouseMonitor capabilities and scrolling verified")
    }

    private static func testTrackpadMonitorState() {
        let monitor = TrackpadMonitor()
        monitor.updateTouches(count: 3)
        assert(monitor.state.activeTouchCount == 3, "Touch count should match")
        assert(monitor.state.isTouching, "isTouching should be true")

        monitor.updateMagnification(1.4)
        assert(monitor.state.magnification == 1.4, "Magnification should match")

        monitor.updateRotation(45.0)
        assert(monitor.state.rotationDegrees == 45.0, "Rotation degrees should match")
        print("✓ TrackpadMonitor state updates verified")
    }
}

