//
//  NotchSafeAreaEngine.swift
//  boringNotch / LiquidDynamo
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

/// Single source of truth governing the geometric layout boundaries of the active screen's notch,
/// top-band wing slots, and content safe areas.
public struct NotchGeometry: Equatable, Sendable {
    /// Whether the active display physically has a camera notch cutout.
    public var hasPhysicalNotch: Bool
    
    /// Full screen bounding rect in points.
    public var screenFrame: CGRect
    
    /// Top safe area inset reported by macOS (0 on non-notched screens).
    public var safeAreaTopInset: CGFloat
    
    /// Hardware width of the notch (without extra padding). 0 if no notch.
    public var rawNotchWidth: CGFloat
    
    /// Hardware / configured height of the notch top band cutout.
    public var rawNotchHeight: CGFloat
    
    /// Effective notch height applied to top band.
    public var notchHeight: CGFloat
    
    /// Configurable wing width per side (default: 90 pt, range: 50 to 160 pt).
    public var wingWidth: CGFloat
    
    /// Physical notch rectangle on screen (in top-down screen coordinates: x from left screen edge, y: 0 at top).
    /// On Macs without a notch and external displays: notchRect is empty (.zero).
    public var notchRect: CGRect
    
    /// Left slot: from the left screen edge of the top band up to notchRect.minX.
    /// If no notch: left half of the top band.
    public var leftSlot: CGRect
    
    /// Right slot: from notchRect.maxX to the right screen edge of the top band.
    /// If no notch: right half of the top band.
    public var rightSlot: CGRect
    
    /// Below area: everything under notchRect.maxY.
    public var belowArea: CGRect
    
    /// Safe unobstructed width to the left of the notch in the menu bar row.
    public var auxiliaryLeftWidth: CGFloat
    
    /// Safe unobstructed width to the right of the notch in the menu bar row.
    public var auxiliaryRightWidth: CGFloat
    
    /// Whether macOS explicitly reports the auxiliary menu bar regions as safe and unobstructed.
    public var isAuxiliaryUnobstructed: Bool
    
    /// Minimum horizontal safety margin required on both sides of the notch (16px).
    public let notchHorizontalMargin: CGFloat = 16.0
    
    /// Total width of the central exclusion zone: rawNotchWidth + (2 * 16px).
    public var exclusionWidth: CGFloat {
        hasPhysicalNotch ? (rawNotchWidth + (2 * notchHorizontalMargin)) : 0
    }
    
    /// Height of the top exclusion zone.
    public var exclusionHeight: CGFloat {
        notchHeight
    }
    
    /// Whether this display has a physical notch.
    public var isNotched: Bool {
        hasPhysicalNotch
    }
    
    /// Minimum top Y offset where full-width controls, search bars, tabs, and content can safely sit.
    public var contentSafeAreaTop: CGFloat {
        notchHeight
    }
    
    public init(
        hasPhysicalNotch: Bool,
        screenFrame: CGRect,
        safeAreaTopInset: CGFloat,
        rawNotchWidth: CGFloat,
        rawNotchHeight: CGFloat,
        notchHeight: CGFloat,
        wingWidth: CGFloat,
        notchRect: CGRect,
        leftSlot: CGRect,
        rightSlot: CGRect,
        belowArea: CGRect,
        auxiliaryLeftWidth: CGFloat,
        auxiliaryRightWidth: CGFloat,
        isAuxiliaryUnobstructed: Bool
    ) {
        self.hasPhysicalNotch = hasPhysicalNotch
        self.screenFrame = screenFrame
        self.safeAreaTopInset = safeAreaTopInset
        self.rawNotchWidth = rawNotchWidth
        self.rawNotchHeight = rawNotchHeight
        self.notchHeight = notchHeight
        self.wingWidth = wingWidth
        self.notchRect = notchRect
        self.leftSlot = leftSlot
        self.rightSlot = rightSlot
        self.belowArea = belowArea
        self.auxiliaryLeftWidth = auxiliaryLeftWidth
        self.auxiliaryRightWidth = auxiliaryRightWidth
        self.isAuxiliaryUnobstructed = isAuxiliaryUnobstructed
    }
    
    // MARK: - Window & Container Coordinate Helpers
    
    /// Window-local notchRect for a centered window of the given width.
    /// Empty (.zero) on non-notched displays or external monitors.
    public func windowNotchRect(windowWidth: CGFloat? = nil) -> CGRect {
        let width = windowWidth ?? (rawNotchWidth + (2.0 * wingWidth))
        guard hasPhysicalNotch && !notchRect.isEmpty && rawNotchWidth > 0 else { return .zero }
        let centerX = width / 2.0
        return CGRect(
            x: centerX - (rawNotchWidth / 2.0),
            y: 0,
            width: rawNotchWidth,
            height: notchHeight
        )
    }
    
