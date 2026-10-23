//
//  SettingsControlCenterSidebar.swift
//  LiquidDynamo
//
//  Futuristic macOS-native Liquid Glass sidebar with animated 3D icons,
//  specular lighting highlights, liquid glow effects, and soft expansion on hover.
//

import AppKit
import Defaults
import SwiftUI

public struct SettingsSidebarItem: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let icon3D: Premium3DIcon
    public let symbolBackup: String
    public let badgeText: String?
    public let accentColor: Color

    public init(
        id: String,
        title: String,
        icon3D: Premium3DIcon,
        symbolBackup: String,
        badgeText: String? = nil,
        accentColor: Color = .blue
    ) {
        self.id = id
        self.title = title
        self.icon3D = icon3D
        self.symbolBackup = symbolBackup
        self.badgeText = badgeText
        self.accentColor = accentColor
    }
}

public struct SettingsControlCenterSidebar: View {
    @Binding var selectedTab: String
    @Binding var searchText: String
    @State private var hoveredTab: String? = nil

    public static let items: [SettingsSidebarItem] = [
        SettingsSidebarItem(id: "Dashboard", title: "Dashboard", icon3D: .desktopMac, symbolBackup: "house.fill", accentColor: Color(red: 0.20, green: 0.60, blue: 1.0)),
        SettingsSidebarItem(id: "Appearance", title: "Appearance", icon3D: .favorites, symbolBackup: "paintpalette.fill", accentColor: Color(red: 0.95, green: 0.35, blue: 0.75)),
        SettingsSidebarItem(id: "Modules", title: "Modules", icon3D: .shelf, symbolBackup: "puzzlepiece.extension.fill", badgeText: "10", accentColor: Color(red: 0.40, green: 0.45, blue: 0.95)),
        SettingsSidebarItem(id: "StorageCleaner", title: "Storage Cleaner", icon3D: .downloads, symbolBackup: "trash.circle.fill", badgeText: "New", accentColor: Color(red: 0.15, green: 0.85, blue: 0.65)),
        SettingsSidebarItem(id: "Behavior", title: "Behavior", icon3D: .settings, symbolBackup: "gearshape.2.fill", accentColor: Color(red: 0.70, green: 0.72, blue: 0.78)),
        SettingsSidebarItem(id: "Permissions", title: "Permissions", icon3D: .library, symbolBackup: "checkmark.shield.fill", accentColor: Color(red: 0.10, green: 0.80, blue: 0.50)),
        SettingsSidebarItem(id: "Shortcuts", title: "Shortcuts", icon3D: .keyboard, symbolBackup: "command", accentColor: Color(red: 0.85, green: 0.65, blue: 0.20)),
        SettingsSidebarItem(id: "FileDroid", title: "FileDroid & OpenMTP", icon3D: .generic, symbolBackup: "externaldrive.fill.badge.wifi", badgeText: "Storage", accentColor: Color(red: 0.20, green: 0.85, blue: 0.55)),
        SettingsSidebarItem(id: "Plexo", title: "Plexo Turbo Downloader", icon3D: .downloads, symbolBackup: "bolt.horizontal.fill", badgeText: "Turbo", accentColor: Color(red: 0.10, green: 0.70, blue: 0.95)),
        SettingsSidebarItem(id: "Devices", title: "Connected Devices", icon3D: .airPods, symbolBackup: "laptopcomputer.and.iphone", accentColor: Color(red: 0.35, green: 0.75, blue: 0.95)),
        SettingsSidebarItem(id: "Clipboard", title: "Clipboard", icon3D: .playlist, symbolBackup: "doc.on.clipboard.fill", accentColor: Color(red: 0.90, green: 0.50, blue: 0.25)),
        SettingsSidebarItem(id: "Hydration", title: "Hydration", icon3D: .generic, symbolBackup: "drop.fill", badgeText: "Fresh", accentColor: Color(red: 0.20, green: 0.70, blue: 1.0)),
        SettingsSidebarItem(id: "Privacy", title: "Camera & Mic", icon3D: .camera, symbolBackup: "video.badge.waveform.fill", accentColor: Color(red: 0.10, green: 0.85, blue: 0.45)),
        SettingsSidebarItem(id: "About", title: "About", icon3D: .userProfile, symbolBackup: "info.circle.fill", accentColor: Color(red: 0.60, green: 0.45, blue: 0.90))
    ]

    var filteredItems: [SettingsSidebarItem] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self.items
        }
        let query = searchText.lowercased()
        return Self.items.filter { $0.title.lowercased().contains(query) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // App Branding Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.cyan.opacity(0.8),
                                    Color.blue.opacity(0.6),
                                    Color.purple.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                        )
                        .shadow(color: Color.cyan.opacity(0.4), radius: 8, x: 0, y: 2)

                    Premium3DIconView(.generic, size: 20, interactive: false)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("LiquidDynamo")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Control Center")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()
                .opacity(0.2)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            // Scrollable Navigation Items
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(filteredItems) { item in
                        sidebarRow(for: item)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 220)
        .background(
            ZStack {
                // Frosted Liquid Glass Sidebar Surface
                Color(nsColor: .windowBackgroundColor).opacity(0.45)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.clear,
                        Color.black.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
    }

    @ViewBuilder
    private func sidebarRow(for item: SettingsSidebarItem) -> some View {
        let isSelected = selectedTab == item.id
        let isHovered = hoveredTab == item.id

        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                selectedTab = item.id
            }
        } label: {
            HStack(spacing: 12) {
                // 3D Animated Icon Container
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            isSelected
                            ? item.accentColor.opacity(0.28)
                            : (isHovered ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
                        )
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    isSelected ? item.accentColor.opacity(0.6) : Color.white.opacity(0.12),
                                    lineWidth: 0.8
                                )
                        )
                        .shadow(
                            color: isSelected ? item.accentColor.opacity(0.35) : Color.clear,
                            radius: 6,
                            x: 0,
                            y: 2
                        )

                    Premium3DIconView(item.icon3D, size: 18, interactive: false)
                        .scaleEffect(isHovered ? 1.08 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
                }

                // Title Label
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()

                // Optional Pill Badge
                if let badge = item.badgeText {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? item.accentColor.opacity(0.3) : Color.white.opacity(0.12))
                        )
                        .foregroundStyle(isSelected ? item.accentColor : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        item.accentColor.opacity(0.18),
                                        item.accentColor.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.4),
                                                item.accentColor.opacity(0.3)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: item.accentColor.opacity(0.2), radius: 8, x: 0, y: 3)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in
            hoveredTab = h ? item.id : nil
        }
    }
}
