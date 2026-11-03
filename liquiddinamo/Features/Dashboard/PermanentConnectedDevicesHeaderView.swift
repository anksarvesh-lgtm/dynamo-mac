//
//  PermanentConnectedDevicesHeaderView.swift
//  LiquidDynamo
//
//  Permanent Connected Devices Header:
//  - MagSafe 3 Charger & Wireless / Wired Audio (realme Buds Wireless / AirPods)
//  - Always persistent across all carousel slides and detail modes
//  - Organic liquid-glass dual capsule layout linked by fluid refractive bridge
//  - Live dynamic telemetry with optical glow and water physics interaction
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

public struct PermanentConnectedDevicesHeaderView: View {
    @ObservedObject var chargingService = ChargingIntelligenceService.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var deviceMonitor = DeviceMonitor.shared
    @ObservedObject var memoryRegistry = DeviceMemoryRegistry.shared

    public var onSelectCharger: (() -> Void)? = nil
    public var onSelectAudioDevice: ((DeviceIdentity?) -> Void)? = nil

    @State private var isHoveringCharger: Bool = false
    @State private var isHoveringAudio: Bool = false
    @State private var pulsePhase: Double = 0.0

    public init(
        onSelectCharger: (() -> Void)? = nil,
        onSelectAudioDevice: ((DeviceIdentity?) -> Void)? = nil
    ) {
        self.onSelectCharger = onSelectCharger
        self.onSelectAudioDevice = onSelectAudioDevice
    }

    // Resolve strictly verified active connected device (audio, peripheral, etc.)
    private var primaryConnectedDevice: DeviceIdentity? {
        // Query only active devices verified by DeviceMonitor
        return deviceMonitor.sortedActiveDevices.first(where: {
            ($0.kind == .neckband || $0.kind == .headphones || $0.kind == .earbuds || $0.kind == .earphones || $0.kind == .airpods || $0.kind == .keyboard || $0.kind == .mouse || $0.kind == .trackpad) &&
            deviceMonitor.activeDevices[$0.stableKey] != nil
        })
    }

    private var isAudioConnected: Bool {
        return primaryConnectedDevice != nil
    }

    public var body: some View {
        HStack(spacing: 8) {
            // MARK: - Left Card: MagSafe 3 / Power Adapter / Mac Battery
            chargerCard
                .onHover { h in withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { isHoveringCharger = h } }
                .onTapGesture {
                    onSelectCharger?()
                }

            // MARK: - Right Card: Verified Connected Bluetooth / Audio Device
            audioDeviceCard
                .onHover { h in withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { isHoveringAudio = h } }
                .onTapGesture {
                    onSelectAudioDevice?(primaryConnectedDevice)
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulsePhase = 1.0
            }
        }
    }