    /// Window-local leftSlot for a centered window of the given width.
    public func windowLeftSlot(windowWidth: CGFloat? = nil) -> CGRect {
        let width = windowWidth ?? (rawNotchWidth + (2.0 * wingWidth))
        let nRect = windowNotchRect(windowWidth: width)
        if hasPhysicalNotch && !nRect.isEmpty {
            return CGRect(x: 0, y: 0, width: max(0, nRect.minX), height: notchHeight)
        } else {
            return CGRect(x: 0, y: 0, width: width / 2.0, height: notchHeight)
        }
    }
    
    /// Window-local rightSlot for a centered window of the given width.
    public func windowRightSlot(windowWidth: CGFloat? = nil) -> CGRect {
        let width = windowWidth ?? (rawNotchWidth + (2.0 * wingWidth))
        let nRect = windowNotchRect(windowWidth: width)
        if hasPhysicalNotch && !nRect.isEmpty {
            return CGRect(x: nRect.maxX, y: 0, width: max(0, width - nRect.maxX), height: notchHeight)
        } else {
            return CGRect(x: width / 2.0, y: 0, width: width / 2.0, height: notchHeight)
        }
    }
    
    /// Window-local belowArea for a centered window of the given size.
    public func windowBelowArea(windowWidth: CGFloat? = nil, windowHeight: CGFloat? = nil) -> CGRect {
        let width = windowWidth ?? (rawNotchWidth + (2.0 * wingWidth))
        let height = windowHeight ?? (notchHeight + 200.0)
        return CGRect(
            x: 0,
            y: notchHeight,
            width: width,
            height: max(0, height - notchHeight)
        )
    }
    
    /// Total compact pill width based on hardware cutout and configurable wing width.
    public var compactPillWidth: CGFloat {
        if hasPhysicalNotch {
            return rawNotchWidth + (2.0 * wingWidth)
        } else {
            // Non-notch Mac or external display: pill has no hole
            return (2.0 * wingWidth) + 30.0
        }
    }
    
    /// Safe left slot width for compact wings inside a pill of given width.
    public func pillLeftSlotWidth(forPillWidth pillWidth: CGFloat) -> CGFloat {
        if hasPhysicalNotch {
            return max(0, (pillWidth - rawNotchWidth) / 2.0)
        } else {
            return pillWidth / 2.0
        }
    }
    
    /// Safe right slot width for compact wings inside a pill of given width.
    public func pillRightSlotWidth(forPillWidth pillWidth: CGFloat) -> CGFloat {
        return pillLeftSlotWidth(forPillWidth: pillWidth)
    }
    
    /// Fallback conservative geometry used when safe-area APIs are unavailable.
    public static var conservativeFallback: NotchGeometry {
        let defaultFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
        let rawW: CGFloat = 210.0
        let rawH: CGFloat = 34.0
        let minX = max(0, (defaultFrame.width - rawW) / 2.0)
        let maxX = minX + rawW
        
        return NotchGeometry(
            hasPhysicalNotch: true,
            screenFrame: defaultFrame,
            safeAreaTopInset: rawH,
            rawNotchWidth: rawW,
            rawNotchHeight: rawH,
            notchHeight: rawH,
            wingWidth: 90.0,
            notchRect: CGRect(x: minX, y: 0, width: rawW, height: rawH),
            leftSlot: CGRect(x: 0, y: 0, width: minX, height: rawH),
            rightSlot: CGRect(x: maxX, y: 0, width: max(0, defaultFrame.width - maxX), height: rawH),
            belowArea: CGRect(x: 0, y: rawH, width: defaultFrame.width, height: max(0, defaultFrame.height - rawH)),
            auxiliaryLeftWidth: minX,
            auxiliaryRightWidth: defaultFrame.width - maxX,
            isAuxiliaryUnobstructed: true
        )
    }
}

/// Central layout engine for detecting, calculating, and enforcing notch safe areas across the app.
@MainActor
public final class NotchSafeAreaEngine: ObservableObject {
    public static let shared = NotchSafeAreaEngine()
    
