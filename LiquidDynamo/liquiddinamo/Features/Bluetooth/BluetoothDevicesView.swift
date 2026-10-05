//
//  BluetoothDevicesView.swift
//  boringNotch
//
//  Created for Boring Notch
//

import Defaults
import SwiftUI

struct BluetoothDevicesView: View {
    @ObservedObject var bluetoothService = BluetoothService.shared
    @ObservedObject var alertManager = BluetoothBatteryAlertManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Label("BLUETOOTH DEVICES", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(bluetoothService.connectedDevices.count) CONNECTED")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if bluetoothService.connectedDevices.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("No connected Bluetooth devices")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 70)
            } else {
                VStack(spacing: 6) {
                    ForEach(bluetoothService.connectedDevices) { device in
                        BluetoothDeviceRowView(device: device)
                    }
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 22, tint: .blue)
        .onAppear {
            alertManager.handleBluetoothTabOpened()
        }
    }
}

// MARK: - Bluetooth Device Row

struct BluetoothDeviceRowView: View {
    let device: BluetoothDeviceInfo

    @ObservedObject private var alertManager = BluetoothBatteryAlertManager.shared
    @Default(.lowBatteryWarningThreshold) private var warningThreshold
    @Default(.mutedBatteryAlertDeviceIDs) private var mutedDeviceIDs

    private var isMuted: Bool {
        mutedDeviceIDs.contains(device.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // Device Icon in Circle
                Premium3DIconView(
                    name: device.iconName,
                    size: 20,
                    interactive: false
                )
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())

                // Device Name & Status
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text("Connected")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)

                        if device.isCharging {
                            Premium3DIconView(.charging, size: 10, interactive: false)
                        }
                    }
                }

                Spacer()

                // Battery Section (only shown when available, never invented)
                if !device.batteryParts.isEmpty {
                    // Multi-part battery display (e.g. Left / Right / Case)
                    HStack(spacing: 6) {
                        ForEach(device.batteryParts) { part in
                            partBatteryView(part: part)
                        }
                    }
                } else if let battery = device.batteryPercentage {
                    // Single battery display
                    singleBatteryView(percentage: battery, isCharging: device.isCharging)
                }

                // Mute Alerts Toggle
                Button {
                    alertManager.toggleDeviceMute(device.id)
                } label: {
                    Premium3DIconView(
                        .notifications,
                        size: 13,
                        customTint: isMuted ? Color.orange : Color.white.opacity(0.4),
                        interactive: false
                    )
                    .frame(width: 24, height: 24)
                    .background(isMuted ? Color.orange.opacity(0.12) : Color.white.opacity(0.05))
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isMuted ? String(localized: "Alerts muted for this device") : String(localized: "Mute alerts for this device"))
            }

            // If multi-part, show labels underneath if needed
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Single Battery View

    @ViewBuilder
    private func singleBatteryView(percentage: Int, isCharging: Bool) -> some View {
        HStack(spacing: 6) {
            // Status Label: "Critical" (<5%), "Low" (<= threshold)
            if percentage < 5 {
                Text(String(localized: "Critical"))
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Color.red.opacity(0.15))
                    .clipShape(Capsule())
            } else if percentage <= warningThreshold {
                Text(String(localized: "Low"))
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Colored Battery Bar
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 44, height: 5)

                Capsule()
                    .fill(batteryColor(for: percentage))
                    .frame(width: max(3, 44 * CGFloat(min(100, max(0, percentage))) / 100.0), height: 5)
            }

            // Battery % Badge
            HStack(spacing: 4) {
                if isCharging {
                    Premium3DIconView(.charging, size: 12, interactive: false)
                } else {
                    Premium3DIconView(.battery, size: 12, customTint: batteryColor(for: percentage), interactive: false)
                }

                Text("\(percentage)%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
        }
    }

    // MARK: - Part Battery View (Left / Right / Case)

    @ViewBuilder
    private func partBatteryView(part: DeviceBatteryPart) -> some View {
        HStack(spacing: 3) {
            Text(partBadgeLetter(for: part.kind))
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            // Mini bar
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 22, height: 4)

                Capsule()
                    .fill(batteryColor(for: part.percentage))
                    .frame(width: max(2, 22 * CGFloat(min(100, max(0, part.percentage))) / 100.0), height: 4)
            }

            Text("\(part.percentage)%")
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(part.percentage <= warningThreshold ? batteryColor(for: part.percentage) : .secondary)

            if part.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2.5)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .help("\(part.kind.displayName): \(part.percentage)%\(part.isCharging ? " (Charging)" : "")")
    }

    private func partBadgeLetter(for kind: DeviceBatteryPart.PartKind) -> String {
        switch kind {
        case .leftEarbud: return "L"
        case .rightEarbud: return "R"
        case .caseUnit: return "C"
        case .general: return ""
        }
    }

    private func batteryIcon(for percent: Int) -> String {
        if percent <= 5 {
            return "battery.0"
        } else if percent <= 15 {
            return "battery.25"
        } else if percent <= 50 {
            return "battery.50"
        } else if percent <= 75 {
            return "battery.75"
        } else {
            return "battery.100"
        }
    }

    private func batteryColor(for percent: Int) -> Color {
        if percent < 5 {
            return .red
        } else if percent <= warningThreshold {
            return .orange // Amber
        } else {
            return .green
        }
    }
}
