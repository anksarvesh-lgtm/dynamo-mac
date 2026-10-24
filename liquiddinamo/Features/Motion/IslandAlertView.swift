//
//  IslandAlertView.swift
//  LiquidDynamo
//
//  Created for Dynamic Island Status & Notification System
//

import SwiftUI
import Defaults

/// Preference key to capture intrinsic width of event content
public struct EventCapsuleIntrinsicWidthPreferenceKey: PreferenceKey {
    public static var defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = max(value, next)
        }
    }
}

/// Shared 3D liquid capsule container for all transient events and HUDs.
/// Adheres strictly to NotchSafeAreaEngine geometry, with Apple Liquid Glass specular sheen,
/// hairline rim reflections, content-aware proportional sizing, and smooth spring physics.
public struct LiquidAlertCapsuleContainer<Content: View>: View {
    public var tintColor: Color?
    public var dwellDuration: TimeInterval
    public var onDismiss: () -> Void
    public var action: (() -> Void)?
    public var content: () -> Content

    @ObservedObject private var safeArea = NotchSafeAreaEngine.shared
    @ObservedObject private var motion = IslandMotion.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovered: Bool = false
    @State private var measuredWidth: CGFloat = 0

    public init(
        tintColor: Color? = nil,
        dwellDuration: TimeInterval = 3.0,
        onDismiss: @escaping () -> Void = {},
        action: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tintColor = tintColor
        self.dwellDuration = dwellDuration
        self.onDismiss = onDismiss
        self.action = action
        self.content = content
    }

