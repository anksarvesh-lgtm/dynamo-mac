//
//  LiquidFlowCoordinator.swift
//  LiquidDynamo
//
//  Step C: Fluid Flow Lifecycle Coordinator (Stream, Swell, Hold, Drain, Absorb).
//  Physics-driven, interruptible with velocity handoff, and zero chained delayed dispatch.
//

import AppKit
import Combine
import Foundation
import SwiftUI

// MARK: - 1. Flow Phase

public enum LiquidFlowPhase: String, Sendable, Equatable {
    case resting    // Inside notch, zero fluid visible
    case stream     // Downward flowing stream emerging from hardware notch
    case swell      // Leading drop arriving at destination and swelling outward
    case hold       // Equilibrium reached, content floating inside liquid
    case drain      // Content fades out first, fluid contracts toward stream and accelerates upward
    case absorb     // Fluid merges up past notch lip with small absorption ripple
}

// MARK: - 2. Fluid Flow Coordinator

@MainActor
public final class LiquidFlowCoordinator: ObservableObject {
    public static let shared = LiquidFlowCoordinator()

    // MARK: - Observable Flow State
    @Published public private(set) var phase: LiquidFlowPhase = .resting
    @Published public private(set) var emergenceProgress: CGFloat = 0.0 // 0.0 = notch lip, 1.0 = fully emerged
    @Published public private(set) var streamThickness: CGFloat = 0.0   // Connecting neck thickness
    @Published public private(set) var massScale: CGFloat = 0.0         // Scale of swelling droplet
    @Published public private(set) var contentAlpha: CGFloat = 0.0      // Opacity of floating content inside fluid
    @Published public private(set) var absorptionRipple: CGFloat = 0.0  // Receding ripple on notch absorption
    @Published public private(set) var currentSeed: CGFloat = 42.0      // Unique per-appearance seed

    // Interaction & Hold tracking
    @Published public var isHovering: Bool = false {
        didSet {
            handleHoverChanged()
        }
    }
    @Published public var cursorLean: CGFloat = 0.0 // Attraction lean towards mouse

    // Active Activity / Content reference
    @Published public private(set) var activeActivityId: String? = nil
    @Published public private(set) var clusters: [ContentDrivenBlobGenerator.ContentCluster] = []

    // Motion & Physics
    private var motion = IslandMotion.shared
    private var dwellTimerTask: Task<Void, Never>?
    private var dwellRemainingSeconds: TimeInterval = 0.0
    private var dwellStartTime: Date = Date()
    private var dismissHandler: (() -> Void)? = nil

    // Velocity state for smooth spring retargeting
    private var emergenceVelocity: CGFloat = 0.0
    private var lastEmergenceUpdateTime: Date = Date()

    public init() {}

    // MARK: - Flow Lifecycle: Emerge (Stream -> Swell -> Hold)

    /// Triggers the liquid emergence flow for a given content cluster set.
    /// If an event arrives mid-flow, this seamlessly retargets the flow with velocity handoff.
    public func emerge(
        activityId: String,
        clusters: [ContentDrivenBlobGenerator.ContentCluster],
        dwellDuration: TimeInterval = 3.5,
        onDismiss: (() -> Void)? = nil
    ) {
        // Cancel any pending dwell timers
        dwellTimerTask?.cancel()
        dwellTimerTask = nil

        self.activeActivityId = activityId
        self.clusters = clusters
        self.dismissHandler = onDismiss

        // Generate new random per-appearance seed if emerging from resting
        if phase == .resting || phase == .absorb {
            self.currentSeed = CGFloat(Int.random(in: 1...9999))
        }

        // Accessibility: Reduce Motion
        if motion.isReduceMotionActive {
            runReducedMotionEmerge(dwellDuration: dwellDuration)
            return
        }

        // Interruptible Velocity Handoff: calculate time multiplier for slow-mo testing (e.g. 0.25x speed)
        let timeMultiplier = motion.timeMultiplier
        let flowSpring = Animation.spring(
            response: motion.expandResponse * 0.95 * timeMultiplier,
            dampingFraction: 0.78,
            blendDuration: 0.1
        )

        // Phase 1: Stream & Swell
        phase = (emergenceProgress < 0.35) ? .stream : .swell

        withAnimation(flowSpring) {
            self.emergenceProgress = 1.0
            self.streamThickness = 1.0
            self.massScale = 1.0
            self.absorptionRipple = 0.0
        }

        // Content fades in gently as the drop begins to swell
        let contentFadeSpring = Animation.easeOut(duration: 0.22 * timeMultiplier).delay(0.12 * timeMultiplier)
        withAnimation(contentFadeSpring) {
            self.contentAlpha = 1.0
        }

        // Transition to Hold state once emergence reaches target
        let totalEmergenceDuration = motion.expandResponse * timeMultiplier
        Task {
            try? await Task.sleep(for: .milliseconds(Int(totalEmergenceDuration * 750)))
            guard !Task.isCancelled, self.activeActivityId == activityId else { return }
            await MainActor.run {
                if self.phase == .stream || self.phase == .swell {
                    self.phase = .hold
                    self.startDwellTimer(seconds: dwellDuration)
                }
            }
        }
    }

