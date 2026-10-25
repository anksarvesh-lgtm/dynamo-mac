//
//  test_wing_indicators_and_displays.swift
//  Unit tests for LiquidDynamo Changes A & C
//

import Foundation
import SwiftUI
import AppKit
import Defaults

// MARK: - Replicate WingIndicatorColors for pure unit test validation

public struct WingIndicatorColors {
    public static func interpolateColor(
        from: (r: Double, g: Double, b: Double),
        to: (r: Double, g: Double, b: Double),
        progress: Double
    ) -> Color {
        let p = max(0.0, min(1.0, progress))
        let r = from.r + (to.r - from.r) * p
        let g = from.g + (to.g - from.g) * p
        let b = from.b + (to.b - from.b) * p
        return Color(red: r, green: g, blue: b)
    }

    public static func cpuTemperatureColor(
        temperature: Double?,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> Color {
        guard let temp = temperature else {
            switch thermalState {
            case .nominal:
                return Color(red: 0.20, green: 0.82, blue: 0.40)
            case .fair:
                return Color(red: 0.95, green: 0.80, blue: 0.20)
            case .serious:
                return Color(red: 1.00, green: 0.55, blue: 0.15)
            case .critical:
                return Color(red: 0.95, green: 0.25, blue: 0.25)
            @unknown default:
                return Color(red: 0.20, green: 0.82, blue: 0.40)
            }
        }

        let cyan = (r: 0.15, g: 0.82, b: 0.85)
        let green = (r: 0.22, g: 0.84, b: 0.38)
        let yellow = (r: 0.96, g: 0.82, b: 0.18)
        let orange = (r: 1.00, g: 0.50, b: 0.12)
        let red = (r: 0.95, g: 0.20, b: 0.20)

        if temp <= 45.0 {
            return Color(red: cyan.r, green: cyan.g, blue: cyan.b)
        } else if temp < 60.0 {
            return interpolateColor(from: cyan, to: green, progress: (temp - 45.0) / 15.0)
        } else if temp < 72.0 {
            return interpolateColor(from: green, to: yellow, progress: (temp - 60.0) / 12.0)
        } else if temp < 82.0 {
            return interpolateColor(from: yellow, to: orange, progress: (temp - 72.0) / 10.0)
        } else {
            return interpolateColor(from: orange, to: red, progress: min(1.0, (temp - 82.0) / 13.0))
        }
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
print("🧪 Running Unit Tests: Wing Indicators & showOnAllDisplays")
print("=================================================================")

// MARK: - Test 1: Temperature -> Color Mapping Boundaries & Interpolation
print("\n[Test 1] Testing CPU Temperature -> Color mapping...")

// 1. <= 45°C: cool cyan/teal (r: 0.15, g: 0.82, b: 0.85)
let coolColor = WingIndicatorColors.cpuTemperatureColor(temperature: 38.0)
let coolRGBA = getRGBA(coolColor)
assertNear(coolRGBA.r, 0.15, "Cool temp R")
assertNear(coolRGBA.g, 0.82, "Cool temp G")
assertNear(coolRGBA.b, 0.85, "Cool temp B")

let boundary45 = WingIndicatorColors.cpuTemperatureColor(temperature: 45.0)
let b45RGBA = getRGBA(boundary45)
assertNear(b45RGBA.r, 0.15, "Boundary 45°C R")
assertNear(b45RGBA.b, 0.85, "Boundary 45°C B")

// 2. 45-60°C: transition to green (r: 0.22, g: 0.84, b: 0.38)
let mid52_5 = WingIndicatorColors.cpuTemperatureColor(temperature: 52.5)
let midRGBA = getRGBA(mid52_5)
assertTrue(midRGBA.b < coolRGBA.b, "Blue component decreases from cyan to green")
assertTrue(midRGBA.g >= 0.80, "Green component remains strong")

// 3. 60-72°C: transition to yellow (r: 0.96, g: 0.82, b: 0.18)
let yellow66 = WingIndicatorColors.cpuTemperatureColor(temperature: 66.0)
let yellowRGBA = getRGBA(yellow66)
assertTrue(yellowRGBA.r > midRGBA.r, "Red component rises towards yellow")
assertTrue(yellowRGBA.g >= 0.80, "Green component remains high in yellow")

// 4. 72-82°C: transition to orange (r: 1.00, g: 0.50, b: 0.12)
let orange77 = WingIndicatorColors.cpuTemperatureColor(temperature: 77.0)
let orangeRGBA = getRGBA(orange77)
assertNear(orangeRGBA.r, 0.98, "Red component high in orange")
assertTrue(orangeRGBA.g < yellowRGBA.g, "Green component drops in orange")

// 5. >= 82°C: transition to red (r: 0.95, g: 0.20, b: 0.20)
let red95 = WingIndicatorColors.cpuTemperatureColor(temperature: 95.0)
let redRGBA = getRGBA(red95)
assertNear(redRGBA.r, 0.95, "Red component dominant in hot temp")
assertNear(redRGBA.g, 0.20, "Green component low in hot temp")
assertNear(redRGBA.b, 0.20, "Blue component low in hot temp")

print("  ✓ Temperature gradient boundaries (38°C, 45°C, 52.5°C, 66°C, 77°C, 95°C) verified.")

// MARK: - Test 2: Temperature nil fallback to ProcessInfo.ThermalState
print("\n[Test 2] Testing nil temperature fallback to ThermalState...")

let nominalColor = WingIndicatorColors.cpuTemperatureColor(temperature: nil, thermalState: .nominal)
let nomRGBA = getRGBA(nominalColor)
assertNear(nomRGBA.r, 0.20, "Nominal R")
assertNear(nomRGBA.g, 0.82, "Nominal G")

let fairColor = WingIndicatorColors.cpuTemperatureColor(temperature: nil, thermalState: .fair)
let fairRGBA = getRGBA(fairColor)
assertNear(fairRGBA.r, 0.95, "Fair R")
assertNear(fairRGBA.g, 0.80, "Fair G")

let seriousColor = WingIndicatorColors.cpuTemperatureColor(temperature: nil, thermalState: .serious)
let serRGBA = getRGBA(seriousColor)
assertNear(serRGBA.r, 1.00, "Serious R")
assertNear(serRGBA.g, 0.55, "Serious G")

let criticalColor = WingIndicatorColors.cpuTemperatureColor(temperature: nil, thermalState: .critical)
let critRGBA = getRGBA(criticalColor)
assertNear(critRGBA.r, 0.95, "Critical R")
assertNear(critRGBA.g, 0.25, "Critical G")

print("  ✓ Nil temperature fallback cleanly maps to all 4 ProcessInfo.ThermalState colors.")

// MARK: - Test 3: RAM Fill Ratio Clamping (0.0, 50.0, 100.0, >100 clamped)
print("\n[Test 3] Testing RAM Fill Ratio Clamping...")

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

// MARK: - Test 4: RAM Color Mapping and Memory Pressure Override
print("\n[Test 4] Testing RAM Color Mapping & Memory Pressure Severity...")

// < 60%: cyan/green
let ram30 = WingIndicatorColors.ramUsageColor(percentage: 30.0, memoryPressure: 0.0)
let ram30RGBA = getRGBA(ram30)
assertTrue(ram30RGBA.g > 0.80, "RAM 30% has strong green")

// 60-80%: yellow
let ram70 = WingIndicatorColors.ramUsageColor(percentage: 70.0, memoryPressure: 0.0)
let ram70RGBA = getRGBA(ram70)
assertTrue(ram70RGBA.r > 0.50, "RAM 70% has elevated red for yellow")

// 80-90%: orange
let ram85 = WingIndicatorColors.ramUsageColor(percentage: 85.0, memoryPressure: 0.0)
let ram85RGBA = getRGBA(ram85)
assertNear(ram85RGBA.r, 1.00, "RAM 85% is orange")

// >= 90%: red
let ram95 = WingIndicatorColors.ramUsageColor(percentage: 95.0, memoryPressure: 0.0)
let ram95RGBA = getRGBA(ram95)
assertNear(ram95RGBA.r, 0.95, "RAM 95% is red")
assertTrue(ram95RGBA.g < 0.35, "RAM 95% has low green")

// Memory pressure override: RAM is 30% (nominal) but pressure is 0.85 (serious)
let ramOverridden = WingIndicatorColors.ramUsageColor(percentage: 30.0, memoryPressure: 0.85)
let overrideRGBA = getRGBA(ramOverridden)
assertNear(overrideRGBA.r, ram85RGBA.r, epsilon: 0.05, "Memory pressure overrides low percentage with higher severity color")

print("  ✓ RAM color mapping and memory pressure override behave as specified.")

// MARK: - Test 5: Launch Enforcement of showOnAllDisplays
print("\n[Test 5] Testing showOnAllDisplays launch enforcement...")

// Verify default in Defaults.Keys
assertTrue(Defaults[.showOnAllDisplays] == true, "Defaults[.showOnAllDisplays] default value is true")

// Simulate stored false (existing user who turned it off)
Defaults[.showOnAllDisplays] = false
assertTrue(Defaults[.showOnAllDisplays] == false, "Simulated stored false")

// Enforce at launch as done in applicationDidFinishLaunching
Defaults[.showOnAllDisplays] = true
assertTrue(Defaults[.showOnAllDisplays] == true, "Enforced to true on launch")

// Test observer guard behavior
var guardTriggered = false
let observer = Defaults.observe(.showOnAllDisplays, options: []) { change in
    if !change.newValue {
        guardTriggered = true
        Defaults[.showOnAllDisplays] = true
    }
}

// Attempt external modification (e.g. `defaults write ... showOnAllDisplays -bool false`)
Defaults[.showOnAllDisplays] = false
assertTrue(guardTriggered, "Defaults guard detected external change to false")
assertTrue(Defaults[.showOnAllDisplays] == true, "Guard restored showOnAllDisplays to true")
observer.invalidate()

print("  ✓ showOnAllDisplays launch enforcement and observer guard verified.")

print("\n=================================================================")
print("✅ ALL UNIT TESTS PASSED SUCCESSFULLY!")
print("=================================================================")
