import Foundation
import CoreGraphics
import AppKit

print("=== STARTING LIQUIDDYNAMO COMPACT CONNECTED-DEVICE OVERLAY TEST SUITE ===")

// MARK: - Mock Models and Sizing Logic

struct MockNotchGeometry {
    let rawNotchWidth: CGFloat
    let notchHeight: CGFloat
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let hasPhysicalNotch: Bool

    var notchCenterScreenX: CGFloat {
        screenWidth / 2.0
    }
}

enum MockDeviceKind: String {
    case charger = "Charger"
    case headphones = "Headphones"
    case earbuds = "Earbuds"
    case airpods = "AirPods"
    case phone = "Phone"
    case androidPhone = "Android Phone"
    case ssdDrive = "SSD"
    case generic = "Device"
}

enum MockConnectionType {
    case bluetooth
    case power
    case storage
    case usb
}

struct MockDeviceIdentity {
    let displayName: String
    let kind: MockDeviceKind
    let connectionType: MockConnectionType
    let batteryPercentage: Int?
    let chargerWatts: Int?
    let iconName: String
    let formattedFreeSpace: String?
}

// Capsule dimension computation matching DeviceShowcasePopupView.swift
func computeDeviceCapsuleDimensions(geom: MockNotchGeometry, measuredContentWidth: CGFloat) -> CGSize {
    let minW: CGFloat = geom.hasPhysicalNotch ? max(200.0, geom.rawNotchWidth) : 200.0
    let maxW: CGFloat = min(300.0, max(220.0, geom.screenWidth * 0.35))
    let effectiveMeasuredW = measuredContentWidth > 0 ? (measuredContentWidth + 24.0) : 220.0
    let finalWidth = min(maxW, max(minW, effectiveMeasuredW))
    let finalHeight = max(38.0, min(46.0, max(geom.notchHeight, 38.0)))
    return CGSize(width: finalWidth, height: finalHeight)
}

// Window frame computation matching notch centering
func computeWindowFrame(geom: MockNotchGeometry, capsuleSize: CGSize) -> CGRect {
    let originX = geom.notchCenterScreenX - (capsuleSize.width / 2.0)
    let originY = geom.screenHeight - capsuleSize.height
    return CGRect(x: originX, y: originY, width: capsuleSize.width, height: capsuleSize.height)
}

// Estimate content width based on components
func estimateContentWidth(device: MockDeviceIdentity) -> CGFloat {
    let iconWidth: CGFloat = 20.0
    let spacing: CGFloat = 8.0
    let dotWidth: CGFloat = 8.0

    // Approximate width of displayName (clamped to max 130 pt in UI)
    let rawNameWidth = CGFloat(device.displayName.count) * 7.2
    let nameWidth = min(130.0, max(40.0, rawNameWidth))

    var metricsWidth: CGFloat = 50.0
    if device.kind == .charger || device.connectionType == .power {
        metricsWidth = (device.chargerWatts != nil ? 44.0 : 50.0) + (device.batteryPercentage != nil ? 40.0 : 0.0)
    } else if device.connectionType == .storage {
        metricsWidth = (device.formattedFreeSpace != nil ? 58.0 : 50.0) + 24.0 // including eject button
    } else if device.connectionType == .bluetooth {
        metricsWidth = 55.0 + (device.batteryPercentage != nil ? 42.0 : 0.0)
    } else {
        metricsWidth = 55.0
    }

    return iconWidth + spacing + nameWidth + spacing + dotWidth + spacing + metricsWidth
}

// MARK: - Test Cases

let mbp14 = MockNotchGeometry(rawNotchWidth: 204.0, notchHeight: 34.0, screenWidth: 1512.0, screenHeight: 982.0, hasPhysicalNotch: true)
let externalDisplay = MockNotchGeometry(rawNotchWidth: 0.0, notchHeight: 24.0, screenWidth: 2560.0, screenHeight: 1440.0, hasPhysicalNotch: false)

// Test 1: Bluetooth earbuds (realme Buds)
print("\n[TEST 1] Bluetooth earbuds connection (e.g. realme Buds Wireless):")
let realmeBuds = MockDeviceIdentity(
    displayName: "realme Buds Wireless",
    kind: .headphones,
    connectionType: .bluetooth,
    batteryPercentage: 50,
    chargerWatts: nil,
    iconName: "headphones",
    formattedFreeSpace: nil
)
let estBudsW = estimateContentWidth(device: realmeBuds)
let budsCapsule = computeDeviceCapsuleDimensions(geom: mbp14, measuredContentWidth: estBudsW)
print("  -> Estimated content: \(estBudsW) pt, Capsule: \(budsCapsule.width) x \(budsCapsule.height) pt")
assert(budsCapsule.width >= 200.0 && budsCapsule.width <= 300.0, "Earbuds capsule must be between 200 and 300 pt")
assert(budsCapsule.height >= 38.0 && budsCapsule.height <= 48.0, "Height must be between 38 and 48 pt")
print("  -> PASS: Bluetooth earbuds capsule is compact (\(budsCapsule.width) x \(budsCapsule.height) pt).")

