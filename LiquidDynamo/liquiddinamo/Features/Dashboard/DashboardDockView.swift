//
//  DashboardDockView.swift
//  boringNotch
//
//  Created for Boring Notch
//

import Defaults
import SwiftUI

struct DockTabItem: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

struct DashboardDockView: View {
    @ObservedObject var coordinator = LiquidViewCoordinator.shared
    @Default(.showStatsTab) var showStatsTab
    @Default(.showBluetoothTab) var showBluetoothTab
    @Default(.showDisplaySoundTab) var showDisplaySoundTab
    @Default(.showCalendarTab) var showCalendarTab
    @Default(.showDevicesTab) var showDevicesTab
    @Default(.showNetworkTab) var showNetworkTab
    @Default(.liquidShelf) var liquidShelf

    @Namespace private var dockAnimation

    private var tabs: [DockTabItem] {
        var list: [DockTabItem] = [
            DockTabItem(label: "Home", icon: "house.fill", view: .home),
        ]
        if showStatsTab {
            list.append(DockTabItem(label: "Stats", icon: "cpu", view: .stats))
        }
        if showBluetoothTab {
            list.append(DockTabItem(label: "Bluetooth", icon: "antenna.radiowaves.left.and.right", view: .bluetooth))
        }
        if showDisplaySoundTab {
            list.append(DockTabItem(label: "Display & Sound", icon: "speaker.wave.2.fill", view: .displaySound))
        }
        if showDevicesTab {
            list.append(DockTabItem(label: "Devices", icon: "laptopcomputer.and.iphone", view: .devices))
        }
        if showNetworkTab {
            list.append(DockTabItem(label: "Network", icon: "network", view: .network))
        }
        if liquidShelf {
            list.append(DockTabItem(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        if showCalendarTab {
            list.append(DockTabItem(label: "Calendar", icon: "calendar", view: .calendar))
        }
        return list
    }

    var body: some View {
        HStack(spacing: 2) {
            // Tab buttons
            ForEach(tabs) { tab in
                let isSelected = coordinator.currentView == tab.view
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.32),
                                        Color.white.opacity(0.12)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8)
                            )
                            .shadow(color: Color.white.opacity(0.25), radius: 4)
                            .matchedGeometryEffect(id: "activeDockTab", in: dockAnimation)
                    }

                    Icon3DView(
                        icon: tab.icon,
                        isSelected: isSelected,
                        size: 11
                    ) {
                        withAnimation(.smooth(duration: 0.28)) {
                            coordinator.currentView = tab.view
                        }
                    }
                }
                .frame(width: 26, height: 24)
                .help(tab.label)
            }

            // Divider between tabs and settings
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.25),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1, height: 14)
                .padding(.horizontal, 2)

            // Settings button
            Icon3DView(
                icon: "gearshape.fill",
                isSelected: false,
                size: 11
            ) {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .frame(width: 26, height: 24)
            .help("Settings")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .liquidGlassCapsule(interactive: false)
    }
}
