//
//  IslandAlertView.swift
//  LiquidDynamo
//
//  Created for Dynamic Island Status & Notification System
//

import SwiftUI
import Defaults

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
        HStack(spacing: 10) {
            contentForKind
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassCapsule(interactive: true)
        .avoidsNotch(id: "IslandAlert:\(alert.id)")
        .contentShape(Capsule())
        .onTapGesture {
            if let action = alert.action {
                action()
            } else {
                IslandController.shared.toggle()
            }
        }
        .contextMenu {
            Button("Dismiss") {
                IslandController.shared.dismissAlert()
            }
            Divider()
            Button("Open Dashboard") {
                IslandController.shared.setExpanded()
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

    // MARK: - 1. Music Track Change Announcement

    private func musicTrackView(title: String, artist: String) -> some View {
        HStack(spacing: 10) {
            // Album Art Thumbnail with Glass Refraction Border
            Image(nsImage: MusicManager.shared.albumArt)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 4, y: 2)

            // Title & Artist
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(artist)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(alert.iconColor.opacity(0.9))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Dynamic Audio Equalizer Bars
            LiquidGlassEqualizerView(isPlaying: true, tint: alert.iconColor)
                .padding(.trailing, 4)
        }
    }

    // MARK: - 2. AirPods Connected Announcement

    private func airPodsConnectedView(name: String, left: Int?, right: Int?, caseLevel: Int?) -> some View {
        HStack(spacing: 10) {
            Premium3DIconView(.airPods, size: 24, interactive: false)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Connected")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            // Battery Badges (L / R / Case)
            HStack(spacing: 6) {
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
        .liquidGlassCapsule(interactive: false)
    }

    // MARK: - 3. Generic Bluetooth Device Connected

    private func deviceConnectedView(name: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Premium3DIconView(name: icon, size: 22, interactive: false)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                    Text("Connected")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Premium3DIconView(.bluetooth, size: 16, interactive: false)
        }
    }

    // MARK: - 4. Battery Low Alert

    private func batteryLowView(percentage: Int, isCritical: Bool) -> some View {
        HStack(spacing: 10) {
            Premium3DIconView(.battery, size: 22, customTint: isCritical ? .red : .orange, interactive: false)

            VStack(alignment: .leading, spacing: 1) {
                Text(isCritical ? "Critical Battery Alert" : "Low Battery Warning")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isCritical ? .red : .orange)

                Text("\(percentage)% Remaining • Connect power source")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(percentage)%")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(isCritical ? .red : .orange)
        }
    }

    // MARK: - 5. Charging Connected

    private func chargingConnectedView(level: Double) -> some View {
        HStack(spacing: 10) {
            Premium3DIconView(.charging, size: 22, interactive: false)

            VStack(alignment: .leading, spacing: 1) {
                Text("Charging Started")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)

                Text("\(Int(level * 100))% Available")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Mini battery level meter
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 50, height: 8)
                Capsule()
                    .fill(Color.green)
                    .frame(width: max(4, 50 * CGFloat(level)), height: 8)
            }
        }
    }

    // MARK: - 6. Download Progress

    private func downloadProgressView(fileName: String, progress: Double, speed: String) -> some View {
        HStack(spacing: 10) {
            Premium3DIconView(.downloads, size: 22, interactive: false)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(fileName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Text(speed)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Liquid Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 6)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, geo.size.width * CGFloat(progress)), height: 6)
                    }
                }
                .frame(height: 6)
            }

            Text("\(Int(progress * 100))%")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
                .frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: - 7. Notification Card

    private func notificationCardView(appName: String, sender: String, message: String) -> some View {
        HStack(spacing: 10) {
            Premium3DIconView(.notifications, size: 22, interactive: false)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(sender)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("• \(appName)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Text("now")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                Text(message)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - 8. System HUD View

    private func systemHUDView(title: String, icon: String, value: Double) -> some View {
        HStack(spacing: 10) {
            Premium3DIconView(name: icon, size: 20, interactive: false)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 6)

                        Capsule()
                            .fill(alert.iconColor)
                            .frame(width: max(4, geo.size.width * CGFloat(value)), height: 6)
                    }
                }
                .frame(height: 6)
            }

            Text("\(Int(value * 100))%")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 32, alignment: .trailing)
        }
    }

    // MARK: - 9. Privacy Indicator View

    private func privacyIndicatorView(type: String, appName: String) -> some View {
        HStack(spacing: 10) {
            Premium3DIconView(name: alert.iconName ?? "mic.fill", size: 20, customTint: alert.iconColor, interactive: false)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(type) Active")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(alert.iconColor)

                Text("Being used by \(appName)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Circle()
                .fill(alert.iconColor)
                .frame(width: 8, height: 8)
                .shadow(color: alert.iconColor.opacity(0.8), radius: 3)
        }
    }

    // MARK: - 10. Generic Alert View

    private var genericAlertView: some View {
        HStack(spacing: 10) {
            Premium3DIconView(name: alert.iconName ?? "bell.fill", size: 20, interactive: false)

            VStack(alignment: .leading, spacing: 1) {
                Text(alert.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let subtitle = alert.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
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
        HStack(spacing: 10) {
            Premium3DIconView(name: alert.iconName ?? "bell.fill", size: 20, interactive: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let subtitle = alert.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassCapsule(interactive: false)
    }
}
