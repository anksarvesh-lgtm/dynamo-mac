//
//  WingBottomIndicators.swift
//  LiquidDynamo
//
//  Created for LiquidDynamo Change C: Ambient Wing Bottom Indicators
//  Updated: 50% "fire flare" CPU temperature fill (1-70 °C rule)
//

import AppKit
import Foundation
import SwiftUI

// MARK: - Wing Temperature Palette (Editable Stops & Colors)

public struct WingTempPalette {
    public static let minTemp: Double = 1.0
    public static let maxTemp: Double = 70.0

    // Range: 70 - 1 = 69
    // 50% stop: 1.0 + 0.50 * 69.0 = 35.5 °C
    // 75% stop: 1.0 + 0.75 * 69.0 = 52.75 °C
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

// MARK: - DEBUG Temperature Override (Active when launch argument or env var provided)

public enum WingTempOverride {
    public static var overrideTemp: Double? {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "-WingTempOverride"), idx + 1 < args.count {
            return Double(args[idx + 1])
        }
        if let env = ProcessInfo.processInfo.environment["WING_TEMP_OVERRIDE"], let val = Double(env) {
            return val
        }
        return nil
    }
}

// MARK: - Wing Indicator Colors & Pure Math Functions

public struct WingIndicatorColors {
    /// Vertical coverage of the flare fill relative to wing height (50%)
    public static let flareFillFraction: CGFloat = 0.5

    /// Pure RGB linear interpolation helper returning raw components
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

