//
//  LiquidGlassMaterial.swift
//  LiquidDynamo
//
//  Advanced Liquid Glass visual styling and material system for LiquidDynamo.
//  Provides chromatic dispersion, Fresnel rim reflections, directional glare,
//  and superellipse squircle curvature across macOS SwiftUI views.
//

import SwiftUI
import AppKit

// MARK: - Presets

public enum LiquidGlassPreset: String, CaseIterable, Identifiable {
    case appleVision     // Ultra-clear crystal glass with subtle frosted backdrop
    case studioLiquid    // Liquid Glass Studio signature with directional glare and chromatic dispersion
    case customStudio    // Calibrated Liquid Glass Studio preset (liquid-glass-2026-11-03T05-29-44.json)
    case obsidianDark    // Deep OLED optical black core with razor specular rim
    case prismaticWater  // Fluid aquatic refraction with gentle iridescent dispersion

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .appleVision: return "Apple Vision Glass"
        case .studioLiquid: return "Studio Liquid Glass"
        case .customStudio: return "Calibrated Studio Glass"
        case .obsidianDark: return "Obsidian Dark Glass"
        case .prismaticWater: return "Prismatic Water Glass"
        }
    }

    public var tintColor: Color {
        switch self {
        case .appleVision:
            return Color.white.opacity(0.08)
        case .studioLiquid, .customStudio:
            // Calibrated warm-slate smoked glass tint (R: 102, G: 98, B: 98, A: 0.28)
            return Color(red: 102.0 / 255.0, green: 98.0 / 255.0, blue: 98.0 / 255.0).opacity(0.28)
        case .obsidianDark:
            return Color.black.opacity(0.65)
        case .prismaticWater:
            return Color(red: 0.05, green: 0.35, blue: 0.55).opacity(0.20)
        }
    }

    public var glareIntensity: Double {
        switch self {
        case .appleVision: return 0.55
        case .studioLiquid, .customStudio: return 0.938 // Calibrated glareFactor: 93.83%
        case .obsidianDark: return 0.60
        case .prismaticWater: return 0.75
        }
    }

    public var dispersionOpacity: Double {
        switch self {
        case .appleVision: return 0.22
        case .studioLiquid, .customStudio: return 0.50 // Calibrated refDispersion: 50
        case .obsidianDark: return 0.18
        case .prismaticWater: return 0.45
        }
    }
}

// MARK: - Liquid Glass View Modifier

public struct LiquidGlassModifier: ViewModifier {
    public let preset: LiquidGlassPreset
    public let cornerRadius: CGFloat
    public let isInteractive: Bool

    @State private var isHovered: Bool = false

    public init(
        preset: LiquidGlassPreset = .studioLiquid,
        cornerRadius: CGFloat = 20,
        isInteractive: Bool = false
    ) {
        self.preset = preset
        self.cornerRadius = cornerRadius
        self.isInteractive = isInteractive
    }

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // 1. Frosted Glass Depth Base
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // 2. Preset Tint Wash
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(preset.tintColor)

                    // 3. Directional Glare Sheen (Liquid Glass Studio -45° top-left illumination)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity((preset.glareIntensity * 0.28) * (isHovered ? 1.25 : 1.0)), location: 0.0),
                                    .init(color: Color.white.opacity((preset.glareIntensity * 0.08) * (isHovered ? 1.15 : 1.0)), location: 0.35),
                                    .init(color: Color.clear, location: 0.70)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // 4. Subtle Inner Refractive Bevel
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(isHovered ? 0.45 : 0.30), location: 0.0),
                                    .init(color: Color.white.opacity(0.12), location: 0.50),
                                    .init(color: Color.white.opacity(0.04), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.0
                        )

                    // 5. Chromatic Dispersion Rim (Wavelength-dependent RGB Prismatic Fringe)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color(red: 1.00, green: 0.40, blue: 0.50).opacity(preset.dispersionOpacity * (isHovered ? 1.3 : 1.0)), location: 0.00),
                                    .init(color: Color(red: 1.00, green: 0.95, blue: 0.40).opacity(preset.dispersionOpacity * 0.8), location: 0.28),
                                    .init(color: Color(red: 0.30, green: 0.95, blue: 0.70).opacity(preset.dispersionOpacity * 0.9), location: 0.62),
                                    .init(color: Color(red: 0.35, green: 0.65, blue: 1.00).opacity(preset.dispersionOpacity * (isHovered ? 1.4 : 1.0)), location: 1.00)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.85
                        )
                        .blendMode(.plusLighter)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.15), radius: 15.73, x: 0, y: isHovered ? 10 : 6)
            .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
            .onHover { hovering in
                guard isInteractive else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - View Extension

public extension View {
    func liquidGlass(
        preset: LiquidGlassPreset = .studioLiquid,
        cornerRadius: CGFloat = 20,
        isInteractive: Bool = false
    ) -> some View {
        self.modifier(
            LiquidGlassModifier(
                preset: preset,
                cornerRadius: cornerRadius,
                isInteractive: isInteractive
            )
        )
    }
}

// MARK: - Liquid Glass Card Container

public struct LiquidGlassCard<Content: View>: View {
    public let preset: LiquidGlassPreset
    public let cornerRadius: CGFloat
    public let isInteractive: Bool
    public let content: Content

    public init(
        preset: LiquidGlassPreset = .studioLiquid,
        cornerRadius: CGFloat = 20,
        isInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.preset = preset
        self.cornerRadius = cornerRadius
        self.isInteractive = isInteractive
        self.content = content()
    }

    public var body: some View {
        content
            .liquidGlass(preset: preset, cornerRadius: cornerRadius, isInteractive: isInteractive)
    }
}

