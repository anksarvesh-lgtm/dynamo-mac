//
//  BluetoothBatteryAlertPopupView.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Defaults
import SwiftUI

/// Compact, notch-anchored 3D Liquid Glass capsule displayed when a Bluetooth device crosses a low-battery or critical threshold.
/// Left: 3D interactive model or icon.
/// Center/Right: Concise device name • Battery glyph + percentage and severity indicator.
public struct BluetoothBatteryAlertPopupView: View {
    public let alert: BluetoothBatteryAlertItem

    @ObservedObject private var vm = LiquidViewModel.shared
    @ObservedObject private var coordinator = LiquidViewCoordinator.shared
    @ObservedObject private var alertManager = BluetoothBatteryAlertManager.shared
    @ObservedObject private var safeArea = NotchSafeAreaEngine.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var measuredContentWidth: CGFloat = 0

    public init(alert: BluetoothBatteryAlertItem) {
        self.alert = alert
    }

    private var capsuleDimensions: (width: CGFloat, height: CGFloat) {
        let geom = safeArea.currentGeometry
        let minW: CGFloat = geom.hasPhysicalNotch ? max(200.0, geom.rawNotchWidth) : 200.0
        let maxW: CGFloat = min(300.0, max(220.0, geom.screenFrame.width * 0.35))
        let effectiveMeasuredW = measuredContentWidth > 0 ? (measuredContentWidth + 24.0) : 220.0
        let finalWidth = min(maxW, max(minW, effectiveMeasuredW))
        let finalHeight = max(38.0, min(46.0, max(geom.notchHeight, 38.0)))
        return (finalWidth, finalHeight)
    }

    public var body: some View {
        let dims = capsuleDimensions

        compactHorizontalContent
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: EventCapsuleIntrinsicWidthPreferenceKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(EventCapsuleIntrinsicWidthPreferenceKey.self) { newWidth in
                if newWidth > 0 && abs(newWidth - measuredContentWidth) > 1.0 {
                    measuredContentWidth = newWidth
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(width: dims.width, height: dims.height)
            .background(
                ZStack {
                    LiquidGlassSurface(
                        shape: Capsule(),
                        isNotchAnchored: false,
                        ambientColor: alert.batteryColor,
                        scrimFloor: 0.35
                    )
                    // 3D Glass Specular Sheen Highlight
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                }
            )
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.40), radius: 8, y: 3)
            .avoidsNotch(id: "BluetoothBatteryAlertPopup")
            .contentShape(Capsule())
            .onHover { hovering in
                alertManager.isHovering = hovering
            }
            .onTapGesture {
                openBluetoothTab()
            }
    }

    // MARK: - Minimal Horizontal Content

    private var compactHorizontalContent: some View {
        HStack(spacing: 8) {
            // 1. Device Icon / 3D Model
            leadingDeviceIcon

            // 2. Device Name
            Text(alert.deviceName)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 130, alignment: .leading)

            // 3. Dot Separator
            Text("•")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))

            // 4. Battery Level & Warning
            HStack(spacing: 4) {
                Image(systemName: alert.percentage <= 5 ? "battery.0" : "battery.25")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(alert.batteryColor)

                Text("\(alert.percentage)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(alert.batteryColor)

                Text(alert.percentage <= 5 ? "Critical" : "Low")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(alert.batteryColor.opacity(0.95))
            }
        }
    }

    @ViewBuilder
    private var leadingDeviceIcon: some View {
        if let identity = alert.deviceIdentity, Defaults[.enableDeviceShowcasePopup] {
            DeviceInteractive3DView(
                device: identity,
                size: 20,
                rpm: reduceMotion ? 0 : 20.0,
                isPaused: false
            )
            .frame(width: 20, height: 20)
        } else {
            Premium3DIconView(name: alert.iconName, size: 18, interactive: false)
        }
    }

    private func openBluetoothTab() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        alertManager.dismissAlert()
        coordinator.currentView = .bluetooth
        vm.open()
    }
}

