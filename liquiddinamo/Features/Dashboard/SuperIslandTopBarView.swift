//
//  SuperIslandTopBarView.swift
//  LiquidDynamo
//
//  Created for LiquidDynamo
//
//  Expanded Dynamic Island Liquid Glass Toolbar with:
//  - Section A: Permanent Home icon (opens primary dashboard)
//  - Section B: Configurable feature shortcut icons (23 verified tools)
//  - Section C: Smart More overflow popover & Edit customization sheet
//  - Intelligent Notch-Safe arrangement allocating safe left/right regions with 0 physical notch overlap.
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
    @ObservedObject private var keepAwake = KeepAwakeManager.shared
    @ObservedObject private var buddy = LiquidBuddyService.shared
    @ObservedObject private var music = MusicManager.shared
    @Default(.toolbarConfig) private var toolbarConfig

    public let layout: SuperIslandTopBarLayout

    @State private var isShowingMorePopover: Bool = false
    @State private var isShowingEditSheet: Bool = false
    @State private var hoveredFeature: ToolbarFeatureID? = nil

    private let shoulderHorizontalPadding: CGFloat = 20
    private let shoulderTopPadding: CGFloat = 4
    private let tabSpacing: CGFloat = 6
    private let iconTabWidth: CGFloat = 28

    public init(layout: SuperIslandTopBarLayout = .shoulder) {
        self.layout = layout
    }

    private var layoutResult: ToolbarLayoutResult {
        let screenW = NSScreen.main?.frame.width ?? 1440
        let targetW = min(screenW - 80, 680)
        return NotchToolbarLayoutEngine.shared.computeLayout(
            totalWidth: targetW,
            geometry: vm.geometry,
            config: toolbarConfig
        )
    }

    public var body: some View {
        Group {
            if layout == .shoulder && vm.geometry.hasPhysicalNotch {
                notchShoulderBar
            } else {
                symmetricalBar
            }
        }
        .sheet(isPresented: $isShowingEditSheet) {
            ToolbarEditSheetView()
                .environmentObject(vm)
        }
    }

    // MARK: - 1. Notched Display Shoulder Bar (Zero Overlap with Camera Notch)

    private var notchShoulderBar: some View {
        let res = layoutResult

        return HStack(spacing: 0) {
            // LEFT SAFE REGION: Home -> Leading Feature Shortcuts
            HStack(spacing: tabSpacing) {
                ForEach(res.leftItems) { feature in
                    toolbarButton(feature)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // CENTRAL REGION: Physical camera notch exclusion zone (0 controls, guaranteed safe)
            Color.clear
                .frame(width: res.exclusionWidth, height: 32)

            // RIGHT SAFE REGION: Trailing Shortcuts -> More -> Edit -> Status Controls
            HStack(spacing: tabSpacing) {
                ForEach(res.rightItems) { feature in
                    toolbarButton(feature)
                }

                // Section C: More Overflow Button (Appears only when enabled tools overflow)
                if res.showMoreButton {
                    moreButton(res.overflowItems)
                }

                // Section C: Edit Customization Action
                editToolbarButton

                // Trailing Status Badges
                trailingStatusPills
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, shoulderHorizontalPadding)
        .padding(.top, shoulderTopPadding)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - 2. Symmetrical Bar (External Displays & Non-Notch Macs)

    private var symmetricalBar: some View {
        let res = layoutResult

        return HStack(spacing: 8) {
            // Leading side: Home and first half of shortcuts
            HStack(spacing: tabSpacing) {
                ForEach(res.leftItems) { feature in
                    toolbarButton(feature)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Trailing side: Second half of shortcuts, More, Edit, and Status
            HStack(spacing: tabSpacing) {
                ForEach(res.rightItems) { feature in
                    toolbarButton(feature)
                }

                if res.showMoreButton {
                    moreButton(res.overflowItems)
                }

                editToolbarButton

                trailingStatusPills
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, shoulderHorizontalPadding)
        .padding(.top, shoulderTopPadding)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Toolbar Feature Button (Liquid Glass Material & Prismatic Refraction)

    private func toolbarButton(_ feature: ToolbarFeatureID) -> some View {
        let isSel = isFeatureSelected(feature)
        let isAct = isFeatureActive(feature)
        let isHov = hoveredFeature == feature

        return Button {
            handleFeatureAction(feature)
        } label: {
            ZStack(alignment: .topTrailing) {
                // Liquid Glass Background Capsule / Circle
                Circle()
                    .fill(
                        isSel ?
                            Color.white.opacity(0.20) :
                            (isHov ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                    )
                    .overlay(
                        // Prismatic Edge Refraction Border (derived from liquid-glass-react R/G/B offset)
                        Circle()
                            .stroke(
                                LinearGradient(
                                    stops: [
                                        .init(color: isSel ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.22), location: 0.0),
                                        .init(color: Color.white.opacity(0.08), location: 0.5),
                                        .init(color: Color.black.opacity(0.30), location: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isSel ? 1.2 : 0.85
                            )
                    )

                // Feature SF Symbol
                Image(systemName: feature.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        isSel ? Color.white : (isAct ? Color.accentColor : Color.white.opacity(0.72))
                    )
                    .frame(width: iconTabWidth, height: iconTabWidth)

                // Active State Indicator Dot / Badge
                if isAct && !isSel {
                    Circle()
                        .fill(feature == .keepAwake ? Color.orange : (feature == .nowPlaying ? Color.green : Color.accentColor))
                        .frame(width: 5, height: 5)
                        .offset(x: -2, y: 2)
                        .shadow(color: Color.accentColor.opacity(0.6), radius: 2)
                }
            }
            .frame(width: iconTabWidth, height: iconTabWidth)
            .scaleEffect(isHov ? 1.05 : 1.0)
            .animation(IslandMotion.shared.springInteractive, value: isHov)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredFeature = isHovering ? feature : nil
        }
        .help(feature.helpText)
    }

    // MARK: - Section C: More Overflow Button & Popover

    private func moreButton(_ overflowItems: [ToolbarFeatureID]) -> some View {
        Button {
            isShowingMorePopover.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(isShowingMorePopover ? Color.white.opacity(0.20) : Color.white.opacity(0.06))
                    .overlay(
                        Circle().stroke(
                            isShowingMorePopover ? Color.orange.opacity(0.7) : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                    )

                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: iconTabWidth, height: iconTabWidth)

                // Overflow item count pill
                Text("\(overflowItems.count)")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.9)))
                    .offset(x: 3, y: -2)
            }
            .frame(width: iconTabWidth, height: iconTabWidth)
        }
        .buttonStyle(.plain)
        .help("More Features (\(overflowItems.count) hidden tools)")
        .popover(isPresented: $isShowingMorePopover, arrowEdge: .bottom) {
            ToolbarMorePopoverView(overflowItems: overflowItems) { selected in
                isShowingMorePopover = false
                handleFeatureAction(selected)
            }
        }
    }

    // MARK: - Section C: Edit Toolbar Button

    private var editToolbarButton: some View {
        Button {
            isShowingEditSheet = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(width: iconTabWidth, height: iconTabWidth)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Customize Toolbar: Reorder, pin, and toggle shortcuts")
    }

    // MARK: - Trailing Status Pills (Buddy, OmniLauncher, Battery, Notification Center)

    private var trailingStatusPills: some View {
        HStack(spacing: 5) {
            // Animated Mascot Buddy sitting on shoulder
            LiquidBuddyView()
                .scaleEffect(0.78)

            // Omni-Launcher Spotlight Shortcut
            Button {
                withAnimation(IslandMotion.shared.springInteractive) {
                    OmniLauncherEngine.shared.toggleVisibility()
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(OmniLauncherEngine.shared.isVisible ? Color.accentColor : Color.white.opacity(0.72))
                    .frame(width: iconTabWidth, height: iconTabWidth)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Omni-Launcher (⌥Space): Quick search & tools")

            // Battery Capsule
            Button {
                withAnimation(IslandMotion.shared.springInteractive) {
                    coordinator.currentView = .stats
                }
            } label: {
                batteryCapsuleLabel
            }
            .buttonStyle(.plain)
            .help("Battery & Power Health")

            // Alert Center Button with badge
            Button {
                alertCenter.isShadeOpen.toggle()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(alertCenter.isShadeOpen ? Color.cyan : Color.white.opacity(0.72))
                        .frame(width: iconTabWidth, height: iconTabWidth)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                        .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))

                    if alertCenter.alerts.count > 0 {
                        Text("\(alertCenter.alerts.count)")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red.opacity(0.9)))
                            .offset(x: 3, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Notifications & Live Alerts")

            // Settings Gear
            Button {
                SettingsWindowController.shared.showWindow()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(width: iconTabWidth, height: iconTabWidth)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    private var batteryCapsuleLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: batteryModel.isCharging ? "battery.100.bolt" : "battery.75")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(batteryModel.isCharging ? Color.green : Color.white.opacity(0.8))
            Text("\(Int(batteryModel.levelBattery))%")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .padding(.horizontal, 5)
        .frame(height: iconTabWidth)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Action Router

    private func handleFeatureAction(_ feature: ToolbarFeatureID) {
        island.cancelHoverCollapse()

        switch feature {
        case .home:
            withAnimation(IslandMotion.shared.springInteractive) {
                coordinator.currentView = .home
            }

        case .colorDropper:
            ColorDropperTool.shared.sampleColor()

        case .keepAwake:
            withAnimation(IslandMotion.shared.springInteractive) {
                if coordinator.currentView == .keepAwake {
                    coordinator.currentView = .home
                } else {
                    coordinator.currentView = .keepAwake
                }
            }

        case .phoneBridge:
            withAnimation(IslandMotion.shared.springInteractive) {
                coordinator.currentView = .phoneBridge
            }

        case .powerload:
            withAnimation(IslandMotion.shared.springInteractive) {
                coordinator.currentView = .powerload
            }

        case .watcher:
            withAnimation(IslandMotion.shared.springInteractive) {
                coordinator.currentView = .agent
            }

        case .nowPlaying:
            withAnimation(IslandMotion.shared.springInteractive) {
                coordinator.currentView = .home
            }

        case .deviceUniverse:
            withAnimation(IslandMotion.shared.springInteractive) {
                coordinator.currentView = .bluetooth
            }

        case .systemStats:
            withAnimation(IslandMotion.shared.springInteractive) {
                coordinator.currentView = .stats
            }

        case .shelf, .downloads:
            withAnimation(IslandMotion.shared.springInteractive) {
                coordinator.currentView = .shelf
            }

        case .timer, .stopwatch:
            withAnimation(IslandMotion.shared.springInteractive) {
                coordinator.currentView = .calendar
            }

        case .privacyGuard, .webcamMonitor:
            withAnimation(IslandMotion.shared.springInteractive) {
                coordinator.currentView = .home
            }

        case .micMonitor, .audioControls, .volumeControl, .brightnessControl, .externalDisplay:
            withAnimation(IslandMotion.shared.springInteractive) {
                coordinator.currentView = .displaySound
            }

        case .clipboard:
            withAnimation(IslandMotion.shared.springInteractive) {
                coordinator.currentView = .home
            }

        case .calendar, .reminders:
            withAnimation(IslandMotion.shared.springInteractive) {
                coordinator.currentView = .calendar
            }

        case .liveActivities:
            withAnimation(IslandMotion.shared.springInteractive) {
                alertCenter.isShadeOpen.toggle()
            }
        }
    }

    private func isFeatureSelected(_ feature: ToolbarFeatureID) -> Bool {
        switch feature {
        case .home:
            return coordinator.currentView == .home
        case .phoneBridge:
            return coordinator.currentView == .phoneBridge
        case .calendar, .reminders:
            return coordinator.currentView == .calendar
        case .shelf, .downloads:
            return coordinator.currentView == .shelf
        case .watcher:
            return coordinator.currentView == .agent
        case .systemStats:
            return coordinator.currentView == .stats
        case .keepAwake:
            return coordinator.currentView == .keepAwake
        case .deviceUniverse:
            return coordinator.currentView == .bluetooth || coordinator.currentView == .devices
        case .powerload:
            return coordinator.currentView == .powerload
        case .volumeControl, .brightnessControl, .audioControls, .micMonitor, .externalDisplay:
            return coordinator.currentView == .displaySound
        default:
            return false
        }
    }

    private func isFeatureActive(_ feature: ToolbarFeatureID) -> Bool {
        switch feature {
        case .keepAwake:
            return keepAwake.isActive
        case .nowPlaying:
            return music.isPlaying
        case .liveActivities:
            return alertCenter.alerts.count > 0
        case .colorDropper:
            return ColorDropperTool.shared.isSampling
        default:
            return false
        }
    }
}
