//
//  LiveActivityTemplateView.swift
//  LiquidDynamo
//
//  Step 2 Unified Live Activity Template View with Auto-Sizing Pipeline & SDF Liquid Physics.
//  Accommodates volume, brightness, battery, and future complex activities.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

// MARK: - Template Presentation Mode

public enum LiveActivityPresentationMode {
    case compactWings          // Top band wing slots (strictly in leftSlot & rightSlot)
    case liquidDropletBloom    // Organic SDF droplet emergence below the notch
}

// MARK: - Liquid Template View

public struct LiveActivityTemplateView<Content: View>: View {
    public let mode: LiveActivityPresentationMode
    public var tintColor: Color
    public var dwellDuration: TimeInterval
    public var onDismiss: () -> Void
    public var content: () -> Content

    @StateObject private var sizingCoordinator = LiquidIslandSizingCoordinator()
    @ObservedObject private var motion = IslandMotion.shared
    @ObservedObject private var hub = LiveActivityCenter.shared

    // SDF Lobe Animation State
    @State private var phase: LiquidDropPhase = .idle
    @State private var rootBulge: CGFloat = 0.0
    @State private var dropletY: CGFloat = 0.0
    @State private var dropletScale: CGFloat = 0.0
    @State private var bodyScale: CGFloat = 0.0
    @State private var contentAlpha: CGFloat = 0.0
    @State private var kSmooth: CGFloat = 24.0
    @State private var isHoveringTemplate: Bool = false
    @State private var dragOffset: CGFloat = 0.0

    @State private var dwellTask: Task<Void, Never>?
    @State private var dwellRemaining: TimeInterval = 0.0
    @State private var dwellStartTime: Date = Date()

    public init(
        mode: LiveActivityPresentationMode = .liquidDropletBloom,
        tintColor: Color = Color(red: 0.06, green: 0.78, blue: 0.48),
        dwellDuration: TimeInterval = 3.5,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.mode = mode
        self.tintColor = tintColor
        self.dwellDuration = dwellDuration
        self.onDismiss = onDismiss
        self.content = content
    }

    public var body: some View {
        Group {
            switch mode {
            case .compactWings:
                compactWingsContainer
            case .liquidDropletBloom:
                liquidBloomContainer
            }
        }
    }

    // MARK: - 1. Compact Wings Presentation (Top Band)

    private var compactWingsContainer: some View {
        content()
            .avoidsNotch(id: "TemplateCompactWings")
    }

    // MARK: - 2. Liquid Droplet Bloom Presentation (Below Notch)

