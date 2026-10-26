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

public enum LiquidDropPhase: Sendable {
    case idle
    case anticipation
    case birth
    case bloom
    case hold
    case reverseShrink
    case reverseRise
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
    @ObservedObject private var safeArea = NotchSafeAreaEngine.shared

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

    // Water Bottom Engine State (Master Spec Step B)
    @State private var waterConfig = LiquidWaterConfig(
        isEnabled: Defaults[.enableWaterBottom],
        sagAmount: Float(Defaults[.waterSagAmount] * Defaults[.waterIntensity]),
        irregularity: Float(Defaults[.waterIntensity]),
        sloshPhase: 0.0,
        meniscusIntensity: 1.2,
        seed: Defaults[.waterSeedLock] ? Float(Defaults[.lockedWaterSeed]) : Float(Int.random(in: 1...99)),
        time: 0.0,
        cursorLean: 0.0
    )
    @State private var sloshPhase: CGFloat = 0.0
    @State private var cursorLean: CGFloat = 0.0

    private var activeWaterConfig: LiquidWaterConfig {
        var cfg = waterConfig
        cfg.sloshPhase = motion.isReduceMotionActive ? 0.0 : Float(sloshPhase)
        cfg.cursorLean = motion.isReduceMotionActive ? 0.0 : Float(cursorLean)
        cfg.time = motion.isReduceMotionActive ? 0.0 : waterConfig.time
        cfg.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        return cfg
    }