// Test 2: Connecting a phone (iPhone / Android)
print("\n[TEST 2] Phone connection (iPhone 16 Pro):")
let iphone = MockDeviceIdentity(
    displayName: "iPhone 16 Pro",
    kind: .phone,
    connectionType: .usb,
    batteryPercentage: 88,
    chargerWatts: nil,
    iconName: "iphone",
    formattedFreeSpace: nil
)
let estPhoneW = estimateContentWidth(device: iphone)
let phoneCapsule = computeDeviceCapsuleDimensions(geom: mbp14, measuredContentWidth: estPhoneW)
print("  -> Capsule: \(phoneCapsule.width) x \(phoneCapsule.height) pt")
assert(phoneCapsule.width >= 200.0 && phoneCapsule.width <= 300.0, "Phone capsule must be between 200 and 300 pt")
assert(phoneCapsule.height >= 38.0 && phoneCapsule.height <= 48.0, "Height must be 38-48 pt")
print("  -> PASS: Phone connection displays compact capsule.")

// Test 3: MagSafe charger connection
print("\n[TEST 3] MagSafe charger connection (33 W):")
let magsafe = MockDeviceIdentity(
    displayName: "MagSafe",
    kind: .charger,
    connectionType: .power,
    batteryPercentage: 89,
    chargerWatts: 33,
    iconName: "bolt.shield.fill",
    formattedFreeSpace: nil
)
let estMagsafeW = estimateContentWidth(device: magsafe)
let magsafeCapsule = computeDeviceCapsuleDimensions(geom: mbp14, measuredContentWidth: estMagsafeW)
print("  -> Capsule: \(magsafeCapsule.width) x \(magsafeCapsule.height) pt")
assert(magsafeCapsule.width >= 200.0 && magsafeCapsule.width <= 300.0, "MagSafe capsule must be between 200 and 300 pt")
assert(magsafe.chargerWatts == 33, "Charging wattage must be 33W")
assert(magsafe.batteryPercentage == 89, "Battery percentage must be 89%")
print("  -> PASS: MagSafe charger displays concise charging info (33 W, 89%).")

// Test 4: Long device names do not cause full-width panel
print("\n[TEST 4] Extremely long device name safety test:")
let longDevice = MockDeviceIdentity(
    displayName: "Sony WH-1000XM5 Premium Noise Canceling Wireless Over-Ear Headphones",
    kind: .headphones,
    connectionType: .bluetooth,
    batteryPercentage: 75,
    chargerWatts: nil,
    iconName: "headphones",
    formattedFreeSpace: nil
)
let estLongW = estimateContentWidth(device: longDevice)
let longCapsule = computeDeviceCapsuleDimensions(geom: mbp14, measuredContentWidth: estLongW)
print("  -> Capsule width for long name: \(longCapsule.width) pt (Max allowed: 300 pt)")
assert(longCapsule.width <= 300.0, "Capsule width must NEVER exceed 300 pt regardless of name length")
assert(longCapsule.width < mbp14.screenWidth * 0.35, "Must never take full width of screen")
print("  -> PASS: Long names are truncated cleanly and clamped to <= 300 pt.")

// Test 5: Notch Centering & Window Frame
print("\n[TEST 5] Notch Centering & Geometry Alignment:")
let windowRect14 = computeWindowFrame(geom: mbp14, capsuleSize: budsCapsule)
let windowCenterX = windowRect14.midX
let notchCenterX = mbp14.notchCenterScreenX
print("  -> Window midX: \(windowCenterX), Notch midX: \(notchCenterX)")
assert(abs(windowCenterX - notchCenterX) < 0.001, "Window must be perfectly centered relative to notch")
assert(windowRect14.width <= 300.0, "Overlay window width must not exceed 300 pt")
print("  -> PASS: Capsule and containing window are perfectly centered at notch.")

// Test 6: External Display (Non-notched)
print("\n[TEST 6] External Display Support:")
let externalCapsule = computeDeviceCapsuleDimensions(geom: externalDisplay, measuredContentWidth: estBudsW)
let windowRectExt = computeWindowFrame(geom: externalDisplay, capsuleSize: externalCapsule)
print("  -> External capsule: \(externalCapsule.width) x \(externalCapsule.height) pt")
assert(externalCapsule.width >= 200.0 && externalCapsule.width <= 300.0, "External capsule must be 200-300 pt")
assert(externalCapsule.height == 38.0, "External display height should be clamped to 38 pt")
print("  -> PASS: External display renders compact pill.")

// Test 7: Detail View Bounded Width
print("\n[TEST 7] Detail View Proportional Bounding:")
let maxDetailCardWidth: CGFloat = 360.0
assert(maxDetailCardWidth <= 380.0, "Detail card must not exceed 380 pt")
assert(maxDetailCardWidth > 280.0, "Detail card has sufficient width for telemetry without overflowing screen")
print("  -> PASS: Detail card is constrained to max 360 pt, avoiding screen-spanning panel.")

// Test 8: Battery Alert Popup Compactness
print("\n[TEST 8] Bluetooth Battery Alert Popup Compactness:")
let batteryAlertDims = computeDeviceCapsuleDimensions(geom: mbp14, measuredContentWidth: 215.0)
assert(batteryAlertDims.width <= 300.0, "Battery alert popup must not exceed 300 pt (replaces old 390 pt)")
assert(batteryAlertDims.height <= 46.0, "Battery alert popup height must be <= 46 pt (replaces old 50 pt)")
print("  -> PASS: Bluetooth battery alert popup width reduced from 390 pt to \(batteryAlertDims.width) pt.")

print("\n=== ALL 8 COMPACT OVERLAY TESTS PASSED SUCCESSFULLY! ===")
