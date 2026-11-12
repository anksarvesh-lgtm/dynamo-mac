//
//  NotchToolbarLayoutEngine.swift
//  LiquidDynamo
//
//  Dynamic spatial layout allocator for the expanded Dynamic Island Toolbar.
//  Strictly prevents physical notch collision, distributes shortcuts across
//  safe left/right regions, and manages automatic overflow into the More popover.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

public struct ToolbarLayoutResult: Equatable, Sendable {
    public let leftItems: [ToolbarFeatureID]
    public let rightItems: [ToolbarFeatureID]
    public let overflowItems: [ToolbarFeatureID]
    public let showMoreButton: Bool
    public let exclusionWidth: CGFloat

    public init(
        leftItems: [ToolbarFeatureID] = [.home],
        rightItems: [ToolbarFeatureID] = [],
        overflowItems: [ToolbarFeatureID] = [],
        showMoreButton: Bool = false,
        exclusionWidth: CGFloat = 0
    ) {
        self.leftItems = leftItems
        self.rightItems = rightItems
        self.overflowItems = overflowItems
        self.showMoreButton = showMoreButton
        self.exclusionWidth = exclusionWidth
    }
}

@MainActor
public final class NotchToolbarLayoutEngine: ObservableObject {
    public static let shared = NotchToolbarLayoutEngine()

    @Published public private(set) var currentLayout: ToolbarLayoutResult = ToolbarLayoutResult()

    public let iconWidth: CGFloat = 28.0
    public let iconSpacing: CGFloat = 6.0
    public let homeWidth: CGFloat = 28.0
    public let moreWidth: CGFloat = 28.0
    public let editWidth: CGFloat = 28.0
    public let horizontalPadding: CGFloat = 20.0
    public let notchSafetyMargin: CGFloat = 16.0

    private init() {}

    /// Calculates the notch-safe distribution of feature shortcuts given the total island width and notch geometry.
    public func computeLayout(
        totalWidth: CGFloat,
        geometry: NotchGeometry,
        config: ToolbarConfig
    ) -> ToolbarLayoutResult {
        let isNotched = geometry.hasPhysicalNotch
        let slotFootprint = iconWidth + iconSpacing

        // Filter out Home from candidate shortcuts (Home is always fixed 1st on the left)
        let candidateShortcuts = config.activeOrderedFeatures.filter { $0 != .home }

        if isNotched {
            // NOTCHED MACBOOK DISPLAY:
            // Calculate central hardware camera exclusion width
            let rawNotch = max(geometry.rawNotchWidth, 160.0)
            let exclusionWidth = rawNotch + (2 * notchSafetyMargin)

            // Available space in Left Safe Region & Right Safe Region
            let halfAvailable = max(0, (totalWidth - exclusionWidth) / 2.0 - horizontalPadding)

            // Left region: reserves Home (28pt) + spacing
            let leftSpaceForShortcuts = max(0, halfAvailable - (homeWidth + iconSpacing))
            let maxLeftSlots = max(0, Int(floor((leftSpaceForShortcuts + iconSpacing) / slotFootprint)))

            // Right region: reserves Edit (28pt) + spacing
            // Case A: Test if all remaining shortcuts fit without More
            let rightSpaceNoMore = max(0, halfAvailable - (editWidth + iconSpacing))
            let maxRightSlotsNoMore = max(0, Int(floor((rightSpaceNoMore + iconSpacing) / slotFootprint)))

            let totalSlotsNoMore = maxLeftSlots + maxRightSlotsNoMore

            if candidateShortcuts.count <= totalSlotsNoMore {
                // All shortcuts fit! More button is hidden
                let leftCount = min(candidateShortcuts.count, maxLeftSlots)
                let leftItems = [.home] + Array(candidateShortcuts.prefix(leftCount))
                let rightItems = Array(candidateShortcuts.dropFirst(leftCount))

                return ToolbarLayoutResult(
                    leftItems: leftItems,
                    rightItems: rightItems,
                    overflowItems: [],
                    showMoreButton: false,
                    exclusionWidth: exclusionWidth
                )
            } else {
                // Shortcuts exceed capacity: More button is required
                let rightSpaceWithMore = max(0, halfAvailable - (editWidth + moreWidth + 2 * iconSpacing))
                let maxRightSlotsWithMore = max(0, Int(floor((rightSpaceWithMore + iconSpacing) / slotFootprint)))

                let leftCount = min(candidateShortcuts.count, maxLeftSlots)
                let leftItems = [.home] + Array(candidateShortcuts.prefix(leftCount))

                let remainingAfterLeft = Array(candidateShortcuts.dropFirst(leftCount))
                let rightCount = min(remainingAfterLeft.count, maxRightSlotsWithMore)
                let rightItems = Array(remainingAfterLeft.prefix(rightCount))
                let overflowItems = Array(remainingAfterLeft.dropFirst(rightCount))

                return ToolbarLayoutResult(
                    leftItems: leftItems,
                    rightItems: rightItems,
                    overflowItems: overflowItems,
                    showMoreButton: true,
                    exclusionWidth: exclusionWidth
                )
            }
        } else {
            // EXTERNAL DISPLAY OR NON-NOTCHED MAC:
            // Symmetrical centered layout with no physical notch hole
            let totalAvailable = max(0, totalWidth - (2 * horizontalPadding))
            // Left reserves Home (28pt), Right reserves Edit (28pt)
            let baseReserved = homeWidth + editWidth + (2 * iconSpacing)
            let spaceForShortcutsNoMore = max(0, totalAvailable - baseReserved)
            let maxSlotsNoMore = max(0, Int(floor((spaceForShortcutsNoMore + iconSpacing) / slotFootprint)))

            if candidateShortcuts.count <= maxSlotsNoMore {
                // Symmetrical split
                let totalCount = candidateShortcuts.count
                let leftCount = (totalCount + 1) / 2
                let leftItems = [.home] + Array(candidateShortcuts.prefix(leftCount))
                let rightItems = Array(candidateShortcuts.dropFirst(leftCount))

                return ToolbarLayoutResult(
                    leftItems: leftItems,
                    rightItems: rightItems,
                    overflowItems: [],
                    showMoreButton: false,
                    exclusionWidth: 0
                )
            } else {
                let spaceWithMore = max(0, totalAvailable - (baseReserved + moreWidth + iconSpacing))
                let maxSlotsWithMore = max(0, Int(floor((spaceWithMore + iconSpacing) / slotFootprint)))

                let visibleCount = min(candidateShortcuts.count, maxSlotsWithMore)
                let leftCount = (visibleCount + 1) / 2
                let rightCount = visibleCount - leftCount

                let leftItems = [.home] + Array(candidateShortcuts.prefix(leftCount))
                let rightItems = Array(candidateShortcuts[leftCount..<leftCount + rightCount])
                let overflowItems = Array(candidateShortcuts.dropFirst(leftCount + rightCount))

                return ToolbarLayoutResult(
                    leftItems: leftItems,
                    rightItems: rightItems,
                    overflowItems: overflowItems,
                    showMoreButton: true,
                    exclusionWidth: 0
                )
            }
        }
    }
}
