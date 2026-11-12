//
//  FullscreenDetectorCore.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team
//  Copyright © 2026 Agrigence. All rights reserved.
//

import CoreGraphics
import Foundation

public enum FullscreenDetectionPolicy: Equatable, Sendable {
    case always
    case nowPlayingOnly
    case never
}

public struct FullscreenScreenDescriptor: Equatable, Sendable {
    public let screenUUID: String
    public let frame: CGRect
    public let safeAreaTopInset: CGFloat

    public init(screenUUID: String, frame: CGRect, safeAreaTopInset: CGFloat) {
        self.screenUUID = screenUUID
        self.frame = frame
        self.safeAreaTopInset = safeAreaTopInset
    }
}

public struct FullscreenWindowDescriptor: Equatable, Sendable {
    public let ownerPID: Int32
    public let ownerBundleIdentifier: String?
    public let ownerName: String?
    public let bounds: CGRect
    public let layer: Int
    public let isOnScreen: Bool

    public init(
        ownerPID: Int32,
        ownerBundleIdentifier: String?,
        ownerName: String? = nil,
        bounds: CGRect,
        layer: Int,
        isOnScreen: Bool
    ) {
        self.ownerPID = ownerPID
        self.ownerBundleIdentifier = ownerBundleIdentifier
        self.ownerName = ownerName
        self.bounds = bounds
        self.layer = layer
        self.isOnScreen = isOnScreen
    }
}

public enum FullscreenDetectorEvaluator {
    private static let alignmentTolerance: CGFloat = 2.0
    private static let minimumTopAllowance: CGFloat = 40.0
    private static let excludedBundleIdentifiers: Set<String> = [
        "com.apple.dock",
        "com.apple.windowmanager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui"
    ]

    public static func primaryHeight(for screens: [FullscreenScreenDescriptor]) -> CGFloat {
        if let menuBarScreen = screens.first(where: { abs($0.frame.origin.x) <= 0.5 && abs($0.frame.origin.y) <= 0.5 }) {
            return menuBarScreen.frame.height
        }
        return screens.first?.frame.height ?? 0
    }

    public static func convertAppKitScreenFrameToCG(
        _ frame: CGRect,
        primaryScreenHeight: CGFloat
    ) -> CGRect {
        let cgY = primaryScreenHeight - frame.maxY
        return CGRect(x: frame.origin.x, y: cgY, width: frame.width, height: frame.height)
    }

    public static func evaluate(
        screens: [FullscreenScreenDescriptor],
        windows: [FullscreenWindowDescriptor],
        primaryScreenHeight: CGFloat,
        excludedPID: Int32? = nil,
        policy: FullscreenDetectionPolicy,
        activeMediaBundleIdentifier: String? = nil
    ) -> [String: Bool] {
        guard !screens.isEmpty, primaryScreenHeight > 0 else {
            return [:]
        }

        var status: [String: Bool] = [:]
        for screen in screens {
            status[screen.screenUUID] = false
        }

        guard policy != .never else {
            return status
        }

        let normalizedMediaBundle: String?
        if policy == .nowPlayingOnly {
            guard let candidate = activeMediaBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !candidate.isEmpty else {
                return status
            }
            normalizedMediaBundle = candidate.lowercased()
        } else {
            normalizedMediaBundle = nil
        }

        for screen in screens {
            let screenCG = convertAppKitScreenFrameToCG(
                screen.frame,
                primaryScreenHeight: primaryScreenHeight
            )
            let topAllowance = max(screen.safeAreaTopInset, minimumTopAllowance)

            let hasFullscreenWindow = windows.contains { window in
                guard isCandidateWindow(
                    window,
                    excludedPID: excludedPID,
                    requiredBundleLowercased: normalizedMediaBundle
                ) else {
                    return false
                }
                return windowCoversScreen(
                    window.bounds,
                    screenCG: screenCG,
                    topAllowance: topAllowance
                )
            }
            status[screen.screenUUID] = hasFullscreenWindow
        }

        return status
    }

    private static func isCandidateWindow(
        _ window: FullscreenWindowDescriptor,
        excludedPID: Int32?,
        requiredBundleLowercased: String?
    ) -> Bool {
        guard window.isOnScreen,
              window.layer == 0,
              window.bounds.width > 0,
              window.bounds.height > 0 else {
            return false
        }
        if let excludedPID, window.ownerPID == excludedPID {
            return false
        }
        let lowerBundle = window.ownerBundleIdentifier?.lowercased()
        if let lowerBundle, excludedBundleIdentifiers.contains(lowerBundle) {
            return false
        }
        if let requiredBundleLowercased {
            guard lowerBundle == requiredBundleLowercased else {
                return false
            }
        }
        return true
    }

    private static func windowCoversScreen(
        _ windowBounds: CGRect,
        screenCG: CGRect,
        topAllowance: CGFloat
    ) -> Bool {
        guard screenCG.width > 0, screenCG.height > 0 else {
            return false
        }
        guard abs(windowBounds.minX - screenCG.minX) <= alignmentTolerance,
              abs(windowBounds.width - screenCG.width) <= alignmentTolerance else {
            return false
        }
        guard windowBounds.minY >= screenCG.minY - alignmentTolerance,
              windowBounds.minY <= screenCG.minY + topAllowance + alignmentTolerance,
              abs(windowBounds.maxY - screenCG.maxY) <= alignmentTolerance,
              windowBounds.height >= screenCG.height - topAllowance - alignmentTolerance else {
            return false
        }
        return true
    }
}
