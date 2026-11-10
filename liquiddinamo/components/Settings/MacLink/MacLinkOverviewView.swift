//
//  MacLinkOverviewView.swift
//  LiquidDynamo
//
//  MacLink Primary Hub: Device Telemetry, Battery Status, 1-Click Screen Mirroring,
//  Clipboard Sync, and Quick Actions.
//

import AppKit
import Defaults
import SwiftUI

public struct MacLinkOverviewView: View {
    @ObservedObject private var bridge = MacLinkBridgeService.shared

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                headerBanner

                // Quick Hardware Telemetry Grid
                telemetryGrid

                // Live Screen Mirroring Card
                mirroringCard

                // Quick Command Switches
                quickSwitchesGrid
            }
            .padding(24)
        }
    }

    private var headerBanner: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 54, height: 54)

                Image(systemName: "iphone.gen3")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(bridge.deviceName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.white)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(bridge.isConnected ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)

                        Text(bridge.isConnected ? "Connected" : "Searching…")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(bridge.isConnected ? Color.green : Color.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((bridge.isConnected ? Color.green : Color.orange).opacity(0.12))
                    )
                }

                Text("High-Speed USB Link • Android 15 • Low Latency Mirroring Active")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.6))
            }

            Spacer()

            Button {
                bridge.startScreenMirroring()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Mirror Screen")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.blue)
                )
                .shadow(color: Color.blue.opacity(0.4), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.12).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var telemetryGrid: some View {
        HStack(spacing: 14) {
            // Battery Card
            telemetryCard(
                title: "Battery Level",
                value: "\(bridge.batteryLevel)%",
                subtitle: bridge.isCharging ? "Charging Fast" : "On Battery",
                icon: bridge.isCharging ? "bolt.batteryblock.fill" : "battery.100",
                tint: .green
            )

            // Cellular Card
            telemetryCard(
                title: "Cellular Network",
                value: "\(bridge.cellularNetworkType)",
                subtitle: "\(bridge.cellularSignalBars)/4 Signal Bars",
                icon: "antenna.radiowaves.left.and.right",
                tint: .blue
            )

            // Storage Card
            telemetryCard(
                title: "Internal Storage",
                value: "\(Int(bridge.storageUsedGB)) GB",
                subtitle: "\(Int(bridge.storageTotalGB - bridge.storageUsedGB)) GB Free",
                icon: "internaldrive.fill",
                tint: .purple
            )

            // Clipboard Sync Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.orange)
                    Spacer()
                    Toggle("", isOn: $bridge.clipboardSyncEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Text("Clipboard Sync")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(bridge.clipboardSyncEnabled ? "Instant Shared" : "Disabled")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(white: 0.12).opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }

    private func telemetryCard(title: String, value: String, subtitle: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(value)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(tint.opacity(0.85))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.12).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var mirroringCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hardware Low-Latency Screen Mirroring")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("Powered by Apple VideoToolbox hardware H.264 decoding & scrcpy socket protocol")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("60 FPS • 1080p • 8ms Latency")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                }
            }

            HStack(spacing: 12) {
                Button {
                    bridge.startScreenMirroring()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.inset.filled.and.cursorarrow")
                        Text("Open Mirror Window")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.85)))
                }
                .buttonStyle(.plain)

                Button {
                    bridge.simulateIncomingCall()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.bubble.left.fill")
                        Text("Test Incoming Call Droplet")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.12).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var quickSwitchesGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Phone Deck Quick Toggles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white)

            HStack(spacing: 12) {
                deckToggleCard(title: "Mobile Hotspot", icon: "wifi", isOn: $bridge.isHotspotActive, activeColor: .orange)
                deckToggleCard(title: "Do Not Disturb", icon: "moon.fill", isOn: $bridge.isDNDActive, activeColor: .indigo)
                deckToggleCard(title: "Flashlight", icon: "flashlight.on.fill", isOn: $bridge.isFlashlightActive, activeColor: .yellow)
                deckToggleCard(title: "Silent Mode", icon: "bell.slash.fill", isOn: $bridge.isSilentModeActive, activeColor: .red)
            }
        }
    }

    private func deckToggleCard(title: String, icon: String, isOn: Binding<Bool>, activeColor: Color) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? activeColor : Color.white.opacity(0.4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text(isOn.wrappedValue ? "Active" : "Off")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(isOn.wrappedValue ? activeColor : Color.white.opacity(0.45))
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn.wrappedValue ? activeColor.opacity(0.15) : Color(white: 0.12).opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isOn.wrappedValue ? activeColor.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

