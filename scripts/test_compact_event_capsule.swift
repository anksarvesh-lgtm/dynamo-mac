import Foundation
import CoreGraphics
import AppKit

print("=== STARTING LIQUIDDYNAMO COMPACT 3D LIQUID GLASS EVENT CAPSULE TEST SUITE ===")

// MARK: - 1. Mock Geometry & Capsule Sizing Logic
struct MockNotchGeometry {
    let rawNotchWidth: CGFloat
    let notchHeight: CGFloat
    let screenWidth: CGFloat
    let hasPhysicalNotch: Bool

    var minCapsuleWidth: CGFloat {
        hasPhysicalNotch ? max(180.0, rawNotchWidth) : 180.0
    }

    var maxCapsuleWidth: CGFloat {
        min(380.0, max(280.0, screenWidth * 0.45))
    }
}

func computeAlertCapsuleSize(geom: MockNotchGeometry, contentWidth: CGFloat? = nil) -> CGSize {
    let defaultWidth: CGFloat = 220.0
    let requestedW = contentWidth ?? defaultWidth
    let width = min(geom.maxCapsuleWidth, max(geom.minCapsuleWidth, requestedW))
    let height = max(36.0, min(48.0, max(geom.notchHeight, 38.0)))
    return CGSize(width: width, height: height)
}

func calculateNotchCenteredWindowRect(notchCenterScreenX: CGFloat, size: CGSize, geom: MockNotchGeometry, screenHeight: CGFloat) -> CGRect {
    let clampedW = min(size.width, geom.screenWidth - 16.0)
    let clampedH = size.height
    let originX = notchCenterScreenX - (clampedW / 2.0)
    let originY = screenHeight - clampedH
    return CGRect(x: originX, y: originY, width: clampedW, height: clampedH)
}

// MARK: - 2. Physical MacBook Notch Geometry Tests
print("\n[TEST 1] Physical Notch Geometry (MacBook Pro 16\" - 1728x1117):")
let mbp16 = MockNotchGeometry(rawNotchWidth: 210.0, notchHeight: 34.0, screenWidth: 1728.0, hasPhysicalNotch: true)
let defaultCapsule16 = computeAlertCapsuleSize(geom: mbp16)

print("  -> Default capsule width: \(defaultCapsule16.width) pt, height: \(defaultCapsule16.height) pt")
assert(defaultCapsule16.width == 220.0, "Default width must be 220 pt")
assert(defaultCapsule16.height == 38.0, "Height must be between 36 and 48 pt")
assert(defaultCapsule16.width < 300.0, "Default capsule must not be an oversized banner")
print("  -> PASS: Default capsule size within target [180-280 pt] range.")

// MARK: - 3. Non-Notched Display Geometry Tests
print("\n[TEST 2] Non-Notched External Display (4K - 1920x1080 scaled):")
let external4k = MockNotchGeometry(rawNotchWidth: 0.0, notchHeight: 24.0, screenWidth: 1920.0, hasPhysicalNotch: false)
let defaultCapsuleExternal = computeAlertCapsuleSize(geom: external4k)

print("  -> Default external capsule width: \(defaultCapsuleExternal.width) pt, height: \(defaultCapsuleExternal.height) pt")
assert(defaultCapsuleExternal.width == 220.0, "Default width on non-notch must be 220 pt")
assert(defaultCapsuleExternal.height == 38.0, "Height on non-notch must be clamped to 38 pt")
print("  -> PASS: External display capsule size is compact and proportionate.")

// MARK: - 4. Mandatory Testing Matrix Across All Event Types
print("\n[TEST 3] Mandatory Event Types Verification Matrix:")

struct EventScenario {
    let name: String
    let measuredContentWidth: CGFloat
    let expectedMinW: CGFloat
    let expectedMaxW: CGFloat
    let description: String
}

