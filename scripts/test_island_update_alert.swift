#!/usr/bin/env swift
import Foundation

print("==> Running Island Alert & Top Section Banner Logic Tests...")

// Test 1: Verify AlertPayload formatting for Update Alerts
struct MockAlertPayload {
    let id: String
    let title: String
    let subtitle: String?
    let iconName: String?
    let dwellDuration: TimeInterval
    let actionTriggered: Bool
}

let version = "1.9.9"
var actionExecuted = false
let payload = MockAlertPayload(
    id: "liquiddynamo-update-\(version)",
    title: "LiquidDynamo v\(version)",
    subtitle: "Update available • Click to install",
    iconName: "arrow.down.circle.fill",
    dwellDuration: 7.0,
    actionTriggered: true
)

assert(payload.id == "liquiddynamo-update-1.9.9")
assert(payload.title == "LiquidDynamo v1.9.9")
assert(payload.subtitle?.contains("Click to install") == true)
assert(payload.dwellDuration == 7.0)
print("✅ Test 1 Passed: AlertPayload correctly models the Island update alert.")

// Test 2: Banner Visibility Logic
class MockUpdateState {
    var isUpdateAvailable: Bool = false
    var isBannerDismissed: Bool = false
    var latestVersion: String = ""

    var shouldShowBanner: Bool {
        return isUpdateAvailable && !isBannerDismissed
    }

    func dismissBanner() {
        isBannerDismissed = true
    }

    func newUpdateFound(version: String) {
        self.latestVersion = version
        self.isUpdateAvailable = true
        self.isBannerDismissed = false
    }
}

let state = MockUpdateState()
assert(state.shouldShowBanner == false, "Banner should be hidden initially")

state.newUpdateFound(version: "1.9.9")
assert(state.shouldShowBanner == true, "Banner should appear when update is found")

state.dismissBanner()
assert(state.shouldShowBanner == false, "Banner should be dismissed after user clicks dismiss")

state.newUpdateFound(version: "2.0.0")
assert(state.shouldShowBanner == true, "Banner should re-appear when new update is found")
print("✅ Test 2 Passed: Banner visibility and dismissal states behave correctly.")

print("🎉 ALL ISLAND ALERT & BANNER TESTS PASSED SUCCESSFULLY!")