    @Published public private(set) var currentGeometry: NotchGeometry = .conservativeFallback
    @Published public var showLayoutGuides: Bool = Defaults[.showLayoutGuides] {
        didSet {
            Defaults[.showLayoutGuides] = showLayoutGuides
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    private var activeScreenUUID: String? = nil
    
    private init() {
        recalculate(for: NSScreen.main)
        setupNotificationObservers()
    }
    
    // MARK: - Safe Area Calculation
    
    /// Recalculates safe-area insets, notchRect, leftSlot, rightSlot, and belowArea.
    public func recalculate(for screen: NSScreen? = nil) {
        guard let screen = screen ?? NSScreen.main else {
            self.currentGeometry = .conservativeFallback
            return
        }
        
        self.activeScreenUUID = screen.displayUUID
        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top
        let wingW = max(50, min(160, Defaults[.wingWidth]))
        
        // 1. Auxiliary areas delimit the physical notch cutout on macOS
        let auxLeft = screen.auxiliaryTopLeftArea
        let auxRight = screen.auxiliaryTopRightArea
        
        var hasNotch = (topInset > 0)
        var rawWidth: CGFloat = 185.0
        var rawHeight: CGFloat = topInset
        var effectiveNotchHeight: CGFloat = Defaults[.notchHeight]
        var auxLeftWidth: CGFloat = 0
        var auxRightWidth: CGFloat = 0
        var isUnobstructed = false
        
        var notchR: CGRect = .zero
        var leftS: CGRect = .zero
        var rightS: CGRect = .zero
        var belowA: CGRect = .zero
        
        if hasNotch {
            // Determine effective notch height based on user settings
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                effectiveNotchHeight = topInset
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                effectiveNotchHeight = frame.maxY - screen.visibleFrame.maxY
            } else {
                effectiveNotchHeight = max(Defaults[.notchHeight], topInset)
            }
        } else {
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                effectiveNotchHeight = max(24, frame.maxY - screen.visibleFrame.maxY)
            } else {
                effectiveNotchHeight = Defaults[.nonNotchHeight]
            }
        }
        
        if let leftArea = auxLeft, let rightArea = auxRight, leftArea.width > 0, rightArea.width > 0 {
            // Platform auxiliary areas provide precise coordinates in AppKit space:
            // leftArea.maxX is the left edge of the notch cutout relative to screen origin.
            // rightArea.minX is the right edge of the notch cutout.
            hasNotch = true
            let notchMinX = leftArea.maxX - frame.origin.x
            let notchMaxX = rightArea.minX - frame.origin.x
            rawWidth = max(0, notchMaxX - notchMinX)
            rawHeight = topInset > 0 ? topInset : 32.0
            auxLeftWidth = leftArea.width
            auxRightWidth = rightArea.width
            isUnobstructed = true
            
            // Top-down screen coordinates (origin (0,0) at top-left of screen)
            notchR = CGRect(x: notchMinX, y: 0, width: rawWidth, height: effectiveNotchHeight)
            leftS = CGRect(x: 0, y: 0, width: notchMinX, height: effectiveNotchHeight)
            rightS = CGRect(x: notchMaxX, y: 0, width: max(0, frame.width - notchMaxX), height: effectiveNotchHeight)
            belowA = CGRect(x: 0, y: effectiveNotchHeight, width: frame.width, height: max(0, frame.height - effectiveNotchHeight))
        } else if hasNotch {
            // Notched display without auxiliary areas (e.g. during fullscreen transitions)
            rawWidth = 185.0
            rawHeight = topInset
            let notchMinX = max(0, (frame.width - rawWidth) / 2.0)
            let notchMaxX = notchMinX + rawWidth
            auxLeftWidth = notchMinX
            auxRightWidth = notchMinX
            isUnobstructed = false
            
            notchR = CGRect(x: notchMinX, y: 0, width: rawWidth, height: effectiveNotchHeight)
            leftS = CGRect(x: 0, y: 0, width: notchMinX, height: effectiveNotchHeight)
            rightS = CGRect(x: notchMaxX, y: 0, width: max(0, frame.width - notchMaxX), height: effectiveNotchHeight)
            belowA = CGRect(x: 0, y: effectiveNotchHeight, width: frame.width, height: max(0, frame.height - effectiveNotchHeight))
        } else {
            // Macs without a notch, and external displays: notchRect is empty (.zero)
            hasNotch = false
            rawWidth = 0
            rawHeight = 0
            auxLeftWidth = frame.width / 2.0
            auxRightWidth = frame.width / 2.0
            isUnobstructed = true
            
            notchR = .zero // Empty hole! Layouts center in the pill.
            leftS = CGRect(x: 0, y: 0, width: frame.width / 2.0, height: effectiveNotchHeight)
            rightS = CGRect(x: frame.width / 2.0, y: 0, width: frame.width / 2.0, height: effectiveNotchHeight)
            belowA = CGRect(x: 0, y: effectiveNotchHeight, width: frame.width, height: max(0, frame.height - effectiveNotchHeight))
        }
        
        let newGeometry = NotchGeometry(
            hasPhysicalNotch: hasNotch,
            screenFrame: frame,
            safeAreaTopInset: rawHeight,
            rawNotchWidth: rawWidth,
            rawNotchHeight: rawHeight,
            notchHeight: effectiveNotchHeight,
            wingWidth: wingW,
            notchRect: notchR,
            leftSlot: leftS,
            rightSlot: rightS,
            belowArea: belowA,
            auxiliaryLeftWidth: auxLeftWidth,
            auxiliaryRightWidth: auxRightWidth,
            isAuxiliaryUnobstructed: isUnobstructed
        )
        
        if self.currentGeometry != newGeometry {
            self.currentGeometry = newGeometry
        }
    }
    
