// SPDX-License-Identifier: MIT
import AppKit
import NotchCore

/// Sizes and placement of one display's notch surface. Measurements come from PUBLIC AppKit APIs
/// (safeAreaInsets, auxiliaryTop*Area): no private frameworks. The math is pure, so tests run it
/// against representative displays instead of whatever screens the build machine has.
struct NotchMetrics: Equatable {
    /// The display's frame in global coordinates.
    var screen: CGRect
    /// The physical notch, a stand-in drawn on a display without one, or nil for the floating pill.
    var notch: CGSize?
    /// Where the notch is centered: the middle of the gap, which can sit a hair off the display's
    /// center (half a point left on a 14" MacBook Pro), or the display's center without a notch.
    var centerX: CGFloat

    static let flare: CGFloat = 6  // the outline's flared top corners, which meet the screen edge
    static let pill = CGSize(width: 180, height: 26)  // resting shape on a notchless display
    static let pillInset: CGFloat = 3  // gap above the floating pill
    static let hoverGrowth = CGSize(width: 12, height: 4)  // hover feedback
    static let activityWing: CGFloat = 120  // the most a live activity's row reaches past each side of the notch
    static let ongoingTab: CGFloat = 120  // the most an ongoing activity reaches beside the notch, over the menu bar
    static let wingInset: CGFloat = 10  // between an ongoing activity's symbol and the notch
    static let wingOutset: CGFloat = 12  // between its text and the tab's outer end
    static let meterDepth: CGFloat = 26  // room under the notch for a live activity's row
    static let rowPadding: CGFloat = 16  // at either end of that row
    static let labelSpacing: CGFloat = 6  // between a live activity's symbol and its text
    static let artworkSide: CGFloat = 18  // a cover shown in place of the symbol, such as what's playing
    static let overshootRoom: CGFloat = 1.08  // springy and jelly animations briefly overshoot

    /// The notch is the gap between the two auxiliary top areas; no insets means no notch, and then
    /// `standIn`, when given, is drawn in the middle of the top edge instead of the pill.
    init(screen: CGRect, safeAreaTop: CGFloat, left: CGRect?, right: CGRect?, standIn: CGSize? = nil) {
        self.screen = screen
        centerX = screen.midX
        notch = standIn
        if safeAreaTop > 0, let left, let right {
            notch = CGSize(width: max(0, right.minX - left.maxX), height: safeAreaTop)
            centerX = (left.maxX + right.minX) / 2
        }
    }

    init(screen: NSScreen, standIn: CGSize? = nil) {
        self.init(
            screen: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            left: screen.auxiliaryTopLeftArea,
            right: screen.auxiliaryTopRightArea,
            standIn: standIn
        )
    }

    /// A 14" MacBook Pro's notch is 185 pt wide: the stand-in's width when there's no real one to copy.
    static let standInWidth: CGFloat = 185
    /// macOS's menu bar on a display without a notch, when the display can't say (it hides it).
    static let menuBarHeight: CGFloat = 24

    /// The stand-in notch for a display without one: as wide as the Mac's own notch, or a
    /// MacBook's, and exactly as tall as the display's menu bar, so it sits inside the bar.
    static func standIn(on screen: NSScreen, among screens: [NSScreen]) -> CGSize {
        // Without a stand-in, a display's metrics hold only its real notch.
        let real = screens.lazy.compactMap { NotchMetrics(screen: $0).notch }.first
        let bar = screen.frame.maxY - screen.visibleFrame.maxY
        return CGSize(width: real?.width ?? standInWidth, height: bar > 0 ? bar : menuBarHeight)
    }

    /// The camera housing, or on a notchless display the pill that stands in for it.
    var housing: CGSize { notch ?? Self.pill }

    /// Resting shape: inside the camera housing, so a closed notch can't be seen. The gap between the
    /// auxiliary areas already includes the cutout's flared top corners (about 4 pt; its bottom
    /// corners are about 8 pt), so the outline's wider flare keeps its body inside the housing's
    /// sides, and it stops a point short of the housing's bottom edge. On notchless displays, a pill.
    var compactSize: CGSize {
        guard let notch else { return Self.pill }
        return CGSize(width: notch.width, height: notch.height - 1)
    }

    /// The open notch at the user's chosen size: never narrower than the notch plus room for the
    /// tabs, never larger than the display allows.
    func expandedSize(_ chosen: CGSize) -> CGSize {
        CGSize(
            width: min(max(chosen.width, housing.width + 80), screen.width - 32),
            height: min(chosen.height, screen.height * 0.6))
    }

