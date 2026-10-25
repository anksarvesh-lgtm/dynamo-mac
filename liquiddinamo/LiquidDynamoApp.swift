//
//  boringNotchApp.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow

    let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

        // Initialize the settings window controller with the updater controller
        SettingsWindowController.shared.setUpdaterController(updaterController)
    }

    var body: some Scene {
        MenuBarExtra("LiquidDynamo", image: "MenuBarIcon", isInserted: $showMenuBarIcon) {
            Button(appDelegate.vm.notchState == .open ? "Close Dashboard" : "Open Dashboard") {
                if appDelegate.vm.notchState == .open {
                    appDelegate.vm.close()
                } else {
                    appDelegate.vm.open()
                }
            }
            .keyboardShortcut(KeyEquivalent("d"), modifiers: [.command, .shift])

            Divider()

            Toggle("Media Player", isOn: Binding(
                get: { Defaults[.showMedia] },
                set: {
                    Defaults[.showMedia] = $0
                    if $0 {
                        Task { await AppPermissionManager.shared.requestPermission(for: .music) }
                    }
                }
            ))

            Toggle("Battery & Power", isOn: Binding(
                get: { Defaults[.showBatteryIndicator] },
                set: { Defaults[.showBatteryIndicator] = $0 }
            ))

            Toggle("Volume & Brightness HUD", isOn: Binding(
                get: { Defaults[.showNotchOSD] },
                set: { Defaults[.showNotchOSD] = $0 }
            ))

            Toggle("Calendar Events", isOn: Binding(
                get: { Defaults[.showCalendar] },
                set: {
                    Defaults[.showCalendar] = $0
                    if $0 {
                        Task { await AppPermissionManager.shared.requestPermission(for: .calendar) }
                    }
                }
            ))

            Toggle("Liquid Shelf", isOn: Binding(
                get: { Defaults[.liquidShelf] },
                set: { Defaults[.liquidShelf] = $0 }
            ))

            if Defaults[.showDashboardClipboard] {
                Menu("Clipboard History") {
                    let service = ClipboardHistoryService.shared
                    if service.isScreenCaptured {
                        Text("Shielded during screen recording")
                    } else if service.pinnedEntries.isEmpty && service.recentEntries.isEmpty {
                        Text("No copied items")
                    } else {
                        if !service.pinnedEntries.isEmpty {
                            Section("Pinned") {
                                ForEach(service.pinnedEntries) { entry in
                                    Button("📌 " + entry.previewText) {
                                        service.copyToPasteboard(entry)
                                    }
                                }
                            }
                        }
                        if !service.recentEntries.isEmpty {
                            Section("Recent") {
                                ForEach(service.recentEntries.prefix(25)) { entry in
                                    Button(entry.previewText) {
                                        service.copyToPasteboard(entry)
                                    }
                                }
                            }
                            Divider()
                            Button("Clear Recent History") {
                                service.clearHistory()
                            }
                        }
                    }
                }
            }

            Divider()

            Toggle(
                "Pause alerts for 1 hour",
                isOn: Binding(
                    get: {
                        if let until = Defaults[.pauseAlertsUntil] {
                            return Date() < until
                        }
                        return false
                    },
                    set: { paused in
                        if paused {
                            Defaults[.pauseAlertsUntil] = Date().addingTimeInterval(3600)
                        } else {
                            Defaults[.pauseAlertsUntil] = nil
                        }
                    }
                )
            )

            Toggle("Show on all displays", isOn: Binding(
                get: { Defaults[.showOnAllDisplays] },
                set: {
                    Defaults[.showOnAllDisplays] = $0
                    NotificationCenter.default.post(
                        name: Notification.Name.showOnAllDisplaysChanged,
                        object: nil
                    )
                }
            ))

            Divider()

            Button("About LiquidDynamo") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow(tab: "About")
                }
            }

            Button("Settings…") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut(KeyEquivalent("q"), modifiers: .command)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    public static weak var shared: AppDelegate?
    var statusItem: NSStatusItem?
    var windows: [String: NSWindow] = [:] // UUID -> NSWindow
    var viewModels: [String: LiquidViewModel] = [:] // UUID -> LiquidViewModel
    var window: NSWindow?
    let vm: LiquidViewModel = LiquidViewModel.shared
    @ObservedObject var coordinator = LiquidViewCoordinator.shared
    var quickShareService = QuickShareService.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    var closeNotchTask: Task<Void, Never>?
    private var previousScreens: [NSScreen]?
    private var onboardingWindowController: NSWindowController?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var isScreenLocked: Bool = false
    private var windowScreenDidChangeObserver: Any?
    private var dragDetectors: [String: DragDetector] = [:] // UUID -> DragDetector
    private var escKeyMonitor: Any?
    private var clickOutsideMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var backgroundActivityAssertion: NSObjectProtocol?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let token = backgroundActivityAssertion {
            ProcessInfo.processInfo.endActivity(token)
            backgroundActivityAssertion = nil
        }
        ProcessInfo.processInfo.enableAutomaticTermination("LiquidDynamo Dynamic Island and Notch background service")
        ProcessInfo.processInfo.enableSuddenTermination()

        NotificationCenter.default.removeObserver(self)
        if let observer = screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenLockedObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenUnlockedObserver = nil
        }
        MusicManager.shared.destroy()
        stopExpandedEventMonitors()
        ShelfStateViewModel.shared.cleanupAllTemporaryItems()
        cleanupDragDetectors()
        cleanupWindows()
        XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        isScreenLocked = true
        if !Defaults[.showOnLockScreen] {
            cleanupWindows()
        } else {
            enableSkyLightOnAllWindows()
        }
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false
        if !Defaults[.showOnLockScreen] {
            adjustWindowPosition(changeAlpha: true)
        } else {
            disableSkyLightOnAllWindows()
        }
    }
    
    @MainActor
    private func enableSkyLightOnAllWindows() {
        if Defaults[.showOnAllDisplays] {
            windows.values.forEach { window in
                if let skyWindow = window as? LiquidDynamoSkyLightWindow {
                    skyWindow.enableSkyLight()
                }
            }
        } else {
            if let skyWindow = window as? LiquidDynamoSkyLightWindow {
                skyWindow.enableSkyLight()
            }
        }
    }
    
    @MainActor
    private func disableSkyLightOnAllWindows() {
        // Delay disabling SkyLight to avoid flicker during unlock transition
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                if Defaults[.showOnAllDisplays] {
                    self.windows.values.forEach { window in
                        if let skyWindow = window as? LiquidDynamoSkyLightWindow {
                            skyWindow.disableSkyLight()
                        }
                    }
                } else {
                    if let skyWindow = self.window as? LiquidDynamoSkyLightWindow {
                        skyWindow.disableSkyLight()
                    }
                }
            }
        }
    }

    private enum EventMonitorMode {
        case none
        case closed
        case expanded
    }
    private var currentMonitorMode: EventMonitorMode = .none

    private var closedMouseMonitor: Any?
    private var closedScrollLocalMonitor: Any?
    private var expandedScrollLocalMonitor: Any?
    private var lastClosedMoveCheckTime: TimeInterval = 0

    // Delta accumulator for smooth, jitter-free gesture detection
    private var accumulatedScrollX: CGFloat = 0
    private var accumulatedScrollY: CGFloat = 0
    private var lastScrollTime: TimeInterval = 0
    private var lastHandledEventTimestamp: TimeInterval = -1

    @discardableResult
    @MainActor
    func handleScrollGesture(event: NSEvent, mouseLocation: NSPoint) -> Bool {
        guard Defaults[.enableGestures] else { return false }

        // Deduplicate events if received by multiple listeners (local monitor + IslandHostingView)
        if event.timestamp == lastHandledEventTimestamp {
            return true
        }

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else {
            return false
        }
        let geom = NotchSafeAreaEngine.shared.currentGeometry
        let screenHasNotch = screen.safeAreaInsets.top > 0

        // Hardware notch / central pill screen rect - strictly exact to notch cutout
        let notchScreenRect: CGRect
        if screenHasNotch,
           #available(macOS 12.0, *),
           let auxLeft = screen.auxiliaryTopLeftArea,
           let auxRight = screen.auxiliaryTopRightArea,
           auxLeft.width > 0, auxRight.width > 0 {
            let notchMinX = auxLeft.maxX
            let notchMaxX = auxRight.minX
            let notchW = max(0, notchMaxX - notchMinX)
            let notchH = screen.safeAreaInsets.top
            notchScreenRect = CGRect(x: notchMinX, y: screen.frame.maxY - notchH, width: notchW, height: notchH)
        } else {
            let notchW = screenHasNotch ? (geom.rawNotchWidth > 0 ? geom.rawNotchWidth : 180.0) : 140.0
            let notchH = screenHasNotch ? geom.notchHeight : 32.0
            let notchCenterX = (screenHasNotch && !geom.notchRect.isEmpty) ? (screen.frame.origin.x + geom.notchRect.midX) : screen.frame.midX
            notchScreenRect = CGRect(
                x: notchCenterX - (notchW / 2.0),
                y: screen.frame.maxY - notchH,
                width: notchW,
                height: notchH
            )
        }

        let wingW = max(60.0, geom.wingWidth)
        let zoneLeft = notchScreenRect.minX - wingW - 40.0
        let zoneRight = notchScreenRect.maxX + wingW + 40.0
        let zoneTop = screen.frame.maxY + 5.0
        let zoneBottom = notchScreenRect.minY - 85.0
        let gestureZone = CGRect(
            x: zoneLeft,
            y: zoneBottom,
            width: zoneRight - zoneLeft,
            height: zoneTop - zoneBottom
        )

        guard gestureZone.contains(mouseLocation) else {
            return false
        }

        // When expanded, only intercept if cursor is on the top notch bar, avoiding interception of content scrollviews
        if vm.notchState == .open {
            guard mouseLocation.y >= notchScreenRect.minY - 10.0 else {
                return false
            }
        }

        lastHandledEventTimestamp = event.timestamp

        // Extract deltas (supports both trackpad precise scrolling and mouse wheels)
        let rawDX: CGFloat
        let rawDY: CGFloat
        if event.hasPreciseScrollingDeltas {
            rawDX = event.scrollingDeltaX
            rawDY = event.scrollingDeltaY
        } else {
            rawDX = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : (event.deltaX * 10.0)
            rawDY = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : (event.deltaY * 10.0)
        }

        // Normalize direction based on macOS scrolling mode.
        // With Natural Scrolling enabled (default on macOS):
        // Sliding two fingers UP on trackpad produces rawDY < 0.
        // Sliding two fingers DOWN on trackpad produces rawDY > 0.
        // Inverting when event.isDirectionInvertedFromDevice is true ensures:
        // effectiveDY > 0 ALWAYS means sliding UP (Volume Increase)
        // effectiveDY < 0 ALWAYS means sliding DOWN (Volume Decrease)
        // effectiveDX > 0 ALWAYS means sliding RIGHT (Brightness Increase)
        // effectiveDX < 0 ALWAYS means sliding LEFT (Brightness Decrease)
        let effectiveDX = event.isDirectionInvertedFromDevice ? -rawDX : rawDX
        let effectiveDY = event.isDirectionInvertedFromDevice ? -rawDY : rawDY

        // Reset accumulator if idle for > 350ms or on gesture phase boundary
        let now = CACurrentMediaTime()
        if now - lastScrollTime > 0.35 || event.phase == .began {
            accumulatedScrollX = 0
            accumulatedScrollY = 0
        }
        lastScrollTime = now

        if event.phase == .ended || event.phase == .cancelled {
            accumulatedScrollX = 0
            accumulatedScrollY = 0
            return true
        }

        accumulatedScrollX += effectiveDX
        accumulatedScrollY += effectiveDY

        let scrollThreshold: CGFloat = 3.5
        let absX = abs(accumulatedScrollX)
        let absY = abs(accumulatedScrollY)

        if absY >= scrollThreshold && absY >= absX {
            // Dominant vertical gesture: Volume
            let isUp = accumulatedScrollY > 0
            let notchCenterX = notchScreenRect.midX
            let isFarLeftWheel = !event.hasPreciseScrollingDeltas && mouseLocation.x < (notchCenterX - 25.0)

            if isFarLeftWheel {
                let delta: Float = isUp ? 0.025 : -0.025
                BrightnessManager.shared.setRelative(delta: delta)
            } else {
                if isUp {
                    VolumeManager.shared.increase(stepDivisor: 2.5)
                } else {
                    VolumeManager.shared.decrease(stepDivisor: 2.5)
                }
            }
            accumulatedScrollY -= (accumulatedScrollY > 0 ? scrollThreshold : -scrollThreshold)
            accumulatedScrollX = 0
            return true
        } else if absX >= scrollThreshold {
            // Dominant horizontal gesture: Brightness
            let isUp = accumulatedScrollX > 0
            let delta: Float = isUp ? 0.025 : -0.025
            BrightnessManager.shared.setRelative(delta: delta)
            accumulatedScrollX -= (accumulatedScrollX > 0 ? scrollThreshold : -scrollThreshold)
            accumulatedScrollY = 0
            return true
        }

        return true
    }

    var allActiveWindows: [NSWindow] {
        var list = Array(windows.values)
        if let w = window, !list.contains(w) {
            list.append(w)
        }
        return list.isEmpty ? (window != nil ? [window!] : []) : list
    }

    @MainActor
    func startClosedEventMonitors() {
        if currentMonitorMode == .closed { return }
        stopClosedEventMonitors()
        stopExpandedEventMonitors()
        currentMonitorMode = .closed

        // Global monitor tracks mouse clicks, hover, and gestures when cursor is over other apps / desktop
        closedMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .mouseMoved, .scrollWheel]) { [weak self] event in
            guard let self = self, self.vm.notchState == .closed else { return }

            let mouseLoc = NSEvent.mouseLocation

            if event.type == .scrollWheel {
                Task { @MainActor [weak self] in
                    self?.handleScrollGesture(event: event, mouseLocation: mouseLoc)
                }
                return
            }

            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) ?? NSScreen.main else { return }
            let hitRects = NotchSafeAreaEngine.shared.collapsedWingHitRects(for: screen)

            if event.type == .leftMouseDown {
                if Defaults[.enableSideReadouts] && Defaults[.leftWingMetric] != .none && hitRects.leftWingRect.contains(mouseLoc) {
                    NotificationCenter.default.post(name: .toggleSideReadoutDetails, object: "left")
                } else if Defaults[.enableSideReadouts] && Defaults[.rightWingMetric] != .none && hitRects.rightWingRect.contains(mouseLoc) {
                    NotificationCenter.default.post(name: .toggleSideReadoutDetails, object: "right")
                } else if hitRects.notchRect.contains(mouseLoc) {
                    Task { @MainActor [weak self] in
                        self?.vm.open(pinned: true)
                    }
                } else {
                    NotificationCenter.default.post(name: .resetSideReadoutDetails, object: nil)
                }
            } else if event.type == .mouseMoved {
                let now = CACurrentMediaTime()
                guard now - self.lastClosedMoveCheckTime >= 0.016 else { return }
                self.lastClosedMoveCheckTime = now

                if Defaults[.enableSideReadouts] {
                    let isLeftHover = (Defaults[.leftWingMetric] != .none) && hitRects.leftWingRect.contains(mouseLoc)
                    let isRightHover = (Defaults[.rightWingMetric] != .none) && hitRects.rightWingRect.contains(mouseLoc)
                    NotificationCenter.default.post(name: .sideReadoutHoverChanged, object: ["left": isLeftHover, "right": isRightHover])
                }
                if Defaults[.openNotchOnHover] {
                    IslandController.shared.checkCursorHover(screenPoint: mouseLoc)
                }
            }
        }

        // Local monitor tracks scroll gestures when our app window is receiving events
        closedScrollLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self = self, self.vm.notchState == .closed else { return event }
            let mouseLoc = NSEvent.mouseLocation
            if self.handleScrollGesture(event: event, mouseLocation: mouseLoc) {
                return nil
            }
            return event
        }
    }

    func stopClosedEventMonitors() {
        if let monitor = closedMouseMonitor {
            NSEvent.removeMonitor(monitor)
            closedMouseMonitor = nil
        }
        if let monitor = closedScrollLocalMonitor {
            NSEvent.removeMonitor(monitor)
            closedScrollLocalMonitor = nil
        }
        if currentMonitorMode == .closed {
            currentMonitorMode = .none
        }
    }

    @MainActor
    func startExpandedEventMonitors() {
        if currentMonitorMode == .expanded { return }
        stopClosedEventMonitors()
        stopExpandedEventMonitors()
        currentMonitorMode = .expanded

        // Esc key closes the open dashboard
        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                Task { @MainActor [weak self] in
                    self?.vm.close()
                }
                return nil
            }
            return event
        }

        // Local scroll monitor for expanded mode top-bar gestures
        expandedScrollLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self = self, self.vm.notchState == .open else { return event }
            let mouseLoc = NSEvent.mouseLocation
            if self.handleScrollGesture(event: event, mouseLocation: mouseLoc) {
                return nil
            }
            return event
        }

        // Click outside the open notch area closes the dashboard on any active screen
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self = self, self.vm.notchState == .open else { return }
            let mouseLoc = NSEvent.mouseLocation

            let clickedInside = self.allActiveWindows.contains { window in
                let winPoint = window.convertPoint(fromScreen: mouseLoc)
                return IslandController.shared.containsPointInVisibleShape(winPoint, inWindow: window)
            }

            if !clickedInside {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if IslandController.shared.activeOrganicItem != .none {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            IslandController.shared.activeOrganicItem = .none
                        }
                    } else {
                        self.vm.close()
                    }
                }
            }
        }
    }

    func stopExpandedEventMonitors() {
        if let monitor = escKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escKeyMonitor = nil
        }
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        if let monitor = expandedScrollLocalMonitor {
            NSEvent.removeMonitor(monitor)
            expandedScrollLocalMonitor = nil
        }
        if currentMonitorMode == .expanded {
            currentMonitorMode = .none
        }
    }

    private func cleanupWindows(shouldInvert: Bool = false) {
        let shouldCleanupMulti = shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays]
        
        if shouldCleanupMulti {
            windows.values.forEach { window in
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            if let obs = windowScreenDidChangeObserver {
                NotificationCenter.default.removeObserver(obs)
                windowScreenDidChangeObserver = nil
            }
            self.window = nil
        }
    }

    private func cleanupDragDetectors() {
        dragDetectors.values.forEach { detector in
            detector.stopMonitoring()
        }
        dragDetectors.removeAll()
    }

    private func setupDragDetectors() {
        cleanupDragDetectors()

        guard Defaults[.expandedDragDetection] else { return }

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens {
                setupDragDetectorForScreen(screen)
            }
        } else {
            let preferredScreen: NSScreen? = window?.screen
                ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                ?? NSScreen.main

            if let screen = preferredScreen {
                setupDragDetectorForScreen(screen)
            }
        }
    }

    private func setupDragDetectorForScreen(_ screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        let screenFrame = screen.frame
        let detectorWidth: CGFloat = 360
        let detectorHeight: CGFloat = 70
        
        // Create compact notch region at top-center where dragging onto the notch activates the dropper
        let notchRegion = CGRect(
            x: screenFrame.midX - detectorWidth / 2,
            y: screenFrame.maxY - detectorHeight,
            width: detectorWidth,
            height: detectorHeight
        )
        
        let detector = DragDetector(notchRegion: notchRegion)
        
        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.handleDragEntersNotchRegion(onScreen: screen)
            }
        }
        
        dragDetectors[uuid] = detector
        detector.startMonitoring()
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard Defaults[.openNotchOnDrag] else { return }
        guard let uuid = screen.displayUUID else { return }
        
        if Defaults[.showOnAllDisplays], let viewModel = viewModels[uuid] {
            viewModel.open()
            coordinator.currentView = .shelf
        } else if !Defaults[.showOnAllDisplays], let windowScreen = window?.screen, screen == windowScreen {
            vm.open()
            coordinator.currentView = .shelf
        }
    }

    private func createLiquidDynamoWindow(for screen: NSScreen, with viewModel: LiquidViewModel) -> NSWindow {
        let geom = NotchSafeAreaEngine.shared.currentGeometry
        let targetSize = CGSize(width: geom.compactPillWidth, height: geom.notchHeight)
        let screenFrame = screen.frame
        let rect = NSRect(
            x: screenFrame.origin.x + (screenFrame.width - targetSize.width) / 2.0,
            y: screenFrame.origin.y + screenFrame.height - targetSize.height,
            width: targetSize.width,
            height: targetSize.height
        )
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]

        let window = LiquidDynamoSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
        window.ignoresMouseEvents = false

        // Enable SkyLight only when screen is locked
        if isScreenLocked {
            window.enableSkyLight()
        } else {
            window.disableSkyLight()
        }

        window.contentView = IslandHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
        )

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)

        // Observe when the window's screen changes so we can update drag detectors
        windowScreenDidChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setupDragDetectors()
                }
        }
        return window
    }

    @MainActor
    func updateWindowFrame(for state: IslandState, explicitSize: CGSize? = nil, animated: Bool = false) {
        let geom = NotchSafeAreaEngine.shared.currentGeometry
        let targetSize: CGSize
        let shouldIgnore: Bool
        switch state {
        case .expanded:
            let islandTarget = explicitSize ?? IslandController.shared.targetSize
            let hasAlert = IslandController.shared.activeExpandedAlert != nil
                || LiveActivityCenter.shared.activeAlert != nil
                || LiveActivityCenter.shared.activeNotification != nil
            if hasAlert && IslandController.shared.activeOrganicItem == .none {
                let contentW = IslandController.shared.dynamicAlertCapsuleWidth ?? IslandController.shared.activeExpandedAlert?.customSize?.width
                let capsuleSize = IslandController.alertCapsuleSize(for: geom, contentWidth: contentW)
                let targetH = geom.isNotched ? (geom.notchHeight + capsuleSize.height + 8) : capsuleSize.height
                targetSize = CGSize(width: capsuleSize.width, height: targetH)
            } else if LiquidViewCoordinator.shared.currentView == .shelf {
                targetSize = CGSize(width: max(islandTarget.width, 440), height: max(islandTarget.height, geom.notchHeight + 115))
            } else if LiquidViewCoordinator.shared.currentView == .plexo {
                targetSize = CGSize(width: max(islandTarget.width, 560), height: max(islandTarget.height, geom.notchHeight + 450))
            } else if LiquidViewCoordinator.shared.currentView == .home {
                targetSize = islandTarget
            } else {
                targetSize = CGSize(width: max(islandTarget.width, openNotchSize.width), height: max(islandTarget.height, openNotchSize.height))
            }
            shouldIgnore = false
        case .alertPop:
            let contentW = explicitSize?.width ?? IslandController.shared.dynamicAlertCapsuleWidth ?? IslandController.shared.activeAlert?.customSize?.width
            let capsuleSize = IslandController.alertCapsuleSize(for: geom, contentWidth: contentW)
            let popH = geom.isNotched ? (geom.notchHeight + capsuleSize.height + 8) : capsuleSize.height
            targetSize = CGSize(width: capsuleSize.width, height: popH)
            shouldIgnore = false
        case .idle, .compact, .minimal:
            let neededW = max(geom.compactPillWidth, explicitSize?.width ?? IslandController.shared.targetSize.width)
            targetSize = CGSize(width: neededW, height: geom.notchHeight)
            shouldIgnore = false
        }

        if let win = self.window, let screen = win.screen ?? NSScreen.main {
            let newRect = calculateNotchCenteredRect(for: screen, size: targetSize)
            if win.frame != newRect {
                win.setFrame(newRect, display: true, animate: animated)
            }
            win.ignoresMouseEvents = shouldIgnore
        }

        for (_, win) in self.windows {
            if let sc = win.screen {
                let winRect = calculateNotchCenteredRect(for: sc, size: targetSize)
                if win.frame != winRect {
                    win.setFrame(winRect, display: true, animate: animated)
                }
                win.ignoresMouseEvents = shouldIgnore
            }
        }
    }

    public func calculateNotchCenteredRect(for sc: NSScreen, size: CGSize) -> NSRect {
        let geom = NotchSafeAreaEngine.shared.currentGeometry
        let scFrame = sc.frame
        let visible = sc.visibleFrame
        let screenHasNotch = sc.safeAreaInsets.top > 0
        let notchCenterScreenX: CGFloat
        if screenHasNotch && !geom.notchRect.isEmpty {
            notchCenterScreenX = scFrame.origin.x + geom.notchRect.midX
        } else {
            notchCenterScreenX = scFrame.midX
        }

        // Boundary constraints: ensure dropdown stays within visible screen area above Dock
        let maxAllowedW = max(100.0, visible.width - 16.0)
        let maxAllowedH = max(32.0, (scFrame.origin.y + scFrame.height) - visible.minY - 12.0)

        let clampedW = min(size.width, maxAllowedW)
        let clampedH = min(size.height, maxAllowedH)

        var windowOriginX = notchCenterScreenX - (clampedW / 2.0)
        // Clamp X within display's visible bounds
        if windowOriginX < visible.minX + 8.0 {
            windowOriginX = visible.minX + 8.0
        } else if windowOriginX + clampedW > visible.maxX - 8.0 {
            windowOriginX = visible.maxX - clampedW - 8.0
        }

        // Anchor Y to the top edge (notch anchor)
        var windowOriginY = (scFrame.origin.y + scFrame.height) - clampedH
        if windowOriginY < visible.minY + 6.0 {
            windowOriginY = visible.minY + 6.0
        }

        return NSRect(
            x: windowOriginX,
            y: windowOriginY,
            width: clampedW,
            height: clampedH
        )
    }

    public func targetFrame(for window: NSWindow, targetSize: CGSize? = nil) -> NSRect {
        guard let sc = window.screen ?? NSScreen.main else { return window.frame }
        let size = targetSize ?? IslandController.shared.targetSize
        return calculateNotchCenteredRect(for: sc, size: size)
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }

        let geom = NotchSafeAreaEngine.shared.currentGeometry
        let state = IslandController.shared.state
        let targetSize: CGSize
        let shouldIgnore: Bool
        switch state {
        case .expanded:
            let islandTarget = IslandController.shared.targetSize
            let hasAlert = IslandController.shared.activeExpandedAlert != nil
                || LiveActivityCenter.shared.activeAlert != nil
                || LiveActivityCenter.shared.activeNotification != nil
            if hasAlert && IslandController.shared.activeOrganicItem == .none {
                let contentW = IslandController.shared.dynamicAlertCapsuleWidth ?? IslandController.shared.activeExpandedAlert?.customSize?.width
                let capsuleSize = IslandController.alertCapsuleSize(for: geom, contentWidth: contentW)
                let targetH = geom.isNotched ? (geom.notchHeight + capsuleSize.height + 8) : capsuleSize.height
                targetSize = CGSize(width: capsuleSize.width, height: targetH)
            } else if LiquidViewCoordinator.shared.currentView == .shelf {
                targetSize = CGSize(width: max(islandTarget.width, 440), height: max(islandTarget.height, geom.notchHeight + 115))
            } else if LiquidViewCoordinator.shared.currentView == .plexo {
                targetSize = CGSize(width: max(islandTarget.width, 560), height: max(islandTarget.height, geom.notchHeight + 450))
            } else if LiquidViewCoordinator.shared.currentView == .home {
                targetSize = islandTarget
            } else {
                targetSize = CGSize(width: max(islandTarget.width, openNotchSize.width), height: max(islandTarget.height, openNotchSize.height))
            }
            shouldIgnore = false
        case .alertPop:
            let contentW = IslandController.shared.dynamicAlertCapsuleWidth ?? IslandController.shared.activeAlert?.customSize?.width
            let capsuleSize = IslandController.alertCapsuleSize(for: geom, contentWidth: contentW)
            let popH = geom.isNotched ? (geom.notchHeight + capsuleSize.height + 8) : capsuleSize.height
            targetSize = CGSize(width: capsuleSize.width, height: popH)
            shouldIgnore = false
        case .idle, .compact, .minimal:
            targetSize = CGSize(width: max(geom.compactPillWidth, IslandController.shared.targetSize.width), height: geom.notchHeight)
            shouldIgnore = false
        }

        let newRect = calculateNotchCenteredRect(for: screen, size: targetSize)
        if window.frame != newRect {
            window.setFrame(newRect, display: true)
        }
        window.ignoresMouseEvents = shouldIgnore
        IslandController.shared.updateScreenStatus(screen: screen)
        window.alphaValue = 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // Proactively prevent macOS automatic termination and sudden background termination
        ProcessInfo.processInfo.disableAutomaticTermination("LiquidDynamo Dynamic Island and Notch background service")
        ProcessInfo.processInfo.disableSuddenTermination()

        // Hold user-initiated latency-critical background activity to prevent App Nap from throttling or sleeping the app
        backgroundActivityAssertion = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "LiquidDynamo live notch monitor, telemetry wings, and system status"
        )

        migrateWingMetricsIfNeeded()
        startClosedEventMonitors()
        if Defaults[.enableWatcherIntegration] {
            _ = WatcherService.shared
        }
        // Auto-check for updates from GitHub releases
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            GitHubUpdateChecker.shared.checkForUpdates(silent: true)
        }
        #if DEBUG
        if CommandLine.arguments.contains("--run-notch-safety-tests") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let success = NotchSafetyTester.shared.runAllTests()
                print("🏁 NOTCH_SAFETY_TEST_RESULT: \(success ? "SUCCESS" : "FAILURE")")
                exit(success ? 0 : 1)
            }
        }
        if CommandLine.arguments.contains("--run-water-acceptance-tests") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let success = WaterBottomAcceptanceTester.shared.runAllAcceptanceTests()
                print("🏁 WATER_BOTTOM_ACCEPTANCE_RESULT: \(success ? "SUCCESS" : "FAILURE")")
                exit(success ? 0 : 1)
            }
        }
        if CommandLine.arguments.contains("--debug-liquid-engine") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                LiquidEngineDebugWindowController.shared.show()
            }
        }
        if CommandLine.arguments.contains("--debug-water-physics") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                WaterPhysicsDebugWindowController.shared.show()
            }
        }
        #endif

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            Task { @MainActor in
                window.alphaValue = self.coordinator.selectedScreenUUID == self.coordinator.preferredScreenUUID ? 1 : 0
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.cleanupWindows(shouldInvert: true)
                self.adjustWindowPosition(changeAlpha: true)
                self.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.expandedDragDetectionChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupDragDetectors()
            }
        }

        // Use closure-based observers for DistributedNotificationCenter and keep tokens for removal
        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenLocked(notification)
                }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenUnlocked(notification)
                }
        }

        // Sleep & Wake Lifecycle Observers
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                IslandController.shared.onSystemSleep()
                SystemStatsService.shared.stop()
                NetworkThroughputService.shared.stop()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                SystemStatsService.shared.stop()
                NetworkThroughputService.shared.stop()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition()
                IslandController.shared.onSystemWake()
                if Defaults[.enableSideReadouts] {
                    SystemStatsService.shared.start()
                    NetworkThroughputService.shared.start()
                }
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                if Defaults[.enableSideReadouts] {
                    SystemStatsService.shared.start()
                    NetworkThroughputService.shared.start()
                }
            }
        }

        // Initialize Dynamic Island Intelligent Status Hub
        _ = DynamicIslandHub.shared

        // Start persistent background clipboard tracking & ambient monitoring
        ClipboardHistoryService.shared.start()
        if Defaults[.enableSideReadouts] {
            SystemStatsService.shared.start()
            NetworkThroughputService.shared.start()
            ConnectionStatusService.shared.start()
        }

        coordinator.$currentView
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.adjustWindowPosition()
                }
            }
            .store(in: &cancellables)

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self else { return }
            if Defaults[.sneakPeekStyles] == .inline {
                let newStatus = !self.coordinator.expandingView.show
                self.coordinator.toggleExpandingView(status: newStatus, type: .music)
            } else {
                self.coordinator.toggleSneakPeek(
                    status: !self.coordinator.sneakPeek.show,
                    type: .music,
                    duration: 3.0
                )
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Task { [weak self] in
                guard let self = self else { return }

                let mouseLocation = NSEvent.mouseLocation

                var viewModel = self.vm

                if Defaults[.showOnAllDisplays] {
                    for screen in NSScreen.screens {
                        if screen.frame.contains(mouseLocation) {
                            if let uuid = screen.displayUUID, let screenViewModel = self.viewModels[uuid] {
                                viewModel = screenViewModel
                                break
                            }
                        }
                    }
                }

                self.closeNotchTask?.cancel()
                self.closeNotchTask = nil

                switch viewModel.notchState {
                case .closed:
                    await MainActor.run {
                        viewModel.open()
                    }
                case .open:
                    await MainActor.run {
                        viewModel.close()
                    }
                }
            }
        }

        if !Defaults[.showOnAllDisplays] {
            let viewModel = self.vm
            let window = createLiquidDynamoWindow(
                for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
            self.window = window
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }

        setupDragDetectors()

        if coordinator.firstLaunch {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
            playWelcomeSound()
        } else if MusicManager.shared.isNowPlayingDeprecated
            && Defaults[.mediaController] == .nowPlaying
        {
            DispatchQueue.main.async {
                self.showOnboardingWindow(step: .musicPermission)
            }
        }

        _ = DeviceMonitor.shared
        _ = AppPermissionManager.shared
        _ = StorageCleanupManager.shared
        StorageCleanupManager.shared.performStartupScanIfNeeded()

        previousScreens = NSScreen.screens

        // Automatically open the Settings window on app launch so user immediately sees a visible interface,
        // while the liquid notch background utility is initialized seamlessly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            if !self.coordinator.firstLaunch {
                self.vm.open()
                self.viewModels.values.forEach { $0.open() }
                SettingsWindowController.shared.showWindow()
            }
        }
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleReopenAppleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEReopenApplication)
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if self.vm.notchState == .closed && !coordinator.firstLaunch {
            Task { @MainActor in
                self.vm.open()
                self.viewModels.values.forEach { $0.open() }
            }
        }
    }

    @objc func handleReopenAppleEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.vm.notchState == .closed && !self.coordinator.firstLaunch {
                self.vm.open()
                self.viewModels.values.forEach { $0.open() }
            }
            SettingsWindowController.shared.showWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.vm.notchState == .closed && !self.coordinator.firstLaunch {
                self.vm.open()
                self.viewModels.values.forEach { $0.open() }
            }
            SettingsWindowController.shared.showWindow()
        }
        return true
    }

    func playWelcomeSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "liquid", fileExtension: "m4a")
    }

    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }

    @objc func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.compactMap { $0.displayUUID })
                != Set(previousScreens?.compactMap { $0.displayUUID } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens

        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(NSScreen.screens.compactMap { $0.displayUUID })

            // Remove windows for screens that no longer exist
            for uuid in windows.keys where !currentScreenUUIDs.contains(uuid) {
                if let window = windows[uuid] {
                    window.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                    windows.removeValue(forKey: uuid)
                    viewModels.removeValue(forKey: uuid)
                }
            }

            // Create or update windows for all screens
            for screen in NSScreen.screens {
                guard let uuid = screen.displayUUID else { continue }
                
                if windows[uuid] == nil {
                    let viewModel = LiquidViewModel(screenUUID: uuid)
                    let window = createLiquidDynamoWindow(for: screen, with: viewModel)

                    windows[uuid] = window
                    viewModels[uuid] = viewModel
                }

                if let window = windows[uuid], let viewModel = viewModels[uuid] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)
                    viewModel.closedNotchSize = getClosedNotchSize(screenUUID: uuid)
                    if viewModel.notchState == .closed {
                        viewModel.notchSize = viewModel.closedNotchSize
                    }
                }
            }

            if self.window == nil {
                self.window = windows.values.first
            }
        } else {
            let selectedScreen: NSScreen

            if let preferred = coordinator.preferredScreenUUID,
               let preferredScreen = NSScreen.screen(withUUID: preferred) {
                coordinator.selectedScreenUUID = preferred
                selectedScreen = preferredScreen
            } else if let builtIn = NSScreen.screens.first(where: {
                if let num = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                    return CGDisplayIsBuiltin(CGDirectDisplayID(num.uint32Value)) != 0
                }
                return false
            }) {
                // Always prioritize built-in screen with the physical notch
                coordinator.selectedScreenUUID = builtIn.displayUUID ?? ""
                selectedScreen = builtIn
            } else if Defaults[.automaticallySwitchDisplay], let mainScreen = NSScreen.main,
                      let mainUUID = mainScreen.displayUUID {
                coordinator.selectedScreenUUID = mainUUID
                selectedScreen = mainScreen
            } else {
                if let window = window {
                    window.alphaValue = 0
                }
                return
            }

            vm.screenUUID = selectedScreen.displayUUID
            vm.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)

            if window == nil {
                window = createLiquidDynamoWindow(for: selectedScreen, with: vm)
            }

            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)

                if vm.notchState == .closed {
                    vm.close()
                }
            }
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(self)
    }

    func showOnboardingWindow(step: OnboardingStep = .welcome) {
        if let controller = onboardingWindowController, let window = controller.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "LiquidDynamo Setup"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if Defaults[.enableWindowTransparency] && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        window.contentView = NSHostingView(
            rootView: OnboardingView(
                step: step,
                onFinish: { [weak self] in
                    window.orderOut(nil)
                    window.close()
                    self?.onboardingWindowController = nil
                    NSApp.deactivate()
                },
                onOpenSettings: { [weak self] in
                    window.close()
                    self?.onboardingWindowController = nil
                    SettingsWindowController.shared.showWindow()
                }
            ))
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")

        onboardingWindowController = NSWindowController(window: window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
    static let toggleSideReadoutDetails = Notification.Name("ToggleSideReadoutDetails")
    static let sideReadoutHoverChanged = Notification.Name("SideReadoutHoverChanged")
    static let resetSideReadoutDetails = Notification.Name("ResetSideReadoutDetails")
}

extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.origin == rhs.origin && lhs.size == rhs.size
    }
}
