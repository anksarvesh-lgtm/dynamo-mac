//
//  LiquidUnifiedSurfaceView.swift
//  LiquidDynamo
//
//  Master Liquid Unified Surface View:
//  - Apple Liquid Glass Visual Language (Dark Smoked Charcoal #17191C, Specular Rim #DDE8F0, Teal #123B36)
//  - One Continuous Liquid Glass Object unifying Left Wing, Central Dynamic Island, and Right Wing
//  - Permanent Connected Devices Header fixed at top (Strictly verified real data only)
//  - 3-Slide Horizontal Utility Carousel (Productivity, System Tools, Monitoring)
//  - Adaptive In-Place Detail Expansion (Single continuous surface morphs into rich 3-column views)
//  - Organic water-physics spring animations and notch anchor synchronization
//

import AppKit
import Combine
import SwiftUI

public struct LiquidUnifiedSurfaceView: View {
    @EnvironmentObject var vm: LiquidViewModel
    @ObservedObject var island = IslandController.shared
    @ObservedObject var motion = IslandMotion.shared
    @ObservedObject var safeArea = NotchSafeAreaEngine.shared
    @ObservedObject var chargingService = ChargingIntelligenceService.shared
    @ObservedObject var deviceMonitor = DeviceMonitor.shared

    @State private var currentSlide: Int = 0
    @State private var expandedMode: ExpandedMode = .none
    @State private var isHovered: Bool = false
    @State private var fluidSurfaceWave: CGFloat = 0.0

    public init() {}

    private var hasConnectedDevices: Bool {
        let isPlugged = chargingService.isPluggedIn || BatteryStatusViewModel.shared.isPluggedIn
        if isPlugged { return true }
        return deviceMonitor.sortedActiveDevices.contains { dev in
            dev.kind != .monitor && dev.kind != .androidPhone && !dev.displayName.contains("Built-in") && deviceMonitor.activeDevices[dev.stableKey] != nil
        }
    }

