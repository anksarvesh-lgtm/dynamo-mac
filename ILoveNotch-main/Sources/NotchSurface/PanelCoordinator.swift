// SPDX-License-Identifier: MIT
import AppKit
import NotchCore

/// Keeps one notch on the preferred display, or on every display, rebuilding them when displays
/// change, and relays sleep, display sleep, and screen lock to all of them.
@MainActor
public final class PanelCoordinator {
    /// Called whenever any notch's presentation, or the set of notches, changes.
    public var onPresentationsChange: (([NotchPresentationState]) -> Void)?

    private let preferences: NotchPreferences
    private let content: NotchContent
    private var controllers: [NotchController] = []
    private var suspensions: Set<SuspendReason> = []
    /// Ongoing activities by the feature that raised them, oldest first.
    private var ongoing: [(feature: FeatureID, activity: Activity)] = []
    private var showingAllDisplays = false
    /// The displays that had the pill when the notches were last built.
    private var builtPills: Set<String> = []
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    public init(preferences: NotchPreferences, content: NotchContent) {
        self.preferences = preferences
        self.content = content
    }

    /// Every notch's current presentation.
    public var presentations: [NotchPresentationState] { controllers.map(\.engine.state.presentation) }

    public func start() {
        showingAllDisplays = preferences.showOnAllDisplays
        rebuild()
        watchSystem()
        observeContinuously { [weak self] in
            guard let self else { return }
            let tabs = preferences.tabs
            if preferences.showOnAllDisplays != showingAllDisplays || preferences.pillDisplays != builtPills {
                showingAllDisplays = preferences.showOnAllDisplays
                rebuild()
            }
            broadcast(.setTabs(tabs))
            broadcast(.setOngoing(shownOngoing))
            onPresentationsChange?(presentations)
        }
    }

    /// Sends one event, such as a live activity, to every notch.
    public func broadcast(_ event: NotchEvent) {
        for controller in controllers { controller.engine.send(event) }
    }

    /// Opens `tab` on every notch, as if the user had chosen it.
    public func open(_ tab: FeatureID) {
        broadcast(.selectTab(tab))
    }

    /// Gives the keyboard to the first open notch, for typing started from a keyboard shortcut.
    public func focusKeyboard() {
        controllers.first { $0.engine.state.presentation.openTab != nil }?.focusKeyboard()
    }

    /// The keyboard shortcut: closes any open notch, or else opens the one on the display under the
    /// pointer (or the only one). Returns whether a notch opened.
    @discardableResult
    public func toggleNotch() -> Bool {
        if presentations.contains(where: { $0.openTab != nil }) {
            dismissAll()
            return false
        }
        guard let controller = controllerUnderPointer else { return false }
        controller.engine.send(.clicked)
        return controller.engine.state.presentation.openTab != nil
    }

    /// A tab's own shortcut: opens `tab` on the display under the pointer and gives it the keyboard,
    /// or closes it when it's already open there. Returns whether it opened.
    @discardableResult
    public func toggle(_ tab: FeatureID) -> Bool {
        // A disabled tab would open the first enabled one instead.
        guard preferences.isEnabled(tab), let controller = controllerUnderPointer else { return false }
        if controller.engine.state.presentation.openTab == tab {
            dismissAll()
            return false
        }
        controller.engine.send(.selectTab(tab))
        guard controller.engine.state.presentation.openTab == tab else { return false }
        controller.focusKeyboard()
        return true
    }

    private var controllerUnderPointer: NotchController? {
        let pointer = NSEvent.mouseLocation
        return controllers.first { $0.screenFrame.contains(pointer) } ?? controllers.first
    }

    /// Closes every open notch, pinned ones too.
    public func dismissAll() {
        for controller in controllers where controller.engine.state.presentation.openTab != nil {
            controller.engine.send(.dismiss)
        }
    }

    /// Shows `activity` on every resting notch until `feature` replaces it, or clears it with nil.
    /// With several at once the newest shows, and the others wait underneath until it clears. An
    /// update keeps its place, so a speed ticking every second can't cover a meeting's countdown, and
    /// the least urgent, the network's speed and what's playing, start out underneath the rest.
    public func setOngoing(_ activity: Activity?, for feature: FeatureID) {
        if let activity, let index = ongoing.firstIndex(where: { $0.feature == feature }) {
            ongoing[index].activity = activity
        } else {
            ongoing.removeAll { $0.feature == feature }
            let underneath: Set<FeatureID> = [.network, .media]
            if let activity {
                ongoing.insert((feature, activity), at: underneath.contains(feature) ? 0 : ongoing.count)
            }
        }
        broadcast(.setOngoing(shownOngoing))
    }