    // MARK: - Flow Lifecycle: Drain & Absorb

    /// Retargets the fluid back up into the hardware notch.
    /// Content fades out FIRST, then the liquid contracts inward and drains into the notch.
    public func drain() {
        dwellTimerTask?.cancel()
        dwellTimerTask = nil

        guard phase != .resting && phase != .absorb else { return }

        // Accessibility: Reduce Motion
        if motion.isReduceMotionActive {
            runReducedMotionDrain()
            return
        }

        let timeMultiplier = motion.timeMultiplier
        phase = .drain

        // STEP 1: Content fades out first with fast easeOut
        withAnimation(.easeOut(duration: 0.14 * timeMultiplier)) {
            self.contentAlpha = 0.0
        }

        // STEP 2: Mass contracts toward stream axis and accelerates upward into notch
        let drainSpring = Animation.spring(
            response: motion.collapseResponse * 0.92 * timeMultiplier,
            dampingFraction: 0.84,
            blendDuration: 0.08
        )

        withAnimation(drainSpring) {
            self.emergenceProgress = 0.0
            self.streamThickness = 0.2
            self.massScale = 0.1
        }

        // STEP 3: Absorption at notch bottom lip with a small dissipating ripple
        let drainDuration = motion.collapseResponse * timeMultiplier
        Task {
            try? await Task.sleep(for: .milliseconds(Int(drainDuration * 800)))
            guard !Task.isCancelled, self.phase == .drain else { return }
            await MainActor.run {
                self.phase = .absorb
                withAnimation(.interpolatingSpring(mass: 0.5, stiffness: 45.0, damping: 6.0, initialVelocity: 4.0)) {
                    self.absorptionRipple = 1.0
                }

                // Final resting state
                Task {
                    try? await Task.sleep(for: .milliseconds(Int(250 * timeMultiplier)))
                    guard !Task.isCancelled, self.phase == .absorb else { return }
                    await MainActor.run {
                        self.phase = .resting
                        self.emergenceProgress = 0.0
                        self.streamThickness = 0.0
                        self.massScale = 0.0
                        self.absorptionRipple = 0.0
                        self.activeActivityId = nil
                        self.clusters.removeAll()
                        self.dismissHandler?()
                        self.dismissHandler = nil
                    }
                }
            }
        }
    }

    // MARK: - Dwell Timer & Hover Pause

    private func startDwellTimer(seconds: TimeInterval) {
        dwellRemainingSeconds = seconds
        dwellStartTime = Date()

        guard !isHovering else { return }

        dwellTimerTask = Task {
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000 * motion.timeMultiplier)))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if !self.isHovering {
                    self.drain()
                }
            }
        }
    }

    private func handleHoverChanged() {
        if isHovering {
            // Pause auto-dismissal while hovered
            dwellTimerTask?.cancel()
            dwellTimerTask = nil
            let elapsed = Date().timeIntervalSince(dwellStartTime)
            dwellRemainingSeconds = max(0.5, dwellRemainingSeconds - elapsed)
        } else {
            // Resume dismissal when mouse leaves
            if phase == .hold && dwellRemainingSeconds > 0 {
                startDwellTimer(seconds: dwellRemainingSeconds)
            }
        }
    }

    // MARK: - Reduced Motion Mode

    private func runReducedMotionEmerge(dwellDuration: TimeInterval) {
        phase = .hold
        let duration = motion.reduceMotionDuration * motion.timeMultiplier

        withAnimation(.easeOut(duration: duration)) {
            self.emergenceProgress = 1.0
            self.streamThickness = 1.0
            self.massScale = 1.0
            self.contentAlpha = 1.0
            self.absorptionRipple = 0.0
        }

        startDwellTimer(seconds: dwellDuration)
    }

    private func runReducedMotionDrain() {
        phase = .drain
        let duration = motion.reduceMotionDuration * motion.timeMultiplier

        withAnimation(.easeIn(duration: duration)) {
            self.contentAlpha = 0.0
            self.emergenceProgress = 0.0
            self.massScale = 0.0
        }

        Task {
            try? await Task.sleep(for: .milliseconds(Int(duration * 1000)))
            await MainActor.run {
                self.phase = .resting
                self.streamThickness = 0.0
                self.activeActivityId = nil
                self.clusters.removeAll()
                self.dismissHandler?()
                self.dismissHandler = nil
            }
        }
    }
}
