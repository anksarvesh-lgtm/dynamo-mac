//
//  ContinuousLiquidIslandShape.swift
//  LiquidDynamo
//
//  Apple Liquid Glass continuous contour geometry:
//  - Seamlessly integrates Left Wing, Central Dynamic Island, and Right Wing
//  - Conforms to physical notch exclusion with continuous concave/convex bezier curves
//  - Falls back to continuous squircle on external or non-notched displays
//  - Eliminates visual gaps, dividers, seams, and disconnected floating capsules
//

import AppKit
import SwiftUI

/// Continuous squircle and wing geometry representing the unified Liquid Glass surface.
/// On physical notch displays, it curves organically around the hardware cutout,
/// seamlessly bridging the left wing, notch underside, and right wing into a single outer contour.
public struct ContinuousLiquidIslandShape: Shape {
    public var topEarRadius: CGFloat
    public var bottomCornerRadius: CGFloat
    public var isNotched: Bool
    public var rawNotchWidth: CGFloat
    public var rawNotchHeight: CGFloat
    public var hasConnectedDevices: Bool

    public init(
        topEarRadius: CGFloat = 8.0,
        bottomCornerRadius: CGFloat = 26.0,
        isNotched: Bool = true,
        rawNotchWidth: CGFloat = 180.0,
        rawNotchHeight: CGFloat = 32.0,
        hasConnectedDevices: Bool = true
    ) {
        self.topEarRadius = topEarRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.isNotched = isNotched
        self.rawNotchWidth = rawNotchWidth
        self.rawNotchHeight = rawNotchHeight
        self.hasConnectedDevices = hasConnectedDevices
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topEarRadius, bottomCornerRadius) }
        set {
            topEarRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        // When not a physical notch, render a continuous Apple squircle lozenge
        if !isNotched {
            let corner = min(rect.height / 2.0, bottomCornerRadius)
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: corner, height: corner), style: .continuous)
            return path
        }

        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY - 1.0 // 1pt extension into bezel area eliminates subpixel Retina halo
        let maxY = rect.maxY

        let midX = rect.midX
        let notchW = rawNotchWidth > 0 ? rawNotchWidth : 180.0
        let notchH = max(rawNotchHeight, 32.0)
        let halfNotch = notchW / 2.0

        let notchLeft = midX - halfNotch
        let notchRight = midX + halfNotch

        let rEar = max(4.0, min(topEarRadius, 10.0))
        let rBot = max(18.0, min(bottomCornerRadius, 30.0))
        let rWingTop: CGFloat = 16.0

        // If height is only collapsed notch height, trace resting notch bridge
        if rect.height <= notchH + 4.0 {
            let corner = min(rect.height / 2.0, 16.0)
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: corner, height: corner), style: .continuous)
            return path
        }

        // Expanded state: Continuous outer perimeter enclosing wings, notch bridge, and lower body
        path.move(to: CGPoint(x: minX + rWingTop, y: minY))

        // Left Wing top edge towards notch cutout
        if notchLeft > minX + rWingTop + rEar {
            path.addLine(to: CGPoint(x: notchLeft - rEar, y: minY))
            // Concave ear dipping down into left notch wall
            path.addQuadCurve(
                to: CGPoint(x: notchLeft, y: minY + rEar),
                control: CGPoint(x: notchLeft, y: minY)
            )
            // Downward along left notch wall
            path.addLine(to: CGPoint(x: notchLeft, y: minY + notchH - rEar))
            // Concave corner under bottom-left of notch cutout
            path.addQuadCurve(
                to: CGPoint(x: notchLeft + rEar, y: minY + notchH),
                control: CGPoint(x: notchLeft, y: minY + notchH)
            )
        } else {
            path.addLine(to: CGPoint(x: notchLeft, y: minY + notchH))
        }

        // Bridge under hardware notch
        if notchRight > notchLeft + 2 * rEar {
            path.addLine(to: CGPoint(x: notchRight - rEar, y: minY + notchH))
            // Concave corner under bottom-right of notch cutout
            path.addQuadCurve(
                to: CGPoint(x: notchRight, y: minY + notchH - rEar),
                control: CGPoint(x: notchRight, y: minY + notchH)
            )
            // Upward along right notch wall
            path.addLine(to: CGPoint(x: notchRight, y: minY + rEar))
            // Concave ear curving up to Right Wing top edge
            path.addQuadCurve(
                to: CGPoint(x: notchRight + rEar, y: minY),
                control: CGPoint(x: notchRight, y: minY)
            )
        } else {
            path.addLine(to: CGPoint(x: notchRight, y: minY))
        }

        // Right Wing top edge to top-right corner
        path.addLine(to: CGPoint(x: maxX - rWingTop, y: minY))

        // Convex top-right corner
        path.addQuadCurve(
            to: CGPoint(x: maxX, y: minY + rWingTop),
            control: CGPoint(x: maxX, y: minY)
        )

        // Downward vertical right edge
        path.addLine(to: CGPoint(x: maxX, y: maxY - rBot))

        // Apple continuous convex bottom-right corner
        path.addCurve(
            to: CGPoint(x: maxX - rBot, y: maxY),
            control1: CGPoint(x: maxX, y: maxY - rBot * 0.448),
            control2: CGPoint(x: maxX - rBot * 0.448, y: maxY)
        )

        // Horizontal bottom edge
        path.addLine(to: CGPoint(x: minX + rBot, y: maxY))

        // Apple continuous convex bottom-left corner
        path.addCurve(
            to: CGPoint(x: minX, y: maxY - rBot),
            control1: CGPoint(x: minX + rBot * 0.448, y: maxY),
            control2: CGPoint(x: minX, y: maxY - rBot * 0.448)
        )

        // Upward vertical left edge
        path.addLine(to: CGPoint(x: minX, y: minY + rWingTop))

        // Convex top-left corner back to start
        path.addQuadCurve(
            to: CGPoint(x: minX + rWingTop, y: minY),
            control: CGPoint(x: minX, y: minY)
        )

        path.closeSubpath()
        return path
    }
}