    func size(
        for presentation: NotchPresentationState, expanded: CGSize = NotchPreferences.defaultExpandedSize
    ) -> CGSize {
        switch presentation {
        case .hidden, .suspended, .compact:
            compactSize
        case .hoverArmed:
            CGSize(width: housing.width + Self.hoverGrowth.width, height: housing.height + Self.hoverGrowth.height)
        case .transient(let activity) where activity.level != nil:
            // A level (volume, battery) keeps to the notch's width: one row under the camera housing,
            // or inside the pill.
            notch == nil
                ? housing
                : CGSize(width: housing.width + Self.hoverGrowth.width, height: housing.height + Self.meterDepth)
        case .transient(let activity):
            // Its symbol and title side by side, in a row under the camera housing or inside the pill:
            // as wide as the notch, wider for a long title, up to a ceiling.
            CGSize(
                width: min(
                    max(housing.width + (notch == nil ? 0 : Self.hoverGrowth.width), Self.rowWidth(for: activity)),
                    housing.width + Self.activityWing * 2),
                height: notch == nil ? housing.height : housing.height + Self.meterDepth)
        case .expanded, .pinned, .focused:
            expandedSize(expanded)
        }
    }

    /// The notch as `state` draws it: like `size(for:)`, but a resting notch with an ongoing activity
    /// grows a tab for it beside the camera, or shows it inside the pill, and hovered it grows a
    /// little more.
    func size(for state: NotchState, expanded: CGSize = NotchPreferences.defaultExpandedSize) -> CGSize {
        guard let resting = state.restingActivity else { return size(for: state.presentation, expanded: expanded) }
        let growth = state.presentation == .hoverArmed ? Self.hoverGrowth : .zero
        let width =
            notch == nil
            ? min(max(housing.width, Self.rowWidth(for: resting)), housing.width + Self.activityWing * 2)
            : housing.width + Self.tab(for: resting)
        return CGSize(width: width + growth.width, height: housing.height + growth.height)
    }

    /// How far the shape sits right of center: half an ongoing activity's tab, so the tab reaches out
    /// on the right while the rest stays over the camera. Zero otherwise.
    func offset(for state: NotchState) -> CGFloat {
        guard notch != nil, let resting = state.restingActivity else { return 0 }
        return Self.tab(for: resting) / 2
    }

    /// A live activity's symbol and title side by side, measured in the fonts they're drawn in. A
    /// countdown makes room for its longest reading.
    static func labelWidth(for activity: Activity, now: Date = .now) -> CGFloat {
        var text = activity.title
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        if let countdown = activity.countdown {
            text = countdown.timeIntervalSince(now) >= 3600 ? "0:00:00" : "00:00"
        }
        let symbol =
            activity.artwork != nil
            ? artworkSide
            : NSImage(systemSymbolName: activity.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))?.size.width
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return ((symbol ?? 16) + labelSpacing + width).rounded(.up)
    }

    /// A one-shot activity's row: its label with room at either end.
    static func rowWidth(for activity: Activity) -> CGFloat {
        labelWidth(for: activity) + rowPadding * 2
    }

    /// How far an ongoing activity's tab reaches beside the notch: just enough for its label, up to
    /// a ceiling, since it stays over the menu bar.
    static func tab(for activity: Activity, now: Date = .now) -> CGFloat {
        min(labelWidth(for: activity, now: now) + wingInset + wingOutset, ongoingTab)
    }

    /// Gap between the top of the display and the shape: none on a notch, a little above a pill.
    var topInset: CGFloat { notch == nil ? Self.pillInset : 0 }

    /// Where the pointer counts as over a notch of `size` in `panel`, in screen coordinates. It
    /// reaches past the top of the display: a pointer pushed against the top edge sits at exactly the
    /// display's maxY, which a rect ending there doesn't contain. The gap above a pill counts too.
    func hoverFrame(for size: CGSize, in panel: CGRect) -> CGRect {
        CGRect(
            x: panel.midX - size.width / 2, y: panel.maxY - topInset - size.height,
            width: size.width, height: size.height + topInset + 1)
    }

    /// The fixed panel: big enough for every state at the largest size the notch can be resized to,
    /// with room for springy overshoot, pinned to the top and centered on the notch. The window never
    /// moves or resizes; only the shape inside it animates.
    var panelFrame: CGRect {
        let largest = [
            size(for: .hoverArmed),
            CGSize(width: housing.width + Self.activityWing * 2, height: housing.height + Self.meterDepth),
            // An ongoing tab reaches out on one side, so it needs that much room on both.
            CGSize(width: housing.width + Self.ongoingTab * 2, height: housing.height),
            size(for: .expanded(tab: .media), expanded: NotchPreferences.maximumExpandedSize),
        ]
        let width = min(largest.map(\.width).max()! * Self.overshootRoom, screen.width)
        let height = min(largest.map(\.height).max()! * Self.overshootRoom + topInset, screen.height)
        return CGRect(x: centerX - width / 2, y: screen.maxY - height, width: width, height: height)
    }
}