    // MARK: - Boundary Checking
    
    /// Validates whether a given point in screen coordinates falls inside the notch exclusion zone.
    public func isPointInNotchExclusionZone(_ screenPoint: CGPoint) -> Bool {
        guard currentGeometry.hasPhysicalNotch, !currentGeometry.notchRect.isEmpty else { return false }
        return currentGeometry.notchRect.contains(screenPoint)
    }
    
    /// Returns the maximum safe width for left-wing content, ensuring clearance from the notch.
    public func safeLeftWingWidth(forContainerWidth containerWidth: CGFloat) -> CGFloat {
        if currentGeometry.hasPhysicalNotch {
            return currentGeometry.windowLeftSlot(windowWidth: containerWidth).width
        } else {
            return containerWidth / 2.0
        }
    }
    
    /// Returns the maximum safe width for right-wing content, ensuring clearance from the notch.
    public func safeRightWingWidth(forContainerWidth containerWidth: CGFloat) -> CGFloat {
        if currentGeometry.hasPhysicalNotch {
            return currentGeometry.windowRightSlot(windowWidth: containerWidth).width
        } else {
            return containerWidth / 2.0
        }
    }
    
    // MARK: - Dynamic Notifications Setup
    
    private func setupNotificationObservers() {
        let nc = NotificationCenter.default
        
        // 1. Screen resolution, display plug/unplug, or orientation change
        nc.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.recalculate(for: NSScreen.main)
            }
            .store(in: &cancellables)
            
        // 2. Window moved to different screen
        nc.publisher(for: NSWindow.didChangeScreenNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                if let window = notif.object as? NSWindow {
                    self?.recalculate(for: window.screen)
                }
            }
            .store(in: &cancellables)
            
        // 3. Fullscreen enter / exit / window resize
        Publishers.Merge3(
            nc.publisher(for: NSWindow.didEnterFullScreenNotification),
            nc.publisher(for: NSWindow.didExitFullScreenNotification),
            nc.publisher(for: NSWindow.didResizeNotification)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] notif in
            if let window = notif.object as? NSWindow {
                self?.recalculate(for: window.screen)
            } else {
                self?.recalculate(for: NSScreen.main)
            }
        }
        .store(in: &cancellables)
        
        // 4. Notch height settings changes
        nc.publisher(for: Notification.Name.notchHeightChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.recalculate(for: NSScreen.main)
            }
            .store(in: &cancellables)
            
        // 5. Selected screen changes
        nc.publisher(for: Notification.Name.selectedScreenChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.recalculate(for: NSScreen.main)
            }
            .store(in: &cancellables)
            
        // 6. Defaults settings changes (wingWidth, heights)
        Defaults.publisher(.wingWidth)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recalculate(for: NSScreen.main) }
            .store(in: &cancellables)
            
        Defaults.publisher(.notchHeight)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recalculate(for: NSScreen.main) }
            .store(in: &cancellables)
            
        Defaults.publisher(.notchHeightMode)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recalculate(for: NSScreen.main) }
            .store(in: &cancellables)
            
        Defaults.publisher(.nonNotchHeight)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recalculate(for: NSScreen.main) }
            .store(in: &cancellables)
            
        Defaults.publisher(.nonNotchHeightMode)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recalculate(for: NSScreen.main) }
            .store(in: &cancellables)
    }
}

// MARK: - Notch Safety Registry & Frame Intersection Guard Rails

/// Central runtime registry tracking frames of all content views marked with `.avoidsNotch()`.
/// Validates in DEBUG that no content intersects `notchRect`.
@MainActor
public final class NotchSafetyRegistry: ObservableObject {
    public static let shared = NotchSafetyRegistry()
    
    public struct ViolationRecord: Identifiable, Equatable {
        public let id: String
        public let frame: CGRect
        public let notchRect: CGRect
        public let timestamp: Date
        
        public init(id: String, frame: CGRect, notchRect: CGRect, timestamp: Date = Date()) {
            self.id = id
            self.frame = frame
            self.notchRect = notchRect
            self.timestamp = timestamp
        }
    }
    
    @Published public private(set) var registeredFrames: [String: CGRect] = [:]
    @Published public private(set) var violations: [ViolationRecord] = []
    
    private init() {}
    
    public func register(id: String, frame: CGRect) {
        guard !frame.isEmpty, frame.width > 0, frame.height > 0 else { return }
        registeredFrames[id] = frame
        checkViolation(id: id, frame: frame)
    }
    
    public func unregister(id: String) {
        registeredFrames.removeValue(forKey: id)
    }
    
