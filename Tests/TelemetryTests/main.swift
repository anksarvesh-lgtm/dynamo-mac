//
//  main.swift
//  TelemetryTests
//

import CoreGraphics
import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("❌ Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

private func runThermalTests() {
    // 1. Threshold sanitization keeps strictly ascending stops even when misconfigured
    let broken = ThermalThresholds(coolMaxC: 80, normalMaxC: 60, elevatedMaxC: 50, highMaxC: 40)
    let fixed = broken.sanitized()
    check(fixed.coolMaxC < fixed.normalMaxC, "coolMaxC must stay < normalMaxC")
    check(fixed.normalMaxC < fixed.elevatedMaxC, "normalMaxC must stay < elevatedMaxC")
    check(fixed.elevatedMaxC < fixed.highMaxC, "elevatedMaxC must stay < highMaxC")

    // 2. Five-zone classification with default stops (45 / 60 / 75 / 88)
    check(ThermalColorScale.zone(forTemperature: 35.0) == .cool, "35°C must classify .cool")
    check(ThermalColorScale.zone(forTemperature: 52.0) == .normal, "52°C must classify .normal")
    check(ThermalColorScale.zone(forTemperature: 68.0) == .elevated, "68°C must classify .elevated")
    check(ThermalColorScale.zone(forTemperature: 82.0) == .high, "82°C must classify .high")
    check(ThermalColorScale.zone(forTemperature: 95.0) == .critical, "95°C must classify .critical")

    // 3. Configurable thresholds alter zone boundaries cleanly
    let custom = ThermalThresholds(coolMaxC: 50, normalMaxC: 65, elevatedMaxC: 80, highMaxC: 92)
    check(ThermalColorScale.zone(forTemperature: 49.0, thresholds: custom) == .cool, "Custom threshold cool failed")
    check(ThermalColorScale.zone(forTemperature: 55.0, thresholds: custom) == .normal, "Custom threshold normal failed")

    // 4. Cool color is cyan and critical color shifts to red
    let coolRGB = ThermalColorScale.rgb(forTemperature: 38.0)
    check(coolRGB == ThermalColorScale.coolCyan, "Cool temp must render cyan")
    let criticalRGB = ThermalColorScale.rgb(forTemperature: 105.0)
    check(criticalRGB == ThermalColorScale.criticalRed, "Critical temp must saturate at red")

    // 5. Fallback when hardware sensor is unavailable (nil) uses thermalState truthfully
    check(ThermalColorScale.zone(forTemperature: nil, thermalState: .nominal) == .normal, "Nil nominal fallback")
    check(ThermalColorScale.zone(forTemperature: nil, thermalState: .fair) == .elevated, "Nil fair fallback")
    check(ThermalColorScale.zone(forTemperature: nil, thermalState: .serious) == .high, "Nil serious fallback")
    check(ThermalColorScale.zone(forTemperature: nil, thermalState: .critical) == .critical, "Nil critical fallback")
    check(ThermalColorScale.rgb(forTemperature: nil, thermalState: .critical) == ThermalColorScale.criticalRed, "Nil critical RGB")
}

private func runMemoryPressureTests() {
    let normal = MemoryPressureEvaluator.classify(usageRatio: 0.45, vmPressureLevel: 1)
    check(normal.label == "Normal" && abs(normal.effectivePressure - 0.45) < 0.001, "Normal pressure mismatch")

    let vmWarn = MemoryPressureEvaluator.classify(usageRatio: 0.30, vmPressureLevel: 2)
    check(vmWarn.label == "Elevated" && vmWarn.effectivePressure >= 0.65, "VM warn level must elevate floor")

    let vmCrit = MemoryPressureEvaluator.classify(usageRatio: 0.50, vmPressureLevel: 4)
    check(vmCrit.label == "Critical" && vmCrit.effectivePressure >= 0.90, "VM critical level must reach critical")
}

private func runWingLayoutAndFormattingTests() {
    // Jitter protection: 1pt delta stays in same current bucket when < hysteresis (4pt)
    let initial = WingLayoutPolicy.stabilizedWidth(measured: 51.0, current: 0.0, forceImmediate: true)
    check(initial == 56.0, "Initial bucket should round up to 56pt, got \(initial)")

    let tinyShift = WingLayoutPolicy.stabilizedWidth(measured: 53.0, current: initial, hysteresis: 4.0, bucketSize: 8.0)
    check(tinyShift == 56.0, "Small shift inside bucket should preserve width")

    let smallBoundaryCross = WingLayoutPolicy.stabilizedWidth(measured: 57.0, current: 62.0, hysteresis: 4.0, bucketSize: 8.0)
    check(smallBoundaryCross == 62.0, "Delta < 4pt must be suppressed by hysteresis")

    // Capped at safe screen maximum so wing never overlaps status items
    let maxCap = WingLayoutPolicy.safeMaxWingWidth(isNotched: true, auxiliaryWidth: 140.0, screenWidth: 1512.0)
    check(maxCap <= 104.0, "Safe cap must leave margin in small auxiliary region, got \(maxCap)")

    let clamped = WingLayoutPolicy.stabilizedWidth(measured: 280.0, maximum: maxCap, current: 56.0, forceImmediate: true)
    check(clamped == maxCap, "Measured overflow must clamp to safe max")

    // External pill symmetry keeps balanced left and right slots even when right side is off
    let singleSideExt = WingLayoutPolicy.symmetricExternalPillLayout(
        leftActive: true,
        rightActive: false,
        leftWidth: 72.0,
        rightWidth: 0.0,
        centralWidth: 160.0,
        gap: 8.0
    )
    check(singleSideExt.leftSlotWidth == 72.0 && singleSideExt.rightSlotWidth == 72.0, "Single-wing external layout must preserve symmetric centering")
    check(singleSideExt.totalWidth == 320.0, "Unexpected total pill width \(singleSideExt.totalWidth)")

    let idleExt = WingLayoutPolicy.symmetricExternalPillLayout(
        leftActive: false,
        rightActive: false,
        leftWidth: 64,
        rightWidth: 64,
        centralWidth: 160.0
    )
    check(idleExt.totalWidth == 160.0, "Idle external pill should equal central pill width")

    // Rate formatter handles degenerate & standard inputs cleanly
    check(WingRateFormatter.compactRate(-50) == "0K", "Negative rate should floor to 0K")
    check(WingRateFormatter.compactRate(.nan) == "0K", "NaN rate should floor to 0K")
    check(WingRateFormatter.compactRate(1_572_864) == "1.5M", "1.5 MB/s compact format mismatch")
    check(WingRateFormatter.rate(2_147_483_648) == "2.0 GB/s", "2.0 GB/s format mismatch")
}

@main
struct TelemetryTestRunner {
    static func main() {
        runThermalTests()
        runMemoryPressureTests()
        runWingLayoutAndFormattingTests()
        print("✅ TelemetryTests: thermal zones, memory pressure, wing stabilization, external symmetry, and rate formatting passed.")
    }
}
