//
//  IslandMotion.swift
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

// MARK: - Centralized Motion Physics & Tokens

/// Single source of truth for motion parameters, spring curves, and content transitions.
/// Includes dynamic tuning properties that update live when sliders in the debug panel move.
@MainActor
public final class IslandMotion: ObservableObject {
    public static let shared = IslandMotion()

    // MARK: - Live Tuning Properties (Observable)

    /// Slow-motion multiplier (1.0 = normal, 0.5 = 2x slower, 0.25 = 4x slower, 0.1 = 10x slower).
    @Published public var speedMultiplier: Double = 1.0

    // Expand Spring
    @Published public var expandResponse: Double = 0.45
    @Published public var expandDamping: Double = 0.75

    // Collapse Spring
    @Published public var collapseResponse: Double = 0.36
    @Published public var collapseDamping: Double = 0.86
    @Published public var collapseDelay: Double = 0.10

    // Alert Pop Spring
    @Published public var alertPopResponse: Double = 0.40
    @Published public var alertPopDamping: Double = 0.65

    // Content Out Parameters
    @Published public var contentOutDuration: Double = 0.15
    @Published public var contentOutBlur: Double = 10.0
    @Published public var contentOutScale: Double = 0.95

    // Content In Parameters
    @Published public var contentInDelay: Double = 0.09
    @Published public var contentInDuration: Double = 0.28
    @Published public var contentInBlur: Double = 10.0
    @Published public var contentInScale: Double = 0.95

    // Compact Content Swap
    @Published public var compactSwapDuration: Double = 0.30

    // Interaction Delays & Grace
    @Published public var hoverOpenDelay: Double = 0.10
    @Published public var hoverCloseGrace: Double = 0.25
    @Published public var alertDwellDuration: Double = 3.50

    // Subsystem Animations (moved from hardcoded values)
    @Published public var tabSwitchDuration: Double = 0.25
    @Published public var sliderSpringResponse: Double = 0.35
    @Published public var sliderSpringDamping: Double = 0.70
    @Published public var cameraSpringResponse: Double = 0.32
    @Published public var cameraSpringDamping: Double = 0.76

    // Liquid Glass Drop Timing & Dynamics
    @Published public var dropAnticipationDuration: Double = 0.12
    @Published public var dropBirthDuration: Double = 0.18
    @Published public var dropReleaseDuration: Double = 0.12
    @Published public var dropSquashResponse: Double = 0.40
    @Published public var dropSquashDamping: Double = 0.65
    @Published public var dropDropletSize: Double = 30.0
    @Published public var dropSpacing: Double = 35.0
    @Published public var dropStretchY: Double = 1.25

    // Reduce Motion & Simple Style Overrides
    @Published public var isReduceMotionForced: Bool = false
    public let reduceMotionDuration: Double = 0.20

    private init() {}

    // MARK: - Time Multiplier Helper

    /// Effective time scaling factor. E.g. speedMultiplier = 0.1 => timeMultiplier = 10.0.
    public var timeMultiplier: Double {
        let valid = max(speedMultiplier, 0.01)
        return 1.0 / valid
    }