let testEvents: [EventScenario] = [
    EventScenario(
        name: "Volume changes",
        measuredContentWidth: 142.0, // [ icon (14) + 10 + "31%" (32) + 10 + level slider (76) ]
        expectedMinW: 210.0,
        expectedMaxW: 230.0,
        description: "Compact icon, percentage, and 76pt level indicator without 'VOLUME' header"
    ),
    EventScenario(
        name: "Brightness changes",
        measuredContentWidth: 142.0, // [ sun icon (14) + 10 + "75%" (32) + 10 + level slider (76) ]
        expectedMinW: 210.0,
        expectedMaxW: 230.0,
        description: "Compact sun icon, percentage, and miniature level slider"
    ),
    EventScenario(
        name: "Media playback & track change",
        measuredContentWidth: 195.0, // [ art (28) + 8 + title/artist (130) + 8 + eq (26) ]
        expectedMinW: 210.0,
        expectedMaxW: 260.0,
        description: "Album art thumbnail, track title, artist, and mini equalizer bars"
    ),
    EventScenario(
        name: "AirPods Connected",
        measuredContentWidth: 220.0, // [ airpods (20) + 8 + name (110) + 8 + battery pills (74) ]
        expectedMinW: 220.0,
        expectedMaxW: 260.0,
        description: "AirPods icon, device name, and L/R/Case battery badges"
    ),
    EventScenario(
        name: "Bluetooth device connected",
        measuredContentWidth: 170.0, // [ icon (20) + 8 + name (120) + 8 + bt icon (14) ]
        expectedMinW: 210.0,
        expectedMaxW: 230.0,
        description: "Bluetooth peripheral icon, name, and connection badge"
    ),
    EventScenario(
        name: "Screen recording & Mic/Cam",
        measuredContentWidth: 155.0, // [ icon (18) + 8 + status (110) + 8 + glowing dot (7) ]
        expectedMinW: 210.0,
        expectedMaxW: 230.0,
        description: "Privacy indicator, active app label, and glowing dot"
    ),
    EventScenario(
        name: "Focus mode change",
        measuredContentWidth: 110.0, // [ moon icon (18) + 8 + 'Work Focus' (80) ]
        expectedMinW: 210.0,
        expectedMaxW: 230.0,
        description: "Focus icon and concise mode name"
    ),
    EventScenario(
        name: "Timers & Countdowns",
        measuredContentWidth: 125.0, // [ countdown ring (32) + 14 + '14:59' (70) ]
        expectedMinW: 210.0,
        expectedMaxW: 230.0,
        description: "Circular countdown ring and monospaced remaining time"
    ),
    EventScenario(
        name: "Battery low alert",
        measuredContentWidth: 165.0, // [ battery (20) + 8 + warning (95) + 8 + '12%' (34) ]
        expectedMinW: 210.0,
        expectedMaxW: 230.0,
        description: "Battery icon, concise warning, and percentage readout"
    ),
    EventScenario(
        name: "Charging connected",
        measuredContentWidth: 160.0, // [ bolt (20) + 8 + text (80) + 8 + meter (44) ]
        expectedMinW: 210.0,
        expectedMaxW: 230.0,
        description: "Charging bolt, percentage available, and mini fluid meter"
    ),
    EventScenario(
        name: "Downloads & File transfer",
        measuredContentWidth: 155.0, // [ download icon (20) + 8 + progress (80) + 8 + percent (34) ]
        expectedMinW: 210.0,
        expectedMaxW: 230.0,
        description: "Download icon, file name, progress bar, and percentage"
    ),
    EventScenario(
        name: "Notifications",
        measuredContentWidth: 180.0, // [ bell (20) + 8 + sender/msg (140) ]
        expectedMinW: 210.0,
        expectedMaxW: 240.0,
        description: "App icon, sender, and concise message preview"
    ),
    EventScenario(
        name: "Clipboard copied",
        measuredContentWidth: 150.0, // [ doc icon (15) + 8 + snippet (120) ]
        expectedMinW: 210.0,
        expectedMaxW: 230.0,
        description: "Clipboard icon, title, and concise snippet"
    ),
    EventScenario(
        name: "Dropper staged item",
        measuredContentWidth: 145.0, // [ tray icon (15) + 8 + count (115) ]
        expectedMinW: 210.0,
        expectedMaxW: 230.0,
        description: "Dropper icon and staged item count"
    )
]

