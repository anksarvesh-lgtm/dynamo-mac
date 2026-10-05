//
//  BatteryLiveActivityView.swift
//  LiquidDynamo
//
//  Migrated Battery & Power Live Activity View for Step 2 of the Liquid Island Engine.
//  Provides both compact top band wing presentation and organic below-notch blooming droplet presentation.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

public struct BatteryLiveActivityView: View {
    @ObservedObject var batteryVM = BatteryStatusViewModel.shared
    @ObservedObject var hub = LiveActivityCenter.shared

    public var isCompactWing: Bool = false
    public var isLeadingWing: Bool = true
    public var isCriticalOverride: Bool? = nil
    public var onDismiss: () -> Void = {}

    public init(
        isCompactWing: Bool = false,
        isLeadingWing: Bool = true,
        isCriticalOverride: Bool? = nil,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.isCompactWing = isCompactWing
        self.isLeadingWing = isLeadingWing
        self.isCriticalOverride = isCriticalOverride
        self.onDismiss = onDismiss
    }

    private var currentLevel: Double {
        Double(batteryVM.levelBattery) / 100.0
    }

    private var isLowBattery: Bool {
        batteryVM.levelBattery <= 15 && !batteryVM.isPluggedIn
    }

    private var isCritical: Bool {
        if let override = isCriticalOverride {
            return override
        }
        return batteryVM.levelBattery <= 5 && !batteryVM.isPluggedIn
    }

    private var tintColor: Color {
        if isCritical {
            return Color.red
        } else if isLowBattery {
            return Color.orange
        } else if batteryVM.isCharging {
            return Color(red: 0.06, green: 0.78, blue: 0.48) // Emerald
        } else {
            return Color.white
        }
    }

    private var statusTitle: String {
        if batteryVM.isCharging {
            return "Charging Started"
        } else if isCritical {
            return "Critical Battery"
        } else if isLowBattery {
            return "Low Battery"
        } else if !batteryVM.isPluggedIn {
            return "On Battery"
        } else {
            return "Fully Charged"
        }
    }

    private var statusSubtitle: String {
        if batteryVM.isCharging {
            return "\(Int(batteryVM.levelBattery))% Available"
        } else if isCritical {
            return "Connect power immediately"
        } else if isLowBattery {
            return "\(Int(batteryVM.levelBattery))% remaining"
        } else {
            return "\(Int(batteryVM.levelBattery))% • Health 98%"
        }
    }

    private var batteryIconName: String {
        if batteryVM.isCharging {
            return "bolt.batteryblock.fill"
        }
        let lvl = batteryVM.levelBattery
        if lvl >= 90 { return "battery.100" }
        if lvl >= 75 { return "battery.75" }
        if lvl >= 50 { return "battery.50" }
        if lvl >= 25 { return "battery.25" }
        return "battery.0"
    }

    public var body: some View {
        if isCompactWing {
            compactWingLayout
        } else {
            bloomingDropletLayout
        }
    }

    // MARK: - 1. Compact Wing Presentation (Top Band)

    private var compactWingLayout: some View {
        HStack(spacing: 5) {
            if isLeadingWing {
                Image(systemName: batteryVM.isCharging ? "bolt.fill" : batteryIconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tintColor)
                Text("\(Int(batteryVM.levelBattery))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else {
                Text("\(Int(batteryVM.levelBattery))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Image(systemName: batteryVM.isCharging ? "bolt.fill" : batteryIconName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tintColor)
            }
        }
        .padding(.horizontal, 6)
        .avoidsNotch(id: isLeadingWing ? "BatteryWingL" : "BatteryWingR")
    }

    // MARK: - 2. Blooming Droplet Presentation (Below Notch)

    private var bloomingDropletLayout: some View {
        HStack(spacing: 12) {
            // Battery Icon with glowing badge
            ZStack {
                Circle()
                    .fill(tintColor.opacity(0.18))
                    .frame(width: 28, height: 28)

                Image(systemName: batteryVM.isCharging ? "bolt.fill" : batteryIconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tintColor)
            }

            // Title & Subtitle
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(statusTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                    if batteryVM.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(tintColor)
                    }
                }

                Text(statusSubtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Percentage readout badge
            Text("\(Int(batteryVM.levelBattery))%")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(tintColor)

            // Dismiss Button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .avoidsNotch(id: "BatteryBloomingDroplet")
    }
}
