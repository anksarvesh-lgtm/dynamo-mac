//
//  NotchGeometry.swift
//  ClaudeIsland
//
//  Geometry calculations for the notch
//

import CoreGraphics
import Foundation

/// Pure geometry calculations for the notch
struct NotchGeometry: Sendable {
    let deviceNotchRect: CGRect
    let screenRect: CGRect
    let windowHeight: CGFloat

    /// The notch rect in screen coordinates (for hit testing with global mouse position).
    /// `horizontalOffset` shifts the rect along the top edge so the live edit "drag mode"
    /// can move the visible notch and have hit-testing follow it.
    func notchScreenRect(horizontalOffset: CGFloat = 0) -> CGRect {
        CGRect(
            x: screenRect.midX - deviceNotchRect.width / 2 + horizontalOffset,
            y: screenRect.maxY - deviceNotchRect.height,
            width: deviceNotchRect.width,
            height: deviceNotchRect.height
        )
    }

    /// The opened panel rect in screen coordinates for a given size, shifted by
    /// `horizontalOffset` so the panel follows the visible notch.
    func openedScreenRect(for size: CGSize, horizontalOffset: CGFloat = 0) -> CGRect {
        // Add small padding (10px) around the panel for comfortable clicking
        let width = size.width + 10
        let height = size.height + 10
        return CGRect(
            x: screenRect.midX - width / 2 + horizontalOffset,
            y: screenRect.maxY - height,
            width: width,
            height: height
        )
    }

    /// Default expansion width for Dynamic Island wings
    var expansionWidth: CGFloat = 240

    /// The collapsed content rect including wings (notch + expansion on both sides),
    /// shifted by `horizontalOffset`.
    func collapsedScreenRect(expansionWidth: CGFloat? = nil, horizontalOffset: CGFloat = 0) -> CGRect {
        let width = expansionWidth ?? self.expansionWidth
        let totalWidth = deviceNotchRect.width + width
        return CGRect(
            x: screenRect.midX - totalWidth / 2 + horizontalOffset,
            y: screenRect.maxY - deviceNotchRect.height,
            width: totalWidth,
            height: deviceNotchRect.height
        )
    }

    /// Check if a point is in the clickable notch area (including expanded wings).
    /// `horizontalOffset` shifts the test area to match the visible notch position.
    func isPointInNotch(_ point: CGPoint, expansionWidth: CGFloat? = nil, horizontalOffset: CGFloat = 0) -> Bool {
        collapsedScreenRect(expansionWidth: expansionWidth, horizontalOffset: horizontalOffset)
            .insetBy(dx: -10, dy: -5)
            .contains(point)
    }

    /// Check if a point is in the opened panel area
    func isPointInOpenedPanel(_ point: CGPoint, size: CGSize, horizontalOffset: CGFloat = 0) -> Bool {
        openedScreenRect(for: size, horizontalOffset: horizontalOffset).contains(point)
    }

    /// Check if a point is outside the opened panel (for closing)
    func isPointOutsidePanel(_ point: CGPoint, size: CGSize, horizontalOffset: CGFloat = 0) -> Bool {
        !openedScreenRect(for: size, horizontalOffset: horizontalOffset).contains(point)
    }
}
