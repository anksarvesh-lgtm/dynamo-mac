//
//  SettingsControlCenterSidebar.swift
//  LiquidDynamo
//
//  Clean native macOS frosted-glass sidebar with authentic application branding,
//  SF Symbols, restrained blue selection background, and responsive search.
//

import AppKit
import Defaults
import SwiftUI

public struct SettingsSidebarItem: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let symbolBackup: String
    public let badgeText: String?
    public let accentColor: Color

    public init(
        id: String,
        title: String,
        symbolBackup: String,
        badgeText: String? = nil,
        accentColor: Color = .blue
    ) {
        self.id = id
        self.title = title
        self.symbolBackup = symbolBackup
        self.badgeText = badgeText
        self.accentColor = accentColor
    }
}

public struct SettingsControlCenterSidebar: View {
    @ObservedObject private var updateChecker = GitHubUpdateChecker.shared
    @Binding var selectedTab: String
    @Binding var searchText: String
    @State private var hoveredTab: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    public static let items: [SettingsSidebarItem] = [
        SettingsSidebarItem(id: "NotchWings", title: "Notch & Wings", symbolBackup: "sparkles.rectangle.stack.fill"),
        SettingsSidebarItem(id: "Appearance", title: "Appearance", symbolBackup: "paintpalette.fill"),
        SettingsSidebarItem(id: "Metrics", title: "Metrics", symbolBackup: "chart.bar.fill"),
        SettingsSidebarItem(id: "Media", title: "Media & Controls", symbolBackup: "play.fill"),
        SettingsSidebarItem(id: "Notifications", title: "Notifications", symbolBackup: "bell.fill"),
        SettingsSidebarItem(id: "Devices", title: "Battery & Devices", symbolBackup: "battery.100"),
        SettingsSidebarItem(id: "Clipboard", title: "Clipboard", symbolBackup: "doc.on.clipboard"),
        SettingsSidebarItem(id: "Hydration", title: "Focus & Timers", symbolBackup: "clock"),
        SettingsSidebarItem(id: "Permissions", title: "Permissions", symbolBackup: "lock.fill"),
        SettingsSidebarItem(id: "General", title: "General", symbolBackup: "gearshape.fill"),
        SettingsSidebarItem(id: "About", title: "About", symbolBackup: "info.circle"),
        SettingsSidebarItem(id: "Watcher", title: "Watcher (Agents)", symbolBackup: "sparkles", badgeText: "AI"),
        SettingsSidebarItem(id: "StorageCleaner", title: "Storage Cleaner", symbolBackup: "trash.circle.fill", badgeText: "Clean"),
        SettingsSidebarItem(id: "FileDroid", title: "FileDroid (ADB)", symbolBackup: "externaldrive.fill.badge.wifi"),
        SettingsSidebarItem(id: "Plexo", title: "Plexo Turbo", symbolBackup: "bolt.horizontal.fill"),
        SettingsSidebarItem(id: "Shortcuts", title: "Shortcuts", symbolBackup: "command")
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
            // App Branding Header matching reference
            VStack(alignment: .center, spacing: 6) {
                // 3D Liquid Blue Droplet Icon
                ReferenceAppIcon(size: 36)
                    .padding(.top, 14)

                VStack(spacing: 2) {
                    Text("LiquidDynamo")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Notch, Wings & More")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(red: 0.55, green: 0.60, blue: 0.68))

                    if updateChecker.isUpdateAvailable {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(red: 0.20, green: 0.55, blue: 1.0))
                                .frame(width: 5, height: 5)
                            Text("v\(updateChecker.latestVersionString) Available")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Color(red: 0.40, green: 0.75, blue: 1.0))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.blue.opacity(0.18))
                        .clipShape(Capsule())
                        .padding(.top, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)

            // Scrollable Navigation Destination Rows
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(filteredItems) { item in
                        sidebarRow(for: item)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
        }
        .frame(width: NativeSettingsTheme.sidebarWidth)
        .background(
            Color(red: 0.08, green: 0.10, blue: 0.13).opacity(0.92)
        )
    }

    @ViewBuilder
    private func sidebarRow(for item: SettingsSidebarItem) -> some View {
        let isSelected = selectedTab == item.id || (item.id == "General" && selectedTab == "Dashboard") || (item.id == "NotchWings" && (selectedTab == "Look" || selectedTab == "NotchWings")) || (item.id == "Media" && selectedTab == "Modules") || (item.id == "Notifications" && selectedTab == "Behavior")
        let isHovered = hoveredTab == item.id

        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedTab = item.id
            }
        } label: {
            HStack(spacing: 10) {
                // SF Symbol
                Image(systemName: item.symbolBackup)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.68))
                    .frame(width: 20, alignment: .center)

                // Title Label
                Text(item.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.75))

                Spacer()

                // Optional Badge
                if item.id == "About" && updateChecker.isUpdateAvailable {
                    Text("UPDATE")
                        .font(.system(size: 8.5, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.blue)
                        )
                        .foregroundStyle(Color.white)
                } else if let badge = item.badgeText {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.20) : Color.white.opacity(0.08))
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.65))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    if isSelected {
                        // Solid Blue Pill matching reference image
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(NativeSettingsTheme.accentBlue)
                            .shadow(color: NativeSettingsTheme.accentBlue.opacity(0.35), radius: 6, x: 0, y: 2)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in
            hoveredTab = h ? item.id : nil
        }
    }
}
