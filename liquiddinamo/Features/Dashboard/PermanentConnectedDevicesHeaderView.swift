//
//  PermanentConnectedDevicesHeaderView.swift
//  LiquidDynamo
//
//  Permanent Connected Devices Header:
//  - Strictly verified real hardware data only (never dummy, placeholder, or fabricated info)
//  - MagSafe 3 / Power Adapter & Verified Bluetooth / Audio Peripherals
//  - Conditional Visibility:
//      * 0 connected: Completely hidden (zero blank space, carousel shifts up)
//      * 1 connected: Exactly 1 card displayed full width
//      * 2+ connected: 2 balanced cards side-by-side
//  - Apple Liquid Glass Visual Language with organic specular lighting
//

import AppKit
import Combine
import SwiftUI

// MARK: - Color Tokens
public struct LiquidColorTokens {
    public static let primaryGlass = Color(red: 0x17 / 255.0, green: 0x19 / 255.0, blue: 0x1C / 255.0) // #17191C
    public static let secondaryGlass = Color(red: 0x24 / 255.0, green: 0x28 / 255.0, blue: 0x2D / 255.0) // #24282D
    public static let deepShadow = Color(red: 0x09 / 255.0, green: 0x0B / 255.0, blue: 0x0E / 255.0) // #090B0E
    public static let tealRefraction = Color(red: 0x12 / 255.0, green: 0x3B / 255.0, blue: 0x36 / 255.0) // #123B36
    public static let blueRefraction = Color(red: 0x14 / 255.0, green: 0x28 / 255.0, blue: 0x3F / 255.0) // #14283F
    public static let emerald = Color(red: 0x00 / 255.0, green: 0xD9 / 255.0, blue: 0x82 / 255.0) // #00D982
    public static let champagneReflection = Color(red: 0xC6 / 255.0, green: 0x9B / 255.0, blue: 0x70 / 255.0) // #C69B70
    public static let silverHighlight = Color(red: 0xDD / 255.0, green: 0xE8 / 255.0, blue: 0xF0 / 255.0) // #DDE8F0
    public static let primaryText = Color(red: 1.0, green: 1.0, blue: 1.0) // #FFFFFF
    public static let secondaryText = Color(red: 0xAE / 255.0, green: 0xB5 / 255.0, blue: 0xBE / 255.0) // #AEB5BE
    public static let mutedText = Color(red: 0x73 / 255.0, green: 0x7B / 255.0, blue: 0x85 / 255.0) // #737B85
}

public enum ConnectedDeviceCardItem: Identifiable, Equatable {
    case charger(name: String, watts: Int, isCharging: Bool)
    case peripheral(device: DeviceIdentity)

    public var id: String {
        switch self {
        case .charger:
            return "card_charger"
        case .peripheral(let dev):
            return "card_dev_\(dev.stableKey)"
        }
    }
}

public struct PermanentConnectedDevicesHeaderView: View {
    @ObservedObject var chargingService = ChargingIntelligenceService.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var deviceMonitor = DeviceMonitor.shared

    public var onSelectCharger: (() -> Void)? = nil
    public var onSelectAudioDevice: ((DeviceIdentity?) -> Void)? = nil

    @State private var hoveredCardId: String? = nil
    @State private var pulsePhase: Double = 0.0

    public init(
        onSelectCharger: (() -> Void)? = nil,
        onSelectAudioDevice: ((DeviceIdentity?) -> Void)? = nil
    ) {
        self.onSelectCharger = onSelectCharger
        self.onSelectAudioDevice = onSelectAudioDevice
    }

    /// Helper to determine if any verified connected hardware exists
    public static var hasAnyConnectedDevice: Bool {
        let isPlugged = ChargingIntelligenceService.shared.isPluggedIn || BatteryStatusViewModel.shared.isPluggedIn
        if isPlugged { return true }
        let hasBt = DeviceMonitor.shared.sortedActiveDevices.contains { dev in
            dev.kind != .monitor && dev.kind != .androidPhone && !dev.displayName.contains("Built-in") && DeviceMonitor.shared.activeDevices[dev.stableKey] != nil
        }
        return hasBt
    }

