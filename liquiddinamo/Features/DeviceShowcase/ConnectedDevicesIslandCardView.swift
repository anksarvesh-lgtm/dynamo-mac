//
//  ConnectedDevicesIslandCardView.swift
//  LiquidDynamo
//
//  Dynamic Island Slot 1 card for currently connected external devices.
//  Strictly collapses to 0 height when 0 devices are connected.
//  Provides compact 28pt rows, battery/charging readout, and click-to-expand details.
//

import AppKit
import Defaults
import SwiftUI

public struct ConnectedDevicesIslandCardView: View {
    @ObservedObject private var monitor = DeviceMonitor.shared
    @ObservedObject private var coordinator = LiquidViewCoordinator.shared
    @Default(.hiddenDeviceIDs) private var hiddenDeviceIDs
    @Default(.showExternalDrivesInDevices) private var showDrives
    @Default(.showExternalDisplaysInDevices) private var showDisplays

    @State private var expandedDeviceKey: String? = nil

    public init() {}

    /// Real external connected devices, strictly excluding internal/virtual hardware and user-hidden devices.
    public var visibleDevices: [DeviceIdentity] {
        monitor.sortedActiveDevices.filter { dev in
            // Filter user-hidden devices
            if hiddenDeviceIDs.contains(dev.stableKey) { return false }

            // Filter internal root hubs, controllers, and built-in hardware
            let name = dev.displayName.lowercased()
            let vendor = dev.vendor.lowercased()
            let model = dev.model.lowercased()

            if name.contains("built-in") || model.contains("built-in") { return false }
            if name.contains("root hub") || model.contains("root hub") { return false }
            if name.contains("apple t2") || name.contains("ambient light") { return false }
            if name.contains("virtual") || vendor.contains("virtual") { return false }

            // Optional external drives toggle
            if (dev.kind == .ssdDrive || dev.kind == .usbStick) && !showDrives {
                return false
            }

            // Optional external displays toggle
            if dev.kind == .monitor && !showDisplays {
                return false
            }

            return true
        }
    }

    public var body: some View {
        if visibleDevices.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                headerRow

                VStack(spacing: 3) {
                    ForEach(visibleDevices.prefix(2)) { dev in
                        deviceRow(dev)
                    }
                }
            }
            .contentShape(Rectangle())
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: visibleDevices.count)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: expandedDeviceKey)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "cable.connector")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.accentColor)

            Text("DEVICES (\(visibleDevices.count))")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(0)

            Spacer(minLength: 2)

            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                    coordinator.currentView = .devices
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(2)
            }
            .buttonStyle(.plain)
            .help("Open Device Library")
            .layoutPriority(1)
        }
    }

    // MARK: - Device Row

    private func deviceRow(_ dev: DeviceIdentity) -> some View {
        let isExpanded = expandedDeviceKey == dev.stableKey

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                // Device Kind Icon
                Image(systemName: dev.iconName.isEmpty ? dev.kind.defaultIconName : dev.iconName)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(iconColor(for: dev))
                    .frame(width: 14, height: 14)

                // Device Name (truncated with ellipsis, flexible layout)
                Text(dev.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(0)

                Spacer(minLength: 2)

                // Battery / Status readout
                if let battery = dev.batteryPercentage {
                    HStack(spacing: 2) {
                        if dev.isChargingState == true {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 7.5))
                                .foregroundStyle(Color.green)
                        }
                        Text("\(battery)%")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(batteryColor(battery))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule().fill(Color.white.opacity(0.06))
                    )
                    .layoutPriority(1)
                } else if dev.kind == .charger, let watts = dev.chargerWatts {
                    Text("\(watts)W")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.yellow)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule().fill(Color.white.opacity(0.06))
                        )
                        .layoutPriority(1)
                }

                // Connection badge
                connectionBadge(dev.connectionType)
                    .layoutPriority(1)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    if expandedDeviceKey == dev.stableKey {
                        expandedDeviceKey = nil
                    } else {
                        expandedDeviceKey = dev.stableKey
                    }
                }
            }

            // In-place Expanded Details
            if isExpanded {
                expandedDetailsView(dev)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isExpanded ? Color.white.opacity(0.07) : Color.white.opacity(0.03))
        )
    }

    // MARK: - In-Place Expanded Detail

    private func expandedDetailsView(_ dev: DeviceIdentity) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Divider()
                .background(Color.white.opacity(0.08))

            HStack {
                Text("\(dev.vendor) • \(dev.model)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)

                Spacer()

                // Hide device button
                Button {
                    hideDevice(dev.stableKey)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 7.5))
                        Text("Hide")
                            .font(.system(size: 8, weight: .medium))
                    }
                    .foregroundStyle(Color.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Hide this device in Island")
            }

            // Storage Details
            if let cap = dev.capacityBytes, cap > 0 {
                let free = dev.freeSpaceBytes ?? 0
                let used = cap > free ? (cap - free) : 0
                Text("Storage: \(formatBytes(used)) used / \(formatBytes(cap)) total")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            // Display Details
            if let res = dev.resolution {
                Text("Resolution: \(res) @ \(Int(dev.refreshRate ?? 60))Hz")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    // MARK: - Helpers

    private func connectionBadge(_ type: ConnectionType) -> some View {
        let title: String
        let color: Color
        switch type {
        case .bluetooth:
            title = "BT"
            color = Color.blue
        case .usb:
            title = "USB"
            color = Color.purple
        case .storage:
            title = "DISK"
            color = Color.orange
        case .display:
            title = "DISP"
            color = Color.cyan
        case .power:
            title = "AC"
            color = Color.yellow
        case .audioJack:
            title = "AUX"
            color = Color.green
        }

        return Text(title)
            .font(.system(size: 7.5, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(
                Capsule().fill(color.opacity(0.15))
            )
    }

    private func iconColor(for dev: DeviceIdentity) -> Color {
        switch dev.connectionType {
        case .bluetooth: return .blue
        case .usb: return .purple
        case .storage: return .orange
        case .display: return .cyan
        case .power: return .yellow
        case .audioJack: return .green
        }
    }

    private func batteryColor(_ level: Int) -> Color {
        if level <= 20 {
            return .red
        } else if level <= 50 {
            return .yellow
        } else {
            return .green
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func hideDevice(_ key: String) {
        var hidden = hiddenDeviceIDs
        if !hidden.contains(key) {
            hidden.append(key)
            Defaults[.hiddenDeviceIDs] = hidden
        }
        if expandedDeviceKey == key {
            expandedDeviceKey = nil
        }
    }
}
