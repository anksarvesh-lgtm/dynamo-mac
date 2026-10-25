//
//  WingBottomIndicators.swift
//  LiquidDynamo
//
//  Created for LiquidDynamo Change C: Ambient Wing Bottom Indicators
//

import AppKit
import Foundation
import SwiftUI

// MARK: - Wing Indicator Colors & Pure Math Functions

public struct WingIndicatorColors {
    /// Pure RGB linear interpolation helper
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

    /// Pure function for CPU temperature color mapping.
    /// Range: <= 45°C cool cyan/teal, 45-60 green, 60-72 yellow, 72-82 orange, >= 82 red.
    /// If temperature is unavailable (nil), cleanly falls back to macOS ThermalState.
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

// MARK: - C1: LEFT Wing CPU Temperature Ambient Glow Edge

public struct CPUTempGlowEdge: View {
    @ObservedObject private var statsService = SystemStatsService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathingState: Bool = false

    public init() {}

    private var activeColor: Color {
        WingIndicatorColors.cpuTemperatureColor(
            temperature: statsService.isTemperatureAvailable ? statsService.cpuTemperature : nil,
            thermalState: statsService.thermalState
        )
    }

    private var isUrgent: Bool {
        if let temp = statsService.cpuTemperature, temp >= 85.0 {
            return true
        }
        return statsService.thermalState == .serious || statsService.thermalState == .critical
    }

    public var body: some View {
        let color = activeColor
        let urgent = isUrgent

        ZStack(alignment: .bottom) {
            // Soft blurred bloom above and behind the edge
            Capsule()
                .fill(color.opacity(urgent ? (breathingState ? 0.95 : 0.45) : 0.70))
                .frame(height: 3.5)
                .blur(radius: 2.5)
                .padding(.bottom, 0.5)

            // Sharp, thin 2pt rounded edge line along the bottom
            Capsule()
                .fill(color.opacity(urgent ? (breathingState ? 1.0 : 0.65) : 0.92))
                .frame(height: 2.0)
        }
        .frame(height: 4.0, alignment: .bottom)
        // Fade toward both ends with gradient mask to blend with curved bottom
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .white, location: 0.18),
                    .init(color: .white, location: 0.82),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .animation(.easeInOut(duration: 0.8), value: color)
        .onAppear {
            if urgent && !reduceMotion {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    breathingState = true
                }
            }
        }
        .onChange(of: urgent) { _, newUrgent in
            if newUrgent && !reduceMotion {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    breathingState = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.4)) {
                    breathingState = false
                }
            }
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