    /// Evaluates genuinely connected hardware only
    private var verifiedConnectedCards: [ConnectedDeviceCardItem] {
        var cards: [ConnectedDeviceCardItem] = []

        // 1. External Charger (Only when plugged in to external power)
        let isPlugged = chargingService.isPluggedIn || batteryModel.isPluggedIn
        if isPlugged {
            let portDesc: String = {
                if chargingService.connectedPortDescription.contains("MagSafe") {
                    return "MagSafe 3 Charger"
                } else if !chargingService.adapterName.isEmpty {
                    return chargingService.adapterName
                } else {
                    return "Power Adapter"
                }
            }()
            let watts = chargingService.adapterWatts
            let isCharging = chargingService.isCharging || batteryModel.isCharging
            cards.append(.charger(name: portDesc, watts: watts, isCharging: isCharging))
        }

        // 2. Verified Active Bluetooth / Audio Peripherals
        let activePeripherals = deviceMonitor.sortedActiveDevices.filter { dev in
            dev.kind != .monitor &&
            dev.kind != .androidPhone &&
            !dev.displayName.contains("Built-in") &&
            deviceMonitor.activeDevices[dev.stableKey] != nil
        }

        for dev in activePeripherals {
            cards.append(.peripheral(device: dev))
        }

        return cards
    }

