//
//  SuperIslandTopBarView.swift
//  LiquidDynamo
//
//  Created for LiquidDynamo
//
//  SuperIsland-style top bar supporting shoulder mode (hardware notch split) and inline mode.
//

import AppKit
import Defaults
import SwiftUI

public enum SuperIslandTopBarLayout {
    case inline
    case shoulder
}

public struct SuperIslandTopBarView: View {
    @EnvironmentObject private var vm: LiquidViewModel
    @ObservedObject private var coordinator = LiquidViewCoordinator.shared
    @ObservedObject private var island = IslandController.shared
    @ObservedObject private var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject private var alertCenter = AlertCenterService.shared
    @ObservedObject private var keepAwake = KeepAwakeService.shared
    @ObservedObject private var buddy = LiquidBuddyService.shared

    public let layout: SuperIslandTopBarLayout

    private let shoulderHorizontalPadding: CGFloat = 36
    private let shoulderTopPadding: CGFloat = 4
    private let shoulderTabSpacing: CGFloat = 8
    private let iconTabWidth: CGFloat = 34

    public init(layout: SuperIslandTopBarLayout = .shoulder) {
        self.layout = layout
    }

    public var body: some View {
        Group {
            if layout == .shoulder {
                shoulderBar
            } else {
                inlineBar
            }
        }
    }

    // MARK: - Inline Bar

    private var inlineBar: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: shoulderTabSpacing) {
                        tabButton(view: .home, icon: "square.grid.2x2.fill", title: "Home")
                        tabButton(view: .phoneBridge, icon: "iphone.gen3", title: "Phone")
                        tabButton(view: .calendar, icon: "calendar", title: "Calendar")
                        tabButton(view: .shelf, icon: "tray.full.fill", title: "Shelf")
                        tabButton(view: .teleprompter, icon: "text.bubble.fill", title: "Prompter")
                        tabButton(view: .agent, icon: "terminal.fill", title: "AgentLink")
                        tabButton(view: .stats, icon: "gauge.with.needle.fill", title: "Stats")
                        tabButton(view: .cleaner, icon: "sparkles", title: "Cleaner")
                        tabButton(view: .bluetooth, icon: "airpodspro", title: "Devices")
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingShoulderControls
                .padding(.bottom, 6)
        }
    }

    // MARK: - Shoulder Bar

    private var shoulderBar: some View {
        HStack(spacing: 0) {
            leadingShoulderTabs
                .frame(maxWidth: .infinity, alignment: .leading)

            // Center Notch Gap
            Color.clear
                .frame(width: max(160, vm.geometry.rawNotchWidth + 12), height: 32)

            trailingShoulderControls
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, shoulderHorizontalPadding)
        .padding(.top, shoulderTopPadding)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Leading Shoulder Tabs

    private var leadingShoulderTabs: some View {
        HStack(spacing: shoulderTabSpacing) {
            tabButton(view: .home, icon: "square.grid.2x2.fill", title: "Home")
                .frame(width: iconTabWidth)

            ScrollViewReader { _ in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: shoulderTabSpacing) {
                        tabButton(view: .phoneBridge, icon: "iphone.gen3", title: "Phone")
                        tabButton(view: .calendar, icon: "calendar", title: "Calendar")
                        tabButton(view: .shelf, icon: "tray.full.fill", title: "Shelf")
                        tabButton(view: .teleprompter, icon: "text.bubble.fill", title: "Prompter")
                        tabButton(view: .agent, icon: "terminal.fill", title: "AgentLink")
                        tabButton(view: .stats, icon: "gauge.with.needle.fill", title: "Stats")
                        tabButton(view: .cleaner, icon: "sparkles", title: "Cleaner")
                        tabButton(view: .bluetooth, icon: "airpodspro", title: "Devices")
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    // MARK: - Tab Button

    private func tabButton(view: NotchViews, icon: String, title: String) -> some View {
        let isSelected = coordinator.currentView == view
        return Button {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                coordinator.currentView = view
                island.cancelHoverCollapse()
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.68))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
                )
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(title)
    }

    // MARK: - Trailing Controls

    private var trailingShoulderControls: some View {
        HStack(spacing: 8) {
            // Animated Mascot Buddy sitting on shoulder
            LiquidBuddyView()
                .scaleEffect(0.85)

            // Keep Awake Clamshell Button
            Button {
                keepAwake.toggleKeepAwake()
            } label: {
                Image(systemName: keepAwake.isKeepAwakeActive ? "bolt.shield.fill" : "bolt.shield")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(keepAwake.isKeepAwakeActive ? Color.orange : Color.white.opacity(0.72))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(Color.white.opacity(keepAwake.isKeepAwakeActive ? 0.16 : 0.06))
                    )
                    .overlay(
                        Circle().stroke(keepAwake.isKeepAwakeActive ? Color.orange.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(keepAwake.isKeepAwakeActive ? "Sleep Blocked (Lid Closed Active)" : "Keep Awake (Sleep Normal)")

            // Lock Island Open Toggle
            Button {
                island.isPinnedOpen.toggle()
            } label: {
                Image(systemName: island.isPinnedOpen ? "lock.fill" : "lock.open")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(island.isPinnedOpen ? Color.accentColor : Color.white.opacity(0.72))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(Color.white.opacity(island.isPinnedOpen ? 0.16 : 0.06))
                    )
                    .overlay(
                        Circle().stroke(island.isPinnedOpen ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(island.isPinnedOpen ? "Lock Island Open (Pinned)" : "Auto-collapse on mouse exit")

            // Omni-Launcher Button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    OmniLauncherEngine.shared.toggleVisibility()
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OmniLauncherEngine.shared.isVisible ? Color.accentColor : Color.white.opacity(0.72))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(Color.white.opacity(OmniLauncherEngine.shared.isVisible ? 0.16 : 0.06))
                    )
                    .overlay(
                        Circle().stroke(OmniLauncherEngine.shared.isVisible ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Omni-Launcher (⌥Space): Search apps, calculate, ask AI")

            // Battery Capsule
            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                    coordinator.currentView = .stats
                }
            } label: {
                batteryCapsuleLabel
            }
            .buttonStyle(.plain)
            .help("Battery & Power Health")

            // Notification Button with Unread Badge
            Button {
                alertCenter.isShadeOpen.toggle()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(alertCenter.isShadeOpen ? Color.cyan : Color.white.opacity(0.72))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle().fill(Color.white.opacity(alertCenter.isShadeOpen ? 0.16 : 0.06))
                        )
                        .overlay(
                            Circle().stroke(alertCenter.isShadeOpen ? Color.cyan.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                        )

                    if alertCenter.alerts.count > 0 {
                        Text("\(alertCenter.alerts.count)")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.red.opacity(0.9)))
                            .offset(x: 4, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Notification Center Shade")

            // Settings Gear Button
            Button {
                SettingsWindowController.shared.showWindow()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    private var batteryCapsuleLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: batteryModel.isCharging ? "battery.100.bolt" : "battery.75")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(batteryModel.isCharging ? Color.green : Color.white.opacity(0.8))
            Text("\(Int(batteryModel.levelBattery))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}