    public var body: some View {
        let geom = safeArea.currentGeometry
        let minW: CGFloat = geom.hasPhysicalNotch ? max(180.0, geom.rawNotchWidth) : 180.0
        let maxW: CGFloat = min(380.0, max(280.0, geom.screenFrame.width * 0.45))
        let effectiveMeasuredW = measuredWidth > 0 ? (measuredWidth + 28.0) : IslandController.alertCapsuleDefaultWidth
        let finalWidth = min(maxW, max(minW, effectiveMeasuredW))
        let finalHeight = max(36.0, min(48.0, max(geom.notchHeight, 38.0)))

        content()
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: EventCapsuleIntrinsicWidthPreferenceKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(EventCapsuleIntrinsicWidthPreferenceKey.self) { newWidth in
                if newWidth > 0 && abs(newWidth - measuredWidth) > 1.0 {
                    measuredWidth = newWidth
                    let calculated = min(maxW, max(minW, newWidth + 28.0))
                    IslandController.shared.reportAlertCapsuleWidth(calculated)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .frame(width: finalWidth, height: finalHeight)
            .background(
                ZStack {
                    LiquidGlassSurface(
                        shape: Capsule(),
                        isNotchAnchored: false,
                        ambientColor: tintColor,
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
            .contentShape(Capsule())
            .onTapGesture {
                if let action = action {
                    action()
                } else {
                    IslandController.shared.toggle()
                }
            }
            .contextMenu {
                Button("Dismiss") {
                    onDismiss()
                }
                Divider()
                Button("Open Dashboard") {
                    IslandController.shared.setExpanded()
                }
            }
            .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
            .onHover { h in
                isHovered = h
            }
    }
}

/// High-fidelity Dynamic Island adaptive presentation view.
/// Adapts its layout, 3D icons, metrics, and animations based on the specific AlertKind.
public struct IslandAlertView: View {
    public let alert: AlertPayload
    @ObservedObject private var motion = IslandMotion.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(alert: AlertPayload) {
        self.alert = alert
    }

    public var body: some View {
        LiquidAlertCapsuleContainer(
            tintColor: alert.iconColor,
            dwellDuration: alert.dwellDuration,
            onDismiss: { IslandController.shared.dismissAlert() },
            action: alert.action
        ) {
            HStack(spacing: 10) {
                contentForKind
            }
        }
        .islandContentIn(when: true)
    }

    // MARK: - Adaptive Content Routing

    @ViewBuilder
    private var contentForKind: some View {
        switch alert.kind {
        case .musicTrackChange(let title, let artist):
            musicTrackView(title: title, artist: artist)

        case .airPodsConnected(let name, let left, let right, let caseLevel):
            airPodsConnectedView(name: name, left: left, right: right, caseLevel: caseLevel)

        case .deviceConnected(let name, let icon):
            deviceConnectedView(name: name, icon: icon)

        case .deviceDisconnected(let name, let icon):
            deviceDisconnectedView(name: name, icon: icon)

        case .clipboardCopied(let snippet):
            clipboardCopiedView(snippet: snippet)

        case .dropperItemAdded(let count):
            dropperItemAddedView(count: count)

        case .batteryLow(_, let percentage, let isCritical):
            batteryLowView(percentage: percentage, isCritical: isCritical)

        case .chargingConnected(let level):
            chargingConnectedView(level: level)

        case .downloadProgress(let fileName, let progress, let speed):
            downloadProgressView(fileName: fileName, progress: progress, speed: speed)

        case .notification(let appName, let sender, let message):
            notificationCardView(appName: appName, sender: sender, message: message)

        case .systemHUD(let title, let icon, let value):
            systemHUDView(title: title, icon: icon, value: value)

        case .privacyIndicator(let type, let appName):
            privacyIndicatorView(type: type, appName: appName)

        case .custom:
            genericAlertView
        }
    }

    private func deviceDisconnectedView(name: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Premium3DIconView(name: icon, size: 20, interactive: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 130, alignment: .leading)
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 5, height: 5)
                    Text("Disconnected")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func clipboardCopiedView(snippet: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text("Copied to Clipboard")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(snippet)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 130, alignment: .leading)
            }
        }
    }

    private func dropperItemAddedView(count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.indigo)
            VStack(alignment: .leading, spacing: 1) {
                Text(count > 1 ? "\(count) Items Staged" : "Item Staged in Dropper")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Ready to drag or transfer")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 1. Music Track Change Announcement

    private func musicTrackView(title: String, artist: String) -> some View {
        HStack(spacing: 8) {
            // Album Art Thumbnail with Glass Refraction Border
            Image(nsImage: MusicManager.shared.albumArt)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 3, y: 1.5)

            // Title & Artist
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 130, alignment: .leading)

                if !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(alert.iconColor.opacity(0.9))
                        .lineLimit(1)
                        .frame(maxWidth: 130, alignment: .leading)
                }
            }

            // Dynamic Audio Equalizer Bars
            LiquidGlassEqualizerView(isPlaying: true, tint: alert.iconColor)
        }
    }

    // MARK: - 2. AirPods Connected Announcement

    private func airPodsConnectedView(name: String, left: Int?, right: Int?, caseLevel: Int?) -> some View {
        HStack(spacing: 8) {
            Premium3DIconView(.airPods, size: 20, interactive: false)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 110, alignment: .leading)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                    Text("Connected")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Battery Badges (L / R / Case)
            HStack(spacing: 4) {
                if let left = left {
                    batteryPill(label: "L", value: left)
                }
                if let right = right {
                    batteryPill(label: "R", value: right)
                }
                if let caseLevel = caseLevel {
                    batteryPill(label: "Case", value: caseLevel)
                }
            }
        }
    }

    private func batteryPill(label: String, value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.secondary)
            Text("\(value)%")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            OrganicFluidShape(
                blobs: [FluidLobe(center: CGPoint(x: 20, y: 10), radiusX: 18, radiusY: 9)],
                irregularity: 0.15
            )
            .fill(Color.white.opacity(0.12))
        )
    }

    // MARK: - 3. Device Connected (Storage & Peripherals)

    @ViewBuilder
    private func deviceConnectedView(name: String, icon: String) -> some View {
        if let device = alert.deviceIdentity {
            if device.connectionType == .storage || device.kind == .ssdDrive || device.kind == .usbStick {
                storageConnectedView(device: device, fallbackName: name, icon: icon)
            } else {
                peripheralInteractiveConnectedView(device: device, fallbackName: name, icon: icon)
            }
        } else {
            standardDeviceConnectedView(name: name, icon: icon)
        }
    }

    private func peripheralInteractiveConnectedView(device: DeviceIdentity, fallbackName: String, icon: String) -> some View {
        HStack(spacing: 8) {
            DeviceInteractive3DView(device: device, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.displayName.isEmpty ? fallbackName : device.displayName)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)

                HStack(spacing: 4) {
                    Circle()
                        .fill(device.kind == .androidPhone ? Color.green : (device.kind == .phone ? Color.blue : Color.cyan))
                        .frame(width: 5, height: 5)
                    Text(device.kind == .androidPhone ? "Android Connected" : (device.kind == .phone ? "iPhone Connected" : "Connected"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let bat = device.batteryPercentage {
                        Text("• \(bat)%")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.green)
                    }
                }
            }

            if device.kind == .androidPhone {
                Premium3DIconView(.androidPhone, size: 16, interactive: false)
            } else if device.kind == .phone {
                Premium3DIconView(.phone, size: 16, interactive: false)
            } else {
                Premium3DIconView(name: icon, size: 16, interactive: false)
            }
        }
    }

    private func storageConnectedView(device: DeviceIdentity, fallbackName: String, icon: String) -> some View {
        HStack(spacing: 8) {
            DeviceInteractive3DView(device: device, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.displayName.isEmpty ? fallbackName : device.displayName)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)

                HStack(spacing: 4) {
                    if let total = device.formattedCapacity {
                        Text(total)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.cyan.opacity(0.95))
                    } else {
                        Text(alert.subtitle ?? "")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    if let fs = device.filesystem {
                        Text("(\(fs))")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            if let usedBytes = device.usedSpaceBytes, let totalBytes = device.capacityBytes, totalBytes > 0 {
                let ratio = min(1.0, max(0.0, Double(usedBytes) / Double(totalBytes)))
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 36, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.cyan)
                            .frame(width: max(4, 36 * CGFloat(ratio)), height: 4)
                    }
            }
        }
    }

    private func standardDeviceConnectedView(name: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Premium3DIconView(name: icon, size: 20, interactive: false)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 5, height: 5)
                    Text("Connected")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Premium3DIconView(.bluetooth, size: 14, interactive: false)
        }
    }

    // MARK: - 4. Battery Low Alert

    private func batteryLowView(percentage: Int, isCritical: Bool) -> some View {
        HStack(spacing: 8) {
            Premium3DIconView(.battery, size: 20, customTint: isCritical ? .red : .orange, interactive: false)

            VStack(alignment: .leading, spacing: 1) {
                Text(isCritical ? "Critical Battery" : "Low Battery")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(isCritical ? .red : .orange)

                Text("\(percentage)% • Connect power")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text("\(percentage)%")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(isCritical ? .red : .orange)
        }
    }

    // MARK: - 5. Charging Connected

    private func chargingConnectedView(level: Double) -> some View {
        HStack(spacing: 8) {
            Premium3DIconView(.charging, size: 20, interactive: false)

            VStack(alignment: .leading, spacing: 1) {
                Text("Charging")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)

                Text("\(Int(level * 100))% Available")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            OrganicFluidLevelView(value: CGFloat(level), tintColor: .green, height: 6)
                .frame(width: 44, height: 16)
        }
    }

    // MARK: - 6. Download Progress

    private func downloadProgressView(fileName: String, progress: Double, speed: String) -> some View {
        HStack(spacing: 8) {
            Premium3DIconView(.downloads, size: 20, interactive: false)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(fileName)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: 80, alignment: .leading)
                    Text(speed)
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                OrganicFluidLevelView(value: CGFloat(progress), tintColor: .cyan, height: 5)
                    .frame(width: 60, height: 10)
            }

            Text("\(Int(progress * 100))%")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
        }
    }

    // MARK: - 7. Notification Card

    private func notificationCardView(appName: String, sender: String, message: String) -> some View {
        HStack(spacing: 8) {
            Premium3DIconView(.notifications, size: 20, interactive: false)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(sender)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: 80, alignment: .leading)

                    Text("• \(appName)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 60, alignment: .leading)
                }

                Text(message)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: 130, alignment: .leading)
            }
        }
    }

    // MARK: - 8. System HUD View

    private func systemHUDView(title: String, icon: String, value: Double) -> some View {
        HStack(spacing: 10) {
            Premium3DIconView(name: icon, size: 18, interactive: false)

            Text("\(Int(round(value * 100)))%")
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .monospacedDigit()
                .frame(minWidth: 32, alignment: .center)

            OrganicFluidLevelView(value: CGFloat(value), tintColor: alert.iconColor, height: 7)
                .frame(width: 76, height: 18)
        }
    }

    // MARK: - 9. Privacy Indicator View

    private func privacyIndicatorView(type: String, appName: String) -> some View {
        HStack(spacing: 8) {
            Premium3DIconView(name: alert.iconName ?? "mic.fill", size: 18, customTint: alert.iconColor, interactive: false)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(type) Active")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(alert.iconColor)

                Text(appName)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 110, alignment: .leading)
            }

            Circle()
                .fill(alert.iconColor)
                .frame(width: 7, height: 7)
                .shadow(color: alert.iconColor.opacity(0.8), radius: 3)
        }
    }

    // MARK: - 10. Generic Alert View

    private var genericAlertView: some View {
        HStack(spacing: 8) {
            Premium3DIconView(name: alert.iconName ?? "bell.fill", size: 18, interactive: false)

            VStack(alignment: .leading, spacing: 1) {
                Text(alert.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 130, alignment: .leading)

                if let subtitle = alert.subtitle {
                    Text(subtitle)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 130, alignment: .leading)
                }
            }
        }
    }
}

