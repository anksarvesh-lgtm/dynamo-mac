//
//  LiquidUnifiedSurfaceView.swift
//  LiquidDynamo
//
//  Master Liquid Unified Surface View:
//  - Apple Liquid Glass Visual Language (Dark Smoked Charcoal #17191C, Specular Rim #DDE8F0, Teal #123B36)
//  - Permanent Connected Devices Header fixed at top
//  - 3-Slide Horizontal Utility Carousel (Productivity, System Tools, Monitoring)
//  - Adaptive In-Place Detail Expansion (Single continuous surface morphs into rich 3-column views)
//  - Organic water-physics spring animations and notch anchor synchronization
//

import AppKit
import Combine
import SwiftUI

public struct LiquidUnifiedSurfaceView: View {
    @ObservedObject var island = IslandController.shared
    @ObservedObject var motion = IslandMotion.shared
    @ObservedObject var safeArea = NotchSafeAreaEngine.shared

    @State private var currentSlide: Int = 0
    @State private var expandedMode: ExpandedMode = .none
    @State private var isHovered: Bool = false
    @State private var fluidSurfaceWave: CGFloat = 0.0

    public init() {}

    public var body: some View {
        let geom = safeArea.currentGeometry

        VStack(spacing: 0) {
            // Physical Notch Exclusion Anchor (wrap seamlessly around hardware cutout)
            if geom.isNotched {
                Color.clear
                    .frame(width: geom.rawNotchWidth, height: geom.rawNotchHeight + 6)
            } else {
                Color.clear
                    .frame(height: 14)
            }

            // Single Continuous Liquid Glass Container
            VStack(spacing: 8) {
                // 1. Permanent Connected Devices Header (MagSafe 3 & Audio / realme Buds)
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
                .frame(maxWidth: .infinity)

                // 2. Adaptive Lower Body: Carousel OR Expanded Detail View
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
                    .frame(maxWidth: .infinity)
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
                    .frame(maxWidth: .infinity)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                        )
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .background(
                liquidSurfaceBackdrop
            )
            .clipShape(
                RoundedRectangle(cornerRadius: expandedMode == .none ? 26 : 28, style: .continuous)
            )
            .shadow(color: LiquidColorTokens.deepShadow.opacity(0.85), radius: 24, x: 0, y: 12)
            .shadow(color: Color.black.opacity(0.40), radius: 6, x: 0, y: 3)
            .onHover { h in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                    isHovered = h
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.spring(response: 0.38, dampingFraction: 0.80), value: expandedMode)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: currentSlide)
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
        LiquidViewModel.shared.open(pinned: true)
        AppDelegate.shared?.vm.open(pinned: true)

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
        case .none, .player: return .none
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
        case .clipboard: return .clipboard
        case .dropper, .colorDropper: return .dropper
        case .storageCleaner: return .scopa
        case .powerload, .plexo: return .powerload
        case .phoneBridge: return .phoneBridge
        case .watcher: return .watcher
        case .device(let key): return .device(key)
        }
    }

    // MARK: - Liquid Surface Backdrop (Apple Dark Liquid Glass)
    @ViewBuilder
    private var liquidSurfaceBackdrop: some View {
        ZStack {
            // Layer 1: Frosted depth base
            RoundedRectangle(cornerRadius: expandedMode == .none ? 26 : 28, style: .continuous)
                .fill(.ultraThinMaterial)

            // Layer 2: Deep Smoked Charcoal (#17191C)
            RoundedRectangle(cornerRadius: expandedMode == .none ? 26 : 28, style: .continuous)
                .fill(LiquidColorTokens.primaryGlass.opacity(0.92))

            // Layer 3: Internal Gradient (#24282D down to #090B0E)
            RoundedRectangle(cornerRadius: expandedMode == .none ? 26 : 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            LiquidColorTokens.secondaryGlass.opacity(0.60),
                            LiquidColorTokens.deepShadow.opacity(0.90)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Layer 4: Prismatic Optical Refraction (Teal #123B36 and Blue #14283F)
            RoundedRectangle(cornerRadius: expandedMode == .none ? 26 : 28, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            LiquidColorTokens.tealRefraction.opacity(0.40),
                            LiquidColorTokens.blueRefraction.opacity(0.22),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: 360
                    )
                )

            // Layer 5: Warm Champagne Environmental Highlight (Bottom Right)
            RoundedRectangle(cornerRadius: expandedMode == .none ? 26 : 28, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            LiquidColorTokens.champagneReflection.opacity(0.20),
                            Color.clear
                        ],
                        center: .bottomTrailing,
                        startRadius: 5,
                        endRadius: 200
                    )
                )

            // Layer 6: Directional Top Specular Sheen (-45° illumination)
            RoundedRectangle(cornerRadius: expandedMode == .none ? 26 : 28, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(isHovered ? 0.25 : 0.16), location: 0.0),
                            .init(color: Color.white.opacity(0.05), location: 0.25),
                            .init(color: Color.clear, location: 0.60)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Layer 7: Razor Specular Rim (Silver #DDE8F0, Teal, Champagne #C69B70)
            RoundedRectangle(cornerRadius: expandedMode == .none ? 26 : 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: LiquidColorTokens.silverHighlight.opacity(isHovered ? 0.80 : 0.60), location: 0.0),
                            .init(color: LiquidColorTokens.tealRefraction.opacity(0.45), location: 0.35),
                            .init(color: Color.white.opacity(0.10), location: 0.65),
                            .init(color: LiquidColorTokens.champagneReflection.opacity(0.55), location: 0.95),
                            .init(color: LiquidColorTokens.silverHighlight.opacity(0.35), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
        }
    }
}