    @State private var dwellTask: Task<Void, Never>?
    @State private var rippleTask: Task<Void, Never>?
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
        LiquidAlertCapsuleContainer(
            tintColor: tintColor,
            dwellDuration: dwellDuration,
            onDismiss: onDismiss
        ) {
            content()
                .opacity(contentAlpha)
        }
        .offset(y: dragOffset)
        .scaleEffect(
            x: motion.isReduceMotionActive ? 1.0 : (0.88 + 0.12 * bodyScale),
            y: motion.isReduceMotionActive ? 1.0 : (0.88 + 0.12 * bodyScale),
            anchor: .top
        )
        .avoidsNotch(id: "TemplateLiquidBloom")
        .onHover { hovering in
            isHoveringTemplate = hovering
            hub.isHovering = hovering
            handleHoverChanged(hovering)
        }
        .onContinuousHover { hoverPhase in
            guard !motion.isReduceMotionActive && Defaults[.enableWaterBottom] else { return }
            switch hoverPhase {
            case .active(let location):
                if phase == .hold {
                    let bodyW = IslandController.alertCapsuleSize(for: safeArea.currentGeometry, contentWidth: IslandController.shared.dynamicAlertCapsuleWidth).width
                    let halfW = max(bodyW / 2.0, 1.0)
                    let rawLean = (location.x - (bodyW / 2.0)) / halfW
                    let clamped = max(-1.0, min(1.0, rawLean))
                    withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
                        cursorLean = clamped
                    }
                }
            case .ended:
                withAnimation(.easeOut(duration: 0.2)) {
                    cursorLean = 0.0
                }
            }
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
            setupDynamicHooks()
            runDropletBloomLifecycle()
        }
        .onDisappear {
            stopHoldRipple()
            dwellTask?.cancel()
            dwellTask = nil
        }
    }

    private func setupDynamicHooks() {
        sizingCoordinator.onContentResize = { [self] _ in
            if phase == .hold && !motion.isReduceMotionActive && Defaults[.enableWaterBottom] {
                // Spring-driven slosh when content grows or shrinks while visible
                sloshPhase = (sloshPhase >= 0) ? -0.75 : 0.75
                withAnimation(.interpolatingSpring(mass: 0.85, stiffness: 36.0, damping: 4.8, initialVelocity: 6.0)) {
                    sloshPhase = 0.0
                }
            }
        }
    }

    // MARK: - 3. Liquid SDF Backdrop (Organic Multi-Blob Metal Shader)

    @ViewBuilder
    private func liquidSDFBackdrop(bodyW: CGFloat, bodyH: CGFloat, geom: NotchGeometry) -> some View {
        let centerX = bodyW / 2.0
        let cluster = ContentDrivenBlobGenerator.ContentCluster(
            id: "templateSafeContent",
            center: CGPoint(x: centerX, y: max(18.0, bodyH * 0.45)),
            size: CGSize(width: max(60, bodyW - 20), height: max(24, bodyH - 8)),
            kind: .swellingDroplet
        )
        let activeLobes = ContentDrivenBlobGenerator.generateLobes(
            clusters: [cluster],
            notchLipY: 0.0,
            notchCenterX: centerX,
            notchWidth: min(geom.rawNotchWidth, bodyW * 0.6),
            emergenceProgress: max(0.1, bodyScale),
            seed: CGFloat(waterConfig.seed),
            time: motion.isReduceMotionActive ? 0.0 : CGFloat(waterConfig.time)
        )

        LiquidBlobCanvasView(
            blobs: activeLobes,
            k: kSmooth,
            tintColor: tintColor,
            notchLipY: 0.0,
            seed: CGFloat(waterConfig.seed),
            time: motion.isReduceMotionActive ? 0.0 : CGFloat(waterConfig.time),
            transparency: Defaults[.islandTransparency],
            bgLuminance: 0.0,
            forceFallback: false
        )
        .frame(width: bodyW, height: bodyH + 12)
        .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)
    }

    // MARK: - 4. Reduced Motion Fallback Backdrop

    @ViewBuilder
    private func reducedMotionBackdrop(bodyW: CGFloat, bodyH: CGFloat, geom: NotchGeometry) -> some View {
        liquidSDFBackdrop(bodyW: bodyW, bodyH: bodyH, geom: geom)
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

        // Initialize appearance seed
        if Defaults[.waterSeedLock] {
            waterConfig.seed = Float(Defaults[.lockedWaterSeed])
        } else {
            waterConfig.seed = Float(Int.random(in: 1...99))
        }

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
                    kSmooth = 14.0 // Organic liquid smoothing
                }

                // Trigger spring-driven slosh wave along bottom edge on bloom
                if Defaults[.enableWaterBottom] {
                    sloshPhase = 1.0
                    withAnimation(.interpolatingSpring(mass: 0.9, stiffness: 35.0, damping: 4.6, initialVelocity: 8.0)) {
                        sloshPhase = 0.0
                    }
                }

                // Phase 4: Reveal Content (0.15s)
                DispatchQueue.main.asyncAfter(deadline: .now() + (0.15 * tm)) {
                    phase = .hold
                    withAnimation(.easeOut(duration: 0.15 * tm)) {
                        contentAlpha = 1.0
                    }
                    startHoldRipple()
                    startDwellTimer(seconds: dwellDuration)
                }
            }
        }
    }

    private func startHoldRipple() {
        stopHoldRipple()
        guard !motion.isReduceMotionActive && Defaults[.enableWaterBottom] else { return }

        let startTime = Date()
        rippleTask = Task { @MainActor in
            while !Task.isCancelled && phase == .hold {
                let elapsed = Date().timeIntervalSince(startTime)
                waterConfig.time = Float(elapsed)
                try? await Task.sleep(nanoseconds: 16_666_667) // 60 Hz subtle ripple update
            }
        }
    }

    private func stopHoldRipple() {
        rippleTask?.cancel()
        rippleTask = nil
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

    // MARK: - 6. Teardrop Collapse Lifecycle (Requirement 5)

    public func collapseAndDismiss() {
        stopHoldRipple()
        dwellTask?.cancel()
        dwellTask = nil

        if motion.isReduceMotionActive {
            withAnimation(.easeIn(duration: 0.15)) {
                contentAlpha = 0.0
                bodyScale = 0.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                phase = .idle
                onDismiss()
            }
            return
        }

        let tm = motion.timeMultiplier
        phase = .reverseShrink

        // Step 1: Content quickly fades out
        withAnimation(.easeIn(duration: 0.10 * tm)) {
            contentAlpha = 0.0
        }

        // Step 2: The belly pulls up into a teardrop point at lowest spot, small bead forms & pinches off
        DispatchQueue.main.asyncAfter(deadline: .now() + (0.08 * tm)) {
            let bodyH = sizingCoordinator.currentBodySize.height
            withAnimation(.spring(response: 0.30 * tm, dampingFraction: 0.72)) {
                bodyScale = 0.25
                waterConfig.sagAmount = 0.0
                dropletY = bodyH * 0.40
                dropletScale = 0.85
                kSmooth = 16.0
            }

            // Step 3: Bead is drawn back up and merges into the notch
            DispatchQueue.main.asyncAfter(deadline: .now() + (0.16 * tm)) {
                phase = .reverseRise
                withAnimation(motion.collapseSpring) {
                    bodyScale = 0.0
                    dropletY = 0.0
                    dropletScale = 0.0
                    rootBulge = 5.0
                    kSmooth = 24.0
                }

                // Step 4: Notch settles with a tiny ripple
                DispatchQueue.main.asyncAfter(deadline: .now() + (0.18 * tm)) {
                    withAnimation(.spring(response: 0.22 * tm, dampingFraction: 0.65)) {
                        rootBulge = 0.0
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + (0.14 * tm)) {
                        phase = .idle
                        onDismiss()
                    }
                }
            }
        }
    }
}
