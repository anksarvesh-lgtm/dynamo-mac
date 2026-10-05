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
        ZStack {
            // Real-time backdrop material
            Rectangle()
                .fill(.ultraThinMaterial)

            // Dark obsidian glass tint to preserve maximum text contrast
            Color.black.opacity(layer.baseFillOpacity)

            // Adaptive ambient color wash
            if let tint = tint {
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
            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.02),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )

            // Interactive mouse-driven dynamic light spot
            if isHovered && interactive && !reduceMotion {
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
        content
            .background(
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)

                    Capsule()
                        .fill(Color.black.opacity(isSelected ? 0.35 : (isHovered ? 0.45 : 0.55)))

                    if let tint = tint {
                        Capsule()
                            .fill(tint.opacity(isSelected ? 0.35 : (isHovered ? 0.2 : 0.1)))
                    }

                    // Top specular sheen
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

// MARK: - 6. Liquid Glass Dynamic Container Backdrop

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
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat,
        isFloating: Bool,
        isExpanded: Bool,
        ambientColor: Color? = nil
    ) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.isFloating = isFloating
        self.isExpanded = isExpanded
        self.ambientColor = ambientColor
    }

    public var body: some View {
        ZStack {
            // 1. Material Backdrop Blur
            if isExpanded {
                DynamicIslandShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius,
                    isFloating: isFloating
                )
                .fill(.ultraThinMaterial)
            } else {
                DynamicIslandShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius,
                    isFloating: isFloating
                )
                .fill(Color.black)
            }

            // 2. Obsidian Glass Tint (Ensures 100% text readability over any wallpaper)
            DynamicIslandShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius,
                isFloating: isFloating
            )
            .fill(isExpanded ? Color.black.opacity(0.78) : Color.black)

            // 3. Ambient Lighting derived from media or status
            if isExpanded, let ambientColor = ambientColor {
                DynamicIslandShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius,
                    isFloating: isFloating
                )
                .fill(
                    RadialGradient(
                        colors: [
                            ambientColor.opacity(0.24),
                            ambientColor.opacity(0.06),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 20,
                        endRadius: 280
                    )
                )
            }

            // 4. Subtle Top Glass Horizon Sheen
            if isExpanded {
                DynamicIslandShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius,
                    isFloating: isFloating
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.02),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }

            // 5. Specular Perimeter Edge Stroke (Chiseled Glass Border)
            if isExpanded {
                DynamicIslandShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius,
                    isFloating: isFloating
                )
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.38), location: 0.0),
                            .init(color: .white.opacity(0.14), location: 0.4),
                            .init(color: .white.opacity(0.05), location: 0.7),
                            .init(color: .white.opacity(0.18), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.0
                )
            }
        }
        // Floating 3D spatial shadow
        .shadow(
            color: Color.black.opacity(isExpanded ? 0.5 : (Defaults[.enableShadow] ? 0.6 : 0.0)),
            radius: isExpanded ? 24 : 4,
            x: 0,
            y: isExpanded ? 10 : 2
        )
        .shadow(
            color: Color.black.opacity(isExpanded ? 0.25 : 0.0),
            radius: 4,
            x: 0,
            y: 1
        )
    }
}
