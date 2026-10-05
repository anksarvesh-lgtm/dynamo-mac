//
//  LiveActivityCenter.swift
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

/// Central hub managing all popups, HUDs, alerts, ongoing activities, and notifications.
/// Coordinates priority preemption, in-place coalescing, multi-activity limits,
/// screen sharing/presentation suppression, and hover pause behavior.
@MainActor
public final class LiveActivityCenter: ObservableObject {
    public static let shared = LiveActivityCenter()

    // MARK: - Active Presentation Slots

    /// Active liquid-drop popup alert
    @Published public private(set) var activeAlert: LiveActivity? = nil

    /// Active HUD (volume, brightness)
    @Published public private(set) var activeHUD: LiveActivity? = nil

    /// Active Progress task
    @Published public private(set) var activeProgress: LiveActivity? = nil

    /// Active Notification banner
    @Published public private(set) var activeNotification: LiveActivity? = nil

    /// Primary ongoing compact activity (left/right wings of the collapsed notch)
    @Published public private(set) var activeOngoing: LiveActivity? = nil

    /// Secondary ongoing activities (at most two minimal bubbles)
    @Published public private(set) var secondaryOngoing: [LiveActivity] = []

    // MARK: - Interaction States

    @Published public var isHovering: Bool = false {
        didSet {
            handleHoverChanged()
        }
    }

    @Published public var isDraggingSlider: Bool = false {
        didSet {
            if isDraggingSlider {
                // Cancel dismissal while user is actively dragging
                hudDismissTask?.cancel()
                hudDismissTask = nil
            } else {
                // Reschedule standard auto-dismissal 1.5s after release
                if let hud = activeHUD {
                    scheduleHUDDismissal(seconds: hud.duration ?? 1.5)
                }
            }
        }
    }

    // MARK: - Internal Queues & Timers

    private var pendingAlerts: [LiveActivity] = []
    private var alertDismissTask: Task<Void, Never>?
    private var hudDismissTask: Task<Void, Never>?
    private var notificationDismissTask: Task<Void, Never>?

    // Hover pause tracking
    private var alertRemainingDuration: TimeInterval = 0
    private var alertStartTime: Date = Date()
    private var notificationRemainingDuration: TimeInterval = 0
    private var notificationStartTime: Date = Date()

    // Deduplication tracking: key -> timestamp
    private var lastEmittedSignatures: [String: Date] = [:]
    private let dedupeWindowSeconds: TimeInterval = 0.4

