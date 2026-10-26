//
//  LiquidWaterCapsuleView.swift
//  LiquidDynamo
//
//  3D Smoked-Glass Capsule Surface & Background Renderer.
//  Provides dark charcoal/obsidian glass depth, subtle upper-edge specular gloss,
//  and clear foreground separation for optimal text and icon readability.
//

import AppKit
import Foundation
import SwiftUI

// MARK: - 3D Glass Capsule Depth Layer

public struct LiquidWaterCapsuleView: View {
    public var fillLevel: CGFloat
    public var tintColor: Color?
    public var streamXRatio: CGFloat
    public var phaseOffset: Double

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
        // High-performance static depth layer — water simulation, loops, and particle effects removed
        ZStack {
            // Subtle dark inner vignette
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.15), location: 0.0),
                    .init(color: Color.clear, location: 0.50),
                    .init(color: Color.black.opacity(0.25), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Optional ambient accent tint
            if let tint = tintColor {
                tint.opacity(0.06)
            }
        }
        .clipShape(Capsule())
        .allowsHitTesting(false)
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
            // 1. Deep charcoal / obsidian solid dark smoked glass base
            // High solid opacity (0.92-0.96) prevents bright/colorful wallpaper bleed-through
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.12, green: 0.13, blue: 0.16).opacity(0.92), location: 0.0),
                    .init(color: Color(red: 0.07, green: 0.08, blue: 0.10).opacity(0.95), location: 0.55),
                    .init(color: Color(red: 0.04, green: 0.04, blue: 0.05).opacity(0.97), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // 2. Subtle upper-edge 3D curved glass gloss sheen (curved horizon reflection)
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.18), location: 0.0),
                    .init(color: Color.white.opacity(0.06), location: 0.35),
                    .init(color: Color.clear, location: 0.70)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // 3. Selection or accent glow
            if isSelected {
                Capsule()
                    .fill(accentColor.opacity(0.20))
            }

            // 4. Outer 3D glass specular rim border
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
