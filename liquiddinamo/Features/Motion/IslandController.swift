//
//  IslandController.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

/// Single source of truth governing the Dynamic Island state machine, animated geometry,
/// hit-testing boundaries, activity queue, and interruptible spring morphing.
@MainActor
public final class IslandController: ObservableObject {
    public static let shared = IslandController()

    // MARK: - State Machine Properties

    @Published public private(set) var state: IslandState = .idle
    @Published public private(set) var previousState: IslandState = .idle

    // MARK: - Current Target Geometry (Driven by State)

    @Published public private(set) var targetSize: CGSize = .zero
    @Published public private(set) var previousSize: CGSize = .zero
    @Published public private(set) var topCornerRadius: CGFloat = 6.0
    @Published public private(set) var bottomCornerRadius: CGFloat = 14.0
    @Published public private(set) var hasShadow: Bool = false
    @Published public private(set) var activeWingWidth: CGFloat = 46.0
    @Published public private(set) var activeLeftWingWidth: CGFloat = 46.0
    @Published public private(set) var activeRightWingWidth: CGFloat = 46.0

    // MARK: - Staged Content Reveal Pipeline

    /// Controls whether dashboard content has phased in after container expansion.
    /// On expand: container opens first -> content fades/blurs/scales in after contentInDelay.
    /// On collapse: content fades out quickly first -> container collapses with collapseDelay.
    @Published public private(set) var isExpandedContentVisible: Bool = false
    private var stagedContentTask: Task<Void, Never>?

    // MARK: - Detached Satellite Bubble & Gooey Metaball Split/Merge

    @Published public private(set) var isDetachedBubbleVisible: Bool = false
    @Published public private(set) var detachedBubbleSize: CGSize = CGSize(width: 32, height: 32)
    public let detachedBubbleGap: CGFloat = 8.0

    /// Active only during liquid split/merge animations (~0.45s) so idle CPU is strictly 0%.
    @Published public private(set) var isGooeyAnimating: Bool = false
    @Published public var splitProgress: CGFloat = 0.0 // 0.0 = merged inside pill, 1.0 = fully detached bubble

    // MARK: - Screen Awareness

    @Published public var isFloatingDisplay: Bool = false

    // MARK: - Alerts (Popped vs In-Dashboard Banner)

    /// Active popup alert when notch is closed
    @Published public private(set) var activeAlert: AlertPayload? = nil
    private var pendingAlerts: [AlertPayload] = []

    /// Dynamically reported intrinsic capsule width from content-measuring alert container
    @Published public private(set) var dynamicAlertCapsuleWidth: CGFloat? = nil

    /// Updates dynamic alert capsule width and resizes overlay window accordingly
    public func reportAlertCapsuleWidth(_ width: CGFloat) {
        guard dynamicAlertCapsuleWidth != width else { return }
        self.dynamicAlertCapsuleWidth = width
        if state == .alertPop {
            let newSize = calculateDimensions(for: .alertPop)
            withAnimation(IslandMotion.shared.expandSpring) {
                self.targetSize = newSize
            }
            AppDelegate.shared?.updateWindowFrame(for: .alertPop, explicitSize: newSize, animated: true)
        } else if state == .expanded {
            let hasAlert = activeExpandedAlert != nil
                || LiveActivityCenter.shared.activeAlert != nil
                || LiveActivityCenter.shared.activeNotification != nil
            if hasAlert && activeOrganicItem == .none {
                let newSize = calculateDimensions(for: .expanded)
                withAnimation(IslandMotion.shared.expandSpring) {
                    self.targetSize = newSize
                }
                AppDelegate.shared?.updateWindowFrame(for: .expanded, explicitSize: newSize, animated: true)
            }
        } else {
            let hasAlert = activeAlert != nil
                || LiveActivityCenter.shared.activeAlert != nil
                || LiveActivityCenter.shared.activeNotification != nil
                || LiveActivityCenter.shared.activeHUD != nil
                || BluetoothBatteryAlertManager.shared.isShowingAlertPopup
                || DeviceShowcaseCoordinator.shared.isShowing
            if hasAlert {
                let newSize = calculateDimensions(for: state)
                withAnimation(IslandMotion.shared.expandSpring) {
                    self.targetSize = newSize
                }
                AppDelegate.shared?.updateWindowFrame(for: state, explicitSize: newSize, animated: true)
            }
        }
    }

    /// Active alert banner displayed inside dashboard when user is hovering or notch is expanded
    @Published public private(set) var activeExpandedAlert: AlertPayload? = nil
    private var pendingExpandedAlerts: [AlertPayload] = []
    private var expandedAlertDwellTask: Task<Void, Never>?

    // MARK: - Activity Queue (Multi-Activity Support)

    @Published public private(set) var registeredActivities: [IslandActivity] = []

    /// Primary activity displayed in compact pill (highest priority)
    public var primaryActivity: IslandActivity? {
        registeredActivities.first
    }

    /// Secondary activity displayed in minimal detached bubble (second highest priority)
    public var secondaryActivity: IslandActivity? {
        registeredActivities.count >= 2 ? registeredActivities[1] : nil
    }

    // MARK: - Interaction Hover Tracking

