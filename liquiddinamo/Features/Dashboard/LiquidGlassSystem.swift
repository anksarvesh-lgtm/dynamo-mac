//
//  LiquidGlassSystem.swift
//  LiquidDynamo
//
//  Created for Liquid Dynamo - Liquid Glass Interface System
//

import SwiftUI
import Defaults

// MARK: - 1. Liquid Glass Layer Specification

public enum LiquidGlassLayer {
    /// Deep background layer with ambient gradients, refractive blur, and subtle environmental lighting
    case background
    /// Floating mid-layer content cards, panels, and navigation surfaces
    case mid
    /// Floating front-layer buttons, dialogs, sliders, and controls
    case front

    public var defaultCornerRadius: CGFloat {
        switch self {
        case .background: return 24
        case .mid: return 20
        case .front: return 18
        }
    }

    public var baseFillOpacity: CGFloat {
        switch self {
        case .background: return 0.72
        case .mid: return 0.28
        case .front: return 0.42
        }
    }

    public var borderOpacity: CGFloat {
        switch self {
        case .background: return 0.22
        case .mid: return 0.18
        case .front: return 0.26
        }
    }
}

// MARK: - 2. Liquid Glass Card Modifier & View

public struct LiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var tint: Color?
    public var interactive: Bool
    public var layer: LiquidGlassLayer

    @State private var isHovered: Bool = false
    @State private var hoverLocation: CGPoint = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    public init(
        cornerRadius: CGFloat = 20,
        tint: Color? = nil,
        interactive: Bool = true,
        layer: LiquidGlassLayer = .mid
    ) {
        self.cornerRadius = max(18, min(cornerRadius, 32))
        self.tint = tint
        self.interactive = interactive
        self.layer = layer
    }

    public func body(content: Content) -> some View {
        content
            .background(glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(glassBordersAndLighting)
            .shadow(
                color: Color.black.opacity(isHovered ? 0.38 : 0.22),
                radius: isHovered ? 16 : 10,
                x: 0,
                y: isHovered ? 8 : 4
            )
            .shadow(
                color: Color.black.opacity(0.12),
                radius: 2,
                x: 0,
                y: 1
            )
            .scaleEffect(interactive && isHovered && !reduceMotion ? 1.012 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
            .onContinuousHover { phase in
                guard interactive, !reduceMotion else { return }
                switch phase {
                case .active(let location):
                    if !isHovered {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            isHovered = true
                        }
                    }
                    hoverLocation = location
                case .ended:
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isHovered = false
                    }
                }
            }
    }

    // Real-time backdrop blur + adaptive opacity glass fill
    @ViewBuilder
    private var glassBackground: some View {
        let isReduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let isIncreaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let tVal = isReduceTransparency ? 0.0 : Defaults[.islandTransparency]

        ZStack {
            // Tier 1 & 2: Real-time behind-window blur
            if !isReduceTransparency && !isIncreaseContrast {
                VisualEffectBackdropView(material: .hudWindow, blendingMode: .behindWindow)
            }

            // Dark obsidian glass tint to preserve maximum text contrast
            if isIncreaseContrast {
                Color.black
            } else if isReduceTransparency {
                Color(white: 0.08).opacity(0.95)
            } else {
                Color.black.opacity(max(0.28, layer.baseFillOpacity * (1.0 - tVal * 0.45)))
            }

            // Adaptive ambient color wash
            if let tint = tint, !isReduceTransparency {
                LinearGradient(
                    colors: [
                        tint.opacity(0.18),
                        tint.opacity(0.04),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Internal light simulation / top specular sheen
            if !isReduceTransparency {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.02),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
            }

            // Interactive mouse-driven dynamic light spot
            if isHovered && interactive && !reduceMotion && !isReduceTransparency {
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.03),
                        Color.clear
                    ],
                    center: UnitPoint(
                        x: max(0, min(1, hoverLocation.x / 300.0)),
                        y: max(0, min(1, hoverLocation.y / 150.0))
                    ),
                    startRadius: 0,
                    endRadius: 120
                )
            }
        }
    }

    // Multi-layer translucent border & edge refraction highlights
    private var glassBordersAndLighting: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(layer.borderOpacity * 1.5), location: 0.0),
                        .init(color: .white.opacity(layer.borderOpacity * 0.8), location: 0.3),
                        .init(color: .white.opacity(layer.borderOpacity * 0.2), location: 0.7),
                        .init(color: .white.opacity(layer.borderOpacity * 0.4), location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.0
            )
            .overlay(
                // Top specular highlight edge
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.05),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
                    .padding(0.5)
            )
    }
}

