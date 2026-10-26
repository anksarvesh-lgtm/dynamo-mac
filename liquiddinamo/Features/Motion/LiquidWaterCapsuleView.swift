//
//  LiquidWaterCapsuleView.swift
//  LiquidDynamo
//
//  Created for Live 3D Half-Filled Water Capsule Notification presentation.
//  Renders real-time procedural water volume (50% fill), dynamic liquid surface,
//  pouring water stream with highlights, expanding ripples, and micro-splashes.
//

import AppKit
import Foundation
import SwiftUI

// MARK: - Ripple Model

public struct WaterRipple: Identifiable {
    public let id: UUID = UUID()
    public var birthTime: TimeInterval
    public var originX: CGFloat
    public var maxRadius: CGFloat
    public var speed: CGFloat
    public var intensity: CGFloat

    public init(birthTime: TimeInterval, originX: CGFloat, maxRadius: CGFloat = 45.0, speed: CGFloat = 38.0, intensity: CGFloat = 0.85) {
        self.birthTime = birthTime
        self.originX = originX
        self.maxRadius = maxRadius
        self.speed = speed
        self.intensity = intensity
    }

    public func currentRadius(at time: TimeInterval) -> CGFloat {
        let age = max(0.0, time - birthTime)
        return CGFloat(age) * speed
    }

    public func currentAlpha(at time: TimeInterval) -> CGFloat {
        let age = max(0.0, time - birthTime)
        let progress = min(1.0, (CGFloat(age) * speed) / maxRadius)
        return (1.0 - progress) * intensity
    }

    public func isDead(at time: TimeInterval) -> Bool {
        return (time - birthTime) * Double(speed) >= Double(maxRadius)
    }
}

// MARK: - Splash Particle Model

public struct WaterDropletParticle: Identifiable {
    public let id: UUID = UUID()
    public var birthTime: TimeInterval
    public var initialX: CGFloat
    public var initialY: CGFloat
    public var velocityX: CGFloat
    public var velocityY: CGFloat
    public var size: CGFloat
    public var lifespan: TimeInterval

    public init(birthTime: TimeInterval, initialX: CGFloat, initialY: CGFloat, velocityX: CGFloat, velocityY: CGFloat, size: CGFloat = 1.8, lifespan: TimeInterval = 0.45) {
        self.birthTime = birthTime
        self.initialX = initialX
        self.initialY = initialY
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.size = size
        self.lifespan = lifespan
    }

    public func position(at time: TimeInterval) -> CGPoint {
        let dt = CGFloat(max(0.0, time - birthTime))
        let gravity: CGFloat = 160.0
        let x = initialX + velocityX * dt
        let y = initialY + velocityY * dt + 0.5 * gravity * dt * dt
        return CGPoint(x: x, y: y)
    }

    public func alpha(at time: TimeInterval) -> CGFloat {
        let age = time - birthTime
        let progress = min(1.0, max(0.0, age / lifespan))
        return CGFloat(1.0 - progress)
    }

    public func isDead(at time: TimeInterval) -> Bool {
        return (time - birthTime) >= lifespan
    }
}

// MARK: - Live 3D Water Capsule View

public struct LiquidWaterCapsuleView: View {
    public var fillLevel: CGFloat
    public var tintColor: Color?
    public var streamXRatio: CGFloat
    public var phaseOffset: Double

    @State private var ripples: [WaterRipple] = []
    @State private var particles: [WaterDropletParticle] = []
    @State private var lastRippleSpawnTime: TimeInterval = 0
    @State private var lastParticleSpawnTime: TimeInterval = 0