    @Published public private(set) var isHovering: Bool = false
    @Published public var isPinnedOpen: Bool = false

    /// Current expanded detail item in LiquidOrganicNotchView (e.g. device popup, clipboard, dropper)
    @Published public var activeOrganicItem: OrganicNotchExpandedItem = .none {
        didSet {
            let targetBefore = targetSize
            if activeOrganicItem != .none {
                cancelHoverCollapse()
                isPinnedOpen = true
                if LiquidViewModel.shared.notchState != .open {
                    LiquidViewModel.shared.open(pinned: true)
                }
                if let appDelegate = AppDelegate.shared, appDelegate.vm.notchState != .open {
                    appDelegate.vm.open(pinned: true)
                }
            }
            if state == .expanded {
                let newTarget = calculateDimensions(for: .expanded)
                lastReportedMeasuredHeight = max(minimumHeight(for: activeOrganicItem), newTarget.height)
                withAnimation(IslandMotion.shared.expandSpring) {
                    targetSize = newTarget
                }
                AppDelegate.shared?.updateWindowFrame(for: .expanded, explicitSize: newTarget, animated: false)
            } else {
                lastReportedMeasuredHeight = minimumHeight(for: activeOrganicItem)
            }
        }
    }
    public private(set) var lastReportedMeasuredHeight: CGFloat = 0

    // Tasks for hover intent and alert dwell
    private var hoverIntentTask: Task<Void, Never>?
    private var alertDwellTask: Task<Void, Never>?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    /// Immediately cancels any in-flight hover collapse timer
    public func cancelHoverCollapse() {
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
    }

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let closedSize = getClosedNotchSize()
        self.targetSize = closedSize
        self.previousSize = closedSize
        self.topCornerRadius = IslandMotion.shared.topCornerRadius(isExpanded: false)
        self.bottomCornerRadius = IslandMotion.shared.bottomCornerRadius(forHeight: closedSize.height)
        self.hasShadow = false

