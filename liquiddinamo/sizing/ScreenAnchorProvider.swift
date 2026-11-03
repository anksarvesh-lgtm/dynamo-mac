//
//  ScreenAnchorProvider.swift
//  LiquidDynamo
//
//  Created for Production Dynamic Island Architecture.
//  Maintains persistent notch-anchored coordinate spaces and guarantees fixed wing positions.
//

import AppKit
import Combine
import Foundation
import SwiftUI

/// Precise geometric anchor descriptors for persistent overlay window and 3-region composition.
public struct ScreenAnchor: Equatable, Sendable {
    public let screenUUID: String
    public let screenFrame: CGRect
    public let hasPhysicalNotch: Bool
    public let notchHeight: CGFloat
    public let rawNotchWidth: CGFloat
    
    /// Global screen coordinate of the notch top center.
    public let screenNotchCenter: CGPoint
    
    /// Stable, persistent reserved overlay window frame in macOS screen coordinates.
    /// This frame remains constant across expand/collapse cycles to prevent window jitter and preserve wing anchors.
    public let persistentWindowFrame: CGRect
    
    /// Fixed local rect for Left Wing within the persistent window coordinate space.
    public let localLeftWingFrame: CGRect
    
    /// Fixed local rect for Right Wing within the persistent window coordinate space.
    public let localRightWingFrame: CGRect
    
    /// Local resting notch frame within the persistent window coordinate space.
    public let localNotchRestingFrame: CGRect
    
    /// Maximum safe width and height available for central island expansion.
    public let maxExpansionSize: CGSize
}

@MainActor
public final class ScreenAnchorProvider: ObservableObject {
    public static let shared = ScreenAnchorProvider()
    
    @Published public private(set) var primaryAnchor: ScreenAnchor
    @Published public private(set) var anchorsByScreen: [String: ScreenAnchor] = [:]
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Initial fallback
        let initialAnchor = ScreenAnchor(
            screenUUID: "default",
            screenFrame: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900),
            hasPhysicalNotch: false,
            notchHeight: 32.0,
            rawNotchWidth: 160.0,
            screenNotchCenter: CGPoint(x: 720, y: 900),
            persistentWindowFrame: CGRect(x: 320, y: 640, width: 800, height: 260),
            localLeftWingFrame: CGRect(x: 180, y: 228, width: 130, height: 32),
            localRightWingFrame: CGRect(x: 490, y: 228, width: 130, height: 32),
            localNotchRestingFrame: CGRect(x: 320, y: 228, width: 160, height: 32),
            maxExpansionSize: CGSize(width: 780, height: 240)
        )
        self.primaryAnchor = initialAnchor
        
        recalculateAnchors()
        setupSystemObservers()
    }
    
    private func setupSystemObservers() {
        // Screen parameters / resolution / scaling changed
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculateAnchors()
            }
            .store(in: &cancellables)
            
        // System / Screen wake
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculateAnchors()
            }
            .store(in: &cancellables)
            
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculateAnchors()
            }
            .store(in: &cancellables)
    }
    
    public func recalculateAnchors() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        var newAnchors: [String: ScreenAnchor] = [:]
        
        for screen in screens {
            let uuid = screen.displayUUID ?? "screen_\(screen.hashValue)"
            let geom = NotchSafeAreaEngine.shared.geometry(for: screen)
            
            let screenFrame = screen.frame
            let notchH = geom.notchHeight
            let rawW = geom.rawNotchWidth > 0 ? geom.rawNotchWidth : (geom.hasPhysicalNotch ? 160.0 : 140.0)
            
            // Fixed reserved persistent window width & height covering notch, maximum wings, and 2x expansion
            let reservedW: CGFloat = min(max(780.0, rawW + 480.0), screenFrame.width - 40.0)
            let reservedH: CGFloat = min(notchH + 230.0, screenFrame.height * 0.45)
            
            // Horizontal center of notch in global screen coords
            let centerX = screenFrame.minX + (screenFrame.width / 2.0)
            let windowX = centerX - (reservedW / 2.0)
            let windowY = screenFrame.maxY - reservedH
            let persistentWinFrame = CGRect(x: windowX, y: windowY, width: reservedW, height: reservedH)
            
            // In AppKit window local coords (bottom-left origin):
            // Top of window is at y = reservedH
            let localTopY = reservedH
            let localCenterX = reservedW / 2.0
            
            let restingNotchX = localCenterX - (rawW / 2.0)
            let restingNotchY = localTopY - notchH
            let localRestingNotch = CGRect(x: restingNotchX, y: restingNotchY, width: rawW, height: notchH)
            
            // Left Wing: strictly positioned to the left of the physical notch resting frame
            let wingW: CGFloat = 135.0
            let wingH: CGFloat = notchH
            let leftWingX = restingNotchX - wingW - 6.0
            let localLeftWing = CGRect(x: leftWingX, y: restingNotchY, width: wingW, height: wingH)
            
            // Right Wing: strictly positioned to the right of the physical notch resting frame
            let rightWingX = restingNotchX + rawW + 6.0
            let localRightWing = CGRect(x: rightWingX, y: restingNotchY, width: wingW, height: wingH)
            
            let anchor = ScreenAnchor(
                screenUUID: uuid,
                screenFrame: screenFrame,
                hasPhysicalNotch: geom.hasPhysicalNotch,
                notchHeight: notchH,
                rawNotchWidth: rawW,
                screenNotchCenter: CGPoint(x: centerX, y: screenFrame.maxY),
                persistentWindowFrame: persistentWinFrame,
                localLeftWingFrame: localLeftWing,
                localRightWingFrame: localRightWing,
                localNotchRestingFrame: localRestingNotch,
                maxExpansionSize: CGSize(width: reservedW - 40.0, height: reservedH - 20.0)
            )
            
            newAnchors[uuid] = anchor
        }
        
        self.anchorsByScreen = newAnchors
        
        // Resolve primary screen (prefer built-in notch display, otherwise primary screen)
        if let builtIn = screens.first(where: {
            if let num = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                return CGDisplayIsBuiltin(CGDirectDisplayID(num.uint32Value)) != 0
            }
            return false
        }), let anchor = newAnchors[builtIn.displayUUID ?? ""] {
            self.primaryAnchor = anchor
        } else if let mainScreen = NSScreen.main, let anchor = newAnchors[mainScreen.displayUUID ?? ""] {
            self.primaryAnchor = anchor
        } else if let first = newAnchors.values.first {
            self.primaryAnchor = first
        }
    }
    
    public func anchor(for screenUUID: String?) -> ScreenAnchor {
        guard let uuid = screenUUID, let anchor = anchorsByScreen[uuid] else {
            return primaryAnchor
        }
        return anchor
    }
}

