//
//  TelemetryPolicy.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team
//  Copyright © 2026 Agrigence. All rights reserved.
//

import CoreGraphics
import Foundation

public struct RGBColorComponents: Equatable, Sendable {
    public let r: Double
    public let g: Double
    public let b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public func interpolated(to target: RGBColorComponents, progress: Double) -> RGBColorComponents {
        let p = max(0.0, min(1.0, progress))
        return RGBColorComponents(
            r: r + (target.r - r) * p,
            g: g + (target.g - g) * p,
            b: b + (target.b - b) * p
        )
    }
}

public enum ThermalZone: String, Equatable, CaseIterable, Sendable {
    case cool
    case normal
    case elevated
    case high
    case critical

    public var label: String {
        switch self {
        case .cool: return "Cool"
        case .normal: return "Normal"
        case .elevated: return "Elevated"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
}

public struct ThermalThresholds: Equatable, Sendable {
    public var coolMaxC: Double
    public var normalMaxC: Double
    public var elevatedMaxC: Double
    public var highMaxC: Double

    public static let standard = ThermalThresholds(
        coolMaxC: 45.0,
        normalMaxC: 60.0,
        elevatedMaxC: 75.0,
        highMaxC: 88.0
    )

    public init(
        coolMaxC: Double = 45.0,
        normalMaxC: Double = 60.0,
        elevatedMaxC: Double = 75.0,
        highMaxC: Double = 88.0
    ) {
        self.coolMaxC = coolMaxC
        self.normalMaxC = normalMaxC
        self.elevatedMaxC = elevatedMaxC
        self.highMaxC = highMaxC
    }

    public func sanitized() -> ThermalThresholds {
        let cool = max(20.0, min(90.0, coolMaxC.isFinite ? coolMaxC : 45.0))
        let normalRaw = normalMaxC.isFinite ? normalMaxC : (cool + 15.0)
        let normal = max(cool + 2.0, min(105.0, normalRaw))
        let elevatedRaw = elevatedMaxC.isFinite ? elevatedMaxC : (normal + 15.0)
        let elevated = max(normal + 2.0, min(115.0, elevatedRaw))
        let highRaw = highMaxC.isFinite ? highMaxC : (elevated + 13.0)
        let high = max(elevated + 2.0, min(125.0, highRaw))
        return ThermalThresholds(
            coolMaxC: cool,
            normalMaxC: normal,
            elevatedMaxC: elevated,
            highMaxC: high
        )
    }
}

public enum ThermalColorScale {
    public static let coolCyan = RGBColorComponents(r: 0.15, g: 0.82, b: 0.86)
    public static let normalGreen = RGBColorComponents(r: 0.22, g: 0.84, b: 0.38)
    public static let elevatedYellow = RGBColorComponents(r: 0.96, g: 0.82, b: 0.18)
    public static let highOrange = RGBColorComponents(r: 1.00, g: 0.50, b: 0.12)
    public static let criticalRed = RGBColorComponents(r: 0.95, g: 0.20, b: 0.20)

    public static func zone(
        forTemperature temperature: Double?,
        thresholds: ThermalThresholds = .standard,
        thermalState: ProcessInfo.ThermalState = .nominal
    ) -> ThermalZone {
        guard let temp = temperature, temp.isFinite else {
            switch thermalState {
            case .nominal: return .normal
            case .fair: return .elevated
            case .serious: return .high
            case .critical: return .critical
            @unknown default: return .normal
            }
        }

        let t = thresholds.sanitized()
        if temp <= t.coolMaxC {
            return .cool
        } else if temp <= t.normalMaxC {
            return .normal
        } else if temp <= t.elevatedMaxC {
            return .elevated
        } else if temp <= t.highMaxC {
            return .high
        } else {
            return .critical
        }
    }

    public static func rgb(
        forTemperature temperature: Double?,
        thresholds: ThermalThresholds = .standard,
        thermalState: ProcessInfo.ThermalState = .nominal
    ) -> RGBColorComponents {
        guard let temp = temperature, temp.isFinite else {
            switch thermalState {
            case .nominal: return normalGreen
            case .fair: return elevatedYellow
            case .serious: return highOrange
            case .critical: return criticalRed
            @unknown default: return normalGreen
            }
        }

        let t = thresholds.sanitized()
        if temp <= t.coolMaxC {
            return coolCyan
        } else if temp < t.normalMaxC {
            let p = (temp - t.coolMaxC) / (t.normalMaxC - t.coolMaxC)
            return coolCyan.interpolated(to: normalGreen, progress: p)
        } else if temp < t.elevatedMaxC {
            let p = (temp - t.normalMaxC) / (t.elevatedMaxC - t.normalMaxC)
            return normalGreen.interpolated(to: elevatedYellow, progress: p)
        } else if temp < t.highMaxC {
            let p = (temp - t.elevatedMaxC) / (t.highMaxC - t.elevatedMaxC)
            return elevatedYellow.interpolated(to: highOrange, progress: p)
        } else {
            let criticalSpan = 10.0
            let p = (temp - t.highMaxC) / criticalSpan
            return highOrange.interpolated(to: criticalRed, progress: p)
        }
    }

    public static func normalizedProgress(
        forTemperature temperature: Double?,
        thresholds: ThermalThresholds = .standard,
        thermalState: ProcessInfo.ThermalState = .nominal
    ) -> Double {
        guard let temp = temperature, temp.isFinite else {
            switch thermalState {
            case .nominal: return 0.25
            case .fair: return 0.55
            case .serious: return 0.80
            case .critical: return 1.0
            @unknown default: return 0.25
            }
        }
        let t = thresholds.sanitized()
        let floorTemp = max(15.0, t.coolMaxC - 15.0)
        let ceilingTemp = t.highMaxC + 10.0
        guard ceilingTemp > floorTemp else { return 0.0 }
        return max(0.0, min(1.0, (temp - floorTemp) / (ceilingTemp - floorTemp)))
    }
}

public struct MemoryPressureClassification: Equatable, Sendable {
    public let effectivePressure: Double
    public let label: String

    public init(effectivePressure: Double, label: String) {
        self.effectivePressure = effectivePressure
        self.label = label
    }
}

public enum MemoryPressureEvaluator {
    public static func classify(usageRatio: Double, vmPressureLevel: Int32 = 0) -> MemoryPressureClassification {
        let clampedUsage = max(0.0, min(1.0, usageRatio.isFinite ? usageRatio : 0.0))
        let pressureFloor: Double
        if vmPressureLevel >= 4 {
            pressureFloor = 0.90
        } else if vmPressureLevel >= 2 {
            pressureFloor = 0.65
        } else {
            pressureFloor = 0.0
        }

        let effective = max(clampedUsage, pressureFloor)
        let label: String
        if effective >= 0.85 {
            label = "Critical"
        } else if effective >= 0.60 {
            label = "Elevated"
        } else {
            label = "Normal"
        }
        return MemoryPressureClassification(effectivePressure: effective, label: label)
    }
}

public enum WingLayoutPolicy {
    public static let minimumFloor: CGFloat = 38.0
    public static let maxWingWidthCap: CGFloat = 200.0
    public static let maximumHardCap: CGFloat = maxWingWidthCap

    public static func safeMaxWingWidth(
        isNotched: Bool,
        auxiliaryWidth: CGFloat,
        screenWidth: CGFloat,
        centralPillWidth: CGFloat = 160.0
    ) -> CGFloat {
        let budget: CGFloat
        if isNotched {
            let aux = auxiliaryWidth > 0 ? auxiliaryWidth : max(minimumFloor, (screenWidth - 200.0) * 0.5)
            budget = aux - 36.0
        } else {
            budget = ((screenWidth - centralPillWidth - 40.0) * 0.5) - 24.0
        }
        return min(maximumHardCap, max(minimumFloor, budget))
    }

    public static func stabilizedWidth(
        measured: CGFloat,
        minimum: CGFloat = minimumFloor,
        maximum: CGFloat = maximumHardCap,
        current: CGFloat,
        hysteresis: CGFloat = 4.0,
        bucketSize: CGFloat = 8.0,
        forceImmediate: Bool = false
    ) -> CGFloat {
        let safeMax = max(minimum, maximum)
        let clamped = min(safeMax, max(minimum, measured.isFinite ? measured : minimum))
        let step = max(1.0, bucketSize)
        let bucketed = min(safeMax, max(minimum, ceil(clamped / step) * step))

        if !forceImmediate, current >= minimum, current <= safeMax, abs(bucketed - current) < hysteresis {
            return current
        }
        return bucketed
    }

    public static func symmetricExternalPillLayout(
        leftActive: Bool,
        rightActive: Bool,
        leftWidth: CGFloat,
        rightWidth: CGFloat,
        centralWidth: CGFloat = 160.0,
        gap: CGFloat = 8.0
    ) -> (leftSlotWidth: CGFloat, rightSlotWidth: CGFloat, totalWidth: CGFloat) {
        let effectiveLeft = leftActive ? max(minimumFloor, leftWidth) : 0.0
        let effectiveRight = rightActive ? max(minimumFloor, rightWidth) : 0.0
        let balancedSlot = max(effectiveLeft, effectiveRight)

        guard leftActive || rightActive else {
            return (0.0, 0.0, centralWidth)
        }
        let total = centralWidth + (2.0 * (balancedSlot + gap))
        return (balancedSlot, balancedSlot, total)
    }
}

public enum WingRateFormatter {
    public static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else {
            return "0 B/s"
        }
        if bytesPerSecond >= 1_073_741_824 {
            return String(format: "%.1f GB/s", bytesPerSecond / 1_073_741_824.0)
        } else if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576.0)
        } else if bytesPerSecond >= 1024 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1024.0)
        } else {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }

    public static func compactRate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else {
            return "0B"
        }
        if bytesPerSecond >= 1_073_741_824 {
            return String(format: "%.1fG", bytesPerSecond / 1_073_741_824.0)
        } else if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1fM", bytesPerSecond / 1_048_576.0)
        } else if bytesPerSecond >= 1024 {
            return String(format: "%.0fK", bytesPerSecond / 1024.0)
        } else {
            return String(format: "%.0fB", bytesPerSecond)
        }
    }
}