    public init(
        fillLevel: CGFloat = 0.50,
        tintColor: Color? = nil,
        streamXRatio: CGFloat = 0.28,
        phaseOffset: Double = 0.0
    ) {
        self.fillLevel = fillLevel
        self.tintColor = tintColor
        self.streamXRatio = streamXRatio
        self.phaseOffset = phaseOffset
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate + phaseOffset
                drawWaterScene(context: context, size: size, time: now)
            }
        }
        .clipShape(Capsule())
        .allowsHitTesting(false)
    }

    // MARK: - Drawing Pipeline

    private func drawWaterScene(context: GraphicsContext, size: CGSize, time: TimeInterval) {
        guard size.width > 10, size.height > 10 else { return }

        let width = size.width
        let height = size.height

        // Target liquid level at ~50% interior height
        let baseWaterY = height * (1.0 - min(0.85, max(0.15, fillLevel)))
        let impactX = width * streamXRatio

        // Spawn periodic ripples & droplets synchronously with animation clock
        let phase = time * 3.2
        let streamWaveOffset = sin(time * 5.0) * 1.2
        let actualImpactX = impactX + streamWaveOffset

        // Surface wave function
        func surfaceY(at x: CGFloat) -> CGFloat {
            let dx = x - actualImpactX
            // 1. Broad gentle ambient swell
            let ambientSwell = sin(phase + x * 0.035) * 0.9
            // 2. Concentric ripples radiating from impact
            let rippleFreq: CGFloat = 0.18
            let rippleWave = sin(time * 9.0 - abs(dx) * rippleFreq) * exp(-abs(dx) * 0.028) * 1.6
            // 3. Local indentation depression at the impact point
            let depression = -exp(-(dx * dx) / 60.0) * 2.0
            return baseWaterY + ambientSwell + rippleWave + depression
        }

        let impactSurfaceY = surfaceY(at: actualImpactX)

        // 1. Draw 3D Water Volume (Bottom half of capsule)
        drawWaterVolume(context: context, size: size, baseWaterY: baseWaterY, surfaceYFunc: surfaceY)

        // 2. Draw Subsurface Caustics & 3D Depth Shading
        drawSubsurfaceCaustics(context: context, size: size, baseWaterY: baseWaterY)

        // 3. Draw Water Surface Meniscus & Specular Rim
        drawSurfaceMeniscus(context: context, size: size, surfaceYFunc: surfaceY)

        // 4. Draw Pouring Stream (Flowing from top edge into the water)
        drawPouringStream(context: context, size: size, impactX: actualImpactX, impactY: impactSurfaceY, time: time)

        // 5. Draw Impact Point Ring & Splash Ripples
        drawImpactRipples(context: context, impactX: actualImpactX, impactY: impactSurfaceY, time: time)
    }

    // MARK: - 1. Water Volume

    private func drawWaterVolume(
        context: GraphicsContext,
        size: CGSize,
        baseWaterY: CGFloat,
        surfaceYFunc: (CGFloat) -> CGFloat
    ) {
        let width = size.width
        let height = size.height

        var waterPath = Path()
        // Start at left surface boundary
        let startY = surfaceYFunc(0)
        waterPath.move(to: CGPoint(x: 0, y: startY))

        // Step across the top liquid surface
        let step: CGFloat = 4.0
        var x: CGFloat = step
        while x <= width {
            let y = surfaceYFunc(x)
            waterPath.addLine(to: CGPoint(x: x, y: y))
            x += step
        }
        waterPath.addLine(to: CGPoint(x: width, y: surfaceYFunc(width)))

        // Close down to bottom right, across bottom, up to bottom left
        waterPath.addLine(to: CGPoint(x: width, y: height))
        waterPath.addLine(to: CGPoint(x: 0, y: height))
        waterPath.closeSubpath()

        // 3D Liquid Volume Gradient: luminous cyan at surface to rich deep ocean blue at base
        let customTint = tintColor ?? Color(red: 0.0, green: 0.72, blue: 0.95)
        let topColor = customTint.opacity(0.38)
        let midColor = Color(red: 0.02, green: 0.45, blue: 0.85, opacity: 0.52)
        let bottomColor = Color(red: 0.01, green: 0.22, blue: 0.60, opacity: 0.68)

        let gradient = Gradient(stops: [
            .init(color: topColor, location: 0.0),
            .init(color: midColor, location: 0.45),
            .init(color: bottomColor, location: 1.0)
        ])

        context.fill(
            waterPath,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: width * 0.5, y: baseWaterY - 4),
                endPoint: CGPoint(x: width * 0.5, y: height)
            )
        )
    }

    // MARK: - 2. Subsurface Caustics & Depth

    private func drawSubsurfaceCaustics(context: GraphicsContext, size: CGSize, baseWaterY: CGFloat) {
        let width = size.width
        let height = size.height

        // Subtle curved light sheen suggesting cylindrical 3D liquid interior
        var causticsPath = Path()
        let innerY = baseWaterY + (height - baseWaterY) * 0.45
        causticsPath.move(to: CGPoint(x: 16, y: innerY))
        causticsPath.addQuadCurve(
            to: CGPoint(x: width - 16, y: innerY),
            control: CGPoint(x: width * 0.5, y: innerY + 6.0)
        )

        context.stroke(
            causticsPath,
            with: .color(Color.white.opacity(0.12)),
            lineWidth: 1.5
        )

        // Soft base glow
        let bottomGlowRect = CGRect(x: 12, y: height - 10, width: width - 24, height: 8)
        let glowGradient = Gradient(stops: [
            .init(color: Color.cyan.opacity(0.15), location: 0.0),
            .init(color: Color.clear, location: 1.0)
        ])
        context.fill(
            Path(roundedRect: bottomGlowRect, cornerRadius: 4),
            with: .radialGradient(
                glowGradient,
                center: CGPoint(x: width * 0.5, y: height - 6),
                startRadius: 2,
                endRadius: width * 0.45
            )
        )
    }

    // MARK: - 3. Surface Meniscus Line

    private func drawSurfaceMeniscus(
        context: GraphicsContext,
        size: CGSize,
        surfaceYFunc: (CGFloat) -> CGFloat
    ) {
        let width = size.width

        var linePath = Path()
        linePath.move(to: CGPoint(x: 0, y: surfaceYFunc(0)))

        let step: CGFloat = 3.0
        var x: CGFloat = step
        while x <= width {
            linePath.addLine(to: CGPoint(x: x, y: surfaceYFunc(x)))
            x += step
        }
        linePath.addLine(to: CGPoint(x: width, y: surfaceYFunc(width)))

        // Glowing specular meniscus edge (air-liquid boundary)
        let meniscusGradient = Gradient(stops: [
            .init(color: Color.white.opacity(0.20), location: 0.0),
            .init(color: Color(red: 0.65, green: 0.95, blue: 1.0, opacity: 0.85), location: 0.30),
            .init(color: Color.white.opacity(0.95), location: 0.50),
            .init(color: Color(red: 0.65, green: 0.95, blue: 1.0, opacity: 0.85), location: 0.70),
            .init(color: Color.white.opacity(0.20), location: 1.0)
        ])

        // Main crisp highlight
        context.stroke(
            linePath,
            with: .linearGradient(
                meniscusGradient,
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: width, y: 0)
            ),
            lineWidth: 1.2
        )

        // Diffuse ambient glow along the surface
        context.stroke(
            linePath,
            with: .color(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.25)),
            lineWidth: 2.8
        )
    }

    // MARK: - 4. Pouring Water Stream

    private func drawPouringStream(
        context: GraphicsContext,
        size: CGSize,
        impactX: CGFloat,
        impactY: CGFloat,
        time: TimeInterval
    ) {
        // Stream flows from top of capsule (y = 0) down to the water surface impact point
        let topY: CGFloat = 0.0
        let bottomY: CGFloat = impactY + 1.5

        guard bottomY > topY else { return }

        // Tapered stream dimensions: slightly wider at entry, narrower before entry into water
        let topHalfW: CGFloat = 2.4
        let bottomHalfW: CGFloat = 1.6

        // Wave turbulence along the stream's height
        var streamPath = Path()
        let steps = 14
        let dy = (bottomY - topY) / CGFloat(steps)

        // Left bank of stream
        var leftPoints: [CGPoint] = []
        var rightPoints: [CGPoint] = []

        for i in 0...steps {
            let y = topY + CGFloat(i) * dy
            let progress = CGFloat(i) / CGFloat(steps)
            let halfW = topHalfW * (1.0 - progress * 0.35) + bottomHalfW * progress
            let sway = sin(time * 7.0 + y * 0.18) * (0.6 * progress)

            let xCenter = impactX + sway
            leftPoints.append(CGPoint(x: xCenter - halfW, y: y))
            rightPoints.append(CGPoint(x: xCenter + halfW, y: y))
        }

        streamPath.move(to: leftPoints[0])
        for pt in leftPoints.dropFirst() {
            streamPath.addLine(to: pt)
        }
        for pt in rightPoints.reversed() {
            streamPath.addLine(to: pt)
        }
        streamPath.closeSubpath()

        // Flowing water stream gradient (animated vertically with time to simulate continuous downward liquid flow)
        let flowCycle = (time * 6.0).truncatingRemainder(dividingBy: 1.0)
        let streamGradient = Gradient(stops: [
            .init(color: Color.white.opacity(0.70), location: 0.0),
            .init(color: Color(red: 0.20, green: 0.88, blue: 1.0, opacity: 0.75), location: CGFloat(flowCycle) * 0.5),
            .init(color: Color.white.opacity(0.90), location: CGFloat(flowCycle)),
            .init(color: Color(red: 0.0, green: 0.75, blue: 1.0, opacity: 0.80), location: min(1.0, CGFloat(flowCycle) + 0.3)),
            .init(color: Color.white.opacity(0.75), location: 1.0)
        ])

        // Outer stream body
        context.fill(
            streamPath,
            with: .linearGradient(
                streamGradient,
                startPoint: CGPoint(x: impactX, y: topY),
                endPoint: CGPoint(x: impactX, y: bottomY)
            )
        )

        // Central bright specular water streak
        var corePath = Path()
        corePath.move(to: CGPoint(x: impactX, y: topY))
        for i in 1...steps {
            let y = topY + CGFloat(i) * dy
            let progress = CGFloat(i) / CGFloat(steps)
            let sway = sin(time * 7.0 + y * 0.18) * (0.6 * progress)
            corePath.addLine(to: CGPoint(x: impactX + sway, y: y))
        }
        context.stroke(
            corePath,
            with: .color(Color.white.opacity(0.85)),
            lineWidth: 0.9
        )

        // Falling stream droplet beads (procedural beadlets flowing down)
        let beadlet1Y = topY + CGFloat((time * 48.0).truncatingRemainder(dividingBy: Double(bottomY - topY)))
        let beadlet2Y = topY + CGFloat(((time + 0.4) * 48.0).truncatingRemainder(dividingBy: Double(bottomY - topY)))

        let beadlet1Rect = CGRect(x: impactX - 1.2, y: beadlet1Y - 1.2, width: 2.4, height: 2.4)
        let beadlet2Rect = CGRect(x: impactX - 1.0, y: beadlet2Y - 1.0, width: 2.0, height: 2.0)

        context.fill(Path(ellipseIn: beadlet1Rect), with: .color(Color.white.opacity(0.80)))
        context.fill(Path(ellipseIn: beadlet2Rect), with: .color(Color(red: 0.7, green: 0.95, blue: 1.0, opacity: 0.75)))
    }

    // MARK: - 5. Impact Ripples & Splashes

    private func drawImpactRipples(
        context: GraphicsContext,
        impactX: CGFloat,
        impactY: CGFloat,
        time: TimeInterval
    ) {
        // Impact crown flare (bright glowing splash disc where stream merges with liquid body)
        let crownPulse = 1.0 + sin(time * 14.0) * 0.22
        let crownW: CGFloat = 9.0 * crownPulse
        let crownH: CGFloat = 3.6 * crownPulse
        let crownRect = CGRect(x: impactX - crownW * 0.5, y: impactY - crownH * 0.5, width: crownW, height: crownH)

        context.fill(
            Path(ellipseIn: crownRect),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(0.90), location: 0.0),
                    .init(color: Color(red: 0.2, green: 0.85, blue: 1.0, opacity: 0.60), location: 0.55),
                    .init(color: Color.clear, location: 1.0)
                ]),
                center: CGPoint(x: impactX, y: impactY),
                startRadius: 0.5,
                endRadius: crownW * 0.5
            )
        )

        // Micro-splash droplets bouncing off impact point
        let splashCycle1 = (time * 3.5).truncatingRemainder(dividingBy: 1.0)
        let splashCycle2 = ((time + 0.33) * 3.5).truncatingRemainder(dividingBy: 1.0)
        let splashCycle3 = ((time + 0.66) * 3.5).truncatingRemainder(dividingBy: 1.0)

        func drawSplashDroplet(cycle: Double, angle: CGFloat, dist: CGFloat) {
            let t = CGFloat(cycle)
            // Parabolic arc
            let dx = cos(angle) * dist * t
            let dy = -sin(angle) * dist * 0.7 * (4.0 * t * (1.0 - t))
            let dropX = impactX + dx
            let dropY = impactY + dy
            let alpha = CGFloat(1.0 - cycle) * 0.75
            guard alpha > 0.05 else { return }

            let dropRect = CGRect(x: dropX - 1.0, y: dropY - 1.0, width: 2.0, height: 2.0)
            context.fill(Path(ellipseIn: dropRect), with: .color(Color.white.opacity(alpha)))
        }

        drawSplashDroplet(cycle: splashCycle1, angle: .pi * 0.35, dist: 8.0)
        drawSplashDroplet(cycle: splashCycle2, angle: .pi * 0.65, dist: 9.0)
        drawSplashDroplet(cycle: splashCycle3, angle: .pi * 0.50, dist: 7.0)

        // Concentric expanding elliptical ripples
        let ripplePhase1 = (time * 1.8).truncatingRemainder(dividingBy: 1.0)
        let ripplePhase2 = ((time + 0.5) * 1.8).truncatingRemainder(dividingBy: 1.0)

        func drawExpandingRipple(phase: Double) {
            let progress = CGFloat(phase)
            let rx = 5.0 + progress * 32.0
            let ry = rx * 0.32 // Perspective compression for surface ring
            let alpha = (1.0 - progress) * 0.55
            guard alpha > 0.02 else { return }

            let rippleRect = CGRect(x: impactX - rx, y: impactY - ry, width: rx * 2.0, height: ry * 2.0)
            context.stroke(
                Path(ellipseIn: rippleRect),
                with: .color(Color(red: 0.6, green: 0.95, blue: 1.0).opacity(alpha)),
                lineWidth: max(0.6, 1.3 * (1.0 - progress))
            )
        }

        drawExpandingRipple(phase: ripplePhase1)
        drawExpandingRipple(phase: ripplePhase2)
    }
}

