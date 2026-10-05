//
//  LiquidDropAlertView.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import Combine
import Defaults
import Foundation
import SwiftUI

// MARK: - Drop Animation Phase

public enum LiquidDropPhase: Equatable {
    case idle
    case anticipation  // Notch bottom swells downward (~0.12s)
    case birth         // Droplet emerges connected by neck (~0.18s)
    case release       // Neck snaps, droplet settles with squash & stretch (~0.12s)
    case bloom         // Droplet morphs into capsule, content fades in
    case hold          // Holding steady for duration
    case reverseShrink // Capsule shrinks back to droplet
    case reverseRise   // Droplet rises and merges into notch
}

// MARK: - Liquid Drop Alert Container

@available(*, deprecated, message: "Use LiveActivityTemplateView with LiquidIslandCanvasView and GenericAlertLiveActivityView instead.")
public struct LiquidDropAlertView: View {
    public let activity: LiveActivity
    public var onDismiss: () -> Void = {}

    @ObservedObject private var motion = IslandMotion.shared
    @State private var phase: LiquidDropPhase = .idle
    @State private var dropYOffset: CGFloat = 0.0
    @State private var dropScaleX: CGFloat = 1.0
    @State private var dropScaleY: CGFloat = 1.0
    @State private var capsuleProgress: CGFloat = 0.0 // 0.0 = circle droplet, 1.0 = expanded capsule
    @State private var contentOpacity: CGFloat = 0.0
    @State private var notchBulgeHeight: CGFloat = 0.0
    @State private var isHoveringCapsule: Bool = false
    @Namespace private var dropNamespace

    public init(activity: LiveActivity, onDismiss: @escaping () -> Void = {}) {
        self.activity = activity
        self.onDismiss = onDismiss
    }

    public var body: some View {
        Group {
            if motion.isReduceMotionActive {
                // Accessibility: Reduced Motion - simple quick fade & scale, no stretch
                reducedMotionAlertView
            } else {
                liquidDropAnimationView
            }
        }
        .avoidsNotch(id: "LiquidDropAlert:\(activity.id)")
        .onAppear {
            runDropSequence()
        }
    }

    // MARK: - Reduced Motion Fallback

    private var reducedMotionAlertView: some View {
        capsuleContentView
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(alertBackgroundShape)
            .opacity(contentOpacity)
            .scaleEffect(contentOpacity == 1.0 ? 1.0 : 0.95)
            .onAppear {
                withAnimation(.easeOut(duration: motion.reduceMotionDuration)) {
                    contentOpacity = 1.0
                }
            }
    }

    // MARK: - Native Liquid Drop Animation View

