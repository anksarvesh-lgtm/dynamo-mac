//
//  DeviceShowcasePopupView.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Defaults
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

// MARK: - Compact Connected-Device Liquid Glass Capsule

/// Compact, notch-anchored 3D Liquid Glass capsule for connected-device notifications.
/// Features content-aware sizing (200–300 pt width, 38–46 pt height), minimal horizontal layout,
/// and smooth Apple Liquid Glass specular highlights without covering the user's workspace.
public struct DeviceShowcasePopupView: View {
    public let device: DeviceIdentity

    @ObservedObject private var vm = LiquidViewModel.shared
    @ObservedObject private var coordinator = LiquidViewCoordinator.shared
    @ObservedObject private var showcase = DeviceShowcaseCoordinator.shared
    @ObservedObject private var safeArea = NotchSafeAreaEngine.shared
    @StateObject private var model = DeviceShowcasePopupViewModel()

    @State private var measuredContentWidth: CGFloat = 0

    public init(device: DeviceIdentity) {
        self.device = device
    }

    private var conciseDisplayName: String {
        let name = device.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? device.kind.rawValue : name
    }

    private var deviceAccentColor: Color {
        if device.kind == .charger || device.connectionType == .power {
            return .green
        } else if device.connectionType == .storage {
            return .cyan
        } else if device.kind == .androidPhone {
            return .green
        } else if device.kind == .phone {
            return .blue
        } else {
            return .accentColor
        }
    }

    private var capsuleDimensions: (width: CGFloat, height: CGFloat) {
        let geom = safeArea.currentGeometry
        let minW: CGFloat = geom.hasPhysicalNotch ? max(200.0, geom.rawNotchWidth) : 200.0
        let maxW: CGFloat = min(460.0, max(300.0, geom.screenFrame.width * 0.45))
        let effectiveMeasuredW = measuredContentWidth > 0 ? (measuredContentWidth + 24.0) : (IslandController.shared.dynamicAlertCapsuleWidth ?? 220.0)
        let finalWidth = min(maxW, max(minW, effectiveMeasuredW))
        let finalHeight = max(38.0, min(46.0, max(geom.notchHeight, 38.0)))
        return (finalWidth, finalHeight)
    }

    public var body: some View {
        let dims = capsuleDimensions

        ZStack {
            compactHorizontalContent
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: EventCapsuleIntrinsicWidthPreferenceKey.self, value: geo.size.width)
                    }
                )
                .hidden()

            compactHorizontalContent
                .frame(width: max(0, dims.width - 24.0))
        }
        .onPreferenceChange(EventCapsuleIntrinsicWidthPreferenceKey.self) { newWidth in
            if newWidth > 0 && abs(newWidth - measuredContentWidth) > 1.0 {
                measuredContentWidth = newWidth
                let geom = safeArea.currentGeometry
                let minW: CGFloat = geom.hasPhysicalNotch ? max(200.0, geom.rawNotchWidth) : 200.0
                let maxW: CGFloat = min(460.0, max(300.0, geom.screenFrame.width * 0.45))
                let calculated = min(maxW, max(minW, newWidth + 24.0))
                IslandController.shared.reportAlertCapsuleWidth(calculated)
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
                        ambientColor: deviceAccentColor,
                        scrimFloor: 0.55
                    )

                    // Static 35-45% Translucent Water Fill with Live Surface Waves
                    LiquidWaterCapsuleView(
                        fillLevel: 0.38,
                        tintColor: deviceAccentColor,
                        phaseOffset: 0.2
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
            .avoidsNotch(id: "DeviceShowcasePopup")
            .contentShape(Capsule())
            .onHover { hovering in
                showcase.isHovering = hovering
            }
            .onTapGesture {
                openInDevicesTab()
            }
    }

    // MARK: - Minimal Horizontal Content

    private var compactHorizontalContent: some View {
        HStack(spacing: 8) {
            // 1. Recognizable Device Icon
            leadingDeviceIcon

            // 2. Concise Device Name
            Text(conciseDisplayName)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            // 3. Dot Separator
            Text("•")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))

            // 4. Concise Status & Key Metrics
            trailingMetricsView
        }
    }

    @ViewBuilder
    private var leadingDeviceIcon: some View {
        if device.kind == .charger || device.connectionType == .power {
            Premium3DIconView(name: device.iconName, size: 18, interactive: false)
        } else if Defaults[.enableDeviceShowcasePopup] {
            DeviceInteractive3DView(
                device: device,
                size: 20,
                rpm: 20.0,
                isPaused: false
            )
            .frame(width: 20, height: 20)
        } else {
            Premium3DIconView(name: device.iconName, size: 18, interactive: false)
        }
    }

    @ViewBuilder
    private var trailingMetricsView: some View {
        if device.kind == .charger || device.connectionType == .power {
            chargerMetricsView
        } else if device.connectionType == .storage {
            storageMetricsView
        } else if device.connectionType == .bluetooth || device.kind == .headphones || device.kind == .earbuds || device.kind == .airpods {
            bluetoothMetricsView
        } else if device.kind == .phone || device.kind == .androidPhone {
            phoneMetricsView
        } else {
            genericMetricsView
        }
    }

    // MARK: - Device Category Views

    @ViewBuilder
    private var chargerMetricsView: some View {
        HStack(spacing: 5) {
            if let watts = device.chargerWatts, watts > 0 {
                Text("\(watts) W")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
            } else {
                Text("Charging")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.green)
            }

            if let bat = device.batteryPercentage {
                Text("•")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))

                Text("\(bat)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var storageMetricsView: some View {
        HStack(spacing: 6) {
            if let free = device.formattedFreeSpace {
                Text("\(free) free")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            } else {
                Text("Connected")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }

            // Compact Eject Button
            Button(action: {
                model.handleEject(device: device) {
                    showcase.dismiss()
                }
            }) {
                Image(systemName: model.isEjected ? "checkmark" : "eject.fill")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(model.isEjected ? .green : (model.isEjectHovered ? .red : .white.opacity(0.85)))
                    .frame(width: 18, height: 18)
                    .background(model.isEjectHovered ? Color.red.opacity(0.25) : Color.white.opacity(0.12))
                    .clipShape(Circle())
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
            Text("Connected")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))

            if let battery = device.batteryPercentage {
                HStack(spacing: 3) {
                    Image(systemName: batteryIconName(percentage: battery))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(batteryColor(percentage: battery))

                    Text("\(battery)%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
        }
    }

    @ViewBuilder
    private var phoneMetricsView: some View {
        HStack(spacing: 5) {
            Text("Connected")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))

            if let battery = device.batteryPercentage {
                Text("\(battery)%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.green)
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
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
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
