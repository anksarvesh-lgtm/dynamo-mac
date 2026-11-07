import AppKit
import IslandCore
import SwiftUI

/// Owns the single Island window: placement on the notch, mouse pass-through, hover detection and
/// keyboard handling. Features never reference this type — they go through ActivityManager.
@MainActor
final class IslandWindowController {
    let panel = IslandPanel()
    /// Core Animation surface (outline, glass, clip, morph). SwiftUI content lives inside it.
    let surface: IslandSurfaceView
    private var lastSurfaceMode: IslandMode = .idle
    let model: IslandViewModel
    let search: SearchViewModel
    private var monitors: [Any] = []
    /// Escape is captured as a temporary hot key while the Island is expanded, because a hover-expanded
    /// Island deliberately never takes keyboard focus from the app you're using.
    private lazy var escapeKey = HotKey { [weak self] in self?.model.escape() }
    private(set) var isVisible = false
    static let exitMargin: CGFloat = 10
    /// Pointer sampling used only near the Island: the notch/menu-bar strip belongs to no app window, so
    /// macOS doesn't reliably deliver mouse-moved events from there to monitors.
    private var proximityTimer: Timer?
    private(set) var mouseEventCount = 0
    private(set) var lastMouse: NSPoint = .zero
    var monitorCount: Int { monitors.count }
    var escapeArmed: Bool { escapeKey.isRegistered }

    init(model: IslandViewModel, search: SearchViewModel) {
        self.model = model
        self.search = search
        let host = IslandHostingView(rootView: IslandRootView(model: model, search: search).ignoresSafeArea())
        host.sizingOptions = []
        surface = IslandSurfaceView(contentHost: host)
        panel.contentView = surface
        model.onModeChange = { [weak self] mode in self?.modeChanged(mode) }
        lastSurfaceMode = model.mode
        observeSurface()
    }

    // MARK: Visibility

    func show() {
        guard !isVisible else { return }
        isVisible = true
        panel.acceptsMouseMovedEvents = true
        reposition()
        panel.orderFrontRegardless()
        installMonitors()
        refreshMouseState()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        removeMonitors()
        stopProximityPolling()
        escapeKey.unregister()
        model.collapse()
        panel.allowsKey = false
        panel.orderOut(nil)
    }

    // MARK: Geometry

    /// Pins the window's top-centre to the notch anchor. The window size is fixed per display (and even,
    /// so its centre lands exactly on the notch centre) so animations never fight a resizing window.
    func reposition() {
        guard let g = model.geometry else { return }
        var size = model.metrics.windowSize
        size.width = ceil(size.width / 2) * 2
        let scale = g.screen.backingScale > 0 ? g.screen.backingScale : 2
        let x = ((g.anchor.x - size.width / 2) * scale).rounded() / scale
        let frame = NSRect(x: x, y: g.screen.frame.maxY - size.height, width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        refreshMouseState()
    }

    /// Global rect of the Island (clicks + hover).
    var interactiveRect: NSRect { global(model.hitRect) }

    private func global(_ r: CGRect) -> NSRect {
        guard let g = model.geometry else { return .zero }
        return NSRect(x: g.anchor.x + r.minX, y: g.anchor.y - r.maxY, width: r.width, height: r.height)
    }

    // MARK: Mouse

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMouseState() }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] e in
            #if DEBUG
            if ProcessInfo.processInfo.environment["ISLAND_TRACE"] != nil { NSLog("Island global click type=%lu at %@ window=%ld", e.type.rawValue, NSStringFromPoint(NSEvent.mouseLocation), e.windowNumber) }
            #endif
            MainActor.assumeIsolated { self?.handleOutsideClick() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.refreshMouseState() }
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] e in
            guard let self else { return e }
            nonisolated(unsafe) let event = e
            let consumed = MainActor.assumeIsolated { self.handleKey(event) }
            return consumed ? nil : e
        }) { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// Diagnostics: lets the stress test drive hover state without the real pointer interfering.
    var pointerTrackingSuspended = false

    func refreshMouseState() {
        guard isVisible, !pointerTrackingSuspended else { return }
        mouseEventCount += 1
        let location = NSEvent.mouseLocation
        lastMouse = location
        // Hysteresis: entering uses the Island's edge, leaving requires going 10 pt beyond it, so a pointer
        // resting on the boundary can't make the Island flicker open and shut.
        let wasInside = model.mouseInside
        let inside = (wasInside ? interactiveRect.insetBy(dx: -Self.exitMargin, dy: -Self.exitMargin) : interactiveRect).contains(location)
        // Outside the Island the window is fully click-through — in every mode, including search.
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        model.mouseInsideChanged(inside)
        updateProximityPolling(near: interactiveRect.insetBy(dx: -120, dy: -120).contains(location))
    }

    /// 30 Hz pointer check while the pointer is near the Island or the Island is open; off otherwise.
    private func updateProximityPolling(near: Bool) {
        let needed = near || model.presentation.isExpanded
        if needed, proximityTimer == nil {
            let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshMouseState() }
            }
            RunLoop.main.add(t, forMode: .common)
            proximityTimer = t
        } else if !needed {
            stopProximityPolling()
        }
    }

    private func stopProximityPolling() {
        proximityTimer?.invalidate()
        proximityTimer = nil
    }

    var isPollingPointer: Bool { proximityTimer != nil }

    private func handleOutsideClick() {
        guard isVisible, !interactiveRect.contains(NSEvent.mouseLocation) else { return }
        if model.mode == .expanded || model.mode == .search { model.clickOutside() }
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        guard model.mode == .search || model.mode == .expanded else { return false }
        if e.keyCode == 53 {
            model.escape()
            return true
        }
        return model.mode == .search ? search.handleKey(e) : false
    }

    // MARK: Surface

    /// Re-applies the surface geometry whenever anything it depends on changes, choosing the spring
    /// from the kind of change (opening, closing or an in-place morph).
    private func observeSurface() {
        let geometry = withObservationTracking { model.surfaceGeometry } onChange: { [weak self] in
            DispatchQueue.main.async { self?.observeSurface() }
        }
        let mode = model.mode
        let wasOpen = lastSurfaceMode == .expanded || lastSurfaceMode == .search
        let isOpen = mode == .expanded || mode == .search
        let motion: IslandSurfaceView.Motion = !wasOpen && isOpen ? .open : (wasOpen && !isOpen ? .close : .morph)
        lastSurfaceMode = mode
        surface.reduceMotion = model.reduceMotion
        surface.speed = model.settings.animationSpeed
        if surface.current != geometry { surface.apply(geometry, motion: motion) }
    }

    // MARK: Mode changes

    private func modeChanged(_ mode: IslandMode) {
        guard isVisible else { return }
        if mode == .search {
            panel.allowsKey = true
            panel.makeKeyAndOrderFront(nil)
            search.activate()
        } else {
            if panel.isKeyWindow { panel.resignKey() }
            panel.allowsKey = false
            search.deactivate()
        }
        if mode == .expanded || mode == .search {
            if !escapeKey.isRegistered { escapeKey.register(IslandShortcut(keyCode: 53, carbonModifiers: 0, display: "⎋")) }
        } else {
            escapeKey.unregister()
        }
        refreshMouseState()
    }
}
