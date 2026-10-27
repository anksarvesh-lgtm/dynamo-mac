//
//  LiquidWaterCapsuleView.swift
//  LiquidDynamo
//
//  Static Water Fill with Live Surface Waves & 3D Glass Capsule Renderer.
//  Provides fixed 35-45% translucent deep-blue water volume with calm, continuous
//  procedural surface waves, glowing specular meniscus, and 3D smoked glass depth.
//  Strictly zero pouring streams, zero droplet particles, and zero progressive fills.
//

import AppKit
import Foundation
import SwiftUI

// MARK: - Static Water Fill with Live Procedural Surface Waves

public struct LiquidWaterCapsuleView: View {
    public var fillLevel: CGFloat
    public var tintColor: Color?
    public var streamXRatio: CGFloat
    public var phaseOffset: Double

    public init(
        fillLevel: CGFloat = 0.38,
        tintColor: Color? = nil,
        streamXRatio: CGFloat = 0.28,
        phaseOffset: Double = 0.0
    ) {
        // Enforce calm, static interior volume (~35-45% of capsule height)
        self.fillLevel = min(max(fillLevel, 0.25), 0.50)
        self.tintColor = tintColor
        self.streamXRatio = streamXRatio
        self.phaseOffset = phaseOffset
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                drawWater(into: &context, size: size, date: timeline.date)
            }
        }
        .clipShape(Capsule())
        .allowsHitTesting(false)
    }

    private func drawWater(into context: inout GraphicsContext, size: CGSize, date: Date) {
        let width = size.width
        let height = size.height
        guard width > 4, height > 4 else { return }

        let time = date.timeIntervalSinceReferenceDate
        let baseWaterY = height * (1.0 - fillLevel)

        // 1. Compute multi-harmonic gentle surface wave points
        let step: CGFloat = 2.5
        var points: [CGPoint] = []
        points.reserveCapacity(Int(width / step) + 2)

        var x: CGFloat = 0.0
        while x <= width {
            let normX = x / width
            let wave = sin(normX * 3.6 * .pi + time * 1.5 + phaseOffset) * 1.5
                     + cos(normX * 5.4 * .pi - time * 1.1 + phaseOffset * 0.7) * 0.7
            let y = baseWaterY + wave
            points.append(CGPoint(x: x, y: y))
            x += step
        }
        if let last = points.last, last.x < width {
            let normX: CGFloat = 1.0
            let wave = sin(normX * 3.6 * .pi + time * 1.5 + phaseOffset) * 1.5
                     + cos(normX * 5.4 * .pi - time * 1.1 + phaseOffset * 0.7) * 0.7
            points.append(CGPoint(x: width, y: baseWaterY + wave))
        }

        guard points.count >= 2 else { return }

        // 2. Build Water Volume Fill Path
        var waterFillPath = Path()
        waterFillPath.move(to: CGPoint(x: 0, y: height))
        waterFillPath.addLine(to: points[0])

        for i in 1..<points.count {
            waterFillPath.addLine(to: points[i])
        }
        waterFillPath.addLine(to: CGPoint(x: width, y: height))
        waterFillPath.closeSubpath()

        // Vibrant translucent deep-blue / aqua ocean gradient
        let primaryAqua = tintColor ?? Color(red: 0.06, green: 0.52, blue: 0.92)
        let deepNavy = Color(red: 0.02, green: 0.14, blue: 0.38)
        let baseAbyss = Color(red: 0.01, green: 0.07, blue: 0.22)

        let waterGradient = Gradient(stops: [
            .init(color: primaryAqua.opacity(0.45), location: 0.0),
            .init(color: deepNavy.opacity(0.68), location: 0.50),
            .init(color: baseAbyss.opacity(0.85), location: 1.0)
        ])

        context.fill(
            waterFillPath,
            with: .linearGradient(
                waterGradient,
                startPoint: CGPoint(x: width * 0.5, y: baseWaterY - 3),
                endPoint: CGPoint(x: width * 0.5, y: height)
            )
        )

        // 3. Subsurface Caustic Ribbon (realistic 3D refraction depth)
        var causticPath = Path()
        causticPath.move(to: CGPoint(x: points[0].x, y: points[0].y + 2.4))
        for pt in points.dropFirst() {
            causticPath.addLine(to: CGPoint(x: pt.x, y: pt.y + 2.4))
        }
        context.stroke(
            causticPath,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(0.20), location: 0.1),
                    .init(color: primaryAqua.opacity(0.35), location: 0.5),
                    .init(color: Color.white.opacity(0.15), location: 0.9)
                ]),
                startPoint: CGPoint(x: 0, y: baseWaterY),
                endPoint: CGPoint(x: width, y: baseWaterY)
            ),
            lineWidth: 1.4
        )

        // 4. Luminous Specular Meniscus Line (Air-Liquid Boundary)
        var meniscusPath = Path()
        meniscusPath.move(to: points[0])
        for pt in points.dropFirst() {
            meniscusPath.addLine(to: pt)
        }

        // Diffuse meniscus glow
        context.stroke(
            meniscusPath,
            with: .color(primaryAqua.opacity(0.40)),
            lineWidth: 2.6
        )

        // Sharp specular core highlight
        let specularGradient = Gradient(stops: [
            .init(color: Color(red: 0.55, green: 0.88, blue: 1.0).opacity(0.90), location: 0.0),
            .init(color: Color.white.opacity(0.95), location: 0.45),
            .init(color: Color(red: 0.45, green: 0.82, blue: 1.0).opacity(0.85), location: 1.0)
        ])

        context.stroke(
            meniscusPath,
            with: .linearGradient(
                specularGradient,
                startPoint: CGPoint(x: 0, y: baseWaterY),
                endPoint: CGPoint(x: width, y: baseWaterY)
            ),
            lineWidth: 1.1
        )
    }
}

