//
//  AirPodsStarfieldCanvas.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import SwiftUI
import Combine

// MARK: - Star Particle Model

private struct StarParticle {
    let x: Double        // 0.0 ... 1.0
    let y: Double        // 0.0 ... 1.0
    let depth: Double    // 0.2 ... 1.0 (parallax scale)
    let size: Double     // 1.0 ... 2.8 pt
    let baseAlpha: Double// 0.3 ... 0.95
    let driftAngle: Double
}

// MARK: - Starfield Canvas View

@MainActor
public struct AirPodsStarfieldCanvas: View {
    public var isVisible: Bool
    public var warpProgress: Double // 0.0 = idle, 1.0 = peak warp stretch
    public var noiseMode: AirPodsNoiseMode?
    public var parallaxOffset: CGSize
    public var isLowPowerMode: Bool
    public var isReduceMotion: Bool

    // Deterministic pseudo-random stars
    private static let stars: [StarParticle] = {
        var result: [StarParticle] = []
        var seed: UInt64 = 42
        func rand() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 32) & 0xFFFFFF) / Double(0xFFFFFF)
        }

        for _ in 0..<72 {
            let x = rand()
            let y = rand()
            let depth = 0.25 + rand() * 0.75
            let size = 1.0 + rand() * 1.8
            let alpha = 0.35 + rand() * 0.60
            let angle = rand() * .pi * 2.0
            result.append(StarParticle(x: x, y: y, depth: depth, size: size, baseAlpha: alpha, driftAngle: angle))
        }
        return result
    }()

    public init(
        isVisible: Bool = true,
        warpProgress: Double = 0.0,
        noiseMode: AirPodsNoiseMode? = nil,
        parallaxOffset: CGSize = .zero,
        isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled,
        isReduceMotion: Bool = false
    ) {
        self.isVisible = isVisible
        self.warpProgress = warpProgress
        self.noiseMode = noiseMode
        self.parallaxOffset = parallaxOffset
        self.isLowPowerMode = isLowPowerMode
        self.isReduceMotion = isReduceMotion
    }

    public var body: some View {
        if !isVisible {
            // Pure black fallback when invisible (zero CPU)
            Color.black
        } else {
            TimelineView(.periodic(from: .now, by: isLowPowerMode ? (1.0 / 15.0) : (1.0 / 30.0))) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    drawScene(context: context, size: size, time: time)
                }
            }
            .background(Color.black)
        }
    }

    // MARK: - Drawing Pipeline

    private func drawScene(context: GraphicsContext, size: CGSize, time: TimeInterval) {
        guard size.width > 0 && size.height > 0 else { return }

        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)

        // 1. Deep Space Black Base
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

        // 2. Faint Nebula Glow
        drawNebula(context: context, size: size, center: center, time: time)

        // 3. Parallax Starfield & Warp Streaks
        drawStars(context: context, size: size, center: center, time: time)

        // 4. Noise Control Visual Overlays
        drawNoiseModeEffects(context: context, size: size, center: center, time: time)
    }

    // MARK: - Nebula Glow

    private func drawNebula(context: GraphicsContext, size: CGSize, center: CGPoint, time: TimeInterval) {
        let shimmer: Double = (noiseMode == .adaptive && !isReduceMotion) ? (sin(time * 2.0) * 0.04) : 0.0
        let baseAlpha = (noiseMode == .noiseCancellation ? 0.08 : 0.16) + shimmer

        // Gradient colors: Deep Violet to Indigo to Black
        let colors: [Color] = [
            Color(red: 0.18, green: 0.10, blue: 0.32).opacity(baseAlpha),
            Color(red: 0.08, green: 0.12, blue: 0.26).opacity(baseAlpha * 0.6),
            Color.black.opacity(0.0)
        ]

        let nebulaRect = CGRect(
            x: center.x - size.width * 0.55,
            y: center.y - size.height * 0.55,
            width: size.width * 1.1,
            height: size.height * 1.1
        )

        let gradient = Gradient(colors: colors)
        context.fill(
            Path(ellipseIn: nebulaRect),
            with: .radialGradient(
                gradient,
                center: center,
                startRadius: 5.0,
                endRadius: size.width * 0.55
            )
        )
    }

    // MARK: - Star Particles & Warp Streaks

    private func drawStars(context: GraphicsContext, size: CGSize, center: CGPoint, time: TimeInterval) {
        let starList = isLowPowerMode ? Self.stars.enumerated().filter { $0.offset % 2 == 0 }.map(\.element) : Self.stars

        // Noise mode modifiers
        let speedMult: Double
        let alphaMult: Double

        switch noiseMode {
        case .noiseCancellation:
            speedMult = 0.20
            alphaMult = 0.50
        case .transparency:
            speedMult = 1.00
            alphaMult = 1.30
        case .adaptive:
            speedMult = 0.70
            alphaMult = 0.90 + (isReduceMotion ? 0.0 : sin(time * 3.0) * 0.20)
        case .off, .none:
            speedMult = 0.80
            alphaMult = 1.00
        }

        let effectiveWarp = isReduceMotion ? 0.0 : warpProgress

        for star in starList {
            // Drift calculation
            let driftDistance = isReduceMotion ? 0.0 : (time * 0.012 * speedMult * star.depth)
            var normX = (star.x + cos(star.driftAngle) * driftDistance).truncatingRemainder(dividingBy: 1.0)
            if normX < 0 { normX += 1.0 }
            var normY = (star.y + sin(star.driftAngle) * driftDistance).truncatingRemainder(dividingBy: 1.0)
            if normY < 0 { normY += 1.0 }

            // Parallax shift
            let px = normX * size.width + Double(parallaxOffset.width) * star.depth * 0.12
            let py = normY * size.height + Double(parallaxOffset.height) * star.depth * 0.12

            let starPos = CGPoint(x: px, y: py)

            // Star Alpha & Twinkle
            let twinkle = isReduceMotion ? 1.0 : (0.85 + 0.15 * sin(time * 4.0 + star.depth * 10.0))
            let finalAlpha = min(1.0, max(0.0, star.baseAlpha * alphaMult * twinkle))
            let starColor = Color.white.opacity(finalAlpha)

            if effectiveWarp > 0.01 {
                // Radial warp streak
                let dx = starPos.x - center.x
                let dy = starPos.y - center.y
                let dist = max(1.0, hypot(dx, dy))
                let dirX = dx / dist
                let dirY = dy / dist

                let streakLength = effectiveWarp * (star.depth * 45.0)
                let endPoint = CGPoint(
                    x: starPos.x + dirX * streakLength,
                    y: starPos.y + dirY * streakLength
                )

                var path = Path()
                path.move(to: starPos)
                path.addLine(to: endPoint)

                context.stroke(
                    path,
                    with: .color(starColor),
                    style: StrokeStyle(lineWidth: star.size * (1.0 + effectiveWarp * 0.5), lineCap: .round)
                )
            } else {
                // Point star
                let rect = CGRect(
                    x: starPos.x - star.size * 0.5,
                    y: starPos.y - star.size * 0.5,
                    width: star.size,
                    height: star.size
                )
                context.fill(Path(ellipseIn: rect), with: .color(starColor))
            }
        }
    }

    // MARK: - Noise Mode Overlays (Vignette & Ripples)

    private func drawNoiseModeEffects(context: GraphicsContext, size: CGSize, center: CGPoint, time: TimeInterval) {
        switch noiseMode {
        case .noiseCancellation:
            // Soft vignette closes in to create quiet isolation
            let vignetteGradient = Gradient(colors: [
                Color.clear,
                Color.black.opacity(0.35),
                Color.black.opacity(0.85)
            ])
            let vignetteRect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(vignetteRect),
                with: .radialGradient(
                    vignetteGradient,
                    center: center,
                    startRadius: size.height * 0.25,
                    endRadius: size.width * 0.65
                )
            )

        case .transparency:
            // Gentle concentric ripples travel outward to visualize ambient sound entering
            guard !isReduceMotion else { break }
            let maxRadius = max(size.width, size.height) * 0.6
            let cycleDuration = 2.4
            let phase = (time.truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration

            for i in 0..<3 {
                let ripplePhase = (phase + Double(i) * 0.33).truncatingRemainder(dividingBy: 1.0)
                let currentRadius = ripplePhase * maxRadius
                let rippleAlpha = (1.0 - ripplePhase) * 0.22

                let rippleRect = CGRect(
                    x: center.x - currentRadius,
                    y: center.y - currentRadius,
                    width: currentRadius * 2.0,
                    height: currentRadius * 2.0
                )

                context.stroke(
                    Path(ellipseIn: rippleRect),
                    with: .color(Color(red: 0.6, green: 0.85, blue: 1.0).opacity(rippleAlpha)),
                    lineWidth: 1.2
                )
            }

        default:
            break
        }
    }
}