    /// True if system accessibility or manual debug override requests reduced motion.
    public var isReduceMotionActive: Bool {
        isReduceMotionForced || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// True if Simple animation style is active in settings or Reduce Motion is engaged.
    public var isSimpleAnimationActive: Bool {
        Defaults[.animationStyle] == .simple || isReduceMotionActive
    }

    // MARK: - Active Animation Curves

    /// Spring used when either width or height expands.
    public var expandSpring: Animation {
        if isSimpleAnimationActive {
            return .easeInOut(duration: reduceMotionDuration * timeMultiplier)
        }
        return .spring(
            response: expandResponse * timeMultiplier,
            dampingFraction: expandDamping,
            blendDuration: 0
        )
    }

    /// Spring used when both width and height collapse.
    public var collapseSpring: Animation {
        if isSimpleAnimationActive {
            return .easeInOut(duration: reduceMotionDuration * timeMultiplier)
        }
        return .spring(
            response: collapseResponse * timeMultiplier,
            dampingFraction: collapseDamping,
            blendDuration: 0
        )
    }

    /// Spring used for high-priority alert popups with punchy overshoot.
    public var alertPopSpring: Animation {
        if isSimpleAnimationActive {
            return .easeInOut(duration: reduceMotionDuration * timeMultiplier)
        }
        return .spring(
            response: alertPopResponse * timeMultiplier,
            dampingFraction: alertPopDamping,
            blendDuration: 0
        )
    }

    /// Spring used when the liquid droplet snaps from the neck and settles with squash-and-stretch.
    public var dropSquashSpring: Animation {
        if isSimpleAnimationActive {
            return .easeInOut(duration: reduceMotionDuration * timeMultiplier)
        }
        return .spring(
            response: dropSquashResponse * timeMultiplier,
            dampingFraction: dropSquashDamping,
            blendDuration: 0
        )
    }

    /// Phase 1: Content exiting during a container state transition.
    public var contentOutAnimation: Animation {
        if isSimpleAnimationActive {
            return .easeOut(duration: (reduceMotionDuration / 2) * timeMultiplier)
        }
        return .easeOut(duration: contentOutDuration * timeMultiplier)
    }

    /// Phase 3: Content entering after the container begins deforming.
    public var contentInAnimation: Animation {
        if isSimpleAnimationActive {
            return .easeIn(duration: (reduceMotionDuration / 2) * timeMultiplier)
        }
        return .easeOut(duration: contentInDuration * timeMultiplier)
            .delay(contentInDelay * timeMultiplier)
    }

    /// Compact mode content crossfade animation.
    public var compactSwapAnimation: Animation {
        .easeInOut(duration: compactSwapDuration * timeMultiplier)
    }

    /// Subsystem: Slider thumb tracking spring.
    public var sliderSpring: Animation {
        if isSimpleAnimationActive { return .linear(duration: 0.1) }
        return .spring(
            response: sliderSpringResponse * timeMultiplier,
            dampingFraction: sliderSpringDamping,
            blendDuration: 0
        )
    }

    /// Subsystem: Camera preview toggle spring.
    public var cameraSpring: Animation {
        if isSimpleAnimationActive { return .easeInOut(duration: reduceMotionDuration) }
        return .interactiveSpring(
            response: cameraSpringResponse * timeMultiplier,
            dampingFraction: cameraSpringDamping,
            blendDuration: 0
        )
    }

    // MARK: - Spring Selection Rule

    /// "Use the expand spring when either dimension grows and the collapse spring when both shrink."
    /// On collapse, delays container resize slightly so exiting content can fade out cleanly first.
    public func spring(from oldSize: CGSize, to newSize: CGSize, isAlert: Bool = false) -> Animation {
        if isSimpleAnimationActive {
            return .easeInOut(duration: reduceMotionDuration * timeMultiplier)
        }
        if isAlert {
            return alertPopSpring
        }
        if newSize.width > oldSize.width || newSize.height > oldSize.height {
            return expandSpring
        } else {
            return collapseSpring.delay(collapseDelay * timeMultiplier)
        }
    }

    // MARK: - Geometry & Dynamic Corner Radius Tokens

    /// Apple continuous curvature: corner radius scales continuously with container height.
    public func bottomCornerRadius(forHeight height: CGFloat) -> CGFloat {
        let scaled = height * 0.44
        return min(max(scaled, 14.0), 28.0)
    }

    /// Top corner radius: blends into the hardware notch top ears.
    public func topCornerRadius(isExpanded: Bool) -> CGFloat {
        isExpanded ? 19.0 : 6.0
    }

    // MARK: - Reset to Defaults

    public func resetToDefaults() {
        speedMultiplier = 1.0
        expandResponse = 0.45
        expandDamping = 0.75
        collapseResponse = 0.36
        collapseDamping = 0.86
        collapseDelay = 0.10
        alertPopResponse = 0.40
        alertPopDamping = 0.65
        contentOutDuration = 0.15
        contentOutBlur = 10.0
        contentOutScale = 0.95
        contentInDelay = 0.09
        contentInDuration = 0.28
        contentInBlur = 10.0
        contentInScale = 0.95
        compactSwapDuration = 0.30
        hoverOpenDelay = 0.10
        hoverCloseGrace = 0.25
        alertDwellDuration = 3.50
        dropAnticipationDuration = 0.12
        dropBirthDuration = 0.18
        dropReleaseDuration = 0.12
        dropSquashResponse = 0.40
        dropSquashDamping = 0.65
        dropDropletSize = 30.0
        dropSpacing = 35.0
        dropStretchY = 1.25
        isReduceMotionForced = false
    }
}

// MARK: - View Modifiers for Staggered Content Pipeline

public struct IslandContentExitModifier: ViewModifier {
    public let isExiting: Bool
    @ObservedObject private var motion = IslandMotion.shared

    public init(isExiting: Bool) {
        self.isExiting = isExiting
    }

    public func body(content: Content) -> some View {
        let blurAmount = motion.isSimpleAnimationActive ? 0.0 : (isExiting ? motion.contentOutBlur : 0.0)
        let scaleAmount = motion.isSimpleAnimationActive ? 1.0 : (isExiting ? motion.contentOutScale : 1.0)
        let opacityAmount = isExiting ? 0.0 : 1.0

        return content
            .opacity(opacityAmount)
            .blur(radius: blurAmount)
            .scaleEffect(scaleAmount)
            .animation(motion.contentOutAnimation, value: isExiting)
    }
}

public struct IslandContentEnterModifier: ViewModifier {
    public let isVisible: Bool
    @ObservedObject private var motion = IslandMotion.shared

    public init(isVisible: Bool) {
        self.isVisible = isVisible
    }

    public func body(content: Content) -> some View {
        let blurAmount = motion.isSimpleAnimationActive ? 0.0 : (isVisible ? 0.0 : motion.contentInBlur)
        let scaleAmount = motion.isSimpleAnimationActive ? 1.0 : (isVisible ? 1.0 : motion.contentInScale)
        let opacityAmount = isVisible ? 1.0 : 0.0

        return content
            .opacity(opacityAmount)
            .blur(radius: blurAmount)
            .scaleEffect(scaleAmount)
            .animation(motion.contentInAnimation, value: isVisible)
    }
}

public struct CompactContentSwapModifier<ID: Hashable>: ViewModifier {
    public let id: ID
    @ObservedObject private var motion = IslandMotion.shared

    public init(id: ID) {
        self.id = id
    }

    public func body(content: Content) -> some View {
        content
            .id(id)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: motion.isSimpleAnimationActive ? 1.0 : motion.contentInScale)),
                    removal: .opacity.combined(with: .scale(scale: motion.isSimpleAnimationActive ? 1.0 : motion.contentOutScale))
                )
            )
            .animation(motion.compactSwapAnimation, value: id)
    }
}

public extension View {
    func islandContentOut(when isExiting: Bool) -> some View {
        modifier(IslandContentExitModifier(isExiting: isExiting))
    }

    func islandContentIn(when isVisible: Bool) -> some View {
        modifier(IslandContentEnterModifier(isVisible: isVisible))
    }

    func islandCompactSwap<ID: Hashable>(id: ID) -> some View {
        modifier(CompactContentSwapModifier(id: id))
    }
}