for event in testEvents {
    let padding: CGFloat = 28.0
    let totalContentW = event.measuredContentWidth + padding
    let size = computeAlertCapsuleSize(geom: mbp16, contentWidth: totalContentW)

    print("  -> Event [\(event.name)]:")
    print("     Content width: \(event.measuredContentWidth) pt + padding -> Calculated width: \(size.width) pt, height: \(size.height) pt")
    print("     Spec: \(event.description)")

    assert(size.width >= event.expectedMinW, "Capsule width (\(size.width)) must meet minimum floor (\(event.expectedMinW))")
    assert(size.width <= event.expectedMaxW, "Capsule width (\(size.width)) must not exceed max (\(event.expectedMaxW))")
    assert(size.width <= 380.0, "Capsule width must never exceed 380 pt ceiling")
    assert(size.width < mbp16.screenWidth * 0.30, "Capsule must never occupy full-width screen banner")
    print("     RESULT: PASS")
}

// MARK: - 5. Anti-Regression & Screen Width Constraint Tests
print("\n[TEST 4] Anti-Regression & Screen Width Constraints:")

// Test long device name or long song title
let longContentWidth: CGFloat = 520.0 // Exceptionally long raw string
let longCapsuleSize = computeAlertCapsuleSize(geom: mbp16, contentWidth: longContentWidth)

print("  -> Exceptionally long raw content (\(longContentWidth) pt):")
print("     Clamped capsule width: \(longCapsuleSize.width) pt")
assert(longCapsuleSize.width == 380.0, "Capsule width must be strictly clamped to 380.0 pt max ceiling")
assert(longCapsuleSize.width < mbp16.screenWidth * 0.25, "Clamped capsule is only ~22% of 1728pt screen, never full-width")
print("  -> PASS: Bounded capsule prevents screen-wide explosion even under long titles.")

// MARK: - 6. Notch Anchoring & Symmetrical Centering Tests
print("\n[TEST 5] Notch Anchoring & Symmetrical Centering:")

let notchMidX: CGFloat = 1728.0 / 2.0 // 864.0 pt
let screenH: CGFloat = 1117.0
let testSize = CGSize(width: 220.0, height: 38.0)

let windowRect = calculateNotchCenteredWindowRect(
    notchCenterScreenX: notchMidX,
    size: testSize,
    geom: mbp16,
    screenHeight: screenH
)

print("  -> Window Rect: origin = (\(windowRect.origin.x), \(windowRect.origin.y)), size = (\(windowRect.width), \(windowRect.height))")

let leftMargin = windowRect.origin.x
let rightMargin = mbp16.screenWidth - (windowRect.origin.x + windowRect.width)
print("  -> Left margin to display edge: \(leftMargin) pt, Right margin: \(rightMargin) pt")
assert(abs(leftMargin - rightMargin) < 0.001, "Window frame must be symmetrically centered horizontally on notchCenterScreenX")
assert(windowRect.width == 220.0, "Window frame width must tightly match capsule width without extra transparent padding")
assert(windowRect.origin.y == screenH - testSize.height, "Window frame must be anchored to top menu bar edge")
print("  -> PASS: Perfect horizontal centering and top-edge anchoring confirmed.")

// MARK: - 7. Rapid Consecutive Events & Replacement Tests
print("\n[TEST 6] Rapid Consecutive Event Replacement:")

var currentActiveWidth: CGFloat = 220.0

// Event 1: Volume (hugs physical notch floor of 210 pt)
currentActiveWidth = computeAlertCapsuleSize(geom: mbp16, contentWidth: 170.0).width
assert(currentActiveWidth == 210.0, "Volume event width on notched Mac must hug the notch floor at 210 pt")

// Event 2: Immediate Track Change (250 pt)
currentActiveWidth = computeAlertCapsuleSize(geom: mbp16, contentWidth: 250.0).width
assert(currentActiveWidth == 250.0, "Track change event width must be 250 pt")

// Event 3: Volume HUD immediately supersedes Track Change (back to 210 pt)
currentActiveWidth = computeAlertCapsuleSize(geom: mbp16, contentWidth: 170.0).width
assert(currentActiveWidth == 210.0, "Volume HUD must cleanly reset width back to 210 pt without retaining track width")

print("  -> PASS: Rapid consecutive event replacement smoothly adjusts capsule width without size leakage.")

print("\n=== ALL COMPACT 3D LIQUID GLASS EVENT CAPSULE TESTS PASSED SUCCESSFULLY! ===")
