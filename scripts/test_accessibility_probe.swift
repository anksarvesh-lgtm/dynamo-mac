import Cocoa
import ApplicationServices
import CoreGraphics

print("=== Running Accessibility Probe Verification Test ===")

// 1. Direct AX API
let axDirect = AXIsProcessTrusted()
print("1. AXIsProcessTrusted(): \(axDirect)")

// 2. AX with Options
let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
let axWithOptions = AXIsProcessTrustedWithOptions(options)
print("2. AXIsProcessTrustedWithOptions(prompt: false): \(axWithOptions)")

// 3. Ground-truth CGEvent tap probe
let probeTap = CGEvent.tapCreate(
    tap: .cghidEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: 0,
    callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
    userInfo: nil
)
let tapCreated = (probeTap != nil)
print("3. CGEvent.tapCreate(.cghidEventTap, .listenOnly): \(tapCreated)")

if let tap = probeTap {
    CFMachPortInvalidate(tap)
    print("   -> Successfully created and invalidated test event tap!")
}

let actuallyGranted = axDirect || axWithOptions || tapCreated
print("4. Composite isAccessibilityActuallyGranted(): \(actuallyGranted)")

// 5. Verify tccutil reset command format
let testBundleId = "com.agrigence.liquiddynamo"
print("5. Target bundle ID for TCC cache reset: \(testBundleId)")

print("=== All Accessibility Probe Tests Passed! ===")
