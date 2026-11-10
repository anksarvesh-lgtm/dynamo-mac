//
//  SuperIslandContainerView.swift
//  LiquidDynamo
//
//  Created for LiquidDynamo
//
//  SuperIsland-style primary Notch presentation surface with Apple Liquid droplet morphing,
//  multi-tier presentation hierarchy, module cycler, shelf drop target, and full gesture navigation.
//

import AppKit
import Combine
import Defaults
import SwiftUI

public enum SuperIslandTier {
    case compact
    case expanded
    case fullExpanded
}

public struct SuperIslandContainerView: View {
    @EnvironmentObject var vm: LiquidViewModel
    @ObservedObject var coordinator = LiquidViewCoordinator.shared
    @ObservedObject var island = IslandController.shared
    @ObservedObject var hub = LiveActivityCenter.shared
    @ObservedObject var phoneBridge = MacLinkBridgeService.shared
    @ObservedObject var shelfState = ShelfStateViewModel.shared

    @State private var isHoveringSurface: Bool = false
    @State private var isShelfDropTargeted: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var isCyclingLeftHovered: Bool = false
    @State private var isCyclingRightHovered: Bool = false

    private let availableModules: [NotchViews] = [
        .home,
        .phoneBridge,
        .calendar,
        .shelf,
        .teleprompter,
        .agent,
        .stats,
        .cleaner,
        .bluetooth
    ]

    public init() {}

    public var currentTier: SuperIslandTier {
        if island.state == .expanded || vm.notchState == .open {
            if island.targetSize.height > 180 || coordinator.currentView != .home {
                return .fullExpanded
            }
            return .expanded
        }
        return .compact
    }