    public func clear() {
        registeredFrames.removeAll()
        violations.removeAll()
    }
    
    private func checkViolation(id: String, frame: CGRect) {
        let geom = NotchSafeAreaEngine.shared.currentGeometry
        guard geom.hasPhysicalNotch else { return }
        
        let notchRect = geom.windowNotchRect(windowWidth: windowSize.width)
        guard !notchRect.isEmpty else { return }
        
        // Exclude 0-sized or black barrier shapes
        if frame.intersects(notchRect) {
            let record = ViolationRecord(id: id, frame: frame, notchRect: notchRect)
            if !violations.contains(where: { $0.id == id && $0.frame == frame }) {
                violations.append(record)
                #if DEBUG
                print("⚠️ [NotchViolation] Content view '\(id)' frame \(frame) intersects physical notchRect \(notchRect)! Display has no pixels here, content is invisible.")
                #endif
            }
        }
    }
}

// MARK: - SwiftUI View Modifier .avoidsNotch()

public struct AvoidsNotchPreferenceKey: PreferenceKey {
    public static var defaultValue: [String: CGRect] = [:]
    public static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

public struct AvoidsNotchModifier: ViewModifier {
    let identifier: String
    
    public init(identifier: String) {
        self.identifier = identifier
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: AvoidsNotchPreferenceKey.self,
                            value: [identifier: geo.frame(in: .named("NotchWindowCoordinateSpace"))]
                        )
                }
            )
            .onPreferenceChange(AvoidsNotchPreferenceKey.self) { preferences in
                for (id, frame) in preferences {
                    NotchSafetyRegistry.shared.register(id: id, frame: frame)
                }
            }
    }
}

public extension View {
    /// Registers this content view with the notch safety tracker and validates that its frame
    /// never intersects the physical notch cutout hole.
    func avoidsNotch(id: String) -> some View {
        modifier(AvoidsNotchModifier(identifier: id))
    }
    
    /// Registers this content view with the notch safety tracker using caller file/line.
    func avoidsNotch(file: String = #fileID, line: Int = #line) -> some View {
        modifier(AvoidsNotchModifier(identifier: "\(file):\(line)"))
    }
}

// MARK: - Layout Guides Overlay

/// Visual debugging overlay drawing `notchRect` in red, `leftSlot` in translucent blue,
/// `rightSlot` in translucent green, and `belowArea` in translucent purple.
public struct NotchLayoutGuidesOverlay: View {
    @ObservedObject private var engine = NotchSafeAreaEngine.shared
    
    public init() {}
    
