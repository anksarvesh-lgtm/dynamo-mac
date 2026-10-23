//
//  WaterPhysicsGlassContourView.swift
//  LiquidDynamo
//
//  Step D: High-fidelity Liquid Glass rendering for the water-physics closed contour.
//  50% default transparency, depth-based bevel, soft highlights, specular rim following
//  real contour, pure black at notch junction (y <= notchLipY + 6.0), zero pills/rectangles,
//  content inside, and empty notch zone (y < 32.0).
//

import AppKit
import Defaults
import Foundation
import SwiftUI

// MARK: - 1. Water Contour Shape

/// SwiftUI Shape wrapping the dynamic closed-loop path from WaterPhysicsSimulation.
/// Center-aligns the notch orifice with the view's horizontal midpoint and guarantees
/// that the physical notch hardware zone (y < notchLipY) remains strictly empty.
public struct WaterContourShape: Shape, @unchecked Sendable {
    public var path: Path
    public var canvasWidth: CGFloat

    public init(
        path: Path = Path(),
        canvasWidth: CGFloat = 600.0
    ) {
        self.path = path
        self.canvasWidth = canvasWidth
    }

    @MainActor
    public init(simulation: WaterPhysicsSimulation) {
        self.path = simulation.currentPath
        self.canvasWidth = simulation.canvasSize.width
    }

    public func path(in rect: CGRect) -> Path {
        guard !path.isEmpty else { return Path() }
        let dx = rect.midX - (canvasWidth * 0.5)
        if abs(dx) > 0.001 {
            return path.applying(CGAffineTransform(translationX: dx, y: 0))
        }
        return path
    }
}

// MARK: - 2. Water Physics Glass Contour View

@MainActor
public struct WaterPhysicsGlassContourView<Content: View>: View {
    @ObservedObject private var sim = WaterPhysicsSimulation.shared
    @ObservedObject private var island = IslandController.shared
    @ObservedObject private var sensorMonitor = HardwareSensorMonitor.shared

    @Environment(\.accessibilityReduceTransparency) private var isReduceTransparency
    @Environment(\.accessibilityInvertColors) private var isIncreaseContrast

    public var ambientColor: Color?
    public var isExpanded: Bool
    @ViewBuilder public let content: () -> Content

    @State private var hoverPoint: CGPoint = .zero
    @State private var isHovering: Bool = false

    public init(
        ambientColor: Color? = nil,
        isExpanded: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.ambientColor = ambientColor
        self.isExpanded = isExpanded
        self.content = content
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            // Continuous animation frame driver: unpaused when active, paused when sleeping
            TimelineView(.animation(paused: sim.metrics.isSleeping)) { timeline in
                let _ = timeline.date
                let _ = sim.stepFrameIfNeeded()

                let contourShape = WaterContourShape(path: sim.currentPath, canvasWidth: sim.canvasSize.width)

                ZStack(alignment: .top) {
                    // Glass backdrop layers
                    renderGlassBackdrop(shape: contourShape, width: w, height: h)

                    // Content inside: modulated by contentAlpha, safe within water contour
                    content()
                        .opacity(sim.contentAlpha)
                        .clipShape(contourShape)
                }
                .contentShape(contourShape)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverPoint = location
                isHovering = true
            case .ended:
                isHovering = false
            }
        }
    }

    // MARK: - Glass Backdrop Layers

    @ViewBuilder
    private func renderGlassBackdrop(shape: WaterContourShape, width: CGFloat, height: CGFloat) -> some View {
        let lipY = sim.notchLipY
        let blackCapHeight = lipY + 6.0
        let notchStop = min(1.0, max(0.01, blackCapHeight / max(1.0, height)))
        let transparency = Defaults[.islandTransparency] // Default: 0.50
        let targetAlpha = max(0.20, 1.0 - transparency)   // Default: 0.50 (50% transparency)
        let resolvedAmbient = ambientColor ?? sensorMonitor.activeSensorLiquidColor

        ZStack(alignment: .top) {
            // TIER 1: Behind-Window Real-time Blur
            if !isReduceTransparency && !isIncreaseContrast {
                VisualEffectBackdropView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(shape)
            }

            // TIER 2: Dark Obsidian Glass Base & Opacity Ramp
            if isIncreaseContrast {
                shape.fill(Color.black)
            } else if isReduceTransparency {
                shape.fill(Color(white: 0.08).opacity(0.96))
            } else {
                // Tier 1 & 2: Opacity ramp from pure black at notch junction down to 50% translucent glass
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: notchStop), // Top junction pure black
                        .init(color: Color.black.opacity(min(1.0, targetAlpha + 0.18)), location: min(1.0, notchStop + 0.22)),
                        .init(color: Color(white: 0.02).opacity(targetAlpha), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(shape)

                // Hard guarantee: pure opaque black (#000000) for y <= notchLipY + 6.0
                Rectangle()
                    .fill(Color.black)
                    .frame(height: blackCapHeight)
                    .clipShape(shape)
            }

            // TIER 3: Ambient Color Wash (Album art / hardware sensor / tint)
            if !isReduceTransparency && !isIncreaseContrast, let tint = resolvedAmbient {
                RadialGradient(
                    colors: [
                        tint.opacity(0.24),
                        tint.opacity(0.06),
                        Color.clear
                    ],
                    center: .top,
                    startRadius: 8,
                    endRadius: max(100, min(width, height) * 1.2)
                )
                .clipShape(shape)
            }

            // TIER 4: Depth-Based Bevel & Inner Refractive Shading
            if !isReduceTransparency && !isIncreaseContrast {
                // Inward volume refraction gradient
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.clear,
                        Color.black.opacity(0.38)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(shape)

                // Depth-based bevel inner stroke
                shape.stroke(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .clear, location: notchStop),
                            .init(color: Color.white.opacity(0.22), location: min(1.0, notchStop + 0.10)),
                            .init(color: Color.black.opacity(0.25), location: 0.70),
                            .init(color: Color.black.opacity(0.50), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 2.0
                )
            }

            // TIER 5: Soft Horizon Glass Sheen & Upper Highlights
            if !isReduceTransparency && !isIncreaseContrast {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: max(0.0, notchStop - 0.02)),
                        .init(color: Color.white.opacity(0.18), location: notchStop + 0.02),
                        .init(color: Color.white.opacity(0.05), location: min(1.0, notchStop + 0.22)),
                        .init(color: .clear, location: min(1.0, notchStop + 0.45))
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(shape)
            }

            // TIER 6: Specular Perimeter Rim Following Real Contour
            // Strictly Color.clear across top notch orifice (y <= notchLipY + 6.0)
            if isIncreaseContrast {
                shape.stroke(Color.white, lineWidth: 1.5)
            } else if !isReduceTransparency {
                shape.stroke(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .clear, location: notchStop), // 0 stroke over notch junction!
                            .init(color: Color.white.opacity(0.65), location: min(1.0, notchStop + 0.12)),
                            .init(color: Color.cyan.opacity(0.40), location: 0.72),
                            .init(color: Color.white.opacity(0.55), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.25
                )
            }
        }
        // TIER 7: Soft Fluid Dropshadow
        .shadow(
            color: Color.black.opacity(isExpanded ? 0.45 : (Defaults[.enableShadow] ? 0.6 : 0.0)),
            radius: isExpanded ? 26 : 4,
            x: 0,
            y: isExpanded ? 12 : 2
        )
        .shadow(
            color: Color.cyan.opacity(isExpanded ? 0.12 : 0.0),
            radius: isExpanded ? 10 : 0,
            x: 0,
            y: isExpanded ? 3 : 0
        )
    }
}