    // MARK: - MagSafe 3 / Power Adapter / Internal Battery Card (100% Real Hardware Telemetry)
    @ViewBuilder
    private var chargerCard: some View {
        let isPlugged = chargingService.isPluggedIn || batteryModel.isPluggedIn
        let isCharging = chargingService.isCharging || batteryModel.isCharging
        let watts = chargingService.adapterWatts
        let portDesc: String = {
            if isPlugged {
                if chargingService.connectedPortDescription.contains("MagSafe") {
                    return "MagSafe 3 Charger"
                } else if !chargingService.adapterName.isEmpty {
                    return chargingService.adapterName
                } else {
                    return "Power Adapter"
                }
            } else {
                return "MacBook Battery"
            }
        }()

        let statusText: String = {
            if isCharging {
                return watts > 0 ? "⚡ \(watts)W · Charging" : "⚡ Charging"
            } else if isPlugged {
                return watts > 0 ? "⚡ \(watts)W · Plugged In" : "⚡ Plugged In"
            } else {
                let bat = Int(batteryModel.levelBattery)
                return "● \(bat)% · On Battery"
            }
        }()

        HStack(spacing: 10) {
            // Circular Charging / Battery Badge
            ZStack {
                Circle()
                    .fill(isPlugged ? LiquidColorTokens.emerald.opacity(0.18) : Color.white.opacity(0.08))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(
                                isPlugged
                                    ? LiquidColorTokens.emerald.opacity(0.55 + pulsePhase * 0.35)
                                    : Color.white.opacity(0.16),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: isPlugged ? LiquidColorTokens.emerald.opacity(0.35 + pulsePhase * 0.25) : .clear, radius: 6)

                Image(systemName: isPlugged ? "bolt.fill" : "battery.100")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isPlugged ? LiquidColorTokens.emerald : LiquidColorTokens.secondaryText)
                    .scaleEffect(isCharging ? (1.0 + pulsePhase * 0.08) : 1.0)
            }

            // Name & Dynamic Metric
            VStack(alignment: .leading, spacing: 2) {
                Text(portDesc)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidColorTokens.primaryText)
                    .lineLimit(1)

                Text(statusText)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(isPlugged ? LiquidColorTokens.emerald : LiquidColorTokens.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(LiquidColorTokens.secondaryText.opacity(isHoveringCharger ? 0.9 : 0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            liquidCapsuleBackdrop(
                isHovered: isHoveringCharger,
                accentColor: isPlugged ? LiquidColorTokens.emerald : nil
            )
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Audio / Peripheral Device Card (Real Telemetry Only)
    @ViewBuilder
    private var audioDeviceCard: some View {
        let dev = primaryConnectedDevice
        let isConn = (dev != nil)
        let displayName = dev?.displayName ?? "Bluetooth Devices"
        let batteryPct = dev?.batteryPercentage

        HStack(spacing: 10) {
            // Icon Inside Rounded Squircle Badge
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isConn ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isConn ? Color.white.opacity(0.28) : Color.white.opacity(0.10), lineWidth: 1.0)
                    )

                if let kind = dev?.kind {
                    switch kind {
                    case .airpods, .earbuds:
                        Image(systemName: "earbuds.case.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white)
                    case .keyboard:
                        Image(systemName: "applekeyboard")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white)
                    case .mouse, .trackpad:
                        Image(systemName: "magicmouse")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white)
                    default:
                        Image(systemName: "headphones")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                } else {
                    Image(systemName: "bluetooth")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LiquidColorTokens.secondaryText)
                }
            }

            // Name & Battery / Status
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidColorTokens.primaryText)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Circle()
                        .fill(isConn ? LiquidColorTokens.emerald : LiquidColorTokens.mutedText)
                        .frame(width: 5, height: 5)
                        .shadow(color: isConn ? LiquidColorTokens.emerald.opacity(0.7) : .clear, radius: 2)

                    Text(isConn ? "Connected" : "No Devices Connected")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(isConn ? LiquidColorTokens.emerald : LiquidColorTokens.mutedText)

                    if let bat = batteryPct {
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
                .foregroundStyle(LiquidColorTokens.secondaryText.opacity(isHoveringAudio ? 0.9 : 0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            liquidCapsuleBackdrop(
                isHovered: isHoveringAudio,
                accentColor: isConn ? LiquidColorTokens.emerald : nil
            )
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Mini Battery Gauge
    @ViewBuilder
    private func batteryMiniGauge(percent: Int) -> some View {
        let barColor = percent <= 20 ? Color.red : LiquidColorTokens.emerald
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                    .stroke(barColor.opacity(0.85), lineWidth: 1.0)
                    .frame(width: 15, height: 8)

                RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                    .fill(barColor)
                    .frame(width: max(2.5, 11.0 * CGFloat(min(100, max(0, percent))) / 100.0), height: 5)
                    .offset(x: 1.2)
            }
            // Battery terminal cap
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(barColor.opacity(0.85))
                .frame(width: 1.5, height: 4)
        }
    }

    // MARK: - Liquid Capsule Backdrop
    @ViewBuilder
    private func liquidCapsuleBackdrop(isHovered: Bool, accentColor: Color?) -> some View {
        ZStack {
            // Dark smoked glass base (#17191C)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LiquidColorTokens.primaryGlass.opacity(0.85))

            // Secondary glass depth (#24282D)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            LiquidColorTokens.secondaryGlass.opacity(0.55),
                            LiquidColorTokens.deepShadow.opacity(0.75)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Subtle optical teal refraction (#123B36)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            (accentColor ?? LiquidColorTokens.tealRefraction).opacity(isHovered ? 0.22 : 0.12),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 90
                    )
                )

            // Silver edge specular highlight (#DDE8F0)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: LiquidColorTokens.silverHighlight.opacity(isHovered ? 0.55 : 0.32), location: 0.0),
                            .init(color: LiquidColorTokens.champagneReflection.opacity(0.18), location: 0.45),
                            .init(color: Color.white.opacity(0.06), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
        }
        .shadow(color: LiquidColorTokens.deepShadow.opacity(0.6), radius: 8, x: 0, y: 3)
    }
}
