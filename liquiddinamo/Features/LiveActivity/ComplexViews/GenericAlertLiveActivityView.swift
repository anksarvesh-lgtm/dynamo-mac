//
//  GenericAlertLiveActivityView.swift
//  LiquidDynamo
//
//  Step 4: Unified Liquid Island Engine generic alert view.
//  Replaces rigid capsule LiquidDropAlertView with continuous auto-sizing liquid container.
//

import AppKit
import Foundation
import SwiftUI

public struct GenericAlertLiveActivityView: View {
    public let title: String
    public let subtitle: String?
    public let iconName: String?
    public let tintColor: Color
    public let progressValue: Double?
    public let activityId: String
    public var onDismiss: () -> Void = {}

    public init(activity: LiveActivity, onDismiss: @escaping () -> Void = {}) {
        self.title = activity.payload.title
        self.subtitle = activity.payload.subtitle
        self.iconName = activity.payload.iconName ?? "bell.fill"
        self.tintColor = activity.payload.iconColor ?? activity.tint
        self.progressValue = activity.payload.value
        self.activityId = activity.id
        self.onDismiss = onDismiss
    }

    public init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        tint: Color = .accentColor,
        value: Double? = nil,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.title = title
        self.subtitle = subtitle
        self.iconName = icon ?? "bell.fill"
        self.tintColor = tint
        self.progressValue = value
        self.activityId = "customAlert"
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Icon Badge
            let icon = iconName ?? "bell.fill"
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tintColor)
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(tintColor.opacity(0.18))
                )

            // Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            // Optional percentage / battery or progress value
            if let val = progressValue {
                Text("\(Int(val * 100))%")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(tintColor)
            }

            // Dismiss Button
            Button(action: {
                onDismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .frame(height: 42)
        .avoidsNotch(id: "GenericAlert:\(activityId)")
    }
}

// MARK: - Display Connected Interactive Live Activity View

public struct DisplayConnectedLiveActivityView: View {
    public let alert: AlertPayload
    public var onDismiss: () -> Void
    @ObservedObject var brightnessService = MultiDisplayBrightnessService.shared

    public init(alert: AlertPayload, onDismiss: @escaping () -> Void = {}) {
        self.alert = alert
        self.onDismiss = onDismiss
    }

    private var targetDisplay: ManagedDisplay? {
        if let dev = alert.deviceIdentity {
            if let d = brightnessService.displays.first(where: { "display_\($0.id)" == dev.stableKey }) {
                return d
            }
            if let d = brightnessService.displays.first(where: { $0.name == dev.displayName }) {
                return d
            }
            if dev.displayName.contains("Built-in") || dev.model.contains("Built-in") {
                return brightnessService.displays.first(where: { $0.isBuiltIn })
            }
        }
        return brightnessService.displays.first(where: { !$0.isBuiltIn }) ?? brightnessService.displays.first
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "display")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.blue)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.blue.opacity(0.20)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let subtitle = alert.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Button {
                    if let dev = alert.deviceIdentity {
                        IslandController.shared.activeOrganicItem = .device(dev.stableKey)
                    }
                    IslandController.shared.setExpanded(view: .home, pin: true)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Open Full Display Controls")
            }

            if let disp = targetDisplay {
                HStack(spacing: 8) {
                    Image(systemName: "sun.min.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)

                    Slider(value: Binding(
                        get: { Double(disp.brightness) },
                        set: { brightnessService.setBrightness(Float($0), for: disp) }
                    ), in: 0...1)
                    .accentColor(disp.isBuiltIn ? .blue : .cyan)

                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text("\(Int(disp.brightness * 100))%")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.horizontal, 4)

                // Quick presets
                HStack(spacing: 6) {
                    ForEach([0.25, 0.50, 0.75, 1.0], id: \.self) { preset in
                        Button {
                            brightnessService.setBrightness(Float(preset), for: disp)
                        } label: {
                            Text("\(Int(preset * 100))%")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