    public var body: some View {
        ZStack(alignment: .top) {
            islandSurface

            // Module Cycler Chevron Overlays on Hover
            if isHoveringSurface && currentTier == .compact {
                moduleCyclerOverlay
            }

            // Shelf Drop Target Overlay
            if isShelfDropTargeted {
                shelfDropOverlay
            }

            // Omni-Launcher Overlay (Spotlight, Math Calculator & AI Web Research)
            OmniLauncherOverlayView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHoveringSurface = true
            case .ended:
                isHoveringSurface = false
            }
        }
    }

    // MARK: - Surface

    private var islandSurface: some View {
        let size = surfaceSize
        let shape = surfaceShape

        return ZStack(alignment: .top) {
            // 1. Obsidian Liquid Glass Base Fill
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.98),
                            Color.black.opacity(0.93)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // 2. Liquid Specular Caustic Glare along Top & Rim
            shape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.24),
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )

            // 3. Main Island Content
            surfaceContent
                .frame(width: size.width, height: size.height, alignment: .top)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .compositingGroup()
        // Dual-tier Apple shadow (suppressed in compact to guarantee clean menu-bar clicks)
        .shadow(
            color: Color.black.opacity(currentTier == .compact ? 0.0 : 0.40),
            radius: currentTier == .compact ? 0 : 10,
            y: currentTier == .compact ? 0 : 6
        )
        .shadow(
            color: Color.black.opacity(currentTier == .compact ? 0.0 : 0.60),
            radius: currentTier == .compact ? 0 : 18,
            y: currentTier == .compact ? 0 : 12
        )
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { val in
                    dragOffset = val.translation
                }
                .onEnded { val in
                    handleDragEnded(val)
                    dragOffset = .zero
                }
        )
        .onTapGesture {
            handleTap()
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    SettingsWindowController.shared.showWindow()
                }
        )
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $isShelfDropTargeted) { providers in
            isShelfDropTargeted = false
            let count = providers.count
            if count > 0 {
                ShelfStateViewModel.shared.load(providers)
                withAnimation(.spring(response: 0.44, dampingFraction: 0.76)) {
                    coordinator.currentView = .shelf
                    island.setExpanded(view: .shelf, pin: true)
                }
                return true
            }
            return false
        }
        .animation(.spring(response: 0.44, dampingFraction: 0.76), value: currentTier)
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: coordinator.currentView)
    }

    // MARK: - Surface Content

    @ViewBuilder
    private var surfaceContent: some View {
        switch currentTier {
        case .compact:
            compactContent
                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
        case .expanded, .fullExpanded:
            expandedContent
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
        }
    }

    // MARK: - Compact Content

    private var compactContent: some View {
        ZStack(alignment: .center) {
            if coordinator.sneakPeek.show && Defaults[.inlineHUD] && coordinator.sneakPeek.type != .music && coordinator.sneakPeek.type != .battery {
                // Inline System HUD event (Volume / Brightness)
                InlineHUDCompactPill()
            } else {
                CollapsedLiveInfoWingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Expanded & Full Expanded Content

    private var expandedContent: some View {
        let isNotched = vm.geometry.hasPhysicalNotch

        return VStack(spacing: 0) {
            // Top Bar (Shoulder layout for notched screens; Inline layout for floating non-notch)
            SuperIslandTopBarView(layout: isNotched ? .shoulder : .inline)
                .frame(maxWidth: .infinity, alignment: .top)

            // Main Body Area
            Group {
                if let call = phoneBridge.incomingCall, phoneBridge.isCallActive || call.callerName.isEmpty == false {
                    IncomingCallHUDView()
                        .padding(.top, 4)
                } else if let notif = hub.activeNotification {
                    LiveActivityNotificationCardView(activity: notif) {
                        hub.dismissNotification()
                    }
                    .padding(.top, 4)
                } else if let alert = hub.activeAlert {
                    ExpandedAlertBannerView(
                        alert: AlertPayload(
                            id: alert.id,
                            kind: .custom(title: alert.payload.title, subtitle: alert.payload.subtitle, icon: alert.payload.iconName),
                            title: alert.payload.title,
                            subtitle: alert.payload.subtitle ?? alert.payload.body,
                            iconName: alert.payload.iconName,
                            iconColor: alert.tint,
                            dwellDuration: alert.duration ?? 3.5,
                            action: alert.payload.action
                        )
                    ) {
                        hub.dismissAlert()
                    }
                    .padding(.top, 4)
                } else {
                    currentExpandedModuleView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Module View Router

    @ViewBuilder
    private var currentExpandedModuleView: some View {
        switch coordinator.currentView {
        case .home:
            SuperIslandHomeScreenView()
        case .phoneBridge:
            PhoneCommandDeckView()
        case .calendar:
            CalendarView().environmentObject(vm)
        case .shelf:
            ShelfView()
        case .teleprompter:
            TeleprompterView()
        case .agent:
            AgentDockTabView()
        case .stats, .powerload, .plexo:
            SystemStatsView()
        case .cleaner:
            NotchStorageCleanerView()
        case .bluetooth, .devices:
            BluetoothDevicesView()
        case .displaySound:
            DisplayAndSoundView()
        case .network, .netMerge:
            NetworkTabView()
        }
    }

    // MARK: - Shape & Geometry

    private var surfaceShape: SuperIslandPillShape {
        let isNotched = vm.geometry.hasPhysicalNotch
        let geom = vm.geometry

        switch currentTier {
        case .compact:
            return SuperIslandPillShape(
                topLeadingRadius: isNotched ? 0 : 14,
                topTrailingRadius: isNotched ? 0 : 14,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 14,
                outwardTopCorners: false,
                topCutoutWidth: 0,
                topCutoutDepth: 0,
                topCutoutCornerRadius: 0
            )
        case .expanded:
            return SuperIslandPillShape(
                topLeadingRadius: isNotched ? 0 : 18,
                topTrailingRadius: isNotched ? 0 : 18,
                bottomLeadingRadius: 22,
                bottomTrailingRadius: 22,
                outwardTopCorners: isNotched,
                topCutoutWidth: isNotched ? geom.rawNotchWidth : 0,
                topCutoutDepth: isNotched ? geom.notchHeight : 0,
                topCutoutCornerRadius: isNotched ? 6 : 0
            )
        case .fullExpanded:
            return SuperIslandPillShape(
                topLeadingRadius: isNotched ? 0 : 22,
                topTrailingRadius: isNotched ? 0 : 22,
                bottomLeadingRadius: 28,
                bottomTrailingRadius: 28,
                outwardTopCorners: isNotched,
                topCutoutWidth: isNotched ? geom.rawNotchWidth : 0,
                topCutoutDepth: isNotched ? geom.notchHeight : 0,
                topCutoutCornerRadius: isNotched ? 6 : 0
            )
        }
    }

    private var surfaceSize: CGSize {
        let geom = vm.geometry
        let isNotched = geom.hasPhysicalNotch

        switch currentTier {
        case .compact:
            let defaultW = isNotched ? max(geom.rawNotchWidth + 140, island.targetSize.width) : 220.0
            let defaultH = isNotched ? geom.notchHeight : 34.0
            return CGSize(width: defaultW, height: defaultH)
        case .expanded:
            return CGSize(width: max(480, island.targetSize.width), height: 140)
        case .fullExpanded:
            let screenW = NSScreen.main?.frame.width ?? 1440
            let targetW = min(screenW - 80, 680)
            return CGSize(width: targetW, height: 236)
        }
    }

    // MARK: - Module Cycler Overlay

    private var moduleCyclerOverlay: some View {
        HStack {
            Button {
                cycleModule(forward: false)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isCyclingLeftHovered ? Color.white : Color.white.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(isCyclingLeftHovered ? 0.2 : 0.08)))
            }
            .buttonStyle(.plain)
            .onHover { isCyclingLeftHovered = $0 }
            .padding(.leading, 6)

            Spacer()

            Button {
                cycleModule(forward: true)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isCyclingRightHovered ? Color.white : Color.white.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(isCyclingRightHovered ? 0.2 : 0.08)))
            }
            .buttonStyle(.plain)
            .onHover { isCyclingRightHovered = $0 }
            .padding(.trailing, 6)
        }
        .frame(width: surfaceSize.width, height: surfaceSize.height)
    }

    // MARK: - Shelf Drop Overlay

    private var shelfDropOverlay: some View {
        surfaceShape
            .stroke(Color.accentColor.opacity(0.92), style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
            .padding(1)
            .overlay(
                HStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                    Text("Drop files to Shelf")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.85)))
                .shadow(radius: 8)
            )
    }

    // MARK: - Actions & Gestures

    private func cycleModule(forward: Bool) {
        guard let currentIdx = availableModules.firstIndex(of: coordinator.currentView) else {
            coordinator.currentView = .home
            return
        }

        let nextIdx: Int
        if forward {
            nextIdx = (currentIdx + 1) % availableModules.count
        } else {
            nextIdx = (currentIdx - 1 + availableModules.count) % availableModules.count
        }

        withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
            coordinator.currentView = availableModules[nextIdx]
        }
    }

    private func handleTap() {
        if currentTier == .compact {
            withAnimation(.spring(response: 0.44, dampingFraction: 0.76)) {
                island.setExpanded(pin: true)
                LiquidViewModel.shared.open(pinned: true)
            }
        }
    }

    private func handleDragEnded(_ val: DragGesture.Value) {
        let horizontal = val.translation.width
        let vertical = val.translation.height

        if abs(horizontal) > abs(vertical) && abs(horizontal) > 30 {
            // Horizontal swipe: cycle modules
            cycleModule(forward: horizontal < 0)
        } else if vertical > 40 {
            // Drag down: expand
            withAnimation(.spring(response: 0.44, dampingFraction: 0.76)) {
                island.setExpanded(pin: true)
                LiquidViewModel.shared.open(pinned: true)
            }
        } else if vertical < -30 {
            // Drag up: collapse
            withAnimation(.spring(response: 0.44, dampingFraction: 0.76)) {
                island.transitionTo(island.resolveRestingState())
                LiquidViewModel.shared.close()
            }
        }
    }
}

// Inline HUD Compact Pill for Volume / Brightness events
private struct InlineHUDCompactPill: View {
    @ObservedObject private var coordinator = LiquidViewCoordinator.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: coordinator.sneakPeek.icon.isEmpty ? "speaker.wave.3.fill" : coordinator.sneakPeek.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)

            ProgressView(value: Double(coordinator.sneakPeek.value), total: 100.0)
                .progressViewStyle(.linear)
                .frame(width: 80)
                .tint(Color.white)

            Text("\(Int(coordinator.sneakPeek.value))%")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
    }
}