// MARK: - Reusable 3D Glass Water Capsule Background

public struct LiquidGlassWaterCapsuleBackground: View {
    public var isSelected: Bool
    public var accentColor: Color
    public var fillLevel: CGFloat
    public var streamXRatio: CGFloat
    public var phaseOffset: Double

    public init(
        isSelected: Bool = false,
        accentColor: Color = Color.cyan,
        fillLevel: CGFloat = 0.50,
        streamXRatio: CGFloat = 0.28,
        phaseOffset: Double = 0.0
    ) {
        self.isSelected = isSelected
        self.accentColor = accentColor
        self.fillLevel = fillLevel
        self.streamXRatio = streamXRatio
        self.phaseOffset = phaseOffset
    }

    public var body: some View {
        ZStack {
            // 1. Dark obsidian glass backdrop with subtle blur
            Capsule()
                .fill(Color.black.opacity(0.55))

            // 2. 3D procedural water simulation with pouring stream, 50% fill, ripples, caustics
            LiquidWaterCapsuleView(
                fillLevel: fillLevel,
                tintColor: isSelected ? accentColor : nil,
                streamXRatio: streamXRatio,
                phaseOffset: phaseOffset
            )

            // 3. Ambient inner glass glow & selection tint
            if isSelected {
                Capsule()
                    .fill(accentColor.opacity(0.18))
            }

            // 4. Outer 3D glass specular rim border
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            isSelected ? accentColor.opacity(0.9) : Color.white.opacity(0.35),
                            isSelected ? accentColor.opacity(0.4) : Color.white.opacity(0.12),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: isSelected ? 1.2 : 0.75
                )
        }
        .clipShape(Capsule())
    }
}

