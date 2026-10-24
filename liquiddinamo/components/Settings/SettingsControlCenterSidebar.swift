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
    @Binding var selectedTab: String
    @Binding var searchText: String
    @State private var hoveredTab: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    public static let items: [SettingsSidebarItem] = [
        SettingsSidebarItem(id: "General", title: "General", symbolBackup: "gearshape.fill"),
        SettingsSidebarItem(id: "NotchWings", title: "Notch & Wings", symbolBackup: "sparkles.rectangle.stack.fill"),
        SettingsSidebarItem(id: "Appearance", title: "Appearance", symbolBackup: "paintpalette.fill"),
        SettingsSidebarItem(id: "Media", title: "Media & Controls", symbolBackup: "play.rectangle.fill"),
        SettingsSidebarItem(id: "Metrics", title: "Metrics", symbolBackup: "gauge.with.needle.fill"),
        SettingsSidebarItem(id: "Devices", title: "Battery & Devices", symbolBackup: "laptopcomputer.and.iphone"),
        SettingsSidebarItem(id: "Clipboard", title: "Clipboard", symbolBackup: "doc.on.clipboard.fill"),
        SettingsSidebarItem(id: "StorageCleaner", title: "Storage Cleaner", symbolBackup: "trash.circle.fill", badgeText: "Clean"),
        SettingsSidebarItem(id: "FileDroid", title: "FileDroid (ADB)", symbolBackup: "externaldrive.fill.badge.wifi"),
        SettingsSidebarItem(id: "Plexo", title: "Plexo Turbo", symbolBackup: "bolt.horizontal.fill"),
        SettingsSidebarItem(id: "Watcher", title: "Watcher (Agents)", symbolBackup: "sparkles", badgeText: "New"),
        SettingsSidebarItem(id: "Hydration", title: "Hydration", symbolBackup: "drop.fill"),
        SettingsSidebarItem(id: "Permissions", title: "Permissions", symbolBackup: "checkmark.shield.fill"),
        SettingsSidebarItem(id: "Shortcuts", title: "Shortcuts", symbolBackup: "command"),
        SettingsSidebarItem(id: "About", title: "About", symbolBackup: "info.circle.fill")
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
                // Genuine LiquidDynamo App Icon
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 1) {
                    Text("LiquidDynamo")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("Control Center")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()
                .opacity(colorScheme == .dark ? 0.2 : 0.12)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

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
            ZStack {
                // Frosted Liquid Glass Sidebar Surface
                if colorScheme == .dark {
                    Color(nsColor: .windowBackgroundColor).opacity(0.35)
                } else {
                    Color.white.opacity(0.40)
                }
            }
        )
    }

    @ViewBuilder
    private func sidebarRow(for item: SettingsSidebarItem) -> some View {
        let isSelected = selectedTab == item.id || (item.id == "General" && selectedTab == "Dashboard") || (item.id == "NotchWings" && selectedTab == "Look") || (item.id == "Media" && selectedTab == "Modules")
        let isHovered = hoveredTab == item.id

        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedTab = item.id
            }
        } label: {
            HStack(spacing: 10) {
                // SF Symbol with balanced frame
                Image(systemName: item.symbolBackup)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.effectiveAccent : Color.secondary)
                    .frame(width: 22, alignment: .center)

                // Title Label
                Text(item.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                Spacer()

                // Optional Badge
                if let badge = item.badgeText {
                    Text(badge)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.effectiveAccent.opacity(0.20) : Color.primary.opacity(0.06))
                        )
                        .foregroundStyle(isSelected ? Color.effectiveAccent : Color.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.effectiveAccent.opacity(colorScheme == .dark ? 0.22 : 0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.effectiveAccent.opacity(colorScheme == .dark ? 0.35 : 0.20), lineWidth: 0.8)
                            )
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
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
