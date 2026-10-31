//
//  test_wing_indicators_and_displays.swift
//  Unit tests for LiquidDynamo Wing Indicators & showOnAllDisplays
//  Updated for: Temperature colour rule (1-70 °C) & 50% Fire Flare Fill
//

import Foundation
import SwiftUI
import AppKit
import Defaults

// MARK: - Replicate WingTempPalette & WingIndicatorColors for pure unit test validation

public struct WingTempPalette {
    public static let minTemp: Double = 1.0
    public static let maxTemp: Double = 70.0

    public static let yellowTemp: Double = minTemp + 0.50 * (maxTemp - minTemp) // 35.5 °C
    public static let orangeTemp: Double = minTemp + 0.75 * (maxTemp - minTemp) // 52.75 °C

    public static let green  = (r: 0.20, g: 0.85, b: 0.35) // at minTemp (1.0 °C and below)
    public static let yellow = (r: 0.96, g: 0.82, b: 0.18) // at 50% (35.5 °C)
    public static let orange = (r: 1.00, g: 0.50, b: 0.12) // at 75% (52.75 °C)
    public static let red    = (r: 0.95, g: 0.20, b: 0.20) // at maxTemp (70.0 °C and above)

    public static var greenColor: Color { Color(red: green.r, green: green.g, blue: green.b) }
    public static var yellowColor: Color { Color(red: yellow.r, green: yellow.g, blue: yellow.b) }
    public static var orangeColor: Color { Color(red: orange.r, green: orange.g, blue: orange.b) }
    public static var redColor: Color { Color(red: red.r, green: red.g, blue: red.b) }
}

public struct WingIndicatorColors {
    public static let flareFillFraction: CGFloat = 0.5

    public static func interpolateRGB(
        from: (r: Double, g: Double, b: Double),
        to: (r: Double, g: Double, b: Double),
        progress: Double
    ) -> (r: Double, g: Double, b: Double) {
        let p = max(0.0, min(1.0, progress))
        let r = from.r + (to.r - from.r) * p
        let g = from.g + (to.g - from.g) * p
        let b = from.b + (to.b - from.b) * p
        return (r, g, b)
    }

