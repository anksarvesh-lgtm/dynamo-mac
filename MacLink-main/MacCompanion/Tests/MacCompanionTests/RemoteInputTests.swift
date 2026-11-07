// SPDX-License-Identifier: MIT
import Foundation
import MacCompanionKit

struct RemoteInputTests {
    static func runAll() {
        print("Running Remote Input Tests...")
        testEmergencyInputCleanup()
        testSessionManagerLifecycle()
        print("All Remote Input Tests passed successfully!")
    }

    private static func testEmergencyInputCleanup() {
        let controller = RemoteInputController()

        // Press down left and right buttons
        controller.handlePointerDown(button: .left)
        controller.handlePointerDown(button: .right)
        assert(controller.buttonStateSummary.contains("Left: true"), "Left button should be recorded as held")
        assert(controller.buttonStateSummary.contains("Right: true"), "Right button should be recorded as held")

        // Emergency cleanup (simulating sudden disconnect)
        controller.emergencyInputCleanup()
        assert(controller.buttonStateSummary.contains("Left: false"), "Left button must be released on emergency cleanup")
        assert(controller.buttonStateSummary.contains("Right: false"), "Right button must be released on emergency cleanup")
        print("✓ EmergencyInputCleanup stuck-button fail-safe verified")
    }

    private static func testSessionManagerLifecycle() {
        let manager = SessionManager()
        let device = PairedDevice(id: "dev-phone-1", name: "Pixel 8", sharedSecret: "secret-xyz")
        manager.addPairedDevice(device)

        let sessionId = manager.createSession(forDeviceId: device.id)
        assert(manager.isSessionValid(sessionId), "Session should be valid")

        manager.closeSession(sessionId)
        assert(!manager.isSessionValid(sessionId), "Closed session must not be valid")
        print("✓ SessionManager lifecycle verified")
    }
}