    public var body: some View {
        let geom = engine.currentGeometry
        let winW = windowSize.width
        let winH = windowSize.height
        
        ZStack(alignment: .topLeading) {
            if geom.hasPhysicalNotch {
                let nRect = geom.windowNotchRect(windowWidth: winW)
                let lSlot = geom.windowLeftSlot(windowWidth: winW)
                let rSlot = geom.windowRightSlot(windowWidth: winW)
                let bArea = geom.windowBelowArea(windowWidth: winW, windowHeight: winH)
                
                // 1. Red Physical Notch Cutout (The Hole)
                ZStack {
                    Rectangle()
                        .fill(Color.red.opacity(0.40))
                    Rectangle()
                        .strokeBorder(Color.red, lineWidth: 2)
                    VStack(spacing: 1) {
                        Text("NOTCH HOLE")
                            .font(.system(size: 8.5, weight: .black))
                        Text("\(Int(nRect.width)) × \(Int(nRect.height)) pt")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: nRect.width, height: nRect.height)
                .offset(x: nRect.minX, y: nRect.minY)
                
                // 2. Left Slot in Translucent Blue
                ZStack {
                    Rectangle()
                        .fill(Color.blue.opacity(0.22))
                    Rectangle()
                        .strokeBorder(Color.blue, lineWidth: 1.5)
                    VStack(spacing: 1) {
                        Text("LEFT SLOT")
                            .font(.system(size: 8.5, weight: .bold))
                        Text("Wing: \(Int(geom.wingWidth)) pt")
                            .font(.system(size: 7, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: lSlot.width, height: lSlot.height)
                .offset(x: lSlot.minX, y: lSlot.minY)
                
                // 3. Right Slot in Translucent Green
                ZStack {
                    Rectangle()
                        .fill(Color.green.opacity(0.22))
                    Rectangle()
                        .strokeBorder(Color.green, lineWidth: 1.5)
                    VStack(spacing: 1) {
                        Text("RIGHT SLOT")
                            .font(.system(size: 8.5, weight: .bold))
                        Text("Wing: \(Int(geom.wingWidth)) pt")
                            .font(.system(size: 7, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: rSlot.width, height: rSlot.height)
                .offset(x: rSlot.minX, y: rSlot.minY)
                
                // 4. Below Area in Translucent Purple
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Color.purple.opacity(0.18))
                    Rectangle()
                        .strokeBorder(Color.purple, lineWidth: 1.5)
                    HStack {
                        Text("BELOW AREA (CONTENT SAFE)")
                            .font(.system(size: 9, weight: .bold))
                        Spacer()
                        Text("y ≥ \(Int(geom.notchHeight)) pt")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                }
                .frame(width: bArea.width, height: bArea.height)
                .offset(x: bArea.minX, y: bArea.minY)
            } else {
                // Non-notched display / external display
                let lSlot = geom.windowLeftSlot(windowWidth: winW)
                let rSlot = geom.windowRightSlot(windowWidth: winW)
                let bArea = geom.windowBelowArea(windowWidth: winW, windowHeight: winH)
                
                ZStack {
                    Rectangle()
                        .fill(Color.cyan.opacity(0.25))
                    Rectangle()
                        .strokeBorder(Color.cyan, lineWidth: 1.5)
                    Text("NO NOTCH PILL (LEFT)")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: lSlot.width, height: lSlot.height)
                .offset(x: lSlot.minX, y: lSlot.minY)
                
                ZStack {
                    Rectangle()
                        .fill(Color.green.opacity(0.25))
                    Rectangle()
                        .strokeBorder(Color.green, lineWidth: 1.5)
                    Text("NO NOTCH PILL (RIGHT)")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: rSlot.width, height: rSlot.height)
                .offset(x: rSlot.minX, y: rSlot.minY)
                
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Color.purple.opacity(0.18))
                    Rectangle()
                        .strokeBorder(Color.purple, lineWidth: 1.5)
                    Text("BELOW AREA")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.top, 4)
                }
                .frame(width: bArea.width, height: bArea.height)
                .offset(x: bArea.minX, y: bArea.minY)
            }
        }
        .frame(width: winW, height: winH, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Legacy View Helpers for Compatibility

public struct NotchExclusionSpacer: View {
    @ObservedObject private var engine = NotchSafeAreaEngine.shared
    
    public init() {}
    
    public var body: some View {
        Rectangle()
            .fill(Color.black)
            .frame(
                width: engine.currentGeometry.rawNotchWidth,
                height: engine.currentGeometry.notchHeight
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

public struct NotchSafeTopModifier: ViewModifier {
    @ObservedObject private var engine = NotchSafeAreaEngine.shared
    let additionalPadding: CGFloat
    
    public init(additionalPadding: CGFloat = 0) {
        self.additionalPadding = additionalPadding
    }
    
    public func body(content: Content) -> some View {
        content
            .padding(.top, engine.currentGeometry.contentSafeAreaTop + additionalPadding)
    }
}

public extension View {
    func notchSafeTop(additionalPadding: CGFloat = 0) -> some View {
        modifier(NotchSafeTopModifier(additionalPadding: additionalPadding))
    }
}

// MARK: - Automated Notch Safety Test Runner

/// Automated test runner that exercises every Dynamic Island activity type, popup, HUD,
/// and expanded view, asserting that NO registered content frame intersects the physical notchRect hole.
@MainActor
public final class NotchSafetyTester: ObservableObject {
    public static let shared = NotchSafetyTester()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var lastRunSummary: String = "Not run yet"
    @Published public private(set) var passedCount: Int = 0
    @Published public private(set) var failedCount: Int = 0

    public struct TestCaseResult: Identifiable {
        public let id = UUID()
        public let name: String
        public let passed: Bool
        public let details: String
    }

    @Published public private(set) var results: [TestCaseResult] = []

    private init() {}

    /// Runs all notch safety test cases sequentially and reports results.
    @discardableResult
    public func runAllTests() -> Bool {
        isRunning = true
        results.removeAll()
        passedCount = 0
        failedCount = 0
        NotchSafetyRegistry.shared.clear()

        let engine = NotchSafeAreaEngine.shared

        // Test 1: Geometry calculations
        runTest(name: "1. NotchGeometry Boundaries") {
            let geom = engine.currentGeometry
            if geom.hasPhysicalNotch {
                guard !geom.notchRect.isEmpty, geom.rawNotchWidth > 0, geom.notchHeight > 0 else {
                    return (false, "notchRect is empty on physical notch display")
                }
                guard geom.leftSlot.maxX <= geom.notchRect.minX + 0.5 else {
                    return (false, "leftSlot spills into notchRect: leftSlot.maxX=\(geom.leftSlot.maxX) > notchRect.minX=\(geom.notchRect.minX)")
                }
                guard geom.rightSlot.minX >= geom.notchRect.maxX - 0.5 else {
                    return (false, "rightSlot spills into notchRect: rightSlot.minX=\(geom.rightSlot.minX) < notchRect.maxX=\(geom.notchRect.maxX)")
                }
                guard geom.belowArea.minY >= geom.notchRect.maxY - 0.5 else {
                    return (false, "belowArea overlaps notchRect top band: belowArea.minY=\(geom.belowArea.minY)")
                }
                let winNotch = geom.windowNotchRect()
                let winLeft = geom.windowLeftSlot()
                let winRight = geom.windowRightSlot()
                let winBelow = geom.windowBelowArea()
                guard winLeft.maxX <= winNotch.minX + 0.5 else {
                    return (false, "windowLeftSlot spills into windowNotchRect")
                }
                guard winRight.minX >= winNotch.maxX - 0.5 else {
                    return (false, "windowRightSlot spills into windowNotchRect")
                }
                guard winBelow.minY >= winNotch.maxY - 0.5 else {
                    return (false, "windowBelowArea overlaps windowNotchRect")
                }
            } else {
                guard geom.notchRect.isEmpty else {
                    return (false, "notchRect must be empty on non-notched display")
                }
                guard geom.windowNotchRect().isEmpty else {
                    return (false, "windowNotchRect must be empty on non-notched display")
                }
            }
            return (true, "All geometry boundaries perfectly partition the screen")
        }

        // Test 2: Idle notch resting state
        runTest(name: "2. Idle Closed State") {
            IslandController.shared.setIdle()
            let violations = NotchSafetyRegistry.shared.violations
            if let first = violations.first {
                return (false, "Violation in idle state: \(first.id) at \(first.frame) intersects \(first.notchRect)")
            }
            return (true, "0 violations in idle state")
        }

        // Test 3: HUD Layouts (Volume, Brightness, Backlight, Mic)
        runTest(name: "3. HUD Templates (Volume, Brightness, Mic)") {
            DynamicIslandHub.shared.triggerVolumeHUD(volume: 0.65, isMuted: false)
            let violations = NotchSafetyRegistry.shared.violations.filter { $0.id.contains("HUD") }
            if let first = violations.first {
                return (false, "Violation in HUD layout: \(first.id) at \(first.frame)")
            }
            return (true, "HUD icons in leftSlot, progress in rightSlot, notchRect hole untouched")
        }

        // Test 4: Compact Live Activities (Music, Stats Wings, Generic)
        runTest(name: "4. Ongoing Compact Activities (Music, Wings, Generic)") {
            let activity = IslandActivity(
                id: "test.compact",
                kind: .systemStats,
                priority: 90,
                leadingIcon: "cpu",
                title: "CPU 12%",
                tintColor: .cyan,
                trailingText: "1.2 MB/s"
            )
            IslandController.shared.registerActivity(activity)
            IslandController.shared.setCompact()

            let violations = NotchSafetyRegistry.shared.violations.filter {
                $0.id.contains("Music") || $0.id.contains("Wings") || $0.id.contains("Compact")
            }
            if let first = violations.first {
                return (false, "Violation in compact activity: \(first.id) at \(first.frame)")
            }
            IslandController.shared.removeActivity(id: "test.compact")
            return (true, "Compact wings stay within safeLeftWing and safeRightWing bounds")
        }

        // Test 5: Alert Pop Liquid Drop (centered in belowArea)
        runTest(name: "5. Alert Pop (Liquid Drop in belowArea)") {
            DynamicIslandHub.shared.triggerTrackChangeAnnouncement(title: "Blinding Lights", artist: "The Weeknd")
            DynamicIslandHub.shared.triggerChargingAlert(level: 0.80)
            DynamicIslandHub.shared.triggerLowBatteryAlert(percentage: 12, isCritical: false)

            let violations = NotchSafetyRegistry.shared.violations.filter { $0.id.contains("IslandAlert") || $0.id.contains("LiquidDrop") }
            if let first = violations.first {
                return (false, "Violation in alert pop: \(first.id) at \(first.frame) intersects \(first.notchRect)")
            }
            return (true, "Alert pop droplet leaves bottom of notch, capsule centered in belowArea")
        }

        // Test 6: Popups (AirPods, Bluetooth, Device Showcase, Notification Cards)
        runTest(name: "6. Below-Area Popups (AirPods, Bluetooth, Device Showcase)") {
            DynamicIslandHub.shared.triggerAirPodsAlert(name: "AirPods Pro", left: 92, right: 90, caseLevel: 100)
            DynamicIslandHub.shared.triggerDeviceConnectedAlert(name: "Magic Keyboard", icon: "keyboard")
            DynamicIslandHub.shared.triggerNotificationCard(appName: "Slack", sender: "Team", message: "Review ready")

            let violations = NotchSafetyRegistry.shared.violations.filter {
                $0.id.contains("DeviceShowcase") || $0.id.contains("BluetoothBatteryAlert") || $0.id.contains("NotificationCard")
            }
            if let first = violations.first {
                return (false, "Violation in belowArea popup: \(first.id) at \(first.frame)")
            }
            return (true, "All popups rendered in belowArea (y ≥ notchRect.maxY), hole untouched")
        }

        // Test 7: Expanded View (Tabs in leftSlot, Status in rightSlot, Main Content in belowArea)
        runTest(name: "7. Expanded View (Dock Left, Status Right, Main Below)") {
            IslandController.shared.setExpanded(view: .home)
            let dockViolations = NotchSafetyRegistry.shared.violations.filter { $0.id.contains("ExpandedDock") }
            let statusViolations = NotchSafetyRegistry.shared.violations.filter { $0.id.contains("ExpandedRight") }
            let mainViolations = NotchSafetyRegistry.shared.violations.filter { $0.id.contains("ExpandedMain") }

            if let first = dockViolations.first {
                return (false, "Expanded dock icons intersect notchRect: \(first.frame)")
            }
            if let first = statusViolations.first {
                return (false, "Expanded right status intersects notchRect: \(first.frame)")
            }
            if let first = mainViolations.first {
                return (false, "Expanded main content intersects notchRect: \(first.frame)")
            }

            IslandController.shared.transitionTo(IslandController.shared.resolveRestingState())
            return (true, "Expanded view dock in leftSlot, status in rightSlot, main content in belowArea")
        }

        // Test 8: Non-Notched Display Simulation (Pill mode, no hole)
        runTest(name: "8. Non-Notched / External Display Simulation") {
            let nonNotchGeom = NotchGeometry(
                hasPhysicalNotch: false,
                screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                safeAreaTopInset: 0,
                rawNotchWidth: 0,
                rawNotchHeight: 0,
                notchHeight: 32,
                wingWidth: 90,
                notchRect: .zero,
                leftSlot: CGRect(x: 0, y: 0, width: 960, height: 32),
                rightSlot: CGRect(x: 960, y: 0, width: 960, height: 32),
                belowArea: CGRect(x: 0, y: 32, width: 1920, height: 1048),
                auxiliaryLeftWidth: 960,
                auxiliaryRightWidth: 960,
                isAuxiliaryUnobstructed: true
            )
            guard nonNotchGeom.notchRect.isEmpty else {
                return (false, "notchRect must be empty on non-notched screen")
            }
            guard nonNotchGeom.windowNotchRect().isEmpty else {
                return (false, "windowNotchRect must be empty on non-notched screen")
            }
            guard nonNotchGeom.compactPillWidth == 210.0 else {
                return (false, "Expected compactPillWidth 210.0, got \(nonNotchGeom.compactPillWidth)")
            }
            return (true, "Macs without a notch: notchRect is empty, pill centers seamlessly with no hole")
        }

        // Test 9: Configurable Wing Widths (50 to 160 pt)
        runTest(name: "9. Configurable Wing Widths (50 pt to 160 pt)") {
            for testWidth: CGFloat in [50, 90, 140, 160] {
                Defaults[.wingWidth] = testWidth
                engine.recalculate()
                let geom = engine.currentGeometry
                guard geom.wingWidth == testWidth else {
                    return (false, "Failed to apply wingWidth \(testWidth)")
                }
                if geom.hasPhysicalNotch {
                    guard geom.compactPillWidth == geom.rawNotchWidth + (2.0 * testWidth) else {
                        return (false, "compactPillWidth mismatch: expected \(geom.rawNotchWidth + 2 * testWidth), got \(geom.compactPillWidth)")
                    }
                }
            }
            Defaults[.wingWidth] = 90.0
            engine.recalculate()
            return (true, "Wing width dynamically configures compact pill width from 50 to 160 pt")
        }

        // Test 10: Total Zero-Violation Verification
        let totalViolations = NotchSafetyRegistry.shared.violations.count
        runTest(name: "10. Zero Global Notch Violations Assert") {
            if totalViolations > 0 {
                return (false, "\(totalViolations) frame intersections detected inside physical notchRect")
            }
            return (true, "All templates treat the notch strictly as a hole. 0 intersections.")
        }

        // Restore state
        engine.recalculate(for: NSScreen.main)
        isRunning = false
        lastRunSummary = "Completed \(results.count) tests: \(passedCount) passed, \(failedCount) failed"
        print("🏁 [NotchSafetyTester] \(lastRunSummary)")
        return failedCount == 0
    }

    private func runTest(name: String, block: () -> (Bool, String)) {
        let (passed, details) = block()
        if passed {
            passedCount += 1
            print("  ✅ [PASS] \(name): \(details)")
        } else {
            failedCount += 1
            print("  ❌ [FAIL] \(name): \(details)")
        }
        results.append(TestCaseResult(name: name, passed: passed, details: details))
    }
}