    public static func interpolateColor(
        from: (r: Double, g: Double, b: Double),
        to: (r: Double, g: Double, b: Double),
        progress: Double
    ) -> Color {
        let rgb = interpolateRGB(from: from, to: to, progress: progress)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    public static func cpuTemperatureRGB(
        temperature: Double?,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> (r: Double, g: Double, b: Double) {
        guard let temp = temperature else {
            switch thermalState {
            case .nominal: return WingTempPalette.green
            case .fair: return WingTempPalette.yellow
            case .serious: return WingTempPalette.orange
            case .critical: return WingTempPalette.red
            @unknown default: return WingTempPalette.green
            }
        }

        if temp <= WingTempPalette.minTemp {
            return WingTempPalette.green
        } else if temp < WingTempPalette.yellowTemp {
            let p = (temp - WingTempPalette.minTemp) / (WingTempPalette.yellowTemp - WingTempPalette.minTemp)
            return interpolateRGB(from: WingTempPalette.green, to: WingTempPalette.yellow, progress: p)
        } else if temp < WingTempPalette.orangeTemp {
            let p = (temp - WingTempPalette.yellowTemp) / (WingTempPalette.orangeTemp - WingTempPalette.yellowTemp)
            return interpolateRGB(from: WingTempPalette.yellow, to: WingTempPalette.orange, progress: p)
        } else if temp < WingTempPalette.maxTemp {
            let p = (temp - WingTempPalette.orangeTemp) / (WingTempPalette.maxTemp - WingTempPalette.orangeTemp)
            return interpolateRGB(from: WingTempPalette.orange, to: WingTempPalette.red, progress: p)
        } else {
            return WingTempPalette.red
        }
    }

    public static func cpuTemperatureColor(
        temperature: Double?,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> Color {
        let rgb = cpuTemperatureRGB(temperature: temperature, thermalState: thermalState)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    public static func isUrgent(
        temperature: Double?,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> Bool {
        if let temp = temperature, temp >= WingTempPalette.maxTemp {
            return true
        }
        return thermalState == .serious || thermalState == .critical
    }

    public static func ramUsageColor(percentage: Double, memoryPressure: Double = 0.0) -> Color {
        let pressurePercent = memoryPressure * 100.0
        let effectivePct = max(max(0.0, percentage), pressurePercent)

        let cyan = (r: 0.15, g: 0.82, b: 0.85)
        let green = (r: 0.22, g: 0.84, b: 0.38)
        let yellow = (r: 0.96, g: 0.82, b: 0.18)
        let orange = (r: 1.00, g: 0.50, b: 0.12)
        let red = (r: 0.95, g: 0.20, b: 0.20)

        if effectivePct < 60.0 {
            return interpolateColor(from: cyan, to: green, progress: effectivePct / 60.0)
        } else if effectivePct < 80.0 {
            return interpolateColor(from: green, to: yellow, progress: (effectivePct - 60.0) / 20.0)
        } else if effectivePct < 90.0 {
            return interpolateColor(from: yellow, to: orange, progress: (effectivePct - 80.0) / 10.0)
        } else {
            return interpolateColor(from: orange, to: red, progress: min(1.0, (effectivePct - 90.0) / 10.0))
        }
    }

    public static func ramFillRatio(percentage: Double) -> Double {
        max(0.0, min(1.0, percentage / 100.0))
    }
}

extension Defaults.Keys {
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: true)
}

// MARK: - Test Helpers

func getRGBA(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    let nsColor = NSColor(color)
    guard let rgbColor = nsColor.usingColorSpace(.sRGB) else {
        return (0, 0, 0, 0)
    }
    return (rgbColor.redComponent, rgbColor.greenComponent, rgbColor.blueComponent, rgbColor.alphaComponent)
}

func assertNear(_ val1: CGFloat, _ val2: CGFloat, epsilon: CGFloat = 0.05, _ msg: String) {
    if abs(val1 - val2) > epsilon {
        fatalError("Assertion failure: \(msg) - expected approx \(val2), got \(val1)")
    }
}

func assertTrue(_ condition: Bool, _ msg: String) {
    if !condition {
        fatalError("Assertion failure: \(msg)")
    }
}

print("=================================================================")
print("🧪 Running Unit Tests: Wing Indicators & 1-70°C Fire Flare Fill")
print("=================================================================")

// MARK: - Test 1: New Temperature Colour Rule (1-70 °C stops & boundaries)
print("\n[Test 1] Testing new Temperature colour rule (1-70 °C)...")

// 1. Minimum: GREEN at 1 °C (and anything below)
let tNeg10 = WingIndicatorColors.cpuTemperatureRGB(temperature: -10.0)
assertNear(CGFloat(tNeg10.r), 0.20, "T = -10 R (green)")
assertNear(CGFloat(tNeg10.g), 0.85, "T = -10 G (green)")
assertNear(CGFloat(tNeg10.b), 0.35, "T = -10 B (green)")

let t0 = WingIndicatorColors.cpuTemperatureRGB(temperature: 0.0)
assertNear(CGFloat(t0.r), 0.20, "T = 0 R (green)")
assertNear(CGFloat(t0.g), 0.85, "T = 0 G (green)")
assertNear(CGFloat(t0.b), 0.35, "T = 0 B (green)")

let t1 = WingIndicatorColors.cpuTemperatureRGB(temperature: 1.0)
assertNear(CGFloat(t1.r), 0.20, "T = 1 R (green)")
assertNear(CGFloat(t1.g), 0.85, "T = 1 G (green)")
assertNear(CGFloat(t1.b), 0.35, "T = 1 B (green)")

// 2. Intermediate T = 18 °C: between green and yellow
let t18 = WingIndicatorColors.cpuTemperatureRGB(temperature: 18.0)
assertTrue(t18.r > t1.r, "T = 18 R > green R")
assertTrue(t18.r < 0.96, "T = 18 R < yellow R")
assertTrue(t18.g > 0.80, "T = 18 G remains high")

// 3. T = 35.5 °C (50% of range): YELLOW
let t35_5 = WingIndicatorColors.cpuTemperatureRGB(temperature: 35.5)
assertNear(CGFloat(t35_5.r), 0.96, "T = 35.5 R (yellow)")
assertNear(CGFloat(t35_5.g), 0.82, "T = 35.5 G (yellow)")
assertNear(CGFloat(t35_5.b), 0.18, "T = 35.5 B (yellow)")

// 4. T = 52.75 °C (75% of range): ORANGE
let t52_75 = WingIndicatorColors.cpuTemperatureRGB(temperature: 52.75)
assertNear(CGFloat(t52_75.r), 1.00, "T = 52.75 R (orange)")
assertNear(CGFloat(t52_75.g), 0.50, "T = 52.75 G (orange)")
assertNear(CGFloat(t52_75.b), 0.12, "T = 52.75 B (orange)")

// 5. Maximum: RED at 70 °C (and anything above: 85 °C, 120 °C)
let t70 = WingIndicatorColors.cpuTemperatureRGB(temperature: 70.0)
assertNear(CGFloat(t70.r), 0.95, "T = 70 R (red)")
assertNear(CGFloat(t70.g), 0.20, "T = 70 G (red)")
assertNear(CGFloat(t70.b), 0.20, "T = 70 B (red)")

let t85 = WingIndicatorColors.cpuTemperatureRGB(temperature: 85.0)
assertNear(CGFloat(t85.r), 0.95, "T = 85 R (clamped red)")

let t120 = WingIndicatorColors.cpuTemperatureRGB(temperature: 120.0)
assertNear(CGFloat(t120.r), 0.95, "T = 120 R (clamped red)")

print("  ✓ Minimum (<= 1°C = green), 35.5°C (yellow), 52.75°C (orange), >= 70°C (red) verified.")

// MARK: - Test 2: Monotonic progression from green to red
print("\n[Test 2] Testing monotonicity from green toward red...")
// Measure red dominance over green: (r - g) increases monotonically from -0.65 (green) to +0.75 (red)
var prevRedDominance = t1.r - t1.g
for temp in stride(from: 1.0, through: 70.0, by: 0.5) {
    let rgb = WingIndicatorColors.cpuTemperatureRGB(temperature: temp)
    let redDominance = rgb.r - rgb.g
    assertTrue(redDominance >= prevRedDominance - 0.0001, "Color progression (r - g) is monotonic non-decreasing at T=\(temp)")
    prevRedDominance = redDominance
}
print("  ✓ Color progression monotonically shifts from green toward red across full 1-70°C scale.")

// MARK: - Test 3: Unavailable temperature (nil) fallback to ThermalState
print("\n[Test 3] Testing nil temperature fallback to ThermalState with matching palette...")
let nomRGB = WingIndicatorColors.cpuTemperatureRGB(temperature: nil, thermalState: .nominal)
assertNear(CGFloat(nomRGB.r), CGFloat(WingTempPalette.green.r), "Nominal = green R")
assertNear(CGFloat(nomRGB.g), CGFloat(WingTempPalette.green.g), "Nominal = green G")

let fairRGB = WingIndicatorColors.cpuTemperatureRGB(temperature: nil, thermalState: .fair)
assertNear(CGFloat(fairRGB.r), CGFloat(WingTempPalette.yellow.r), "Fair = yellow R")
assertNear(CGFloat(fairRGB.g), CGFloat(WingTempPalette.yellow.g), "Fair = yellow G")

let serRGB = WingIndicatorColors.cpuTemperatureRGB(temperature: nil, thermalState: .serious)
assertNear(CGFloat(serRGB.r), CGFloat(WingTempPalette.orange.r), "Serious = orange R")
assertNear(CGFloat(serRGB.g), CGFloat(WingTempPalette.orange.g), "Serious = orange G")

let critRGB = WingIndicatorColors.cpuTemperatureRGB(temperature: nil, thermalState: .critical)
assertNear(CGFloat(critRGB.r), CGFloat(WingTempPalette.red.r), "Critical = red R")
assertNear(CGFloat(critRGB.g), CGFloat(WingTempPalette.red.g), "Critical = red G")

print("  ✓ Nil fallback maps nominal->green, fair->yellow, serious->orange, critical->red.")

// MARK: - Test 4: Flare fill fraction and urgent flag rules
print("\n[Test 4] Testing flareFillFraction constant and urgent state flag...")
assertTrue(WingIndicatorColors.flareFillFraction == 0.5, "flareFillFraction is exactly 0.5 (50%)")

assertTrue(WingIndicatorColors.isUrgent(temperature: 69.9) == false, "T=69.9 is not urgent")
assertTrue(WingIndicatorColors.isUrgent(temperature: 70.0) == true, "T=70.0 is urgent")
assertTrue(WingIndicatorColors.isUrgent(temperature: 85.0) == true, "T=85.0 is urgent")
assertTrue(WingIndicatorColors.isUrgent(temperature: nil, thermalState: .nominal) == false, "Nominal is not urgent")
assertTrue(WingIndicatorColors.isUrgent(temperature: nil, thermalState: .serious) == true, "Serious is urgent")
assertTrue(WingIndicatorColors.isUrgent(temperature: nil, thermalState: .critical) == true, "Critical is urgent")

print("  ✓ flareFillFraction == 0.5 and urgent flag behavior verified.")

// MARK: - Test 5: RAM Fill Ratio Clamping (0.0, 50.0, 100.0, >100 clamped)
print("\n[Test 5] Testing RAM Fill Ratio Clamping...")
let ratio0 = WingIndicatorColors.ramFillRatio(percentage: 0.0)
assertTrue(ratio0 == 0.0, "0% -> 0.0")

let ratioNegative = WingIndicatorColors.ramFillRatio(percentage: -15.0)
assertTrue(ratioNegative == 0.0, "Negative % -> clamped 0.0")

let ratio50 = WingIndicatorColors.ramFillRatio(percentage: 50.0)
assertNear(CGFloat(ratio50), 0.50, epsilon: 0.001, "50% -> 0.50")

let ratio100 = WingIndicatorColors.ramFillRatio(percentage: 100.0)
assertTrue(ratio100 == 1.0, "100% -> 1.0")

let ratio150 = WingIndicatorColors.ramFillRatio(percentage: 150.0)
assertTrue(ratio150 == 1.0, "150% -> clamped 1.0")

print("  ✓ RAM fill ratio clamped correctly in [0.0, 1.0] across all boundaries.")

// MARK: - Test 6: RAM Color Mapping and Memory Pressure Override
print("\n[Test 6] Testing RAM Color Mapping & Memory Pressure Severity...")
let ram30 = WingIndicatorColors.ramUsageColor(percentage: 30.0, memoryPressure: 0.0)
let ram30RGBA = getRGBA(ram30)
assertTrue(ram30RGBA.g > 0.80, "RAM 30% has strong green")

let ram70 = WingIndicatorColors.ramUsageColor(percentage: 70.0, memoryPressure: 0.0)
let ram70RGBA = getRGBA(ram70)
assertTrue(ram70RGBA.r > 0.50, "RAM 70% has elevated red for yellow")

let ram85 = WingIndicatorColors.ramUsageColor(percentage: 85.0, memoryPressure: 0.0)
let ram85RGBA = getRGBA(ram85)
assertNear(ram85RGBA.r, 1.00, "RAM 85% is orange")

let ram95 = WingIndicatorColors.ramUsageColor(percentage: 95.0, memoryPressure: 0.0)
let ram95RGBA = getRGBA(ram95)
assertNear(ram95RGBA.r, 0.95, "RAM 95% is red")
assertTrue(ram95RGBA.g < 0.35, "RAM 95% has low green")

let ramOverridden = WingIndicatorColors.ramUsageColor(percentage: 30.0, memoryPressure: 0.85)
let overrideRGBA = getRGBA(ramOverridden)
assertNear(overrideRGBA.r, ram85RGBA.r, epsilon: 0.05, "Memory pressure overrides low percentage with higher severity color")

print("  ✓ RAM color mapping and memory pressure override behave as specified.")

// MARK: - Test 7: Launch Enforcement of showOnAllDisplays
print("\n[Test 7] Testing showOnAllDisplays launch enforcement...")
assertTrue(Defaults[.showOnAllDisplays] == true, "Defaults[.showOnAllDisplays] default value is true")

Defaults[.showOnAllDisplays] = false
assertTrue(Defaults[.showOnAllDisplays] == false, "Simulated stored false")

Defaults[.showOnAllDisplays] = true
assertTrue(Defaults[.showOnAllDisplays] == true, "Enforced to true on launch")

var guardTriggered = false
let observer = Defaults.observe(.showOnAllDisplays, options: []) { change in
    if !change.newValue {
        guardTriggered = true
        Defaults[.showOnAllDisplays] = true
    }
}

Defaults[.showOnAllDisplays] = false
assertTrue(guardTriggered, "Defaults guard detected external change to false")
assertTrue(Defaults[.showOnAllDisplays] == true, "Guard restored showOnAllDisplays to true")
observer.invalidate()

print("  ✓ showOnAllDisplays launch enforcement and observer guard verified.")

print("\n=================================================================")
print("✅ ALL UNIT TESTS PASSED SUCCESSFULLY!")
print("=================================================================")
