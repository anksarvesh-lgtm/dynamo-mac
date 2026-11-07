import CoreGraphics

/// What the island is showing.
/// Precedence: launcher > shade > banner > expanded (hover / drag) > activity > compact > collapsed.
enum IslandMode: Equatable {
    case collapsed   // matches the physical notch
    case compact     // notch + "ears" (artwork / timer ring / mic-camera-focus indicators)
    case activity    // a short live-activity HUD: volume, charger, download, AirPods, timer done…
    case banner      // a notification dropped in
    case expanded    // hover: status, timer, next event, media card
    case shade       // click: iOS/Android-style media + notification shade
    case launcher    // hotkey: Spotlight-style search
}

/// Pure description of the island's shape, shared by the SwiftUI view and the NSPanel.
///
/// Everything is one black surface flush with the top of the screen (flat top, rounded bottom,
/// uniform width), so the notch and whatever drops down read as a single thing.
struct IslandLayout: Equatable {
    var mode: IslandMode = .collapsed
    var showsMedia = false     // expanded content includes the Now Playing card
    var showsFooter = false    // expanded content includes the recent-notification / hint line
    var compactEars = false    // compact state has something to show beside the notch

    static let earWidth: CGFloat = 44
    static let shadeWidth: CGFloat = 400
    static let launcherWidth: CGFloat = 600

    // Max heights of the open content below the notch; the black surface hugs the real content,
    // these only size the (transparent) window so nothing is clipped.
    static let activityMaxHeight: CGFloat = 70
    static let expandedMaxHeight: CGFloat = 400
    static let bannerMaxHeight: CGFloat = 120
    static let shadeMaxHeight: CGFloat = 760
    static let launcherMaxHeight: CGFloat = 520

    var isBanner: Bool { mode == .banner }
    var isOpen: Bool { mode == .shade || mode == .launcher }

    var cornerRadius: CGFloat {
        switch mode {
        case .collapsed, .compact: return 12
        case .activity: return 18
        default: return 26
        }
    }

    /// Fixed width of the black surface for this mode. Once the notch is opened from a tap or hover
    /// (banner / expanded / shade) it keeps one width, so expanding further doesn't change the width.
    func surfaceWidth(_ geo: NotchGeometry) -> CGFloat {
        let w = geo.notchWidth
        switch mode {
        case .collapsed:            return w
        case .compact:              return compactEars ? w + 2 * Self.earWidth : w
        case .activity:             return min(Self.shadeWidth, w + 240)
        case .banner, .expanded, .shade:
            return Self.shadeWidth
        case .launcher:             return Self.launcherWidth
        }
    }

    /// Size of the transparent window that hosts the surface.
    func panelSize(_ geo: NotchGeometry) -> CGSize {
        let h = geo.notchHeight
        let width = surfaceWidth(geo)
        switch mode {
        case .collapsed, .compact:
            return CGSize(width: width + 16, height: h + 8)
        case .activity:
            return CGSize(width: width + 40, height: h + Self.activityMaxHeight + 20)
        case .banner:
            return CGSize(width: width + 40, height: h + Self.bannerMaxHeight + 24)
        case .expanded:
            return CGSize(width: width + 40, height: h + Self.expandedMaxHeight + 24)
        case .shade:
            return CGSize(width: width + 40, height: h + Self.shadeMaxHeight)
        case .launcher:
            return CGSize(width: width + 40, height: h + Self.launcherMaxHeight)
        }
    }
}
