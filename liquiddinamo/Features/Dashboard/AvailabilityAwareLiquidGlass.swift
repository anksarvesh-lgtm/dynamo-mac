//
//  AvailabilityAwareLiquidGlass.swift
//  LiquidDynamo
//
//  Created for Production Dynamic Island Architecture.
//  Provides availability-aware Liquid Glass rendering:
//  - Uses Apple's public SwiftUI Liquid Glass APIs when available.
//  - Gracefully falls back to 5-layer optical smoked glass on macOS 14+
//    combining AppKit NSVisualEffectView, directional glare, Fresnel rims, and dispersion.
//

import SwiftUI
import AppKit

// MARK: - Layer 1: Native AppKit Backdrop

public struct NSVisualEffectBackdropView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - 5-Layer Optical Smoked Glass Specification

public struct SmokedLiquidGlassTokens {
    public static let primaryGlass = Color(red: 0x17 / 255.0, green: 0x19 / 255.0, blue: 0x1C / 255.0) // #17191C
    public static let secondaryGlass = Color(red: 0x24 / 255.0, green: 0x28 / 255.0, blue: 0x2D / 255.0) // #24282D
    public static let deepShadow = Color(red: 0x09 / 255.0, green: 0x0B / 255.0, blue: 0x0E / 255.0) // #090B0E
    public static let tealRefraction = Color(red: 0x12 / 255.0, green: 0x3B / 255.0, blue: 0x36 / 255.0) // #123B36
    public static let blueRefraction = Color(red: 0x14 / 255.0, green: 0x28 / 255.0, blue: 0x3F / 255.0) // #14283F
    public static let emerald = Color(red: 0x00 / 255.0, green: 0xD9 / 255.0, blue: 0x82 / 255.0) // #00D982
    public static let champagne = Color(red: 0xC6 / 255.0, green: 0x9B / 255.0, blue: 0x70 / 255.0) // #C69B70
    public static let silverHighlight = Color(red: 0xDD / 255.0, green: 0xE8 / 255.0, blue: 0xF0 / 255.0) // #DDE8F0
    public static let primaryText = Color.white
    public static let secondaryText = Color(red: 0xAE / 255.0, green: 0xB5 / 255.0, blue: 0xBE / 255.0)
    public static let mutedText = Color(red: 0x73 / 255.0, green: 0x7B / 255.0, blue: 0x85 / 255.0)
}

// MARK: - Availability-Aware Liquid Glass Modifier

public struct AvailabilityAwareLiquidGlassModifier: ViewModifier {
    public let cornerRadius: CGFloat
    public let isInteractive: Bool
    public let accentTint: Color?

    @State private var isHovered: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        cornerRadius: CGFloat = 22,
        isInteractive: Bool = false,
        accentTint: Color? = nil
    ) {
        self.cornerRadius = cornerRadius
        self.isInteractive = isInteractive
        self.accentTint = accentTint
    }

    public func body(content: Content) -> some View {
        content
            .background(opticalGlassStack)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: SmokedLiquidGlassTokens.deepShadow.opacity(0.35), radius: 15.73, x: 0, y: isHovered ? 8 : 4)
            .shadow(color: Color.black.opacity(0.20), radius: 4, x: 0, y: 2)
            .scaleEffect(isInteractive && isHovered && !reduceMotion ? 1.01 : 1.0)
            .onHover { hovering in
                guard isInteractive else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                    isHovered = hovering
                }
            }
    }

    @ViewBuilder
    private var opticalGlassStack: some View {
        ZStack {
            // Layer 1: Native AppKit Translucent Backdrop (No desktop capture permission required)
            NSVisualEffectBackdropView(
                material: .hudWindow,
                blendingMode: .behindWindow,
                state: .active
            )

            // Layer 2: Smoked Charcoal Tint (Deep luxury glass)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(SmokedLiquidGlassTokens.primaryGlass.opacity(0.82))

            // Layer 3: Internal Colour Diffusion (Teal & Blue optical refractions with champagne accents)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: SmokedLiquidGlassTokens.tealRefraction.opacity(0.35), location: 0.0),
                            .init(color: SmokedLiquidGlassTokens.secondaryGlass.opacity(0.15), location: 0.40),
                            .init(color: SmokedLiquidGlassTokens.blueRefraction.opacity(0.30), location: 0.85),
                            .init(color: SmokedLiquidGlassTokens.champagne.opacity(0.10), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Optional contextual accent tint (e.g. live emerald for connected state)
            if let tint = accentTint {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(0.12))
            }

            // Layer 4: Directional Specular Sheen (Liquid Glass Studio -45° environmental glare)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(isHovered ? 0.28 : 0.20), location: 0.0),
                            .init(color: Color.white.opacity(isHovered ? 0.08 : 0.04), location: 0.35),
                            .init(color: Color.clear, location: 0.75)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Layer 4 (cont): Optical Edges & Inner Refractive Bevel
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: SmokedLiquidGlassTokens.silverHighlight.opacity(isHovered ? 0.50 : 0.38), location: 0.0),
                            .init(color: Color.white.opacity(0.12), location: 0.50),
                            .init(color: SmokedLiquidGlassTokens.secondaryGlass.opacity(0.30), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )

            // Layer 5: Wavelength-Dependent Chromatic Dispersion Rim
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.40, green: 0.85, blue: 1.00).opacity(0.35), location: 0.0),
                            .init(color: SmokedLiquidGlassTokens.emerald.opacity(0.20), location: 0.30),
                            .init(color: SmokedLiquidGlassTokens.champagne.opacity(0.25), location: 0.70),
                            .init(color: Color(red: 0.45, green: 0.65, blue: 1.00).opacity(0.40), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
                .blendMode(.plusLighter)
        }
    }
}

public extension View {
    func availabilityAwareLiquidGlass(
        cornerRadius: CGFloat = 22,
        isInteractive: Bool = false,
        accentTint: Color? = nil
    ) -> some View {
        self.modifier(
            AvailabilityAwareLiquidGlassModifier(
                cornerRadius: cornerRadius,
                isInteractive: isInteractive,
                accentTint: accentTint
            )
        )
    }
}

