//
//  NotchShape.swift
//  boringNotch
//
// Created by Kai Azim on 2023-08-24.
// Original source: https://github.com/MrKai77/DynamicNotchKit
// Modified by Alexander on 2025-05-18.

import SwiftUI

@available(*, deprecated, message: "Obsolete rigid polygon shape. Use NotchGeometry and LiquidBlobCanvasView instead.")
struct NotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat

    init(
        topCornerRadius: CGFloat? = nil,
        bottomCornerRadius: CGFloat? = nil
    ) {
        self.topCornerRadius = topCornerRadius ?? 6
        self.bottomCornerRadius = bottomCornerRadius ?? 14
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get {
            .init(
                topCornerRadius,
                bottomCornerRadius
            )
        }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.minY + topCornerRadius
            ),
            control: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.maxY - bottomCornerRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topCornerRadius + bottomCornerRadius,
                y: rect.maxY
            ),
            control: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - topCornerRadius - bottomCornerRadius,
                y: rect.maxY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.maxY - bottomCornerRadius
            ),
            control: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.minY + topCornerRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX,
                y: rect.minY
            ),
            control: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        return path
    }
}

/// Continuous squircle geometry representing the notch container.
/// Features concave outward ears at the top that blend into the hardware notch,
/// with Apple continuous curvature on bottom chin corners.
public struct DynamicIslandShape: Shape {
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat
    public var isFloating: Bool
    public var waterSag: CGFloat
    public var waterIrregularity: CGFloat
    public var waterSeed: CGFloat

    public init(
        topCornerRadius: CGFloat = 6.0,
        bottomCornerRadius: CGFloat = 14.0,
        isFloating: Bool = false,
        waterSag: CGFloat = 0.0,
        waterIrregularity: CGFloat = 0.0,
        waterSeed: CGFloat = 42.0
    ) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.isFloating = isFloating
        self.waterSag = waterSag
        self.waterIrregularity = waterIrregularity
        self.waterSeed = waterSeed
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get {
            AnimatablePair(topCornerRadius, bottomCornerRadius)
        }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        let rTop = max(topCornerRadius, 0)
        let rBot = max(bottomCornerRadius, 0)

        if isFloating {
            // Smooth pill/capsule shape with highly rounded corners
            let corner = rect.height <= 44 ? (rect.height / 2.0) : min(rect.height / 2.0, max(rBot, 24.0))
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: corner, height: corner),
                style: .continuous
            )
            return path
        }

        // Notch shape with concave top ears and continuous bottom corners
        let minX = rect.minX
        let maxX = rect.maxX
        // Extend top boundary 1pt into the bezel area on notched displays to eliminate any subpixel Retina seam/halo
        let minY = rect.minY - 1.0
        let maxY = rect.maxY

        // Start at top-left ear origin
        path.move(to: CGPoint(x: minX, y: minY))

        // Concave top-left ear: curves downward and inward into notch left side
        path.addQuadCurve(
            to: CGPoint(x: minX + rTop, y: minY + rTop),
            control: CGPoint(x: minX + rTop, y: minY)
        )

        // Downward vertical left edge
        path.addLine(to: CGPoint(x: minX + rTop, y: maxY - rBot))

        // Convex bottom-left corner with Apple continuous smoothing
        path.addCurve(
            to: CGPoint(x: minX + rTop + rBot, y: maxY),
            control1: CGPoint(x: minX + rTop, y: maxY - rBot * 0.448),
            control2: CGPoint(x: minX + rTop + rBot * 0.448, y: maxY)
        )

        // Bottom horizontal chin edge (Apple continuous squircle)
        let leftX = minX + rTop + rBot
        let rightX = maxX - rTop - rBot
        path.addLine(to: CGPoint(x: rightX, y: maxY))

        // Convex bottom-right corner with Apple continuous smoothing
        path.addCurve(
            to: CGPoint(x: maxX - rTop, y: maxY - rBot),
            control1: CGPoint(x: maxX - rTop - rBot * 0.448, y: maxY),
            control2: CGPoint(x: maxX - rTop, y: maxY - rBot * 0.448)
        )

        // Upward vertical right edge
        path.addLine(to: CGPoint(x: maxX - rTop, y: minY + rTop))

        // Concave top-right ear: curves outward to top-right
        path.addQuadCurve(
            to: CGPoint(x: maxX, y: minY),
            control: CGPoint(x: maxX - rTop, y: minY)
        )

        // Top horizontal edge closing the shape
        path.addLine(to: CGPoint(x: minX, y: minY))

        return path
    }
}
