import CoreGraphics
import Foundation

/// How wide the compact wings need to be for the current primary activity.
public enum CompactStyle: Equatable, Sendable {
    /// Icon on the left, short value on the right (timer, download, battery…).
    case standard
    /// Artwork + title on the left (media).
    case wide
}

/// Content-driven expanded heights.
public enum ExpandedStyle: Equatable, Sendable {
    case home, media, timer, download, event, device, research
}

/// All Island geometry, derived from the notch. Nothing here is hard-coded to a screen.
public struct IslandMetrics: Equatable, Sendable {
    public var notchSize: CGSize
    public var hasNotch: Bool
    public var scale: CGFloat
    public var expandedCornerRadius: CGFloat

    public init(notchSize: CGSize, hasNotch: Bool, scale: CGFloat = 1, expandedCornerRadius: CGFloat = 32) {
        self.notchSize = CGSize(width: max(80, notchSize.width), height: max(18, notchSize.height))
        self.hasNotch = hasNotch
        self.scale = min(1.4, max(0.7, scale.isFinite ? scale : 1))
        self.expandedCornerRadius = min(48, max(8, expandedCornerRadius))
    }

    public var compactHeight: CGFloat { notchSize.height }
    /// Width each secondary ("minimal") activity adds inside the trailing wing.
    public var minimalSlot: CGFloat { 22 * scale }
    public static let maxMinimals = 2

    /// iPhone-sized wings: just enough for one glyph each side, so the Island covers as little of the
    /// menu bar as possible. `.wide` is used for short-lived events that need a few words.
    public func wingWidth(_ style: CompactStyle) -> CGFloat {
        switch style {
        case .standard: (compactHeight + 12) * scale
        case .wide: (compactHeight + 100) * scale
        }
    }

    /// Leading/trailing wing widths. Secondary activities sit inside the trailing wing (not floating over
    /// the menu bar), so the wings can differ; `horizontalOffset` keeps the notch gap on the notch.
    public func compactWings(_ style: CompactStyle, minimals: Int) -> (leading: CGFloat, trailing: CGFloat) {
        let base = wingWidth(style)
        let n = CGFloat(min(max(0, minimals), Self.maxMinimals))
        return (base, base + (n > 0 ? n * minimalSlot + 6 * scale : 0))
    }

    public func horizontalOffset(mode: IslandMode, compact: CompactStyle, minimals: Int) -> CGFloat {
        guard mode == .compact else { return 0 }
        let w = compactWings(compact, minimals: minimals)
        return (w.trailing - w.leading) / 2
    }

    public var expandedWidth: CGFloat { max(notchSize.width + 160, 440 * scale, notchSize.width + 2 * wingWidth(.wide) + 24) }
    public var searchWidth: CGFloat { max(notchSize.width + 220, 580 * scale) }
    public var searchMaxHeight: CGFloat { 440 * scale }

    /// Padding around expanded content (below the notch-height header row).
    public static let expandedTopPadding: CGFloat = 4
    public static let expandedBottomPadding: CGFloat = 18

    /// Best estimate of each layout's content height; the live layout's measured height replaces it.
    public func estimatedContentHeight(_ style: ExpandedStyle) -> CGFloat {
        switch style {
        case .home: 64
        case .media: 132
        case .timer: 56
        case .download: 54
        case .event: 46
        case .device: 64
        case .research: 280
        }
    }

    public func expandedHeight(_ style: ExpandedStyle, measuredContent: CGFloat? = nil) -> CGFloat {
        let content = measuredContent.map { min(max($0, 20), 320) } ?? estimatedContentHeight(style)
        return compactHeight + Self.expandedTopPadding + content + Self.expandedBottomPadding
    }


    /// Size of the main island shape for a given state.
    public func size(mode: IslandMode, compact: CompactStyle, expanded: ExpandedStyle, searchHeight: CGFloat = 0,
                     measuredContent: CGFloat? = nil, minimals: Int = 0) -> CGSize {
        switch mode {
        case .idle:
            // Hidden inside the notch. On notch-less displays it collapses to nothing at the top edge.
            return hasNotch ? notchSize : CGSize(width: notchSize.width * 0.6, height: 0)
        case .compact:
            let w = compactWings(compact, minimals: minimals)
            return CGSize(width: notchSize.width + w.leading + w.trailing, height: compactHeight)
        case .expanded:
            return CGSize(width: expandedWidth, height: expandedHeight(expanded, measuredContent: measuredContent))
        case .search:
            let h = min(searchMaxHeight, max(compactHeight + 52 * scale, searchHeight))
            return CGSize(width: searchWidth, height: h)
        }
    }

    public func bottomCornerRadius(mode: IslandMode, height: CGFloat) -> CGFloat {
        switch mode {
        case .idle, .compact: min(height / 2, max(8, compactHeight * 0.38))
        case .expanded, .search: min(height / 2, expandedCornerRadius * scale)
        }
    }

    public func topEarRadius(mode: IslandMode) -> CGFloat {
        switch mode {
        case .idle, .compact: 6
        case .expanded, .search: 12
        }
    }

    /// Fixed window size large enough for every state (window never resizes during animation).
    public var windowSize: CGSize {
        let wide = compactWings(.wide, minimals: Self.maxMinimals)
        let compactWide = notchSize.width + 2 * max(wide.leading, wide.trailing) + 24
        let w = max(searchWidth, expandedWidth, compactWide) + 80
        let h = max(searchMaxHeight, expandedHeight(.research, measuredContent: 320)) + 40
        return CGSize(width: ceil(w), height: ceil(h))
    }

    /// Interactive region relative to the top-centre anchor (y grows downward): the Island body,
    /// shifted by its horizontal offset. In idle it's the notch itself, so an empty Island can be revealed.
    public func hitRect(islandSize: CGSize, offset: CGFloat, mode: IslandMode) -> CGRect {
        var rect = CGRect(x: -islandSize.width / 2 + offset, y: 0, width: islandSize.width, height: max(islandSize.height, 1))
        if mode == .idle {
            rect = CGRect(x: -notchSize.width / 2, y: 0, width: notchSize.width, height: compactHeight)
        }
        return rect.insetBy(dx: -4, dy: 0).union(CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height + 4))
    }

}
