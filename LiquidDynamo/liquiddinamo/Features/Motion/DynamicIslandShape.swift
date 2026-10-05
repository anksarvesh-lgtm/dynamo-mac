//
//  DynamicIslandShape.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import SwiftUI

/// Continuous squircle geometry representing the notch container.
/// Features concave outward ears at the top that blend into the hardware notch,
/// with Apple continuous curvature on bottom chin corners.
public struct DynamicIslandShape: Shape {
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat
    public var isFloating: Bool // If true (e.g. non-notch display), renders rounded top corners without ears

    public init(
        topCornerRadius: CGFloat = 6.0,
        bottomCornerRadius: CGFloat = 14.0,
        isFloating: Bool = false
    ) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.isFloating = isFloating
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
            // Floating pill/squircle on non-notch external screens
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: rBot, height: rBot),
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

        // Bottom horizontal chin edge
        path.addLine(to: CGPoint(x: maxX - rTop - rBot, y: maxY))

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
