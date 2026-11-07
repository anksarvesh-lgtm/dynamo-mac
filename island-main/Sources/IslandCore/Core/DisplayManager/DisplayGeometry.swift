import CoreGraphics
import Foundation

/// Plain description of a screen (decoupled from NSScreen so it can be tested).
public struct ScreenDescriptor: Equatable, Sendable {
    public var id: UInt32
    public var name: String
    /// Global AppKit coordinates (origin bottom-left of the primary screen).
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var safeAreaTop: CGFloat
    public var auxiliaryTopLeft: CGRect?
    public var auxiliaryTopRight: CGRect?
    public var backingScale: CGFloat
    public var isBuiltIn: Bool
    public var isMain: Bool

    public init(id: UInt32, name: String, frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat = 0,
                auxiliaryTopLeft: CGRect? = nil, auxiliaryTopRight: CGRect? = nil, backingScale: CGFloat = 2,
                isBuiltIn: Bool = false, isMain: Bool = false) {
        self.id = id
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
        self.backingScale = backingScale
        self.isBuiltIn = isBuiltIn
        self.isMain = isMain
    }
}

public enum DisplaySelection: Codable, Equatable, Sendable, Hashable {
    /// Built-in notched display when available, else the main display.
    case automatic
    case main
    case specific(name: String)
}

/// Where the Island lives on a given screen.
public struct NotchGeometry: Equatable, Sendable {
    public var screen: ScreenDescriptor
    public var hasNotch: Bool
    /// Physical notch (or the virtual equivalent on non-notched displays), global coordinates.
    public var notchRect: CGRect
    public var menuBarHeight: CGFloat

    public var notchSize: CGSize { notchRect.size }
    /// Top-centre anchor in global coordinates — the Island always hangs from this point.
    public var anchor: CGPoint { CGPoint(x: notchRect.midX, y: screen.frame.maxY) }
}

public enum DisplayResolver {
    public static let virtualNotchWidth: CGFloat = 190
    public static let fallbackMenuBarHeight: CGFloat = 24

    public static func choose(from screens: [ScreenDescriptor], selection: DisplaySelection) -> ScreenDescriptor? {
        guard !screens.isEmpty else { return nil }
        switch selection {
        case .specific(let name):
            if let s = screens.first(where: { $0.name == name }) { return s }
            return choose(from: screens, selection: .automatic)
        case .main:
            return screens.first(where: \.isMain) ?? screens.first
        case .automatic:
            return screens.first(where: { geometry(for: $0).hasNotch })
                ?? screens.first(where: \.isMain)
                ?? screens.first
        }
    }

    public static func geometry(for s: ScreenDescriptor) -> NotchGeometry {
        let menuBar: CGFloat = {
            if s.safeAreaTop > 0 { return s.safeAreaTop }
            let h = s.frame.maxY - s.visibleFrame.maxY
            return h > 0 ? h : fallbackMenuBarHeight
        }()
        if s.safeAreaTop > 0, let left = s.auxiliaryTopLeft, let right = s.auxiliaryTopRight, right.minX > left.maxX {
            let rect = CGRect(x: left.maxX, y: s.frame.maxY - s.safeAreaTop, width: right.minX - left.maxX, height: s.safeAreaTop)
            return NotchGeometry(screen: s, hasNotch: true, notchRect: rect, menuBarHeight: menuBar)
        }
        let rect = CGRect(x: s.frame.midX - virtualNotchWidth / 2, y: s.frame.maxY - menuBar, width: virtualNotchWidth, height: menuBar)
        return NotchGeometry(screen: s, hasNotch: false, notchRect: rect, menuBarHeight: menuBar)
    }
}