    public var body: some View {
        let cards = verifiedConnectedCards

        // Rule: If 0 devices connected, completely hide section!
        if cards.isEmpty {
            EmptyView()
        } else if cards.count == 1 {
            // Rule: Exactly 1 card displayed full width
            HStack(spacing: 0) {
                renderCard(cards[0], isFullWidth: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .onAppear { startPulse() }
        } else {
            // Rule: 2+ devices connected, display 2 balanced cards side-by-side
            HStack(spacing: 8) {
                renderCard(cards[0], isFullWidth: false)
                renderCard(cards[1], isFullWidth: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .onAppear { startPulse() }
        }
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
            pulsePhase = 1.0
        }
    }

    @ViewBuilder
    private func renderCard(_ item: ConnectedDeviceCardItem, isFullWidth: Bool) -> some View {
        switch item {
        case .charger(let name, let watts, let isCharging):
            chargerCardView(name: name, watts: watts, isCharging: isCharging, isFullWidth: isFullWidth)
                .onHover { h in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        hoveredCardId = h ? "charger" : nil
                    }
                }
                .onTapGesture {
                    onSelectCharger?()
                }

        case .peripheral(let dev):
            peripheralCardView(device: dev, isFullWidth: isFullWidth)
                .onHover { h in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        hoveredCardId = h ? dev.stableKey : nil
                    }
                }
                .onTapGesture {
                    onSelectAudioDevice?(dev)
                }
        }
    }

    // MARK: - Charger Card View (Real Hardware Telemetry)
    @ViewBuilder
    private func chargerCardView(name: String, watts: Int, isCharging: Bool, isFullWidth: Bool) -> some View {
        let isHovered = hoveredCardId == "charger"
        let statusText: String = {
            if isCharging {
                return watts > 0 ? "⚡ \(watts)W · Charging" : "⚡ Charging"
            } else {
                return watts > 0 ? "⚡ \(watts)W · Plugged In" : "⚡ Plugged In"
            }
        }()

        HStack(spacing: 10) {
            // Circular Charging Badge with Live Emerald Glow
            ZStack {
                Circle()
                    .fill(LiquidColorTokens.emerald.opacity(0.18))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle()
                            .stroke(
                                LiquidColorTokens.emerald.opacity(0.55 + pulsePhase * 0.35),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: LiquidColorTokens.emerald.opacity(0.35 + pulsePhase * 0.25), radius: 6)

                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(LiquidColorTokens.emerald)
                    .scaleEffect(isCharging ? (1.0 + pulsePhase * 0.08) : 1.0)
            }

            // Name & Dynamic Charging Metric
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidColorTokens.primaryText)
                    .lineLimit(1)

                Text(statusText)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidColorTokens.emerald)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(LiquidColorTokens.secondaryText.opacity(isHovered ? 0.9 : 0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: isFullWidth ? .infinity : nil)
        .background(
            liquidCapsuleBackdrop(isHovered: isHovered, accentColor: LiquidColorTokens.emerald)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Peripheral / Bluetooth Card View (Real Hardware Data Only)
    @ViewBuilder
    private func peripheralCardView(device: DeviceIdentity, isFullWidth: Bool) -> some View {
        let isHovered = hoveredCardId == device.stableKey
        let batteryPct = device.batteryPercentage

        HStack(spacing: 10) {
            // Rounded Squircle Badge with Device Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 30, height: 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1.0)
                    )

                deviceIcon(for: device.kind)
            }

            // Name & Battery / Connection Status
            VStack(alignment: .leading, spacing: 1) {
                Text(device.displayName)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidColorTokens.primaryText)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Circle()
                        .fill(LiquidColorTokens.emerald)
                        .frame(width: 5, height: 5)
                        .shadow(color: LiquidColorTokens.emerald.opacity(0.7), radius: 2)

                    Text("Connected")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidColorTokens.emerald)

                    if let bat = batteryPct, bat > 0 {
                        Text("· \(bat)%")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(LiquidColorTokens.secondaryText)

                        batteryMiniGauge(percent: bat)
                    }
                }
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(LiquidColorTokens.secondaryText.opacity(isHovered ? 0.9 : 0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: isFullWidth ? .infinity : nil)
        .background(
            liquidCapsuleBackdrop(isHovered: isHovered, accentColor: nil)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func deviceIcon(for kind: DeviceKind) -> some View {
        switch kind {
        case .airpods, .earbuds, .neckband, .earphones:
            Image(systemName: "earbuds.case.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
        case .headphones:
            Image(systemName: "headphones")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
        case .keyboard:
            Image(systemName: "applekeyboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
        case .mouse, .trackpad:
            Image(systemName: "magicmouse")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
        case .ssdDrive, .usbStick:
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
        default:
            Image(systemName: "headphones")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
        }
    }

    @ViewBuilder
    private func batteryMiniGauge(percent: Int) -> some View {
        let clamped = max(0, min(100, percent))
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 16, height: 7)

            Capsule()
                .fill(clamped > 20 ? LiquidColorTokens.emerald : Color.red)
                .frame(width: max(2, 16.0 * CGFloat(clamped) / 100.0), height: 7)
        }
    }

    // MARK: - Liquid Capsule Backdrop (Apple Dark Liquid Glass)
    @ViewBuilder
    private func liquidCapsuleBackdrop(isHovered: Bool, accentColor: Color?) -> some View {
        ZStack {
            // Frosted blur depth
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)

            // Deep obsidian charcoal (#17191C, 75% opacity)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LiquidColorTokens.primaryGlass.opacity(0.75))

            // Internal gradient (#24282D down to #090B0E)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            LiquidColorTokens.secondaryGlass.opacity(0.45),
                            LiquidColorTokens.deepShadow.opacity(0.70)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Optional accent glow
            if let accent = accentColor {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent.opacity(isHovered ? 0.16 : 0.08))
            }

            // Directional specular sheen
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(isHovered ? 0.22 : 0.12), location: 0.0),
                            .init(color: Color.white.opacity(0.03), location: 0.40),
                            .init(color: Color.clear, location: 0.80)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Specular border rim
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: LiquidColorTokens.silverHighlight.opacity(isHovered ? 0.70 : 0.45), location: 0.0),
                            .init(color: LiquidColorTokens.tealRefraction.opacity(0.30), location: 0.50),
                            .init(color: LiquidColorTokens.champagneReflection.opacity(0.40), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        }
    }
}
