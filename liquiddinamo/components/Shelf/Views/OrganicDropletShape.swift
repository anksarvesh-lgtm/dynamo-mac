//
//  OrganicDropletShape.swift
//  LiquidDynamo
//
//  Soft organic droplet mask shape for thumbnails, previews, and liquid touches.
//

import SwiftUI

public struct OrganicDropletShape: InsettableShape {
    public var pinch: CGFloat = 0.15
    public var insetAmount: CGFloat = 0

    public init(pinch: CGFloat = 0.15, insetAmount: CGFloat = 0) {
        self.pinch = pinch
        self.insetAmount = insetAmount
    }

    public func inset(by amount: CGFloat) -> OrganicDropletShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    public func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        let w = max(insetRect.width, 1)
        let h = max(insetRect.height, 1)
        let ox = insetRect.origin.x
        let oy = insetRect.origin.y

        let top = CGPoint(x: ox + w * 0.50, y: oy)
        let right = CGPoint(x: ox + w, y: oy + h * 0.52)
        let bottom = CGPoint(x: ox + w * 0.50, y: oy + h)
        let left = CGPoint(x: ox, y: oy + h * 0.52)

        path.move(to: top)
        path.addCurve(
            to: right,
            control1: CGPoint(x: ox + w * (0.50 + pinch), y: oy),
            control2: CGPoint(x: ox + w, y: oy + h * 0.32)
        )
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: ox + w, y: oy + h * 0.78),
            control2: CGPoint(x: ox + w * 0.78, y: oy + h)
        )
        path.addCurve(
            to: left,
            control1: CGPoint(x: ox + w * 0.22, y: oy + h),
            control2: CGPoint(x: ox, y: oy + h * 0.78)
        )
        path.addCurve(
            to: top,
            control1: CGPoint(x: ox, y: oy + h * 0.32),
            control2: CGPoint(x: ox + w * (0.50 - pinch), y: oy)
        )
        path.closeSubpath()
        return path
    }
}