    public var body: some View {
        let geom = safeArea.currentGeometry
        let isNotched = geom.isNotched
        let notchW = geom.rawNotchWidth > 0 ? geom.rawNotchWidth : 180.0
        let notchH = geom.notchHeight

        ZStack(alignment: .top) {
            // 1. Unified Continuous 5-Layer Optical Liquid Glass Backdrop
            ContinuousLiquidIslandBackdrop(
                isNotched: isNotched,
                rawNotchWidth: notchW,
                rawNotchHeight: notchH,
                bottomCornerRadius: expandedMode == .none ? 26 : 28,
                isHovered: isHovered
            )

            // 2. Continuous Fluid Content Stack
            VStack(spacing: 6) {
                // Top Flanking Row (Notch Exclusion Zone + Left/Right Wings or Verified Connected Devices)
                if isNotched {
                    if hasConnectedDevices {
                        PermanentConnectedDevicesHeaderView(
                            onSelectCharger: {
                                toggleExpansion(.device("sim_magsafe"))
                            },
                            onSelectAudioDevice: { dev in
                                if let key = dev?.stableKey {
                                    toggleExpansion(.device(key))
                                } else {
                                    toggleExpansion(.device("bluetooth_library"))
                                }
                            }
                        )
                        .padding(.top, 2)
                    } else {
                        // When 0 devices connected, notch cutout clearance allows carousel to shift up naturally
                        Color.clear
                            .frame(height: notchH + 2)
                    }
                } else {
                    // Non-notched display: Connected devices header if any, with smooth top margin
                    if hasConnectedDevices {
                        PermanentConnectedDevicesHeaderView(
                            onSelectCharger: {
                                toggleExpansion(.device("sim_magsafe"))
                            },
                            onSelectAudioDevice: { dev in
                                if let key = dev?.stableKey {
                                    toggleExpansion(.device(key))
                                } else {
                                    toggleExpansion(.device("bluetooth_library"))
                                }
                            }
                        )
                        .padding(.top, 4)
                    } else {
                        Color.clear
                            .frame(height: 8)
                    }
                }

                // Lower Body: Carousel OR Expanded Detail View (In-Place Morphing)
                if expandedMode == .none {
                    UtilityCarouselView(
                        currentSlide: $currentSlide,
                        onSelectUtility: { utility in
                            switch utility {
                            case .player:
                                toggleExpansion(.player)
                            case .clipboard:
                                toggleExpansion(.clipboard)
                            case .dropper:
                                toggleExpansion(.dropper)
                            case .scopa:
                                toggleExpansion(.scopa)
                            case .powerload:
                                toggleExpansion(.powerload)
                            case .phoneBridge:
                                toggleExpansion(.phoneBridge)
                            case .watcher:
                                toggleExpansion(.watcher)
                            }
                        }
                    )
                    .padding(.horizontal, 10)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                        )
                    )
                } else {
                    LiquidUnifiedDetailContainerView(
                        mode: expandedMode,
                        onDismiss: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                                expandedMode = .none
                                island.activeOrganicItem = .none
                            }
                        }
                    )
                    .environmentObject(vm)
                    .padding(.horizontal, 10)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                        )
                    )
                }
            }
            .padding(.bottom, 10)
            .clipShape(
                ContinuousLiquidIslandShape(
                    topEarRadius: 8.0,
                    bottomCornerRadius: expandedMode == .none ? 26 : 28,
                    isNotched: isNotched,
                    rawNotchWidth: notchW,
                    rawNotchHeight: notchH,
                    hasConnectedDevices: hasConnectedDevices
                )
            )
        }
        .contentShape(
            ContinuousLiquidIslandShape(
                topEarRadius: 8.0,
                bottomCornerRadius: expandedMode == .none ? 26 : 28,
                isNotched: isNotched,
                rawNotchWidth: notchW,
                rawNotchHeight: notchH,
                hasConnectedDevices: hasConnectedDevices
            )
        )
        .shadow(color: LiquidColorTokens.deepShadow.opacity(0.85), radius: 24, x: 0, y: 12)
        .shadow(color: Color.black.opacity(0.40), radius: 6, x: 0, y: 3)
        .onHover { h in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                isHovered = h
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.spring(response: 0.38, dampingFraction: 0.80), value: expandedMode)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: currentSlide)
        .animation(.spring(response: 0.38, dampingFraction: 0.80), value: hasConnectedDevices)
        .onAppear {
            syncStateFromIsland()
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                fluidSurfaceWave = 1.0
            }
        }
        .onChange(of: island.activeOrganicItem) { _, newItem in
            let mapped = fromOrganicItem(newItem)
            if mapped != expandedMode {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                    expandedMode = mapped
                }
            }
        }
    }

    // MARK: - Expansion Toggle
    private func toggleExpansion(_ mode: ExpandedMode) {
        island.cancelHoverCollapse()
        island.isPinnedOpen = true
        if vm.notchState != .open {
            vm.open(pinned: true)
        }

        withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
            if expandedMode == mode {
                expandedMode = .none
                island.activeOrganicItem = .none
            } else {
                expandedMode = mode
                island.activeOrganicItem = toOrganicItem(mode)
            }
        }
    }

    private func syncStateFromIsland() {
        if island.activeOrganicItem != .none {
            expandedMode = fromOrganicItem(island.activeOrganicItem)
        }
    }

    private func toOrganicItem(_ mode: ExpandedMode) -> OrganicNotchExpandedItem {
        switch mode {
        case .none: return .none
        case .player: return .player
        case .clipboard: return .clipboard
        case .dropper: return .dropper
        case .scopa: return .storageCleaner
        case .powerload: return .powerload
        case .phoneBridge: return .phoneBridge
        case .watcher: return .watcher
        case .device(let key): return .device(key)
        }
    }

    private func fromOrganicItem(_ item: OrganicNotchExpandedItem) -> ExpandedMode {
        switch item {
        case .none: return .none
        case .player: return .player
        case .clipboard: return .clipboard
        case .dropper, .colorDropper: return .dropper
        case .storageCleaner: return .scopa
        case .powerload, .plexo: return .powerload
        case .phoneBridge: return .phoneBridge
        case .watcher: return .watcher
        case .device(let key): return .device(key)
        }
    }
}
