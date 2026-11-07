import AppKit
import IslandCore
import Observation
import SwiftUI

/// Drives the Island UI: combines activity state, presentation state, geometry and preferences.
/// Owns hover-intent / collapse timing. Features never touch this type directly.
@MainActor
@Observable
final class IslandViewModel {
    let manager: ActivityManager
    let settings: IslandSettings
    let accessibility: AccessibilityMonitor
    @ObservationIgnored var commands: CommandRouter
    /// AirPods connection animation (separate component; the Island only reads its reveal state).
    @ObservationIgnored var airPods: AirPodsConnectionAnimator?

    private(set) var presentation = IslandPresentation()
    private(set) var geometry: NotchGeometry?
    var searchHeight: CGFloat = 0
    /// Measured natural height of each expanded layout (content only), learned from the live view.
    private(set) var measuredContent: [ExpandedStyle: CGFloat] = [:]
    /// Bumped on every mode change; useful for diagnostics and tests.
    private(set) var transitionCount = 0
    private(set) var isAnimating = false

    @ObservationIgnored private var hoverWork: DispatchWorkItem?
    @ObservationIgnored private var collapseWork: DispatchWorkItem?
    @ObservationIgnored private var transientWork: DispatchWorkItem?
    @ObservationIgnored private var animationEndWork: DispatchWorkItem?
    @ObservationIgnored private(set) var mouseInside = false
    @ObservationIgnored var onModeChange: ((IslandMode) -> Void)?
    /// Recent input → mode transitions (diagnostics; shown in the debug dump).
    @ObservationIgnored private(set) var trace: [String] = []
    private func note(_ s: String) {
        trace.append(String(format: "%.3f ", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 100)) + s)
        if trace.count > 40 { trace.removeFirst(trace.count - 40) }
    }

    init(manager: ActivityManager, settings: IslandSettings, accessibility: AccessibilityMonitor, commands: CommandRouter) {
        self.manager = manager
        self.settings = settings
        self.accessibility = accessibility
        self.commands = commands
        presentation.hoverExpansionEnabled = settings.hoverExpansion
        observeActivities()
    }

    // MARK: Derived state

    var mode: IslandMode { presentation.mode }
    var primary: Activity? { manager.primary }
    var secondaries: [Activity] { manager.secondaries }

    var metrics: IslandMetrics {
        IslandMetrics(
            notchSize: geometry?.notchSize ?? CGSize(width: DisplayResolver.virtualNotchWidth, height: 32),
            hasNotch: geometry?.hasNotch ?? false,
            scale: settings.islandScale,
            expandedCornerRadius: settings.cornerRadius
        )
    }

    var compactStyle: CompactStyle { ActivityPresentation.compactStyle(for: primary, showsTitle: settings.compactShowsTitle) }
    /// Secondary activities shown inside the compact Island.
    var minimals: [Activity] { mode == .compact ? Array(secondaries.prefix(IslandMetrics.maxMinimals)) : [] }
    var horizontalOffset: CGFloat { metrics.horizontalOffset(mode: mode, compact: compactStyle, minimals: minimals.count) }
    var expandedStyle: ExpandedStyle { ActivityPresentation.expandedStyle(for: primary) }

    var islandSize: CGSize {
        metrics.size(mode: mode, compact: compactStyle, expanded: expandedStyle, searchHeight: searchHeight,
                     measuredContent: measuredContent[expandedStyle], minimals: minimals.count)
    }


    var reduceMotion: Bool { settings.forceReduceMotion || accessibility.reduceMotion }
    var reduceTransparency: Bool { settings.forceReduceTransparency || accessibility.reduceTransparency }
    var highContrast: Bool { settings.forceHighContrast || accessibility.increaseContrast }

    /// Everything the Core Animation surface needs to draw the current state.
    var surfaceGeometry: IslandSurfaceView.Geometry {
        let m = metrics, size = islandSize
        let ear = m.topEarRadius(mode: mode)
        let open = mode == .expanded || mode == .search
        let compactGlass = mode == .compact && settings.compactGlass
        let glass = reduceTransparency ? 0 : (open || compactGlass ? settings.glassIntensity : 0)
        return IslandSurfaceView.Geometry(
            width: size.width + 2 * ear, height: max(size.height, 0.5), earRadius: ear,
            bottomRadius: m.bottomCornerRadius(mode: mode, height: size.height), offsetX: horizontalOffset,
            glass: glass, clearGlass: compactGlass, visible: mode != .idle || m.hasNotch, highContrast: highContrast)
    }

    var morphAnimation: Animation { IslandAnimation.morph(reduceMotion: reduceMotion, speed: settings.animationSpeed) }

    /// Window-local hit rect (anchor-relative, y downward).
    var hitRect: CGRect { metrics.hitRect(islandSize: islandSize, offset: horizontalOffset, mode: mode) }

    // MARK: Geometry

    func updateGeometry(_ g: NotchGeometry?) { geometry = g }

    /// Called by the expanded layout with its natural content height. Ignores sub-point jitter.
    func reportContentHeight(_ h: CGFloat, for style: ExpandedStyle) {
        guard h.isFinite, h > 0 else { return }
        let rounded = h.rounded(.up)
        if let old = measuredContent[style], abs(old - rounded) < 1 { return }
        withAnimation(morphAnimation) { measuredContent[style] = rounded }
    }

    // MARK: Input

    func mouseInsideChanged(_ inside: Bool) {
        guard inside != mouseInside else { return }
        mouseInside = inside
        note("pointer \(inside ? "in" : "out")")
        hoverWork?.cancel()
        if inside {
            collapseWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.apply(.hoverBegan) }
            hoverWork = work
            let delay = mode == .compact || mode == .idle ? settings.hoverDelay : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            guard presentation.hovering || mode == .expanded else { return }
            let work = DispatchWorkItem { [weak self] in self?.apply(.hoverEnded) }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + settings.collapseDelay, execute: work)
        }
    }

    func click() { apply(.click) }
    func clickOutside() { apply(.clickOutside) }
    func escape() { apply(.escape) }
    func toggleSearch() { apply(.toggleSearch) }
    func expand() { apply(.expand) }
    func collapse() { apply(.collapse) }

    func presentTransient(seconds: TimeInterval) {
        apply(.presentTransient)
        transientWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.apply(.transientEnded) }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func settingsChanged() {
        presentation.hoverExpansionEnabled = settings.hoverExpansion
    }

    func apply(_ input: IslandInput) {
        var next = presentation
        next.hoverExpansionEnabled = settings.hoverExpansion
        next.handle(input)
        guard next != presentation else { return }
        let modeChanged = next.mode != presentation.mode
        note("\(input) → \(next.mode.rawValue)\(modeChanged ? "" : " (same)")")
        let opening = !presentation.isExpanded && next.isExpanded
        let closing = presentation.isExpanded && !next.isExpanded
        _ = (opening, closing)
        // The outline springs in Core Animation (IslandSurfaceView); SwiftUI only fades content.
        withAnimation(IslandAnimation.contentChange(reduceMotion: reduceMotion)) { presentation = next }
        if modeChanged {
            transitionCount += 1
            markAnimating()
            if next.mode == .expanded, settings.hapticFeedback {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            #if DEBUG
            if ProcessInfo.processInfo.environment["ISLAND_TRACE"] != nil { NSLog("Island mode → %@ (%@)", next.mode.rawValue, String(describing: input)) }
            #endif
            onModeChange?(next.mode)
        }
        scheduleAutoCollapse()
    }

    private func scheduleAutoCollapse() {
        collapseWork?.cancel()
        guard settings.autoCollapse, presentation.mode == .expanded, presentation.reason == .click, !mouseInside else { return }
        let work = DispatchWorkItem { [weak self] in self?.apply(.autoCollapse) }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.autoCollapseDelay, execute: work)
    }

    private func markAnimating() {
        isAnimating = true
        animationEndWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.isAnimating = false }
        animationEndWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 / settings.animationSpeed, execute: work)
    }

    private func observeActivities() {
        manager.onChange = { [weak self] in self?.activitiesChanged() }
        activitiesChanged()
    }

    /// Synchronous, so the presentation can never drift from the activity state.
    private func activitiesChanged() {
        let has = manager.primary != nil
        if has != presentation.hasActivity { apply(.activityAvailabilityChanged(hasActivity: has)) }
    }
}