public extension View {
    func liquidGlassCard(
        cornerRadius: CGFloat = 20,
        tint: Color? = nil,
        interactive: Bool = true,
        layer: LiquidGlassLayer = .mid
    ) -> some View {
        self
            .modifier(
                LiquidGlassCardModifier(
                    cornerRadius: cornerRadius,
                    tint: tint,
                    interactive: interactive,
                    layer: layer
                )
            )
    }
}

// MARK: - 3. Liquid Glass Capsule Modifier & View

public struct LiquidGlassCapsuleModifier: ViewModifier {
    public var tint: Color?
    public var interactive: Bool
    public var isSelected: Bool

    @State private var isHovered: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(tint: Color? = nil, interactive: Bool = true, isSelected: Bool = false) {
        self.tint = tint
        self.interactive = interactive
        self.isSelected = isSelected
    }

    public func body(content: Content) -> some View {
        let isReduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let isIncreaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

        return content
            .background(
                ZStack {
                    LiquidGlassSurface(
                        shape: Capsule(),
                        isNotchAnchored: false,
                        scrimFloor: isSelected ? 0.40 : (isHovered ? 0.35 : 0.30)
                    )

                    if let tint = tint, !isReduceTransparency {
                        Capsule()
                            .fill(tint.opacity(isSelected ? 0.35 : (isHovered ? 0.2 : 0.1)))
                    }

                    // Top specular sheen
                    if !isReduceTransparency && !isIncreaseContrast {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered ? 0.25 : 0.12),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isSelected ? 0.45 : (isHovered ? 0.35 : 0.18)),
                                Color.white.opacity(isSelected ? 0.2 : (isHovered ? 0.12 : 0.04))
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(
                color: Color.black.opacity(isHovered ? 0.25 : 0.12),
                radius: isHovered ? 6 : 3,
                y: isHovered ? 3 : 1
            )
            .scaleEffect(interactive && isHovered && !reduceMotion ? 1.04 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isHovered)
            .onContinuousHover { phase in
                guard interactive, !reduceMotion else { return }
                switch phase {
                case .active:
                    if !isHovered {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            isHovered = true
                        }
                    }
                case .ended:
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        isHovered = false
                    }
                }
            }
    }
}

public extension View {
    func liquidGlassCapsule(tint: Color? = nil, interactive: Bool = true, isSelected: Bool = false) -> some View {
        self.modifier(LiquidGlassCapsuleModifier(tint: tint, interactive: interactive, isSelected: isSelected))
    }
}

// MARK: - 4. Liquid Glass Button

public struct LiquidGlassButton<Content: View>: View {
    let action: () -> Void
    let tint: Color?
    let haptic: Bool
    @ViewBuilder let content: () -> Content

    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        tint: Color? = nil,
        haptic: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tint = tint
        self.haptic = haptic
        self.action = action
        self.content = content
    }

    public var body: some View {
        Button(action: {
            action()
        }) {
            content()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .liquidGlassCapsule(tint: tint, interactive: false, isSelected: isPressed)
                .scaleEffect(isPressed ? 0.94 : (isHovered && !reduceMotion ? 1.05 : 1.0))
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            guard !reduceMotion else { return }
            switch phase {
            case .active:
                if !isHovered {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        isHovered = true
                    }
                }
            case .ended:
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isHovered = false
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

// MARK: - 5. Liquid Glass Equalizer (Integrated Audio Waveform)

public struct LiquidGlassEqualizerView: View {
    let isPlaying: Bool
    let tint: Color
    let barCount: Int = 4

    public init(isPlaying: Bool, tint: Color = .white) {
        self.isPlaying = isPlaying
        self.tint = tint
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: isPlaying ? 0.08 : nil)) { timeline in
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { index in
                    let height = barHeight(for: index, date: timeline.date)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint,
                                    tint.opacity(0.6)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2.5, height: height)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                        )
                        .shadow(color: tint.opacity(0.5), radius: 2, y: 1)
                }
            }
            .frame(height: 14)
        }
    }

    private func barHeight(for index: Int, date: Date) -> CGFloat {
        guard isPlaying else { return 3.0 }
        let time = date.timeIntervalSince1970 * 4.0
        let offset = Double(index) * 1.3
        let sine = sin(time + offset)
        let normalized = (sine + 1.0) / 2.0 // 0.0 to 1.0
        return CGFloat(4.0 + normalized * 10.0)
    }
}

// MARK: - 5. Visual Effect Backdrop View (AppKit Behind-Window Blending)

public struct VisualEffectBackdropView: NSViewRepresentable {
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
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - 6. Liquid Glass Surface (4-Tier Fallback Chain)

public struct LiquidGlassSurface<S: Shape>: View {
    public let shape: S
    public var isNotchAnchored: Bool
    public var ambientColor: Color?
    public var scrimFloor: CGFloat
    public var cornerRadius: CGFloat