    private var liquidDropAnimationView: some View {
        VStack(spacing: 0) {
            // 1. Notch Bulge (Anticipation)
            if notchBulgeHeight > 0 {
                Capsule()
                    .fill(Color.black)
                    .frame(width: 44, height: notchBulgeHeight)
                    .offset(y: -notchBulgeHeight / 2)
                    .transition(.identity)
            }

            // 2. Glass Droplet & Blooming Capsule
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: motion.dropSpacing) {
                    dropGlassShape
                }
            } else {
                LiquidDropFallbackView(
                    progress: capsuleProgress,
                    dropOffset: dropYOffset,
                    stretchY: dropScaleY,
                    tint: activity.tint,
                    content: {
                        capsuleContentView
                            .opacity(contentOpacity)
                    }
                )
            }
        }
        .offset(y: dropYOffset)
        .scaleEffect(x: dropScaleX, y: dropScaleY, anchor: .top)
    }

    // MARK: - Glass Shape (macOS 26+)

    @available(macOS 26.0, *)
    @ViewBuilder
    private var dropGlassShape: some View {
        let capsuleWidth: CGFloat = 260.0
        let currentWidth = motion.dropDropletSize + (capsuleWidth - motion.dropDropletSize) * capsuleProgress
        let currentHeight: CGFloat = 38.0

        Capsule()
            .frame(width: currentWidth, height: currentHeight)
            .glassEffect(
                .regular
                    .tint(activity.tint.opacity(0.85))
                    .interactive(true),
                in: Capsule()
            )
            .glassEffectID("liquidDropCapsule", in: dropNamespace)
            .overlay(
                capsuleContentView
                    .opacity(contentOpacity)
            )
            .onHover { hovering in
                isHoveringCapsule = hovering
                LiveActivityCenter.shared.isHovering = hovering
            }
    }

    // MARK: - Capsule Inner Content

    private var capsuleContentView: some View {
        HStack(spacing: 10) {
            // Icon Badge
            if let icon = activity.payload.iconName {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(activity.payload.iconColor ?? activity.tint)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill((activity.payload.iconColor ?? activity.tint).opacity(0.2))
                    )
            }

            // Title & Subtitle
            VStack(alignment: .leading, spacing: 1) {
                Text(activity.payload.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let subtitle = activity.payload.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Optional percentage / battery or progress value
            if let val = activity.payload.value {
                Text("\(Int(val * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }

            // Dismiss Button
            Button(action: {
                reverseAndDismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    // MARK: - Background Shape for Fallback & Reduce Transparency

    @ViewBuilder
    private var alertBackgroundShape: some View {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            Capsule()
                .fill(Color(white: 0.14))
                .overlay(
                    Capsule().strokeBorder(activity.tint.opacity(0.4), lineWidth: 1)
                )
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [activity.tint.opacity(0.6), .white.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
        }
    }

    // MARK: - Phased Animation Sequence

    private func runDropSequence() {
        let tm = IslandMotion.shared.timeMultiplier

        // Phase 1: Anticipation (0.12s) - Notch swells downward
        phase = .anticipation
        withAnimation(.easeIn(duration: motion.dropAnticipationDuration * tm)) {
            notchBulgeHeight = 6.0
        }

        // Phase 2: Birth (0.18s) - Droplet emerges, neck forms, stretch vertically
        DispatchQueue.main.asyncAfter(deadline: .now() + (motion.dropAnticipationDuration * tm)) {
            phase = .birth
            withAnimation(.easeOut(duration: motion.dropBirthDuration * tm)) {
                dropYOffset = 24.0
                dropScaleY = CGFloat(motion.dropStretchY) // 1.25 vertical stretch
                dropScaleX = 0.88                         // Horizontal compression
            }

            // Phase 3: Release (0.12s) - Neck snaps, squash & stretch settle
            DispatchQueue.main.asyncAfter(deadline: .now() + (motion.dropBirthDuration * tm)) {
                phase = .release
                withAnimation(motion.dropSquashSpring) {
                    notchBulgeHeight = 0.0
                    dropYOffset = 36.0
                    dropScaleY = 1.0
                    dropScaleX = 1.0
                }

                // Phase 4: Bloom - Morph from droplet to capsule, fade content in
                DispatchQueue.main.asyncAfter(deadline: .now() + (motion.dropReleaseDuration * tm)) {
                    phase = .bloom
                    withAnimation(motion.expandSpring) {
                        capsuleProgress = 1.0
                    }
                    withAnimation(motion.contentInAnimation) {
                        contentOpacity = 1.0
                    }

                    // Phase 5: Hold for alert duration
                    phase = .hold
                }
            }
        }
    }

    // MARK: - Reverse Shrink & Rise on Dismissal

    public func reverseAndDismiss() {
        let tm = IslandMotion.shared.timeMultiplier

        guard phase != .reverseShrink && phase != .reverseRise else { return }
        phase = .reverseShrink

        // 1. Content fades out
        withAnimation(motion.contentOutAnimation) {
            contentOpacity = 0.0
        }

        // 2. Capsule shrinks back to droplet
        withAnimation(motion.collapseSpring) {
            capsuleProgress = 0.0
        }

        // 3. Droplet rises and merges into the notch
        DispatchQueue.main.asyncAfter(deadline: .now() + (motion.contentOutDuration * tm)) {
            phase = .reverseRise
            withAnimation(.easeInOut(duration: motion.dropBirthDuration * tm)) {
                dropYOffset = 0.0
                dropScaleY = 0.8
                notchBulgeHeight = 4.0
            }

            // Settle notch
            DispatchQueue.main.asyncAfter(deadline: .now() + (motion.dropBirthDuration * tm)) {
                withAnimation(.easeOut(duration: motion.dropAnticipationDuration * tm)) {
                    notchBulgeHeight = 0.0
                }
                onDismiss()
            }
        }
    }
}

// MARK: - Step 4: Liquid Drop Fallback (macOS 14 - 25)

/// Fallback view for systems without native GlassEffect:
/// Uses SwiftUI Canvas with blur and alphaThreshold on two shapes to form the gooey neck,
/// filled with ultraThinMaterial plus gradient specular highlights, a rim light, and an inner shadow.
public struct LiquidDropFallbackView<Content: View>: View {
    public var progress: CGFloat // 0.0 = droplet, 1.0 = capsule
    public var dropOffset: CGFloat
    public var stretchY: CGFloat
    public var tint: Color
    public var content: () -> Content

    public init(
        progress: CGFloat,
        dropOffset: CGFloat,
        stretchY: CGFloat,
        tint: Color,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.progress = progress
        self.dropOffset = dropOffset
        self.stretchY = stretchY
        self.tint = tint
        self.content = content
    }

    public var body: some View {
        let capsuleWidth: CGFloat = 260.0
        let dropletSize: CGFloat = 30.0
        let currentWidth = dropletSize + (capsuleWidth - dropletSize) * progress

        ZStack {
            // Gooey neck canvas
            Canvas { context, size in
                context.addFilter(.alphaThreshold(min: 0.5, color: .black))
                context.addFilter(.blur(radius: 8.0))

                context.drawLayer { ctx in
                    let centerX = size.width / 2.0
                    // Top neck anchor
                    let anchorRect = CGRect(x: centerX - 20, y: 0, width: 40, height: 12)
                    ctx.fill(Path(roundedRect: anchorRect, cornerRadius: 6), with: .color(.black))

                    // Falling droplet
                    let dropRect = CGRect(
                        x: centerX - (currentWidth / 2.0),
                        y: dropOffset,
                        width: currentWidth,
                        height: 38.0 * stretchY
                    )
                    ctx.fill(Path(roundedRect: dropRect, cornerRadius: 19), with: .color(.black))
                }
            }
            .frame(width: 320, height: 90)
            .mask(
                // Mask with material + specular rim highlights
                Capsule()
                    .frame(width: currentWidth, height: 38)
            )

            // Glass Styling: ultraThinMaterial, rim light, specular gradient highlight, inner shadow
            Capsule()
                .fill(.ultraThinMaterial)
                .frame(width: currentWidth, height: 38)
                .overlay(
                    // Specular gradient rim
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.8),
                                    .white.opacity(0.4),
                                    tint.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: tint.opacity(0.25), radius: 6, y: 2)
                .overlay(content())
        }
    }
}
