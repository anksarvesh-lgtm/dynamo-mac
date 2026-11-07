// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import SwiftUI

/// One display's notch: owns its engine and fixed panel, turns AppKit input into engine events,
/// and mirrors presentation changes onto the panel. Purely event-driven: no polling.
@MainActor
final class NotchController {
    let engine = NotchEngine()
    let displayID: CGDirectDisplayID
    /// Called after every presentation change.
    var onPresentationChange: (() -> Void)?
    /// The display's frame in global coordinates.
    var screenFrame: CGRect { metrics.screen }

    private let metrics: NotchMetrics
    private let preferences: NotchPreferences
    private let panel: NotchWindow
    private var scrollMonitor: Any?
    private var clickAwayMonitors: [Any] = []
    private var keyObservers: [NSObjectProtocol] = []

    /// `standIn` is the notch to draw when the display has none; without one, it gets the pill.
    init(screen: NSScreen, content: NotchContent, preferences: NotchPreferences, standIn: CGSize?) {
        displayID = screen.displayID
        metrics = NotchMetrics(screen: screen, standIn: standIn)
        self.preferences = preferences
        panel = NotchWindow(frame: metrics.panelFrame)
        let view = NotchView(engine: engine, metrics: metrics, preferences: preferences, content: content)
        panel.contentView = NotchHostingView(rootView: view)
        panel.onCancel = { [weak self] in self?.engine.send(.dismiss) }
        engine.onPresentationChange = { [weak self] old, new in self?.render(from: old, to: new) }
        engine.pointerCheck = { [weak self] in
            PointerCheck(
                isInside: self?.notchFrame().contains(NSEvent.mouseLocation) ?? false,
                isButtonDown: NSEvent.pressedMouseButtons != 0)
        }

        // The panel only becomes key for text entry, so key status is the focused state.
        let center = NotificationCenter.default
        keyObservers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.engine.send(.beginTextInput) }
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.engine.send(.endTextInput) }
            },
        ]
        // A two-finger pull down on the resting notch opens it. Local monitors only see events
        // already addressed to this app, so this costs nothing while the pointer is elsewhere.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handleScroll(event) }
            return event
        }
        Log.surface.info("Notch on display \(self.displayID, privacy: .public), notch: \(self.metrics.notch != nil)")
    }

    /// Makes the panel key so a text field in it can take typing, without activating the app. Key
    /// status moves the notch to its focused state, and closing hands the keyboard back.
    func focusKeyboard() {
        panel.makeKeyAndOrderFront(nil)
    }

    /// Tears the notch down. Call before dropping the controller.
    func close() {
        stopClickAway()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        engine.send(.hide)
        panel.close()
    }

    private func render(from old: NotchPresentationState, to new: NotchPresentationState) {
        switch new {
        case .hidden, .suspended: panel.orderOut(nil)
        default: if !panel.isVisible { panel.orderFrontRegardless() }
        }
        let open = new.openTab != nil
        if open != (old.openTab != nil) {
            open ? startClickAway() : stopClickAway()
        }
        if !open, panel.isKeyWindow { handBackKeyboard() }
        onPresentationChange?()
    }

    /// The notch closed while it still had the keyboard (Escape, or collapsing mid-typing): give
    /// the keyboard back to the app the user was in. Ordering the panel out and in drops its key
    /// status; waiting for the collapse to finish makes that invisible, since the compact notch sits
    /// over the black camera housing. (Doing it on every tab switch is what used to flicker.)
    private func handBackKeyboard() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, panel.isKeyWindow, panel.isVisible, engine.state.presentation.openTab == nil else { return }
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    /// Where the pointer counts as over the notch as it's drawn right now, in screen coordinates.
    private func notchFrame() -> CGRect {
        let size = metrics.size(for: engine.state, expanded: preferences.expandedSize)
        return metrics.hoverFrame(for: size, in: panel.frame).offsetBy(dx: metrics.offset(for: engine.state), dy: 0)
    }

    private func handleScroll(_ event: NSEvent) {
        guard event.window === panel else { return }
        switch engine.state.presentation {
        case .compact, .hoverArmed, .transient:
            // With natural scrolling the delta follows the fingers; otherwise it's inverted.
            let delta = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
            let fingersDown = delta > 4
            if fingersDown { engine.send(.clicked) }
        default:
            break
        }
    }

    /// Watches for clicks outside the notch only while it's open, so a resting notch never wakes
    /// for other apps' clicks. Global monitors see other apps; the local one sees our other windows.
    private func startClickAway() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            MainActor.assumeIsolated { self?.engine.send(.clickedOutside) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self.panel { self.engine.send(.clickedOutside) }
            }
            return event
        }
        clickAwayMonitors = [global, local].compactMap { $0 }
    }

    private func stopClickAway() {
        clickAwayMonitors.forEach(NSEvent.removeMonitor)
        clickAwayMonitors = []
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// The display's UUID, which, unlike its ID, stays the same across reconnects and restarts.
    public var uuid: String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return "\(displayID)" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Whether it has a camera notch of its own.
    public var hasNotch: Bool { safeAreaInsets.top > 0 }
}
