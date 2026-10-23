//
//  DeviceShowcasePopupView.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import SwiftUI

// MARK: - View Model

@MainActor
public final class DeviceShowcasePopupViewModel: ObservableObject {
    @Published public var isEjected: Bool = false
    @Published public var isEjectHovered: Bool = false

    public init() {}

    public func handleEject(device: DeviceIdentity, onDismiss: @escaping () -> Void) {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        let success = device.eject()
        if success {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.isEjected = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onDismiss()
            }
        }
    }
}

// MARK: - Popup View

/// Collapsed notch notification popup displayed when a device connects.
/// Left: 3D interactive turntable model + device name.
/// Center: Hardware notch physical cutout spacing.
/// Right: Live metrics (battery or storage free space & capacity) + Eject button (for storage).
public struct DeviceShowcasePopupView: View {
    public let device: DeviceIdentity

    @ObservedObject private var vm = LiquidViewModel.shared
    @ObservedObject private var coordinator = LiquidViewCoordinator.shared
    @ObservedObject private var showcase = DeviceShowcaseCoordinator.shared
    @StateObject private var model = DeviceShowcasePopupViewModel()

    public init(device: DeviceIdentity) {
        self.device = device
    }

    public var body: some View {
        HStack(spacing: 12) {
            // MARK: - Left Side: 3D Model & Name
            HStack(spacing: 8) {
                DeviceInteractive3DView(
                    device: device,
                    size: 28,
                    rpm: 20.0,
                    isPaused: false
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.displayName)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(device.kind.rawValue)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // MARK: - Right Side: Metrics & Controls
            HStack(spacing: 6) {
                if device.connectionType == .storage {
                    storageMetricsView
                } else if device.connectionType == .bluetooth {
                    bluetoothMetricsView
                } else {
                    genericMetricsView
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: 400, height: 50)
        .liquidGlassCapsule(interactive: true)
        .avoidsNotch(id: "DeviceShowcasePopup")
        .contentShape(Capsule())
        .onHover { hovering in
            showcase.isHovering = hovering
        }
        .onTapGesture {
            // Clicking background expands notch directly into the Devices tab
            openInDevicesTab()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var storageMetricsView: some View {
        HStack(spacing: 6) {
            VStack(alignment: .trailing, spacing: 1) {
                if let free = device.formattedFreeSpace {
                    Text("\(free) free")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }

                if let total = device.formattedCapacity {
                    Text("of \(total)")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            // Eject Button
            Button(action: {
                model.handleEject(device: device) {
                    showcase.dismiss()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(model.isEjectHovered ? Color.red.opacity(0.3) : Color.white.opacity(0.12))
                        .frame(width: 22, height: 22)

                    Image(systemName: model.isEjected ? "checkmark" : "eject.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(model.isEjected ? .green : (model.isEjectHovered ? .red : .white))
                }
            }
            .buttonStyle(.plain)
            .help(model.isEjected ? "Ejected" : "Eject \(device.displayName)")
            .onHover { model.isEjectHovered = $0 }
            .disabled(model.isEjected)
        }
    }

    @ViewBuilder
    private var bluetoothMetricsView: some View {
        HStack(spacing: 6) {
            if let battery = device.batteryPercentage {
                HStack(spacing: 3) {
                    Image(systemName: batteryIconName(percentage: battery))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(batteryColor(percentage: battery))

                    Text("\(battery)%")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)

                Text("Connected")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private var genericMetricsView: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.green)
                .frame(width: 5, height: 5)

            Text("Connected")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Actions & Helpers

    private func openInDevicesTab() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        showcase.dismiss()
        coordinator.currentView = .devices
        vm.open()
    }

    private func batteryIconName(percentage: Int) -> String {
        switch percentage {
        case 0...20: return "battery.25"
        case 21...50: return "battery.50"
        case 51...85: return "battery.75"
        default: return "battery.100"
        }
    }

    private func batteryColor(percentage: Int) -> Color {
        if percentage <= 20 { return .red }
        if percentage <= 40 { return .orange }
        return .green
    }
}