// MARK: - Reusable 3D Dark Smoked-Glass Capsule Background

public struct LiquidGlassWaterCapsuleBackground: View {
    public var isSelected: Bool
    public var accentColor: Color
    public var fillLevel: CGFloat
    public var streamXRatio: CGFloat
    public var phaseOffset: Double

    public init(
        isSelected: Bool = false,
        accentColor: Color = Color.cyan,
        fillLevel: CGFloat = 0.38,
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
            // 1. Deep charcoal / obsidian solid dark smoked glass base
            // Solid dark backdrop ensures high-contrast readability of white text, icons, and badges
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.12, green: 0.13, blue: 0.16).opacity(0.92), location: 0.0),
                    .init(color: Color(red: 0.07, green: 0.08, blue: 0.10).opacity(0.95), location: 0.55),
                    .init(color: Color(red: 0.04, green: 0.04, blue: 0.05).opacity(0.97), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // 2. Static 35-45% Translucent Water Fill with Live Surface Waves
            LiquidWaterCapsuleView(
                fillLevel: fillLevel,
                tintColor: accentColor,
                streamXRatio: streamXRatio,
                phaseOffset: phaseOffset
            )

            // 3. Subtle upper-edge 3D curved glass gloss sheen (curved horizon reflection above water line)
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.18), location: 0.0),
                    .init(color: Color.white.opacity(0.06), location: 0.35),
                    .init(color: Color.clear, location: 0.70)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // 4. Selection or accent glow
            if isSelected {
                Capsule()
                    .fill(accentColor.opacity(0.20))
            }

            // 5. Outer 3D glass specular rim border
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            isSelected ? accentColor.opacity(0.95) : Color.white.opacity(0.40),
                            isSelected ? accentColor.opacity(0.40) : Color.white.opacity(0.15),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: isSelected ? 1.2 : 0.8
                )
        }
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.40), radius: 3, y: 1.5)
    }
}

public typealias Liquid3DGlassCapsuleBackground = LiquidGlassWaterCapsuleBackground
