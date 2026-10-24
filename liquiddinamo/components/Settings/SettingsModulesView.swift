//
//  SettingsModulesView.swift
//  LiquidDynamo
//
//  Control Center Modules: 10 large Liquid Glass tiles with status,
//  live toggle, quick actions, and expanding configuration drawers.
//

import AppKit
import Defaults
import SwiftUI

public struct SettingsModulesView: View {
    @Default(.showMedia) private var showMedia
    @Default(.showNotchOSD) private var showNotchOSD
    @Default(.liquidShelf) private var liquidShelf
    @Default(.showDashboardClipboard) private var showDashboardClipboard
    @Default(.showDevicesTab) private var showDevicesTab
    @Default(.showDashboardSystemInfo) private var showWeatherOrSystem
    @Default(.enableStorageCleanerModule) private var enableStorageCleaner
    @Default(.hydrationEnabled) private var hydrationEnabled
    @Default(.cameraNotchGlowEnabled) private var cameraNotchGlow
    @Default(.micNotchGlowEnabled) private var micNotchGlow
    @State private var breakReminderPlaceholder: Bool = false

    @State private var expandedModuleID: String? = nil

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Interactive Modules")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Configure features projected dynamically around your MacBook notch")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // 2-Column Grid of Large Glass Tiles
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    // 1. Media Player
                    moduleTile(
                        id: "media",
                        title: "Media Player",
                        subtitle: "Now Playing visualizer, album art & controls",
                        icon: .music,
                        accent: Color(red: 1.0, green: 0.28, blue: 0.45),
                        isOn: $showMedia,
                        configTarget: "Media"
                    )

                    // 2. Volume & Brightness HUD
                    moduleTile(
                        id: "hud",
                        title: "Volume & Brightness HUD",
                        subtitle: "Over-the-notch system level sliders",
                        icon: .volume,
                        accent: Color(red: 0.35, green: 0.75, blue: 0.98),
                        isOn: $showNotchOSD,
                        configTarget: "HUD"
                    )

                    // 3. Dropper Shelf
                    moduleTile(
                        id: "shelf",
                        title: "Dropper Shelf",
                        subtitle: "Temporary file stash & drag-and-drop tray",
                        icon: .shelf,
                        accent: Color(red: 0.40, green: 0.50, blue: 0.95),
                        isOn: $liquidShelf,
                        configTarget: "Shelf"
                    )

                    // 4. Clipboard Manager
                    moduleTile(
                        id: "clipboard",
                        title: "Clipboard Manager",
                        subtitle: "Searchable history with privacy shielding",
                        icon: .playlist,
                        accent: Color(red: 0.95, green: 0.60, blue: 0.20),
                        isOn: $showDashboardClipboard,
                        configTarget: "Clipboard"
                    )

                    // 5. Connected Devices
                    moduleTile(
                        id: "devices",
                        title: "Connected Devices",
                        subtitle: "AirPods, external monitors, mice & storage",
                        icon: .airPods,
                        accent: Color(red: 0.20, green: 0.85, blue: 0.65),
                        isOn: $showDevicesTab,
                        configTarget: "Devices"
                    )

                    // 6. Weather Engine
                    moduleTile(
                        id: "weather",
                        title: "Weather Engine",
                        subtitle: "Atmospheric conditions & rain radar updates",
                        icon: .generic,
                        accent: Color(red: 0.30, green: 0.70, blue: 1.0),
                        isOn: $showWeatherOrSystem,
                        configTarget: "Dashboard"
                    )

                    // 7. Storage Cleaner
                    moduleTile(
                        id: "cleaner",
                        title: "Storage Cleaner",
                        subtitle: "Automatic startup scan & safe junk removal",
                        icon: .downloads,
                        accent: Color(red: 0.25, green: 0.85, blue: 0.55),
                        isOn: $enableStorageCleaner,
                        configTarget: "StorageCleaner"
                    )

                    // 8. Water Reminder (Coming Soon)
                    moduleTile(
                        id: "water_reminder",
                        title: "Water Reminder",
                        subtitle: "Smart hydration cadence & fluid droplet notch alerts",
                        icon: .generic,
                        accent: Color(red: 0.15, green: 0.75, blue: 0.95),
                        isOn: $hydrationEnabled,
                        configTarget: "Hydration",
                        badge: "COMING SOON"
                    )

                    // 9. Break Reminder (Coming Soon)
                    moduleTile(
                        id: "break_reminder",
                        title: "Break Reminder",
                        subtitle: "20-20-20 screen rest, posture & stretch intervals",
                        icon: .stats,
                        accent: Color(red: 1.0, green: 0.55, blue: 0.15),
                        isOn: $breakReminderPlaceholder,
                        configTarget: "Hydration",
                        badge: "COMING SOON"
                    )

                    // 10. Camera Activity
                    moduleTile(
                        id: "camera",
                        title: "Camera Activity",
                        subtitle: "Subtle emerald glow when webcam is active",
                        icon: .camera,
                        accent: Color(red: 0.10, green: 0.85, blue: 0.40),
                        isOn: $cameraNotchGlow,
                        configTarget: "Privacy"
                    )

                    // 11. Microphone Activity
                    moduleTile(
                        id: "mic",
                        title: "Microphone Activity",
                        subtitle: "Ambient amber glow when audio is captured",
                        icon: .mic,
                        accent: Color(red: 1.0, green: 0.60, blue: 0.15),
                        isOn: $micNotchGlow,
                        configTarget: "Privacy"
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private func moduleTile(
        id: String,
        title: String,
        subtitle: String,
        icon: Premium3DIcon,
        accent: Color,
        isOn: Binding<Bool>,
        configTarget: String,
        badge: String? = nil
    ) -> some View {
        let isExpanded = expandedModuleID == id
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                // 3D Icon Box
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.22))
                        .frame(width: 42, height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(accent.opacity(0.45), lineWidth: 0.8)
                        )
                        .shadow(color: accent.opacity(0.3), radius: 6, x: 0, y: 2)

                    Premium3DIconView(icon, size: 24, interactive: false)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accent.opacity(0.18))
                                .foregroundStyle(accent)
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(accent.opacity(0.40), lineWidth: 0.6))
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Native Switch Toggle
                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Divider().opacity(0.2)

            // Status Badge & Quick Action Row
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(badge != nil ? accent : (isOn.wrappedValue ? Color.green : Color.gray))
                        .frame(width: 6, height: 6)

                    Text(badge != nil ? "Coming Soon" : (isOn.wrappedValue ? "Active" : "Disabled"))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(badge != nil ? accent : (isOn.wrappedValue ? .primary : .secondary))
                }

                Spacer()

                Button {
                    SettingsNavigationState.shared.selectedTab = configTarget
                } label: {
                    HStack(spacing: 4) {
                        Text("Configure")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(accent.opacity(0.18))
                            .overlay(Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 0.8))
                    )
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.25), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
        )
    }
}
