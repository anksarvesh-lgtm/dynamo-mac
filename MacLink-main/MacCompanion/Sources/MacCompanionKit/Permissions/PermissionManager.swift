// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices

public struct PermissionStatus: Sendable {
    public let isAccessibilityGranted: Bool
    public let isInputMonitoringGranted: Bool

    public init(isAccessibilityGranted: Bool, isInputMonitoringGranted: Bool) {
        self.isAccessibilityGranted = isAccessibilityGranted
        self.isInputMonitoringGranted = isInputMonitoringGranted
    }
}

public final class PermissionManager: Sendable {
    public static func checkPermissions() -> PermissionStatus {
        let axGranted = AXIsProcessTrusted()

        // Check listen event permission via CGEventTap probe
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: (1 << CGEventType.mouseMoved.rawValue),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        )
        let inputMonitoringGranted = (tap != nil)

        return PermissionStatus(
            isAccessibilityGranted: axGranted,
            isInputMonitoringGranted: inputMonitoringGranted
        )
    }

    public static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    public static func openSystemAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public static func openSystemInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}

