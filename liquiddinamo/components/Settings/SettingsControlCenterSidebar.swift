//
//  SettingsControlCenterSidebar.swift
//  LiquidDynamo
//
//  Clean native macOS frosted-glass sidebar with two distinct categories:
//  1. MACLINK PHONE COMPANION (Primary app UI)
//  2. DYNAMIC ISLAND & NOTCH SETTINGS
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

    // Category 1: MacLink Phone Companion
    public static let macLinkItems: [SettingsSidebarItem] = [
        SettingsSidebarItem(id: "overview", title: "Overview & Mirror", symbolBackup: "iphone.gen3"),
        SettingsSidebarItem(id: "messages", title: "Messages", symbolBackup: "message.fill"),
        SettingsSidebarItem(id: "calls", title: "Calls & Dialer", symbolBackup: "phone.fill"),
        SettingsSidebarItem(id: "deck", title: "Command Deck", symbolBackup: "slider.horizontal.3"),
        SettingsSidebarItem(id: "files", title: "File Manager", symbolBackup: "folder.fill"),
        SettingsSidebarItem(id: "photos", title: "Photos & Media", symbolBackup: "photo.on.rectangle.angled"),
        SettingsSidebarItem(id: "apps", title: "Installed Apps", symbolBackup: "square.grid.3x3.fill"),
        SettingsSidebarItem(id: "timeline", title: "Timeline & Sync", symbolBackup: "clock.arrow.circlepath"),
        SettingsSidebarItem(id: "pairing", title: "Pairing & Devices", symbolBackup: "qrcode")
    ]

    // Category 2: Dynamic Island & Notch Settings
    public static let islandItems: [SettingsSidebarItem] = [
        SettingsSidebarItem(id: "islandLook", title: "Island Look & Wings", symbolBackup: "macbook"),
        SettingsSidebarItem(id: "islandLiquid", title: "Liquid Glass & Motion", symbolBackup: "drop.fill"),
        SettingsSidebarItem(id: "islandModules", title: "Modules & Overlays", symbolBackup: "app.badge"),
        SettingsSidebarItem(id: "islandExtensions", title: "Extensions & System", symbolBackup: "puzzlepiece.fill")
    ]

    public var body: some View {
        VStack(spacing: 0) {
            // App Branding Header
            VStack(alignment: .center, spacing: 6) {
                ReferenceAppIcon(size: 36)
                    .padding(.top, 14)

                VStack(spacing: 2) {
                    Text("MacLink & LiquidDynamo")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Phone Companion & Dynamic Island")
                        .font(.system(size: 10.5, weight: .regular))
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
            .padding(.bottom, 12)

            // Scrollable Navigation Destination Rows
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // Category 1: MacLink
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MACLINK COMPANION")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)

                        ForEach(Self.macLinkItems) { item in
                            sidebarRow(for: item)
                        }
                    }

                    Divider().opacity(0.15)
                        .padding(.horizontal, 10)

                    // Category 2: Dynamic Island & Notch
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DYNAMIC ISLAND & NOTCH")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)

                        ForEach(Self.islandItems) { item in
                            sidebarRow(for: item)
                        }
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

    private func isTabSelected(_ itemId: String) -> Bool {
        if selectedTab == itemId { return true }
        if itemId == "islandLook" && (selectedTab == "Look" || selectedTab == "NotchWings") { return true }
        if itemId == "islandLiquid" && selectedTab == "Appearance" { return true }
        if itemId == "islandModules" && (selectedTab == "Media" || selectedTab == "Modules") { return true }
        if itemId == "islandExtensions" && (selectedTab == "About" || selectedTab == "General") { return true }
        return false
    }

    @ViewBuilder
    private func sidebarRow(for item: SettingsSidebarItem) -> some View {
        let isSelected = isTabSelected(item.id)
        let isHovered = hoveredTab == item.id

        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedTab = item.id
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbolBackup)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.68))
                    .frame(width: 20, alignment: .center)

                Text(item.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.75))

                Spacer()

                if let badge = item.badgeText {
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