/// Unified 5-layer optical Liquid Glass backdrop rendered over ContinuousLiquidIslandShape.
public struct ContinuousLiquidIslandBackdrop: View {
    public var isNotched: Bool
    public var rawNotchWidth: CGFloat
    public var rawNotchHeight: CGFloat
    public var bottomCornerRadius: CGFloat
    public var isHovered: Bool

    public init(
        isNotched: Bool,
        rawNotchWidth: CGFloat,
        rawNotchHeight: CGFloat,
        bottomCornerRadius: CGFloat = 26.0,
        isHovered: Bool = false
    ) {
        self.isNotched = isNotched
        self.rawNotchWidth = rawNotchWidth
        self.rawNotchHeight = rawNotchHeight
        self.bottomCornerRadius = bottomCornerRadius
        self.isHovered = isHovered
    }

    private var shape: ContinuousLiquidIslandShape {
        ContinuousLiquidIslandShape(
            topEarRadius: 8.0,
            bottomCornerRadius: bottomCornerRadius,
            isNotched: isNotched,
            rawNotchWidth: rawNotchWidth,
            rawNotchHeight: rawNotchHeight
        )
    }

    public var body: some View {
        ZStack {
            // Layer 1: AppKit NSVisualEffectView real-time backdrop blur (hudWindow behindWindow)
            NSVisualEffectBackdropView(
                material: .hudWindow,
                blendingMode: .behindWindow,
                state: .active
            )
            .clipShape(shape)

            // Layer 2: Deep Smoked Charcoal base (#17191C, 92% opacity)
            shape
                .fill(LiquidColorTokens.primaryGlass.opacity(0.92))

            // Layer 3: Internal Gradient (#24282D down to #090B0E, 90% opacity)
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            LiquidColorTokens.secondaryGlass.opacity(0.65),
                            LiquidColorTokens.deepShadow.opacity(0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Layer 4: Prismatic Optical Refraction (Teal #123B36 and Blue #14283F)
            shape
                .fill(
                    RadialGradient(
                        colors: [
                            LiquidColorTokens.tealRefraction.opacity(0.42),
                            LiquidColorTokens.blueRefraction.opacity(0.24),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: 420
                    )
                )

            // Layer 5: Warm Champagne Environmental Reflection (Bottom-Right)
            shape
                .fill(
                    RadialGradient(
                        colors: [
                            LiquidColorTokens.champagneReflection.opacity(0.22),
                            Color.clear
                        ],
                        center: .bottomTrailing,
                        startRadius: 10,
                        endRadius: 260
                    )
                )

            // Layer 6: Directional Top Specular Sheen (-45° illumination)
            shape
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(isHovered ? 0.26 : 0.18), location: 0.0),
                            .init(color: Color.white.opacity(0.06), location: 0.30),
                            .init(color: Color.clear, location: 0.65)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Layer 7: Razor Specular Rim (Silver #DDE8F0, Teal, Champagne #C69B70)
            shape
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: LiquidColorTokens.silverHighlight.opacity(isHovered ? 0.85 : 0.65), location: 0.0),
                            .init(color: LiquidColorTokens.tealRefraction.opacity(0.48), location: 0.35),
                            .init(color: Color.white.opacity(0.12), location: 0.65),
                            .init(color: LiquidColorTokens.champagneReflection.opacity(0.58), location: 0.95),
                            .init(color: LiquidColorTokens.silverHighlight.opacity(0.38), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
        }
    }
}