    /// Pure RGB linear interpolation helper returning SwiftUI Color
    public static func interpolateColor(
        from: (r: Double, g: Double, b: Double),
        to: (r: Double, g: Double, b: Double),
        progress: Double
    ) -> Color {
        let rgb = interpolateRGB(from: from, to: to, progress: progress)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// Pure function returning raw RGB components for CPU temperature color mapping.
    /// Scale: 1.0 °C (green) -> 35.5 °C (yellow) -> 52.75 °C (orange) -> 70.0 °C (red).
    /// If temperature is unavailable (nil), cleanly falls back to macOS ThermalState using the same palette.
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

    /// Pure function for CPU temperature color mapping returning SwiftUI Color.
    public static func cpuTemperatureColor(
        temperature: Double?,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> Color {
        let rgb = cpuTemperatureRGB(temperature: temperature, thermalState: thermalState)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// Normalized temperature progress `t` in [0.0, 1.0] across the 1-70 °C scale
    public static func normalizedTemperature(
        temperature: Double?,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> Double {
        guard let temp = temperature else {
            switch thermalState {
            case .nominal: return 0.0
            case .fair: return 0.50
            case .serious: return 0.75
            case .critical: return 1.0
            @unknown default: return 0.0
            }
        }
        return max(0.0, min(1.0, (temp - WingTempPalette.minTemp) / (WingTempPalette.maxTemp - WingTempPalette.minTemp)))
    }

    /// Pure function for RAM usage and memory pressure color mapping.
    /// Suggested: < 60% cyan/green, 60-80 yellow, 80-90 orange, >= 90 red.
    /// If memoryPressure (0.0 to 1.0) indicates higher severity than percentage, uses higher severity.
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

    /// Pure function for RAM fill ratio (0.0 to 1.0 clamped)
    public static func ramFillRatio(percentage: Double) -> Double {
        max(0.0, min(1.0, percentage / 100.0))
    }
}

// MARK: - C1: LEFT Wing CPU Temperature Fire Flare Fill (50% Wing Height)

public struct CPUTempGlowEdge: View {
    @ObservedObject private var statsService = SystemStatsService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    private var activeTemperature: Double? {
        if let override = WingTempOverride.overrideTemp {
            return override
        }
        return statsService.isTemperatureAvailable ? statsService.cpuTemperature : nil
    }

    private var activeColor: Color {
        WingIndicatorColors.cpuTemperatureColor(
            temperature: activeTemperature,
            thermalState: statsService.thermalState
        )
    }

    private var activeRGB: (r: Double, g: Double, b: Double) {
        WingIndicatorColors.cpuTemperatureRGB(
            temperature: activeTemperature,
            thermalState: statsService.thermalState
        )
    }

    private var isUrgent: Bool {
        if let temp = activeTemperature, temp >= WingTempPalette.maxTemp {
            return true
        }
        return statsService.thermalState == .serious || statsService.thermalState == .critical
    }

    private var normalizedT: Double {
        WingIndicatorColors.normalizedTemperature(
            temperature: activeTemperature,
            thermalState: statsService.thermalState
        )
    }

    private var shouldUseStaticRender: Bool {
        reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    // Specification for 6 independent flame tongues along the wing width
    private struct TongueSpec {
        let relX: CGFloat
        let widthFraction: CGFloat
        let speed: Double
        let phase: Double
        let baseHeightPct: Double
        let heightAmpPct: Double
        let swayAmp: CGFloat
    }

    private static let tongues: [TongueSpec] = [
        TongueSpec(relX: 0.12, widthFraction: 0.22, speed: 2.1, phase: 0.0, baseHeightPct: 0.65, heightAmpPct: 0.25, swayAmp: 1.2),
        TongueSpec(relX: 0.28, widthFraction: 0.25, speed: 3.4, phase: 1.8, baseHeightPct: 0.75, heightAmpPct: 0.22, swayAmp: 1.5),
        TongueSpec(relX: 0.45, widthFraction: 0.28, speed: 2.7, phase: 3.6, baseHeightPct: 0.82, heightAmpPct: 0.18, swayAmp: 1.8),
        TongueSpec(relX: 0.62, widthFraction: 0.26, speed: 3.1, phase: 5.2, baseHeightPct: 0.78, heightAmpPct: 0.20, swayAmp: 1.6),
        TongueSpec(relX: 0.78, widthFraction: 0.24, speed: 2.3, phase: 2.4, baseHeightPct: 0.70, heightAmpPct: 0.24, swayAmp: 1.4),
        TongueSpec(relX: 0.90, widthFraction: 0.20, speed: 3.8, phase: 4.1, baseHeightPct: 0.60, heightAmpPct: 0.28, swayAmp: 1.0)
    ]

    public var body: some View {
        let color = activeColor
        let rgb = activeRGB
        let urgent = isUrgent
        let t = normalizedT
        let staticMode = shouldUseStaticRender

        Group {
            if staticMode {
                StaticFlareView(
                    color: color,
                    fraction: WingIndicatorColors.flareFillFraction,
                    isUrgent: urgent
                )
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    Canvas { ctx, size in
                        let time = context.date.timeIntervalSinceReferenceDate
                        drawFlare(
                            in: &ctx,
                            size: size,
                            time: time,
                            rgb: rgb,
                            baseColor: color,
                            t: t,
                            urgent: urgent
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Horizontal mask for soft blending into rounded wing ends
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .white, location: 0.14),
                    .init(color: .white, location: 0.86),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .animation(.easeInOut(duration: 0.8), value: color)
    }

    private func drawFlare(
        in ctx: inout GraphicsContext,
        size: CGSize,
        time: Double,
        rgb: (r: Double, g: Double, b: Double),
        baseColor: Color,
        t: Double,
        urgent: Bool
    ) {
        guard size.width > 0, size.height > 0 else { return }

        let fillFraction = WingIndicatorColors.flareFillFraction
        let maxFlareHeight = size.height * fillFraction

        // Breathing modulation when in urgent state (1.2s cycle)
        var breathMult: Double = 1.0
        if urgent {
            let breathPhase = sin(time * (2.0 * .pi / 1.2))
            breathMult = 0.85 + 0.15 * breathPhase
        }

        // Overall intensity rises with normalized temperature t
        let intensityMult = (0.75 + 0.25 * t) * breathMult

        // Core color: temperature color lightened with ~35% white
        let coreRGB = (
            r: rgb.r * 0.65 + 0.35,
            g: rgb.g * 0.65 + 0.35,
            b: rgb.b * 0.65 + 0.35
        )
        let coreColor = Color(red: coreRGB.r, green: coreRGB.g, blue: coreRGB.b)
        let deepColor = Color(red: rgb.r * 0.90, green: rgb.g * 0.82, blue: rgb.b * 0.82)

        // 1. Base vertical gradient: solid temperature color at bottom edge fading to transparent at 50% line
        let baseRect = CGRect(x: 0, y: size.height - maxFlareHeight, width: size.width, height: maxFlareHeight)
        let baseGrad = Gradient(stops: [
            .init(color: baseColor.opacity(0.46 * intensityMult), location: 1.0),
            .init(color: baseColor.opacity(0.22 * intensityMult), location: 0.50),
            .init(color: baseColor.opacity(0.0), location: 0.0)
        ])
        ctx.fill(
            Path(baseRect),
            with: .linearGradient(
                baseGrad,
                startPoint: CGPoint(x: size.width * 0.5, y: size.height - maxFlareHeight),
                endPoint: CGPoint(x: size.width * 0.5, y: size.height)
            )
        )

        // 2. Flame tongues: 6 soft vertical lobes along width whose heights flicker independently
        // Overshoot of at most +10% wing height allowed only when temperature >= 70 °C (t >= 1.0)
        let maxAllowedTongueHeight = (t >= 1.0) ? (maxFlareHeight + size.height * 0.10) : maxFlareHeight

        for tongue in Self.tongues {
            let effectiveSpeed = tongue.speed * (0.65 + 0.70 * t)
            let osc = sin(time * effectiveSpeed + tongue.phase)
            let sway = tongue.swayAmp * CGFloat(sin(time * effectiveSpeed * 0.7 + tongue.phase + 1.2)) * CGFloat(0.4 + 0.6 * t)

            let heightFactor = tongue.baseHeightPct + tongue.heightAmpPct * osc * (0.40 + 0.60 * t)
            let tongueH = max(2.0, min(maxAllowedTongueHeight, maxFlareHeight * CGFloat(heightFactor)))

            let centerX = size.width * tongue.relX + sway
            let tongueW = size.width * tongue.widthFraction

            var path = Path()
            path.move(to: CGPoint(x: centerX - tongueW * 0.5, y: size.height))
            path.addCurve(
                to: CGPoint(x: centerX, y: size.height - tongueH),
                control1: CGPoint(x: centerX - tongueW * 0.35, y: size.height - tongueH * 0.45),
                control2: CGPoint(x: centerX - tongueW * 0.10, y: size.height - tongueH * 0.92)
            )
            path.addCurve(
                to: CGPoint(x: centerX + tongueW * 0.5, y: size.height),
                control1: CGPoint(x: centerX + tongueW * 0.10, y: size.height - tongueH * 0.92),
                control2: CGPoint(x: centerX + tongueW * 0.35, y: size.height - tongueH * 0.45)
            )
            path.closeSubpath()

            // Tongue gradient: lighter core at base, deeper at tip
            let tongueGrad = Gradient(stops: [
                .init(color: coreColor.opacity(0.38 * intensityMult), location: 0.0),
                .init(color: baseColor.opacity(0.30 * intensityMult), location: 0.45),
                .init(color: deepColor.opacity(0.0), location: 1.0)
            ])
            ctx.fill(
                path,
                with: .linearGradient(
                    tongueGrad,
                    startPoint: CGPoint(x: centerX, y: size.height),
                    endPoint: CGPoint(x: centerX, y: size.height - tongueH)
                )
            )
        }

        // 3. Additive hot glow along bottom edge
        let glowH: CGFloat = 3.0
        let glowRect = CGRect(x: 0, y: size.height - glowH, width: size.width, height: glowH)
        ctx.blendMode = .plusLighter
        let glowGrad = Gradient(stops: [
            .init(color: coreColor.opacity(0.50 * intensityMult), location: 1.0),
            .init(color: coreColor.opacity(0.0), location: 0.0)
        ])
        ctx.fill(
            Path(glowRect),
            with: .linearGradient(
                glowGrad,
                startPoint: CGPoint(x: size.width * 0.5, y: size.height - glowH),
                endPoint: CGPoint(x: size.width * 0.5, y: size.height)
            )
        )
        ctx.blendMode = .normal
    }
}

// MARK: - Static Flare View (Reduce Motion & Low Power Mode Fallback)

private struct StaticFlareView: View {
    let color: Color
    let fraction: CGFloat
    let isUrgent: Bool

    var body: some View {
        GeometryReader { proxy in
            let fillHeight = proxy.size.height * fraction
            ZStack(alignment: .bottom) {
                // Static smooth vertical gradient fill
                Rectangle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: color.opacity(isUrgent ? 0.55 : 0.45), location: 0.0),
                                .init(color: color.opacity(0.20), location: 0.60),
                                .init(color: color.opacity(0.0), location: 1.0)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: fillHeight)

                // Static mild bottom edge glow
                Capsule()
                    .fill(color.opacity(isUrgent ? 0.70 : 0.55))
                    .frame(height: 2.5)
                    .blur(radius: 1.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: - C2: RIGHT Wing RAM Progress Bar

public struct RAMBottomBar: View {
    @ObservedObject private var statsService = SystemStatsService.shared

    public init() {}

    private var fillRatio: Double {
        WingIndicatorColors.ramFillRatio(percentage: statsService.memoryPercentage)
    }

    private var barColor: Color {
        WingIndicatorColors.ramUsageColor(
            percentage: statsService.memoryPercentage,
            memoryPressure: statsService.memoryPressure
        )
    }

    public var body: some View {
        let ratio = fillRatio
        let color = barColor

        GeometryReader { proxy in
            let totalW = max(0, proxy.size.width - 12.0) // 6pt padding on each side
            let filledW = max(0, totalW * CGFloat(ratio))

            ZStack(alignment: .leading) {
                // Background Track: White at ~12% opacity
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: totalW, height: 2.5)

                // Active Fill: Progress with subtle glow, anchored from notch outward (leading)
                Capsule()
                    .fill(color)
                    .frame(width: filledW, height: 2.5)
                    .shadow(color: color.opacity(0.50), radius: 2.0, x: 0, y: 0)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: proxy.size.height, alignment: .bottom)
        }
        .frame(height: 3.5, alignment: .bottom)
        .padding(.bottom, 1.0)
        .animation(.easeInOut(duration: 0.6), value: ratio)
        .animation(.easeInOut(duration: 0.6), value: color)
    }
}