    @Default(.islandTransparency) private var islandTransparency
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var weather = AmbientWeatherService.shared

    public init(
        shape: S,
        isNotchAnchored: Bool = false,
        ambientColor: Color? = nil,
        scrimFloor: CGFloat = 0.38,
        cornerRadius: CGFloat = 18.0
    ) {
        self.shape = shape
        self.isNotchAnchored = isNotchAnchored
        self.ambientColor = ambientColor
        self.scrimFloor = scrimFloor
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let isReduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let isIncreaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let tVal = isReduceTransparency ? 0.0 : max(0.0, min(1.0, islandTransparency))
        let glare = weather.specularGlareIntensity

        ZStack {
            // TIER 1 & 2: Behind-Window Liquid Glass Backdrop Blur
            // Active only when Reduce Transparency is NOT enabled
            if !isReduceTransparency && !isIncreaseContrast {
                VisualEffectBackdropView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(shape)
            }

            // TIER 3 & 4 / DARK SCRIM: Opacity Ramp & Dark Obsidian Tint
            // Hard guarantee: if notch-anchored, top 10-12pt and concave ears are 100% pure opaque black (#000000)
            if isIncreaseContrast {
                // Tier 4: High Contrast Solid Black
                shape.fill(Color.black)
            } else if isReduceTransparency {
                // Tier 3: Solid Dark Shapes (No blur, no caustics)
                shape.fill(Color(white: 0.08).opacity(0.96))
            } else if isNotchAnchored {
                // Tier 1 & 2: Pure Apple Obsidian glass body (10% subtle transparency)
                // Top area against notch hardware is 100% pure opaque black (#000000) blending seamlessly into hardware
                let targetAlpha: CGFloat = 0.90
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.20),
                        .init(color: Color(red: 0.04, green: 0.04, blue: 0.05).opacity(targetAlpha), location: 0.60),
                        .init(color: Color(red: 0.06, green: 0.06, blue: 0.07).opacity(targetAlpha), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(shape)
            } else {
                // Floating card / wing / HUD surface (unanchored, 10% subtle transparency)
                let baseAlpha: CGFloat = 0.90
                Color(red: 0.05, green: 0.05, blue: 0.06).opacity(baseAlpha)
                    .clipShape(shape)
            }

            // Ambient Glow & Background Refraction (e.g. from album art or status color)
            if !isReduceTransparency && !isIncreaseContrast, let ambientColor = ambientColor {
                RadialGradient(
                    colors: [
                        ambientColor.opacity(0.18),
                        ambientColor.opacity(0.04),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 280
                )
                .clipShape(shape)
            }

            // Apple Glossy Top Glass Horizon Sheen & Refraction
            if !isReduceTransparency && !isIncreaseContrast {
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.16), location: 0.0),
                        .init(color: Color.white.opacity(0.04), location: 0.20),
                        .init(color: Color.clear, location: 0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(shape)
            }

            // Apple Glossy Specular Perimeter Rim (Hairline glossy glass border)
            if isIncreaseContrast {
                shape.stroke(Color.white, lineWidth: 1.5)
            } else if !isReduceTransparency {
                shape.stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.32), location: 0.0),
                            .init(color: Color.white.opacity(0.12), location: 0.35),
                            .init(color: Color.white.opacity(0.06), location: 0.70),
                            .init(color: Color.white.opacity(0.18), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85
                )
            }
        }
    }
}

// MARK: - 7. Liquid Glass Dynamic Container Backdrop

/// Full-fidelity Liquid Glass Backdrop for the Dynamic Island container.
/// Features true backdrop blur, dark obsidian depth, album-art ambient lighting,
/// and edge specular reflections.
public struct LiquidGlassContainerBackdrop: View {
    public let topCornerRadius: CGFloat
    public let bottomCornerRadius: CGFloat
    public let isFloating: Bool
    public let isExpanded: Bool
    public let ambientColor: Color?

    public init(
        topCornerRadius: CGFloat = 20,
        bottomCornerRadius: CGFloat = 20,
        isFloating: Bool = true,
        isExpanded: Bool = false,
        ambientColor: Color? = nil
    ) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.isFloating = isFloating
        self.isExpanded = isExpanded
        self.ambientColor = ambientColor
    }

    public var body: some View {
        if isExpanded {
            // User request: Remove the background black dropdown completely; keep only individual floating contents
            EmptyView()
        } else {
            // Closed resting physical notch or compact floating pill
            DynamicIslandShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius,
                isFloating: isFloating
            )
            .fill(Color.black)
            .shadow(
                color: Color.black.opacity(Defaults[.enableShadow] ? 0.6 : 0.0),
                radius: 4,
                x: 0,
                y: 2
            )
        }
    }
}