    private var liquidBloomContainer: some View {
        let geom = NotchSafeAreaEngine.shared.currentGeometry
        let bodyW = sizingCoordinator.currentBodySize.width
        let bodyH = sizingCoordinator.currentBodySize.height

        return ZStack {
            // Liquid Backdrop Layer
            if !motion.isReduceMotionActive {
                liquidSDFBackdrop(bodyW: bodyW, bodyH: bodyH, geom: geom)
            } else {
                reducedMotionBackdrop(bodyW: bodyW, bodyH: bodyH)
            }

            // Measured Content Layer
            content()
                .measureIntrinsicContentSize { measuredSize in
                    sizingCoordinator.updateMeasuredSize(measuredSize)
                }
                .opacity(contentAlpha)
                .frame(width: max(160, bodyW - 20), height: max(32, bodyH - 10))
                .clipped()
        }
        .frame(width: bodyW, height: bodyH)
        .offset(y: dragOffset)
        .scaleEffect(
            x: motion.isReduceMotionActive ? 1.0 : (0.85 + 0.15 * bodyScale),
            y: motion.isReduceMotionActive ? 1.0 : (0.85 + 0.15 * bodyScale),
            anchor: .top
        )
        .avoidsNotch(id: "TemplateLiquidBloom")
        .onHover { hovering in
            isHoveringTemplate = hovering
            hub.isHovering = hovering
            handleHoverChanged(hovering)
        }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { gesture in
                    if gesture.translation.height < 0 {
                        dragOffset = gesture.translation.height
                    }
                }
                .onEnded { gesture in
                    if gesture.translation.height < -25 || gesture.velocity.height < -120 {
                        // Swipe-up flick dismiss
                        withAnimation(motion.collapseSpring) {
                            dragOffset = -60
                            bodyScale = 0.0
                            contentAlpha = 0.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            onDismiss()
                        }
                    } else {
                        // Snap back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            dragOffset = 0.0
                        }
                    }
                }
        )
        .onAppear {
            runDropletBloomLifecycle()
        }
        .onDisappear {
            dwellTask?.cancel()
            dwellTask = nil
        }
    }

    // MARK: - 3. Liquid SDF Backdrop (Metal Shader with Dynamic Lobes)

    @ViewBuilder
    private func liquidSDFBackdrop(bodyW: CGFloat, bodyH: CGFloat, geom: NotchGeometry) -> some View {
        let rootLobe = LiquidIslandLobe(
            id: 0,
            name: "Root",
            centerX: bodyW / 2.0,
            centerY: 0.0,
            halfWidth: min(geom.rawNotchWidth / 2.0, bodyW * 0.4),
            halfHeight: max(4.0, rootBulge),
            cornerRadius: 4.0,
            isActive: rootBulge > 0.5
        )

        let bodyLobe = LiquidIslandLobe(
            id: 1,
            name: "Body",
            centerX: bodyW / 2.0,
            centerY: bodyH / 2.0,
            halfWidth: (bodyW / 2.0) * bodyScale,
            halfHeight: (bodyH / 2.0) * bodyScale,
            cornerRadius: 18.0,
            isActive: bodyScale > 0.05
        )

        let neckLobe = LiquidIslandLobe(
            id: 4,
            name: "Droplet",
            centerX: bodyW / 2.0,
            centerY: dropletY,
            halfWidth: 14.0 * dropletScale,
            halfHeight: 18.0 * dropletScale,
            cornerRadius: 10.0,
            isActive: dropletScale > 0.05
        )

        let lobes = [rootLobe, bodyLobe, neckLobe]

        LiquidIslandCanvasView(
            lobes: lobes,
            k: kSmooth,
            lighting: .init(),
            tintColor: tintColor
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.4), radius: 8, y: 4)
    }

    // MARK: - 4. Reduced Motion Fallback Backdrop

    @ViewBuilder
    private func reducedMotionBackdrop(bodyW: CGFloat, bodyH: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color.black)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        LinearGradient(
                            colors: [tintColor.opacity(0.6), Color.white.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            )
            .shadow(color: Color.black.opacity(0.4), radius: 6, y: 3)
    }

    // MARK: - 5. Phased Emergence & Lifecycle Physics

    private func runDropletBloomLifecycle() {
        if motion.isReduceMotionActive {
            bodyScale = 1.0
            contentAlpha = 1.0
            startDwellTimer(seconds: dwellDuration)
            return
        }

        let tm = motion.timeMultiplier

        // Phase 1: Swell (0.12s) - Notch lip bulges downward
        phase = .anticipation
        kSmooth = 28.0
        withAnimation(.easeIn(duration: motion.dropAnticipationDuration * tm)) {
            rootBulge = 6.0
        }

        // Phase 2: Birth & Neck Drop (0.20s) - Droplet emerges
        DispatchQueue.main.asyncAfter(deadline: .now() + (motion.dropAnticipationDuration * tm)) {
            phase = .birth
            withAnimation(.easeOut(duration: motion.dropBirthDuration * tm)) {
                dropletY = 16.0
                dropletScale = 1.0
            }

            // Phase 3: Bloom into Body (0.35s)
            DispatchQueue.main.asyncAfter(deadline: .now() + (motion.dropBirthDuration * tm * 0.7)) {
                phase = .bloom
                withAnimation(motion.expandSpring) {
                    rootBulge = 0.0
                    dropletScale = 0.0
                    bodyScale = 1.0
                    kSmooth = 12.0 // Tighten smoothing for crisp definition
                }

                // Phase 4: Reveal Content (0.15s)
                DispatchQueue.main.asyncAfter(deadline: .now() + (0.15 * tm)) {
                    phase = .hold
                    withAnimation(.easeOut(duration: 0.15 * tm)) {
                        contentAlpha = 1.0
                    }
                    startDwellTimer(seconds: dwellDuration)
                }
            }
        }
    }

    private func startDwellTimer(seconds: TimeInterval) {
        dwellTask?.cancel()
        dwellStartTime = Date()
        dwellRemaining = seconds

        dwellTask = Task { @MainActor in
            let delay = seconds * motion.timeMultiplier
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }

            if isHoveringTemplate || hub.isHovering || hub.isDraggingSlider {
                return
            }

            collapseAndDismiss()
        }
    }

    private func handleHoverChanged(_ hovering: Bool) {
        if hovering {
            // Pause countdown
            let elapsed = Date().timeIntervalSince(dwellStartTime)
            dwellRemaining = max(0.5, dwellRemaining - elapsed)
            dwellTask?.cancel()
            dwellTask = nil
        } else {
            // Resume countdown
            if dwellRemaining > 0 {
                startDwellTimer(seconds: dwellRemaining)
            } else {
                collapseAndDismiss()
            }
        }
    }

    public func collapseAndDismiss() {
        dwellTask?.cancel()
        dwellTask = nil

        let tm = motion.timeMultiplier

        // Content fades out first
        withAnimation(.easeIn(duration: 0.12 * tm)) {
            contentAlpha = 0.0
        }

        // Body shrinks into droplet
        DispatchQueue.main.asyncAfter(deadline: .now() + (0.10 * tm)) {
            withAnimation(motion.collapseSpring) {
                bodyScale = 0.0
                kSmooth = 20.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + (0.22 * tm)) {
                onDismiss()
            }
        }
    }
}