/// In-dashboard alert banner displayed inside the expanded notch when hovering or opened.
public struct ExpandedAlertBannerView: View {
    public let alert: AlertPayload
    public var onDismiss: () -> Void = {}

    public init(alert: AlertPayload, onDismiss: @escaping () -> Void = {}) {
        self.alert = alert
        self.onDismiss = onDismiss
    }

    public var body: some View {
        LiquidAlertCapsuleContainer(
            tintColor: alert.iconColor,
            dwellDuration: alert.dwellDuration,
            onDismiss: onDismiss,
            action: alert.action
        ) {
            bannerContent
        }
    }

    @ViewBuilder
    private var bannerContent: some View {
        HStack(spacing: 10) {
            // Visual Leading: 3D interactive model or glowing icon
            if let identity = alert.deviceIdentity {
                DeviceInteractive3DView(device: identity, size: 24)
                    .frame(width: 26, height: 26)
            } else if let icon = alert.iconName {
                ZStack {
                    Circle()
                        .fill(alert.iconColor.opacity(0.18))
                        .frame(width: 24, height: 24)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(alert.iconColor)
                        .shadow(color: alert.iconColor.opacity(0.6), radius: 3)
                }
            } else {
                Premium3DIconView(name: "bell.fill", size: 18, interactive: false)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(alert.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let subtitle = alert.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                }
            }

            if let progress = alert.progress {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(alert.iconColor)
                            .frame(width: max(4, g.size.width * CGFloat(progress)))
                    }
                }
                .frame(width: 50, height: 4)
            }

            Spacer()

            if let trailing = alert.trailingText {
                Text(trailing)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(alert.iconColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(alert.iconColor.opacity(0.15)))
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .buttonStyle(.plain)
        }
    }
}