        setupObservers()
        startHoverMonitoring()
    }

    private func setupObservers() {
        MusicManager.shared.$isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncAutomaticActivities() }
            .store(in: &cancellables)

        MusicManager.shared.$isPlayerIdle
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncAutomaticActivities() }
            .store(in: &cancellables)

        BluetoothBatteryAlertManager.shared.$hasActiveLowBatteryDot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncAutomaticActivities() }
            .store(in: &cancellables)

        Defaults.publisher(.leftWingMetric)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncAutomaticActivities() }
            .store(in: &cancellables)

        Defaults.publisher(.rightWingMetric)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncAutomaticActivities() }
            .store(in: &cancellables)

        LiquidViewCoordinator.shared.$expandingView
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, self.state != .expanded else { return }
                withAnimation(IslandMotion.shared.expandSpring) {
                    self.targetSize = self.calculateDimensions(for: self.state)
                }
            }
            .store(in: &cancellables)

        LiquidViewCoordinator.shared.$sneakPeek
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, self.state != .expanded else { return }
                withAnimation(IslandMotion.shared.expandSpring) {
                    self.targetSize = self.calculateDimensions(for: self.state)
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.openNotchOnHover)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                if change.newValue {
                    self?.startHoverMonitoring()
                } else {
                    self?.stopHoverMonitoring()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Automatic System Activities Sync

    private func syncAutomaticActivities() {
        // Sync Music Playback Activity
        let isMusicActive = MusicManager.shared.isPlaying || !MusicManager.shared.isPlayerIdle
        if isMusicActive {
            let songTitle = MusicManager.shared.songTitle.isEmpty ? "Music" : MusicManager.shared.songTitle
            registerActivity(IslandActivity(
                id: "system.music",
                kind: .musicPlayback,
                priority: 80,
                leadingIcon: "music.note",
                title: songTitle,
                tintColor: .green
            ), suppressRestingUpdate: true)
        } else {
            removeActivity(id: "system.music", suppressRestingUpdate: true)
        }

        // Sync Low Battery Warning Activity
        let hasLowBattery = BluetoothBatteryAlertManager.shared.hasActiveLowBatteryDot && Defaults[.keepLowBatteryDot]
        if hasLowBattery {
            registerActivity(IslandActivity(
                id: "system.batteryLow",
                kind: .batteryLevel,
                priority: 70,
                leadingIcon: "battery.25",
                title: "Low Battery",
                tintColor: .orange
            ), suppressRestingUpdate: true)
        } else {
            removeActivity(id: "system.batteryLow", suppressRestingUpdate: true)
        }

        // Sync System Wings Activity (A wing exists iff left or right metric != .none)
        let hasWings = Defaults[.leftWingMetric] != .none || Defaults[.rightWingMetric] != .none
        if hasWings {
            registerActivity(IslandActivity(
                id: "system.wings",
                kind: .systemStats,
                priority: 50,
                leadingIcon: "gauge",
                title: "Stats",
                tintColor: .cyan
            ), suppressRestingUpdate: true)
        } else {
            removeActivity(id: "system.wings", suppressRestingUpdate: true)
        }

        updateRestingStateIfNeeded()
    }

    // MARK: - Activity Queue Management

    /// Registers a live activity and re-sorts by priority.
    /// Automatically manages gooey split if count increases to 2+.
    public func registerActivity(_ activity: IslandActivity, suppressRestingUpdate: Bool = false) {
        let oldCount = registeredActivities.count
        registeredActivities.removeAll { $0.id == activity.id }
        registeredActivities.append(activity)
        registeredActivities.sort { $0.priority > $1.priority }

        let newCount = registeredActivities.count
        if oldCount < 2 && newCount >= 2 {
            startGooeySplit()
        }

        if !suppressRestingUpdate {
            updateRestingStateIfNeeded()
        }
    }

    /// Removes an activity by ID.
    /// Automatically manages gooey merge if count drops below 2.
    public func removeActivity(id: String, suppressRestingUpdate: Bool = false) {
        let oldCount = registeredActivities.count
        registeredActivities.removeAll { $0.id == id }

        let newCount = registeredActivities.count
        if oldCount >= 2 && newCount < 2 {
            startGooeyMerge()
        }

        if !suppressRestingUpdate {
            updateRestingStateIfNeeded()
        }
    }

    public func clearCustomActivities() {
        registeredActivities.removeAll { !$0.id.hasPrefix("system.") }
        updateRestingStateIfNeeded()
    }

    public func updateRestingStateIfNeeded() {
        guard state != .expanded && state != .alertPop else { return }
        let target = resolveRestingState()
        if target != state {
            transitionTo(target)
        }
    }

    public func updateScreenStatus(screen: NSScreen?) {
        let hasNotch = (screen?.safeAreaInsets.top ?? 0) > 0
        self.isFloatingDisplay = !hasNotch
    }

    // MARK: - Single Source of Truth Transitions

    /// Transitions the island to a new state with interruptible spring physics and staged content.
    public func transitionTo(_ newState: IslandState, alertPayload: AlertPayload? = nil) {
        guard newState != state || (newState == .alertPop && alertPayload != activeAlert) else { return }

        let oldState = state
        let oldSize = targetSize
        let isAlert = newState == .alertPop

        self.previousState = oldState
        self.previousSize = oldSize
        self.state = newState

        if isAlert {
            self.activeAlert = alertPayload
            self.dynamicAlertCapsuleWidth = alertPayload?.customSize?.width
        } else if oldState == .alertPop {
            self.activeAlert = nil
            self.dynamicAlertCapsuleWidth = nil
        }

        let newSize = calculateDimensions(for: newState, alertPayload: alertPayload)
        let isExpanded = newState == .expanded

        // Detached bubble visibility
        if newState == .minimal {
            if !isDetachedBubbleVisible && !isGooeyAnimating {
                startGooeySplit()
            }
        } else if oldState == .minimal && newState != .minimal {
            if isDetachedBubbleVisible && !isGooeyAnimating {
                startGooeyMerge()
            }
        }

        // Staged Content Choreography:
        // On expand: container moves first, content reveals after delay
        // On collapse: content fades out quickly first, container collapses with delayed spring
        stagedContentTask?.cancel()
        if isExpanded {
            DeviceMonitor.shared.refreshBluetoothDevices()
            let inDelay = IslandMotion.shared.contentInDelay * IslandMotion.shared.timeMultiplier
            stagedContentTask = Task { @MainActor [weak self] in
                if inDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(inDelay * 1_000_000_000))
                }
                guard !Task.isCancelled, self?.state == .expanded else { return }
                withAnimation(IslandMotion.shared.contentInAnimation) {
                    self?.isExpandedContentVisible = true
                }
            }
        } else if oldState == .expanded {
            withAnimation(IslandMotion.shared.contentOutAnimation) {
                self.isExpandedContentVisible = false
            }
        }

        // Select spring: expand when either dimension grows, collapse when both shrink
        let spring = IslandMotion.shared.spring(from: oldSize, to: newSize, isAlert: isAlert)

        if isExpanded {
            AppDelegate.shared?.updateWindowFrame(for: .expanded, explicitSize: newSize, animated: false)
        } else if newState == .alertPop {
            AppDelegate.shared?.updateWindowFrame(for: .alertPop, explicitSize: newSize, animated: false)
        }

        withAnimation(spring) {
            self.targetSize = newSize
            self.topCornerRadius = IslandMotion.shared.topCornerRadius(isExpanded: isExpanded)
            self.bottomCornerRadius = IslandMotion.shared.bottomCornerRadius(forHeight: newSize.height)
            self.hasShadow = (newState != .idle)

            if isExpanded {
                if LiquidViewModel.shared.notchState != .open {
                    LiquidViewModel.shared.open(pinned: self.isPinnedOpen)
                }
                if let appDelegate = AppDelegate.shared {
                    if appDelegate.vm.notchState != .open {
                        appDelegate.vm.open(pinned: self.isPinnedOpen)
                    }
                    for vm in appDelegate.viewModels.values where vm.notchState != .open {
                        vm.open(pinned: self.isPinnedOpen)
                    }
                }
            } else if oldState == .expanded {
                self.activeOrganicItem = .none
                if LiquidViewModel.shared.notchState != .closed {
                    LiquidViewModel.shared.close()
                }
                if let appDelegate = AppDelegate.shared {
                    if appDelegate.vm.notchState != .closed {
                        appDelegate.vm.close()
                    }
                    for vm in appDelegate.viewModels.values where vm.notchState != .closed {
                        vm.close()
                    }
                }
            }
        }

        if !isExpanded && newState != .alertPop {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self = self, self.state != .expanded else { return }
                AppDelegate.shared?.updateWindowFrame(for: self.state, animated: false)
            }
        }

        // Auto-retraction for transient alert pops
        if isAlert, let payload = alertPayload {
            scheduleAlertDwell(duration: payload.dwellDuration)
        } else {
            alertDwellTask?.cancel()
            alertDwellTask = nil
        }
    }

    // MARK: - Liquid Metaball Gooey Split & Merge Controls

    /// Secondary detached bubble is disabled to eliminate extra circular icon and reserved space
    public func startGooeySplit() {
        self.isDetachedBubbleVisible = false
    }

    /// Merges the secondary bubble back into the main notch pill.
    public func startGooeyMerge() {
        self.isDetachedBubbleVisible = false
    }

    // MARK: - Direct State Actions

    public func setIdle() {
        transitionTo(.idle)
    }

    public func setCompact() {
        transitionTo(.compact)
    }

    public func setMinimal() {
        transitionTo(.minimal)
    }

    public func setExpanded(view: NotchViews? = nil, pin: Bool = true) {
        if let view = view {
            LiquidViewCoordinator.shared.currentView = view
        }
        if pin {
            isPinnedOpen = true
        }
        transitionTo(.expanded)
    }

    /// Alert presentation routing:
    /// Auto-expands the island with proper details upon event trigger, and retracts cleanly after dwell duration.
    public func showAlert(payload: AlertPayload) {
        triggerEventExpansion(payload: payload)
    }

    /// Primary event auto-expansion pipeline
    public func triggerEventExpansion(payload: AlertPayload) {
        if !self.isPinnedOpen && self.activeOrganicItem == .none {
            self.isPinnedOpen = false
        }
        showExpandedAlert(payload)
        if state != .expanded {
            transitionTo(.expanded, alertPayload: payload)
        }
    }

    public func showExpandedAlert(_ payload: AlertPayload) {
        withAnimation(IslandMotion.shared.expandSpring) {
            self.activeExpandedAlert = payload
        }

        expandedAlertDwellTask?.cancel()
        expandedAlertDwellTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let duration = payload.dwellDuration * IslandMotion.shared.timeMultiplier
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard !self.isHovering else { return }
            self.dismissExpandedAlert()
        }
    }

    public func dismissExpandedAlert() {
        expandedAlertDwellTask?.cancel()
        expandedAlertDwellTask = nil
        withAnimation(IslandMotion.shared.contentOutAnimation) {
            self.activeExpandedAlert = nil
            self.dynamicAlertCapsuleWidth = nil
            LiveActivityCenter.shared.dismissAlert(immediate: true)
            LiveActivityCenter.shared.dismissNotification()
        }

        if !pendingExpandedAlerts.isEmpty {
            let next = pendingExpandedAlerts.removeFirst()
            showExpandedAlert(next)
        } else if !isPinnedOpen && !isHovering && activeOrganicItem == .none {
            transitionTo(resolveRestingState())
        }
    }

    public func dismissAlert() {
        self.dynamicAlertCapsuleWidth = nil
        if !pendingAlerts.isEmpty {
            let next = pendingAlerts.removeFirst()
            transitionTo(.alertPop, alertPayload: next)
            return
        }
        if state == .alertPop {
            if isPinnedOpen || activeOrganicItem != .none {
                transitionTo(.expanded)
            } else {
                transitionTo(resolveRestingState())
            }
        }
    }

    public func toggle() {
        if state == .expanded {
            isPinnedOpen = false
            transitionTo(resolveRestingState())
        } else if state == .alertPop {
            if let alert = activeAlert {
                activeAlert = nil
                showExpandedAlert(alert)
            }
            isPinnedOpen = true
            transitionTo(.expanded)
        } else {
            isPinnedOpen = true
            transitionTo(.expanded)
        }
    }

    // MARK: - Sleep & Wake Lifecycle

    public func onSystemSleep() {
        hoverIntentTask?.cancel()
        alertDwellTask?.cancel()
        expandedAlertDwellTask?.cancel()
        activeAlert = nil
        activeExpandedAlert = nil
        pendingAlerts.removeAll()
        pendingExpandedAlerts.removeAll()
        isHovering = false
        transitionTo(.idle)
    }

    public func onSystemWake() {
        updateRestingStateIfNeeded()
    }

    // MARK: - Resting State Resolver

    /// Determines what state the island should return to when not expanded or displaying an alert pop.
    public func resolveRestingState() -> IslandState {
        let count = registeredActivities.count
        if count >= 2 {
            return .minimal
        } else if count == 1 {
            return .compact
        } else {
            return .idle
        }
    }

    // MARK: - Dimension Calculation

    public func calculateDimensions(for state: IslandState, alertPayload: AlertPayload? = nil) -> CGSize {
        let geom = NotchSafeAreaEngine.shared.currentGeometry
        let restingWidth = geom.hasPhysicalNotch ? geom.rawNotchWidth : 140.0
        let restingHeight = geom.notchHeight

        // When a sneak peek or power status notification is active in the top bar,
        // expand the island pill container so the wings are fully unclipped outside the notch hole
        if (LiquidViewCoordinator.shared.expandingView.show || LiquidViewCoordinator.shared.sneakPeek.show) && state != .expanded {
            return CGSize(width: geom.compactPillWidth, height: restingHeight)
        }

        switch state {
        case .idle, .compact:
            let hasTransientAlert = activeAlert != nil
                || LiveActivityCenter.shared.activeAlert != nil
                || LiveActivityCenter.shared.activeNotification != nil
                || LiveActivityCenter.shared.activeHUD != nil
                || BluetoothBatteryAlertManager.shared.isShowingAlertPopup
                || DeviceShowcaseCoordinator.shared.isShowing
            if hasTransientAlert {
                let estimatedW = activeAlert?.estimatedContentWidth ?? 220.0
                let contentW = dynamicAlertCapsuleWidth ?? estimatedW
                let capsuleSize = IslandController.alertCapsuleSize(for: geom, contentWidth: contentW)
                let targetH = geom.isNotched ? (geom.notchHeight + capsuleSize.height + 8) : capsuleSize.height
                return CGSize(width: capsuleSize.width + 24.0, height: targetH)
            }

            let hasWings = Defaults[.leftWingMetric] != .none || Defaults[.rightWingMetric] != .none
            let showWings = hasWings || !registeredActivities.isEmpty
            let wingW = Defaults[.autoFitWings] ? activeWingWidth : max(geom.wingWidth, activeWingWidth)
            let baseW = geom.isNotched ? (geom.rawNotchWidth + 14.0 + (2.0 * wingW)) : (160.0 + (2.0 * (wingW + 8.0)))
            let w = showWings ? (Defaults[.autoFitWings] ? baseW : max(geom.compactPillWidth, baseW)) : (geom.isNotched ? restingWidth : 160.0)
            return CGSize(width: w, height: restingHeight)

        case .minimal:
            return CGSize(width: restingWidth + geom.wingWidth, height: restingHeight)

        case .expanded:
            let hasAlert = activeExpandedAlert != nil
                || alertPayload != nil
                || LiveActivityCenter.shared.activeAlert != nil
                || LiveActivityCenter.shared.activeNotification != nil
            // Transient alerts only resize the container if no item is selected
            if hasAlert && activeOrganicItem == .none {
                let estimatedW: CGFloat = {
                    if let notif = LiveActivityCenter.shared.activeNotification {
                        return 330.0
                    }
                    return activeExpandedAlert?.estimatedContentWidth ?? alertPayload?.estimatedContentWidth ?? 220.0
                }()
                let contentW = dynamicAlertCapsuleWidth ?? activeExpandedAlert?.customSize?.width ?? alertPayload?.customSize?.width ?? estimatedW
                let capsuleSize = IslandController.alertCapsuleSize(for: geom, contentWidth: contentW)
                let targetH = geom.isNotched ? (geom.notchHeight + capsuleSize.height + 8) : capsuleSize.height
                return CGSize(width: capsuleSize.width + 24.0, height: targetH)
            }

            let screenMaxH: CGFloat = {
                if let sc = NSScreen.main {
                    let scFrame = sc.frame
                    let visible = sc.visibleFrame
                    return max(200, (scFrame.origin.y + scFrame.height) - visible.minY - 24.0)
                }
                return 700
            }()

            if LiquidViewCoordinator.shared.currentView == .shelf {
                return CGSize(width: 480, height: min(geom.notchHeight + 220, screenMaxH))
            } else if LiquidViewCoordinator.shared.currentView == .plexo || LiquidViewCoordinator.shared.currentView == .powerload {
                return CGSize(width: 560, height: min(max(480, geom.notchHeight + 450), screenMaxH))
            } else if LiquidViewCoordinator.shared.currentView == .phoneBridge {
                return CGSize(width: 580, height: min(max(480, geom.notchHeight + 450), screenMaxH))
            } else if LiquidViewCoordinator.shared.currentView == .home {
                let homeWidth = max(openNotchSize.width, 740)
                switch activeOrganicItem {
                case .none:
                    return CGSize(width: homeWidth, height: min(max(200, geom.notchHeight + 175), screenMaxH))
                case .clipboard:
                    return CGSize(width: homeWidth, height: min(max(440, geom.notchHeight + 430), screenMaxH))
                case .dropper:
                    return CGSize(width: homeWidth, height: min(max(340, geom.notchHeight + 320), screenMaxH))
                case .device:
                    return CGSize(width: homeWidth, height: min(max(420, geom.notchHeight + 390), screenMaxH))
                case .storageCleaner:
                    return CGSize(width: homeWidth, height: min(max(460, geom.notchHeight + 430), screenMaxH))
                case .colorDropper:
                    return CGSize(width: homeWidth, height: min(max(340, geom.notchHeight + 320), screenMaxH))
                case .plexo, .powerload:
                    return CGSize(width: homeWidth, height: min(max(480, geom.notchHeight + 450), screenMaxH))
                case .phoneBridge:
                    return CGSize(width: homeWidth, height: min(max(480, geom.notchHeight + 450), screenMaxH))
                case .watcher:
                    return CGSize(width: homeWidth, height: min(max(440, geom.notchHeight + 410), screenMaxH))
                }
            }
            return CGSize(width: max(openNotchSize.width, 660), height: min(openNotchSize.height, screenMaxH))

        case .alertPop:
            let estimatedW = alertPayload?.estimatedContentWidth ?? activeAlert?.estimatedContentWidth ?? 200.0
            let contentW = dynamicAlertCapsuleWidth ?? alertPayload?.customSize?.width ?? activeAlert?.customSize?.width ?? estimatedW
            let capsuleSize = IslandController.alertCapsuleSize(for: geom, contentWidth: contentW)
            let targetH = geom.isNotched ? (geom.notchHeight + capsuleSize.height + 6) : capsuleSize.height
            return CGSize(width: capsuleSize.width + 16.0, height: targetH)
        }
    }

    /// Named constant base width for transient alert and HUD 3D liquid capsules
    public static let alertCapsuleDefaultWidth: CGFloat = 200.0

    /// Derives the exact 3D liquid capsule size from NotchSafeAreaEngine geometry and content measurements
    public static func alertCapsuleSize(for geom: NotchGeometry, contentWidth: CGFloat? = nil) -> CGSize {
        let minW: CGFloat = geom.hasPhysicalNotch ? max(170.0, geom.rawNotchWidth) : 170.0
        let maxW: CGFloat = min(350.0, max(240.0, geom.screenFrame.width * 0.30))
        let requestedW = contentWidth ?? alertCapsuleDefaultWidth
        let width = min(maxW, max(minW, requestedW))
        let height = max(34.0, min(42.0, max(geom.notchHeight, 36.0)))
        return CGSize(width: width, height: height)
    }

    /// Minimum required height floor for an organic expanded item so it never shrinks prematurely
    public func minimumHeight(for item: OrganicNotchExpandedItem) -> CGFloat {
        let geom = NotchSafeAreaEngine.shared.currentGeometry
        switch item {
        case .none:
            return max(200, geom.notchHeight + 175)
        case .clipboard:
            return max(440, geom.notchHeight + 430)
        case .dropper:
            return max(340, geom.notchHeight + 320)
        case .device:
            return max(420, geom.notchHeight + 390)
        case .storageCleaner:
            return max(460, geom.notchHeight + 430)
        case .colorDropper:
            return max(340, geom.notchHeight + 320)
        case .plexo, .powerload:
            return max(480, geom.notchHeight + 450)
        case .phoneBridge:
            return max(480, geom.notchHeight + 450)
        case .watcher:
            return max(440, geom.notchHeight + 410)
        }
    }

    /// Dynamically adapts the target height of the expanded dropdown based on measured intrinsic child content.
    public func adjustTargetHeightIfNeeded(_ measuredHeight: CGFloat) {
        guard state == .expanded else { return }
        let minH = minimumHeight(for: activeOrganicItem)
        let effectiveMeasured = max(measuredHeight, minH)
        guard abs(effectiveMeasured - lastReportedMeasuredHeight) >= 6.0 else { return }
        lastReportedMeasuredHeight = effectiveMeasured

        let screenMaxH: CGFloat = {
            if let sc = NSScreen.main {
                let scFrame = sc.frame
                let visible = sc.visibleFrame
                return max(200, (scFrame.origin.y + scFrame.height) - visible.minY - 24.0)
            }
            return 700
        }()

        let neededH = min(effectiveMeasured + 14.0, screenMaxH)
        if abs(targetSize.height - neededH) >= 8.0 {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.state == .expanded else { return }
                let currentMin = self.minimumHeight(for: self.activeOrganicItem)
                let finalH = max(neededH, currentMin)
                if abs(self.targetSize.height - finalH) >= 8.0 {
                    withAnimation(IslandMotion.shared.expandSpring) {
                        self.targetSize.height = finalH
                    }
                    AppDelegate.shared?.updateWindowFrame(for: .expanded, explicitSize: CGSize(width: self.targetSize.width, height: finalH), animated: false)
                }
            }
        }
    }

    /// Dynamically expands the target width of the island when wings contain expanded details (e.g. CPU %, Network Speed, Hover/Tapped details).
    public func adjustTargetWidthForWingsIfNeeded(_ measuredWidth: CGFloat, wingWidth: CGFloat, leftWidth: CGFloat? = nil, rightWidth: CGFloat? = nil) {
        guard state == .idle || state == .compact else { return }
        let geom = NotchSafeAreaEngine.shared.currentGeometry
        let minW = geom.hasPhysicalNotch ? (geom.rawNotchWidth + 14.0) : 160.0
        let neededW = max(minW, measuredWidth)

        if let lw = leftWidth, abs(activeLeftWingWidth - lw) >= 1.0 {
            activeLeftWingWidth = lw
        }
        if let rw = rightWidth, abs(activeRightWingWidth - rw) >= 1.0 {
            activeRightWingWidth = rw
        }
        if abs(activeWingWidth - wingWidth) >= 1.0 {
            activeWingWidth = wingWidth
        }

        guard abs(targetSize.width - neededW) >= 1.5 else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.state == .idle || self.state == .compact else { return }
            let finalW = max(minW, neededW)
            if abs(self.targetSize.width - finalW) >= 1.5 {
                withAnimation(IslandMotion.shared.expandSpring) {
                    self.targetSize.width = finalW
                }
                AppDelegate.shared?.updateWindowFrame(for: self.state, explicitSize: CGSize(width: finalW, height: self.targetSize.height), animated: false)
            }
        }
    }

    // MARK: - Hover Intent & Grace Sequencing

    public func onHoverEntered() {
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
        isHovering = true

        guard state != .expanded else { return }

        if state == .alertPop {
            alertDwellTask?.cancel()
            return
        }

        guard Defaults[.openNotchOnHover] else { return }

        // Opened via hover (not pinned) - expand immediately upon entering notch hitbox
        self.isPinnedOpen = false
        self.transitionTo(.expanded)
    }

    public func onHoverExited() {
        if state == .alertPop {
            scheduleAlertDwell(duration: 0.5)
            return
        }

        guard state == .expanded else { return }

        // Pinned open (e.g. opened via click) or active organic detail item must stay open
        guard !self.isPinnedOpen else { return }
        guard self.activeOrganicItem == .none else { return }
        guard !LiquidViewModel.shared.isBatteryPopoverActive else { return }
        guard !SharingStateManager.shared.preventNotchClose else { return }

        isHovering = false

        // Grace delay before collapsing so smooth cursor movement across boundaries never abruptly shrinks or collapses
        hoverIntentTask?.cancel()
        hoverIntentTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            guard let self = self, !self.isHovering else { return }
            guard self.state == .expanded else { return }
            guard !self.isPinnedOpen && self.activeOrganicItem == .none else { return }
            guard !LiquidViewModel.shared.isBatteryPopoverActive else { return }
            guard !SharingStateManager.shared.preventNotchClose else { return }

            self.dismissExpandedAlert()
            self.activeOrganicItem = .none
            self.transitionTo(self.resolveRestingState())
        }
    }

    /// Checks if dynamic content warrants keeping the island open longer
    public func hasActiveImportantContent() -> Bool {
        if activeAlert != nil || activeExpandedAlert != nil {
            return true
        }
        if LiveActivityCenter.shared.activeNotification != nil
            || LiveActivityCenter.shared.activeAlert != nil
            || LiveActivityCenter.shared.activeProgress != nil
            || LiveActivityCenter.shared.activeHUD != nil {
            return true
        }
        if DynamicIslandHub.shared.activeDownload != nil || DynamicIslandHub.shared.activePrivacySession != nil {
            return true
        }
        if !DeviceMonitor.shared.activeDevices.isEmpty {
            return true
        }
        if !ShelfStateViewModel.shared.items.isEmpty {
            return true
        }
        if !ClipboardHistoryService.shared.recentEntries.isEmpty || !ClipboardHistoryService.shared.pinnedEntries.isEmpty {
            return true
        }
        return false
    }

    private func scheduleAlertDwell(duration: TimeInterval) {
        alertDwellTask?.cancel()
        alertDwellTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let effDuration = duration * IslandMotion.shared.timeMultiplier
            try? await Task.sleep(nanoseconds: UInt64(effDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard !self.isHovering else { return }

            self.dismissAlert()
        }
    }

    // MARK: - Hit-Testing Boundary Calculation

    public func containsPointInVisibleShape(_ point: NSPoint, inWindow window: NSWindow) -> Bool {
        let screenPoint = window.convertPoint(toScreen: point)
        if state == .expanded || LiquidViewModel.shared.notchState == .open || state == .alertPop {
            let targetRect = AppDelegate.shared?.targetFrame(for: window) ?? window.frame
            let unionFrame = window.frame.union(targetRect)
            return isMouseInHoverRegion(screenPoint) || unionFrame.contains(screenPoint)
        } else {
            // STEP C (Preferred approach):
            // In collapsed states (.idle, .compact, .minimal), window.ignoresMouseEvents is kept false
            // so SwiftUI .onHover and .onTapGesture can work natively. To prevent the wide window frame
            // from stealing clicks or hover from underlying apps, menu bar items, and desktop windows,
            // we restrict hit-testing strictly to the visible hardware notch rect and the active left/right
            // wing drop rects. Any coordinate outside these tight bounds returns false (hitTest returns nil),
            // allowing mouse events to pass cleanly straight through to whatever is underneath.
            guard let screen = window.screen ?? NSScreen.screens.first(where: { $0.frame.contains(screenPoint) }) ?? NSScreen.main else {
                return false
            }
            let hitRects = NotchSafeAreaEngine.shared.collapsedWingHitRects(for: screen)
            let inNotch = hitRects.notchRect.contains(screenPoint)
            let inLeft = (Defaults[.leftWingMetric] != .none) && hitRects.leftWingRect.contains(screenPoint)
            let inRight = (Defaults[.rightWingMetric] != .none) && hitRects.rightWingRect.contains(screenPoint)
            return inNotch || inLeft || inRight
        }
    }

    // MARK: - Global Cursor Tracking

    private var lastHoverCheckTime: TimeInterval = 0

    public func startHoverMonitoring() {
        stopHoverMonitoring()
        guard Defaults[.openNotchOnHover] else { return }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            guard let self = self else { return }
            let now = CACurrentMediaTime()
            guard now - self.lastHoverCheckTime >= 0.016 else { return }
            self.lastHoverCheckTime = now
            Task { @MainActor [weak self] in
                self?.handleGlobalMouseMove()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            guard let self = self else { return event }
            let now = CACurrentMediaTime()
            guard now - self.lastHoverCheckTime >= 0.016 else { return event }
            self.lastHoverCheckTime = now
            Task { @MainActor [weak self] in
                self?.handleGlobalMouseMove()
            }
            return event
        }
    }

    public func stopHoverMonitoring() {
        if let mon = globalMouseMonitor {
            NSEvent.removeMonitor(mon)
            globalMouseMonitor = nil
        }
        if let mon = localMouseMonitor {
            NSEvent.removeMonitor(mon)
            localMouseMonitor = nil
        }
    }

    private func handleGlobalMouseMove() {
        guard Defaults[.openNotchOnHover] else { return }
        let mouseLoc = NSEvent.mouseLocation
        let inRegion = isMouseInHoverRegion(mouseLoc)
        if inRegion {
            if !isHovering {
                onHoverEntered()
            }
        } else {
            if isHovering {
                onHoverExited()
            }
        }
    }

    public func checkCursorHover(screenPoint: NSPoint) {
        guard Defaults[.openNotchOnHover] else { return }
        let inRegion = isMouseInHoverRegion(screenPoint)
        if inRegion {
            if !isHovering {
                onHoverEntered()
            }
        } else {
            if isHovering {
                onHoverExited()
            }
        }
    }

    public func isMouseInHoverRegion(_ screenPoint: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) }) ?? NSScreen.main else {
            return false
        }
        let screenFrame = screen.frame
        let topY = screenFrame.maxY
        let screenHasNotch = screen.safeAreaInsets.top > 0

        let notchRect: CGRect
        if screenHasNotch,
           #available(macOS 12.0, *),
           let auxLeft = screen.auxiliaryTopLeftArea,
           let auxRight = screen.auxiliaryTopRightArea,
           auxLeft.width > 0, auxRight.width > 0 {
            // Exact physical hardware notch bounds between top auxiliary menu bar segments
            let notchMinX = auxLeft.maxX
            let notchMaxX = auxRight.minX
            let notchW = max(0, notchMaxX - notchMinX)
            let notchH = screen.safeAreaInsets.top
            notchRect = CGRect(x: notchMinX, y: topY - notchH, width: notchW, height: notchH)
        } else if screenHasNotch {
            let geom = NotchSafeAreaEngine.shared.currentGeometry
            let notchW = geom.rawNotchWidth > 0 ? geom.rawNotchWidth : 180.0
            let notchH = geom.notchHeight > 0 ? geom.notchHeight : 32.0
            let notchCenterX = (!geom.notchRect.isEmpty) ? (screenFrame.origin.x + geom.notchRect.midX) : screenFrame.midX
            notchRect = CGRect(x: notchCenterX - (notchW / 2.0), y: topY - notchH, width: notchW, height: notchH)
        } else {
            let notchW: CGFloat = 140.0
            let notchH: CGFloat = 32.0
            notchRect = CGRect(x: screenFrame.midX - (notchW / 2.0), y: topY - notchH, width: notchW, height: notchH)
        }

        if state != .expanded {
            // STRICT HIT-TESTING: Exactly matches visible physical notch rectangle only.
            // Zero proximity detection, zero hover radius, zero padding below or around notch.
            let minX = notchRect.minX
            let maxX = notchRect.maxX
            let minY = notchRect.minY
            let maxY = topY + 1.0

            return screenPoint.x >= minX && screenPoint.x <= maxX && screenPoint.y >= minY && screenPoint.y <= maxY
        } else {
            // When expanded, the interactive zone covers the expanded island rectangle with a 20pt buffer.
            let targetW: CGFloat
            let targetH: CGFloat
            if let win = AppDelegate.shared?.window {
                let targetRect = AppDelegate.shared?.targetFrame(for: win) ?? win.frame
                let union = win.frame.union(targetRect)
                targetW = max(targetSize.width, max(previousSize.width, union.width))
                targetH = max(targetSize.height, max(previousSize.height, union.height))
            } else {
                targetW = max(targetSize.width, previousSize.width)
                targetH = max(targetSize.height, previousSize.height)
            }
            let minX = notchRect.midX - (targetW / 2.0) - 20.0
            let maxX = notchRect.midX + (targetW / 2.0) + 20.0
            let minY = topY - targetH - 20.0
            let maxY = topY + 1.0

            return screenPoint.x >= minX && screenPoint.x <= maxX && screenPoint.y >= minY && screenPoint.y <= maxY
        }
    }
}