    private var registeredSources: [String: LiveActivitySource] = [:]
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupObservers()
        registerDefaultSources()
    }

    private func registerDefaultSources() {
        registerSource(AudioActivitySource.shared)
        registerSource(DisplayBrightnessActivitySource.shared)
        registerSource(MicrophoneActivitySource.shared)
        registerSource(CameraActivitySource.shared)
        registerSource(PowerActivitySource.shared)
        registerSource(CapsLockActivitySource.shared)
        registerSource(TimerActivitySource.shared)
        registerSource(CalendarActivitySource.shared)
        registerSource(NetworkActivitySource.shared)
        registerSource(FocusModeActivitySource.shared)
    }

    private func setupObservers() {
        // Observe screen sharing & full-screen changes to preempt/suppress non-critical
        FullscreenMediaDetector.shared.$fullscreenStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.evaluateSuppression()
            }
            .store(in: &cancellables)
    }

    // MARK: - Source Registration

    public func registerSource(_ source: LiveActivitySource) {
        registeredSources[source.identifier] = source
        source.activityPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] activity in
                self?.submit(activity)
            }
            .store(in: &cancellables)
        source.start()
    }

    public func unregisterSource(_ identifier: String) {
        registeredSources[identifier]?.stop()
        registeredSources.removeValue(forKey: identifier)
    }

    // MARK: - Suppression Rules

    /// Checks if screen recording, screen sharing, or full-screen presentation is active.
    public var isSuppressionActive: Bool {
        // 1. Sharing state manager active session
        if SharingStateManager.shared.preventNotchClose {
            return true
        }

        // 2. Fullscreen presentations (Keynote, PowerPoint, or full-screen space active)
        let isFullscreenActive = FullscreenMediaDetector.shared.fullscreenStatus.values.contains(true)
        if isFullscreenActive {
            // Check frontmost app presentation mode
            if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
                if front.contains("keynote") || front.contains("powerpoint") || front.contains("zoom") || front.contains("meet") {
                    return true
                }
            }
        }

        // 3. Screen recording detection
        let recordingBundles = ["com.apple.QuickTimePlayerX", "com.apple.screencapture", "com.obsproject.obs-studio"]
        let isRecordingAppActive = NSWorkspace.shared.runningApplications.contains { app in
            guard let bid = app.bundleIdentifier else { return false }
            return recordingBundles.contains(bid) && !app.isTerminated
        }
        if isRecordingAppActive && Defaults[.hideFromScreenRecording] {
            return true
        }

        return false
    }

    private func evaluateSuppression() {
        if isSuppressionActive {
            // Dismiss active non-critical alert/HUD
            if let alert = activeAlert, alert.priority < LiveActivityPriority.critical {
                dismissAlert(immediate: true)
            }
            if let notif = activeNotification, notif.priority < LiveActivityPriority.critical {
                dismissNotification()
            }
        }
    }

    // MARK: - Primary Submission Dispatcher

    public func submit(_ activity: LiveActivity) {
        // Rule 5: Honor per-source toggles from ModuleCatalog
        guard ModuleCatalog.shared.isSourceEnabled(activity.source) else {
            return
        }

        // Rule 6: Suppress non-critical activities during screen sharing/recording/presentation
        if isSuppressionActive && activity.priority < LiveActivityPriority.critical {
            return
        }

        // Apply per-source custom duration and severity from ModuleCatalog
        var configured = activity
        if configured.duration != nil {
            configured.duration = ModuleCatalog.shared.sourceDuration(for: activity.source)
        }
        if configured.priority < LiveActivityPriority.critical {
            configured.tint = ModuleCatalog.shared.sourceSeverity(for: activity.source).color
        }

        // Rule 4: Deduplicate rapid duplicate submissions
        let signature = "\(configured.source):\(configured.payload.title):\(configured.payload.value ?? 0)"
        if let last = lastEmittedSignatures[signature], Date().timeIntervalSince(last) < dedupeWindowSeconds {
            // If same coalescing key and value changed slightly, allow update; otherwise drop duplicate
            if configured.coalescingKey == nil {
                return
            }
        }
        lastEmittedSignatures[signature] = Date()

        // Route by Kind
        switch configured.kind {
        case .hud:
            handleHUDSubmission(configured)
        case .alert:
            handleAlertSubmission(configured)
        case .notification:
            handleNotificationSubmission(configured)
        case .progress:
            handleProgressSubmission(configured)
        case .ongoing:
            handleOngoingSubmission(configured)
        }
    }

    // MARK: - HUD Routing & In-Place Coalescing

    private func handleHUDSubmission(_ activity: LiveActivity) {
        // Rule 2: Coalescing in-place for same coalescing key (e.g. volume sweeps)
        if let current = activeHUD, current.coalescingKey != nil && current.coalescingKey == activity.coalescingKey {
            // Mutate current HUD smoothly without creating a new popup or restarting animations
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.85)) {
                self.activeHUD = activity
            }
            if !isDraggingSlider {
                scheduleHUDDismissal(seconds: activity.duration ?? 1.5)
            }
            return
        }

        // Rule 1: Priority preemption
        withAnimation(IslandMotion.shared.expandSpring) {
            self.activeHUD = activity
        }

        if !isDraggingSlider {
            scheduleHUDDismissal(seconds: activity.duration ?? 1.5)
        }
    }

    public func dismissHUD() {
        hudDismissTask?.cancel()
        hudDismissTask = nil
        withAnimation(IslandMotion.shared.contentOutAnimation) {
            self.activeHUD = nil
        }
    }

    private func scheduleHUDDismissal(seconds: TimeInterval) {
        hudDismissTask?.cancel()
        hudDismissTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let duration = seconds * IslandMotion.shared.timeMultiplier
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard !self.isDraggingSlider else { return }
            self.dismissHUD()
        }
    }

    // MARK: - Alert Routing & Preemption

    private func handleAlertSubmission(_ activity: LiveActivity) {
        // Rule 2: Same coalescing key updates in place
        if let current = activeAlert, current.coalescingKey != nil && current.coalescingKey == activity.coalescingKey {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                self.activeAlert = activity
            }
            scheduleAlertDismissal(seconds: activity.duration ?? 3.5)
            return
        }

        // Rule 1: Higher priority preempts active alert
        if let current = activeAlert {
            if activity.priority > current.priority {
                // Preempt: push current back to pending queue
                pendingAlerts.insert(current, at: 0)
                presentAlert(activity)
            } else {
                // Enqueue behind sorted by priority
                pendingAlerts.append(activity)
                pendingAlerts.sort { $0.priority > $1.priority }
            }
        } else {
            presentAlert(activity)
        }
    }

    private func presentAlert(_ activity: LiveActivity) {
        alertDismissTask?.cancel()
        alertStartTime = Date()
        alertRemainingDuration = activity.duration ?? 3.5

        withAnimation(IslandMotion.shared.expandSpring) {
            self.activeAlert = activity
        }

        if let duration = activity.duration {
            scheduleAlertDismissal(seconds: duration)
        }
    }

    public func dismissAlert(immediate: Bool = false) {
        alertDismissTask?.cancel()
        alertDismissTask = nil

        let anim = immediate ? nil : IslandMotion.shared.collapseSpring
        withAnimation(anim) {
            self.activeAlert = nil
        }

        // Check if there is another queued alert
        if !pendingAlerts.isEmpty {
            let next = pendingAlerts.removeFirst()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.presentAlert(next)
            }
        }
    }

    private func scheduleAlertDismissal(seconds: TimeInterval) {
        alertDismissTask?.cancel()
        alertStartTime = Date()
        alertRemainingDuration = seconds

        alertDismissTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let duration = seconds * IslandMotion.shared.timeMultiplier
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }

            // If user is hovering and hover pause is enabled, do not dismiss yet
            if self.isHovering && (self.activeAlert?.pauseDismissalOnHover ?? true) {
                return
            }

            self.dismissAlert()
        }
    }

    // MARK: - Notification Routing

    private func handleNotificationSubmission(_ activity: LiveActivity) {
        withAnimation(IslandMotion.shared.expandSpring) {
            self.activeNotification = activity
        }

        let duration = activity.duration ?? 4.0
        scheduleNotificationDismissal(seconds: duration)
    }

    public func dismissNotification() {
        notificationDismissTask?.cancel()
        notificationDismissTask = nil
        withAnimation(IslandMotion.shared.collapseSpring) {
            self.activeNotification = nil
        }
    }

    private func scheduleNotificationDismissal(seconds: TimeInterval) {
        notificationDismissTask?.cancel()
        notificationStartTime = Date()
        notificationRemainingDuration = seconds

        notificationDismissTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let duration = seconds * IslandMotion.shared.timeMultiplier
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }

            if self.isHovering && (self.activeNotification?.pauseDismissalOnHover ?? true) {
                return
            }

            self.dismissNotification()
        }
    }

    // MARK: - Progress Routing

    private func handleProgressSubmission(_ activity: LiveActivity) {
        withAnimation(IslandMotion.shared.expandSpring) {
            self.activeProgress = activity
        }

        // If completed (value >= 1.0), auto dismiss after 1.5s
        if let val = activity.payload.value, val >= 1.0 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if self?.activeProgress?.id == activity.id {
                    withAnimation(IslandMotion.shared.collapseSpring) {
                        self?.activeProgress = nil
                    }
                }
            }
        }
    }

    public func dismissProgress() {
        withAnimation(IslandMotion.shared.collapseSpring) {
            self.activeProgress = nil
        }
    }

    public func dismissOngoing() {
        withAnimation(IslandMotion.shared.collapseSpring) {
            self.activeOngoing = nil
            self.secondaryOngoing.removeAll()
        }
    }

    // MARK: - Ongoing Activities (Compact Wing + Up to 2 Minimal Bubbles)

    private func handleOngoingSubmission(_ activity: LiveActivity) {
        // If primary slot is empty or this activity has higher priority
        if activeOngoing == nil || (activeOngoing?.id == activity.id) {
            withAnimation(IslandMotion.shared.expandSpring) {
                self.activeOngoing = activity
            }
        } else if let primary = activeOngoing, activity.priority > primary.priority {
            // Demote previous primary to secondary bubble
            let previous = primary
            self.activeOngoing = activity
            demoteToSecondary(previous)
        } else {
            // Add or update in secondary bubbles
            demoteToSecondary(activity)
        }
    }

    private func demoteToSecondary(_ activity: LiveActivity) {
        // Update existing if present
        if let index = secondaryOngoing.firstIndex(where: { $0.id == activity.id }) {
            secondaryOngoing[index] = activity
            return
        }

        // Rule 3: At most two minimal bubbles
        if secondaryOngoing.count < 2 {
            withAnimation(IslandMotion.shared.expandSpring) {
                secondaryOngoing.append(activity)
            }
        } else {
            // Replace lowest priority in secondary if new one has higher priority
            if let lowestIndex = secondaryOngoing.indices.min(by: { secondaryOngoing[$0].priority < secondaryOngoing[$1].priority }),
               activity.priority > secondaryOngoing[lowestIndex].priority {
                secondaryOngoing[lowestIndex] = activity
            }
        }
    }

    public func removeOngoing(id: String) {
        if activeOngoing?.id == id {
            withAnimation(IslandMotion.shared.collapseSpring) {
                if !self.secondaryOngoing.isEmpty {
                    self.activeOngoing = self.secondaryOngoing.removeFirst()
                } else {
                    self.activeOngoing = nil
                }
            }
        } else {
            secondaryOngoing.removeAll { $0.id == id }
        }
    }

    // MARK: - Hover State Changes & Dwell Resumption

    private func handleHoverChanged() {
        if isHovering {
            // Hover paused: record elapsed time and cancel scheduled tasks
            let elapsedAlert = Date().timeIntervalSince(alertStartTime)
            alertRemainingDuration = max(0.5, alertRemainingDuration - elapsedAlert)
            alertDismissTask?.cancel()

            let elapsedNotif = Date().timeIntervalSince(notificationStartTime)
            notificationRemainingDuration = max(0.5, notificationRemainingDuration - elapsedNotif)
            notificationDismissTask?.cancel()
        } else {
            // Mouse exited: resume timers with remaining duration
            if let alert = activeAlert, alert.pauseDismissalOnHover, alert.duration != nil {
                scheduleAlertDismissal(seconds: alertRemainingDuration)
            }
            if let notif = activeNotification, notif.pauseDismissalOnHover, notif.duration != nil {
                scheduleNotificationDismissal(seconds: notificationRemainingDuration)
            }
            if let hud = activeHUD, !isDraggingSlider {
                scheduleHUDDismissal(seconds: 1.0)
            }
        }
    }
}
