//
//  BluetoothBatteryAlertPopupView.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Defaults
import SwiftUI

/// Collapsed notch notification popup displayed when a Bluetooth device crosses the low-battery or critical threshold.
/// Left: 3D interactive turntable model (or device icon) + colored battery glyph.
/// Center: Hardware notch physical cutout spacing.
/// Right: Text hierarchy (Title, Device + % line, Action line).
public struct BluetoothBatteryAlertPopupView: View {
    public let alert: BluetoothBatteryAlertItem

    @ObservedObject private var vm = LiquidViewModel.shared
    @ObservedObject private var coordinator = LiquidViewCoordinator.shared
    @ObservedObject private var alertManager = BluetoothBatteryAlertManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(alert: BluetoothBatteryAlertItem) {
        self.alert = alert
    }

    public var body: some View {
        HStack(spacing: 12) {
            // MARK: - Left Side: Device Model or Icon + Battery Glyph
            HStack(spacing: 7) {
                // 3D Model or Icon
                if let identity = alert.deviceIdentity, Defaults[.enableDeviceShowcasePopup] {
                    DeviceInteractive3DView(
                        device: identity,
                        size: 28,
                        rpm: reduceMotion ? 0 : 20.0,
                        isPaused: false
                    )
                } else {
                    Premium3DIconView(name: alert.iconName, size: 24)
                }

                // Battery Glyph (Amber below threshold, Red below 5%)
                HStack(spacing: 3) {
                    Premium3DIconView(.battery, size: 14)

                    Text("\(alert.percentage)%")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(alert.batteryColor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(alert.batteryColor.opacity(0.18))
                .clipShape(Capsule())
            }

            Spacer(minLength: 8)

            // MARK: - Right Side: Copy & Advice
            VStack(alignment: .trailing, spacing: 1.5) {
                // Title
                Text(alert.titleText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(alert.batteryColor)
                    .lineLimit(1)

                // Warning / Detail line
                Text(alert.detailLineText)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)

                // Action line
                Text(alert.actionLineText)
                    .font(.system(size: 8.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: 390, height: 50)
        .liquidGlassCapsule(interactive: true)
        .avoidsNotch(id: "BluetoothBatteryAlertPopup")
        .contentShape(Capsule())
        .onHover { hovering in
            alertManager.isHovering = hovering
        }
        .onTapGesture {
            // Tap navigates to Bluetooth tab and dismisses popup
            openBluetoothTab()
        }
    }

    private func openBluetoothTab() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        alertManager.dismissAlert()
        coordinator.currentView = .bluetooth
        vm.open()
    }
}
