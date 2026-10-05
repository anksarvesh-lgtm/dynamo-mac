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

    // Tasks for hover intent and alert dwell
    private var hoverIntentTask: Task<Void, Never>?
    private var alertDwellTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let closedSize = getClosedNotchSize()
        self.targetSize = closedSize
        self.previousSize = closedSize
        self.topCornerRadius = IslandMotion.shared.topCornerRadius(isExpanded: false)
        self.bottomCornerRadius = IslandMotion.shared.bottomCornerRadius(forHeight: closedSize.height)
        self.hasShadow = false

        setupObservers()
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

        Defaults.publisher(.showCollapsedCPUWing)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncAutomaticActivities() }
            .store(in: &cancellables)

        Defaults.publisher(.showCollapsedBluetoothWing)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncAutomaticActivities() }
            .store(in: &cancellables)

        Defaults.publisher(.showCollapsedNetworkWing)
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

        // Sync System Wings Activity
        let hasWings = Defaults[.showCollapsedCPUWing] || Defaults[.showCollapsedBluetoothWing] || Defaults[.showCollapsedNetworkWing]
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
        } else if oldState == .alertPop {
            self.activeAlert = nil
        }

        let newSize = calculateDimensions(for: newState, alertPayload: alertPayload)
        self.targetSize = newSize

        let isExpanded = newState == .expanded
        self.topCornerRadius = IslandMotion.shared.topCornerRadius(isExpanded: isExpanded)
        self.bottomCornerRadius = IslandMotion.shared.bottomCornerRadius(forHeight: newSize.height)
        self.hasShadow = (newState != .idle)

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

        withAnimation(spring) {
            if isExpanded {
                LiquidViewModel.shared.open()
            } else if oldState == .expanded {
                LiquidViewModel.shared.close()
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

    /// Splits off a secondary minimal bubble using the liquid gooey Canvas metaball bridge.
    public func startGooeySplit() {
        if IslandMotion.shared.isSimpleAnimationActive {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.isDetachedBubbleVisible = true
            }
            return
        }

        isGooeyAnimating = true
        splitProgress = 0.0
        isDetachedBubbleVisible = true

        withAnimation(IslandMotion.shared.expandSpring) {
            self.splitProgress = 1.0
        }

        let settleDuration = (IslandMotion.shared.expandResponse * IslandMotion.shared.timeMultiplier) + 0.15
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(settleDuration * 1_000_000_000))
            self?.isGooeyAnimating = false
        }
    }

    /// Merges the secondary bubble back into the main notch pill.
    public func startGooeyMerge() {
        if IslandMotion.shared.isSimpleAnimationActive {
            withAnimation(.easeInOut(duration: 0.20)) {
                self.isDetachedBubbleVisible = false
            }
            return
        }

        isGooeyAnimating = true
        splitProgress = 1.0

        withAnimation(IslandMotion.shared.collapseSpring) {
            self.splitProgress = 0.0
        }

        let settleDuration = (IslandMotion.shared.collapseResponse * IslandMotion.shared.timeMultiplier) + 0.15
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(settleDuration * 1_000_000_000))
            self?.isDetachedBubbleVisible = false
            self?.isGooeyAnimating = false
        }
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

    public func setExpanded(view: NotchViews? = nil) {
        if let view = view {
            LiquidViewCoordinator.shared.currentView = view
        }
        transitionTo(.expanded)
    }

    /// Alert presentation routing:
    /// "If the user is hovering or the notch is expanded, show the alert inside the expanded view instead of popping."
    /// Queues sequential alerts if multiple alerts arrive concurrently.
    public func showAlert(payload: AlertPayload) {
        // Do not re-submit a duplicate generic .alert to LiveActivityCenter if payload
        // is a notification card, since IslandController handles the rich presentation directly.
        if case .notification = payload.kind {
            // Managed directly by IslandAlertView in belowArea
        } else {
            let hubActivity = LiveActivity(
                id: UUID().uuidString,
                source: "system",
                kind: .alert,
                priority: LiveActivityPriority.alert,
                tint: payload.iconColor,
                duration: payload.dwellDuration,
                payload: LiveActivityPayload(
                    title: payload.title,
                    subtitle: payload.subtitle,
                    iconName: payload.iconName,
                    iconColor: payload.iconColor
                )
            )
            LiveActivityCenter.shared.submit(hubActivity)
        }

        if state == .expanded || isHovering {
            if activeExpandedAlert != nil {
                pendingExpandedAlerts.append(payload)
            } else {
                showExpandedAlert(payload)
            }
        } else {
            if state == .alertPop && activeAlert != nil {
                pendingAlerts.append(payload)
            } else {
                transitionTo(.alertPop, alertPayload: payload)
            }
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
            self.dismissExpandedAlert()
        }
    }

    public func dismissExpandedAlert() {
        expandedAlertDwellTask?.cancel()
        expandedAlertDwellTask = nil
        withAnimation(IslandMotion.shared.contentOutAnimation) {
            self.activeExpandedAlert = nil
        }

        if !pendingExpandedAlerts.isEmpty {
            let next = pendingExpandedAlerts.removeFirst()
            showExpandedAlert(next)
        }
    }

    public func dismissAlert() {
        if !pendingAlerts.isEmpty {
            let next = pendingAlerts.removeFirst()
            transitionTo(.alertPop, alertPayload: next)
            return
        }
        if state == .alertPop {
            transitionTo(resolveRestingState())
        }
    }

    public func toggle() {
        if state == .expanded {
            transitionTo(resolveRestingState())
        } else if state == .alertPop {
            if let alert = activeAlert {
                activeAlert = nil
                showExpandedAlert(alert)
            }
            transitionTo(.expanded)
        } else {
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

    private func calculateDimensions(for state: IslandState, alertPayload: AlertPayload? = nil) -> CGSize {
        let geom = NotchSafeAreaEngine.shared.currentGeometry
        let restingWidth = geom.hasPhysicalNotch ? geom.rawNotchWidth : 140.0
        let restingHeight = geom.notchHeight

        // When a sneak peek or power status notification is active in the top bar,
        // expand the island pill container so the wings are fully unclipped outside the notch hole
        if (LiquidViewCoordinator.shared.expandingView.show || LiquidViewCoordinator.shared.sneakPeek.show) && state != .expanded {
            return CGSize(width: geom.compactPillWidth, height: restingHeight)
        }

        switch state {
        case .idle:
            return CGSize(width: restingWidth, height: restingHeight)

        case .compact:
            return CGSize(width: geom.compactPillWidth, height: restingHeight)

        case .minimal:
            return CGSize(width: restingWidth + geom.wingWidth, height: restingHeight)

        case .expanded:
            return CGSize(width: openNotchSize.width, height: openNotchSize.height)

        case .alertPop:
            // Top container remains resting notch height while the alert capsule blooms in belowArea
            let activeWidth = registeredActivities.isEmpty ? restingWidth : geom.compactPillWidth
            return CGSize(width: activeWidth, height: restingHeight)
        }
    }

    // MARK: - Hover Intent & Grace Sequencing

    public func onHoverEntered() {
        hoverIntentTask?.cancel()
        isHovering = true

        guard state != .expanded else { return }

        if state == .alertPop {
            alertDwellTask?.cancel()
            return
        }

        hoverIntentTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let delay = IslandMotion.shared.hoverOpenDelay * IslandMotion.shared.timeMultiplier
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, self.isHovering else { return }
            guard Defaults[.openNotchOnHover] else { return }

            self.transitionTo(.expanded)
        }
    }

    public func onHoverExited() {
        hoverIntentTask?.cancel()
        isHovering = false

        if state == .alertPop {
            scheduleAlertDwell(duration: 2.0)
            return
        }

        guard state == .expanded else { return }

        hoverIntentTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let grace = IslandMotion.shared.hoverCloseGrace * IslandMotion.shared.timeMultiplier
            if grace > 0 {
                try? await Task.sleep(nanoseconds: UInt64(grace * 1_000_000_000))
            }
            guard !Task.isCancelled, !self.isHovering else { return }
            guard !LiquidViewModel.shared.isBatteryPopoverActive else { return }
            guard !SharingStateManager.shared.preventNotchClose else { return }

            self.transitionTo(self.resolveRestingState())
        }
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
        let winWidth = window.frame.width
        let winHeight = window.frame.height

        let centerX = winWidth / 2.0
        let topY = winHeight

        let w = targetSize.width
        let h = targetSize.height

        let mainMinX = centerX - w / 2.0
        let mainMaxX = centerX + w / 2.0
        let mainMinY = topY - h
        let mainMaxY = topY

        let inMainShape = (point.x >= mainMinX && point.x <= mainMaxX && point.y >= mainMinY && point.y <= mainMaxY)
        if inMainShape {
            return true
        }

        if isDetachedBubbleVisible {
            let bubbleMinX = mainMaxX + detachedBubbleGap
            let bubbleMaxX = bubbleMinX + detachedBubbleSize.width
            let bubbleMinY = topY - detachedBubbleSize.height
            let bubbleMaxY = topY

            let inBubble = (point.x >= bubbleMinX && point.x <= bubbleMaxX && point.y >= bubbleMinY && point.y <= bubbleMaxY)
            if inBubble {
                return true
            }
        }

        return false
    }
}