    /// The newest ongoing activity whose feature is enabled.
    private var shownOngoing: Activity? {
        ongoing.last { preferences.isEnabled($0.feature) }?.activity
    }

    /// Opens every closed notch and closes it again, to preview the open and close animation. Only
    /// notches the preview opened are closed, and only if nothing (like a pin) changed them since.
    public func previewAnimation() {
        let engines = controllers.map(\.engine).filter { $0.state.presentation.openTab == nil }
        for engine in engines { engine.send(.clicked) }
        let opened = engines.map { ($0, $0.state.presentation) }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            for (engine, presentation) in opened where engine.state.presentation == presentation {
                engine.send(.dismiss)
            }
        }
    }

    private func rebuild() {
        for controller in controllers { controller.close() }
        let all = NSScreen.screens
        let screens = showingAllDisplays ? all : [NSScreen.preferredForNotch].compactMap { $0 }
        builtPills = preferences.pillDisplays
        controllers = screens.map { screen in
            // A display without a notch gets one drawn, unless the user picked the pill for it.
            let pill = screen.hasNotch || preferences.notchlessStyle(for: screen.uuid) == .pill
            let standIn = pill ? nil : NotchMetrics.standIn(on: screen, among: all)
            let controller = NotchController(
                screen: screen, content: content, preferences: preferences, standIn: standIn)
            controller.onPresentationChange = { [weak self] in
                guard let self else { return }
                onPresentationsChange?(presentations)
            }
            controller.engine.send(.setTabs(preferences.tabs))
            controller.engine.send(.setOngoing(shownOngoing))
            for reason in suspensions { controller.engine.send(.suspend(reason)) }
            controller.engine.send(.show)
            return controller
        }
        Log.surface.info("Showing \(self.controllers.count) notch(es)")
        hideUnderFullScreen()
        onPresentationsChange?(presentations)
    }

    private func suspend(_ reason: SuspendReason, _ suspended: Bool) {
        if suspended { suspensions.insert(reason) } else { suspensions.remove(reason) }
        broadcast(suspended ? .suspend(reason) : .resume(reason))
    }

    /// A Space changed, maybe into or out of full screen. The window list trails a Space's slide by
    /// up to a second and a half, so it's read now and again once the slide has settled.
    private func spaceChanged() {
        hideUnderFullScreen()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.hideUnderFullScreen()
        }
    }

    /// Hides the notch on each display a full-screen app fills, and brings it back once none does. A
    /// notched display keeps its notch: full screen there stops below the camera.
    private func hideUnderFullScreen() {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        for controller in controllers {
            let filled = Self.isFilled(CGDisplayBounds(controller.displayID), by: windows)
            controller.engine.send(filled ? .suspend(.fullScreen) : .resume(.fullScreen))
        }
    }

    /// Whether an app's window covers all of `display`, as a full-screen app does. Apps' windows sit
    /// in layer 0, under the menu bar, the Dock, and the notch. Bounds are the window server's,
    /// measured from the top left, like CGDisplayBounds.
    nonisolated static func isFilled(_ display: CGRect, by windows: [[String: Any]]) -> Bool {
        windows.contains { window in
            guard window[kCGWindowLayer as String] as? Int == 0,
                let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return false }
            return frame.contains(display)
        }
    }

    private func watchSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let events: [(NotificationCenter, Notification.Name, @MainActor (PanelCoordinator) -> Void)] = [
            (.default, NSApplication.didChangeScreenParametersNotification, { $0.rebuild() }),
            (workspace, NSWorkspace.willSleepNotification, { $0.suspend(.systemSleep, true) }),
            (workspace, NSWorkspace.didWakeNotification, { $0.suspend(.systemSleep, false) }),
            (workspace, NSWorkspace.screensDidSleepNotification, { $0.suspend(.displaySleep, true) }),
            (workspace, NSWorkspace.screensDidWakeNotification, { $0.suspend(.displaySleep, false) }),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, { $0.suspend(.screenLocked, true) }),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, { $0.suspend(.screenLocked, false) }),
            (distributed, Notification.Name("com.apple.screenIsLocked"), { $0.suspend(.screenLocked, true) }),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), { $0.suspend(.screenLocked, false) }),
            (workspace, NSWorkspace.activeSpaceDidChangeNotification, { $0.spaceChanged() }),
        ]
        for (center, name, handle) in events {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    handle(self)
                }
            }
            observers.append((center, token))
        }
    }
}

extension NSScreen {
    /// The built-in display with a notch, else the display with the menu bar.
    static var preferredForNotch: NSScreen? {
        screens.first(where: \.hasNotch) ?? screens.first
    }
}
