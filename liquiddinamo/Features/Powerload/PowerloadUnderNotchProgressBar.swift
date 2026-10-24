//
//  PowerloadUnderNotchProgressBar.swift
//  LiquidDynamo
//
//  Created for Powerload Multi-Network Download Accelerator.
//  Renders a sleek, fluid glowing progress bar directly under the hardware notch
//  or Dynamic Island when downloads are actively in progress.
//  Dynamic color shift: 1% Red -> 25% Orange -> 50% Yellow -> 75% Lime -> 100% Green.
//  Equipped with liquid glow bloom, specular shimmer, and animated droplet tip.
//

import AppKit
import SwiftUI

// MARK: - Color Interpolation Helper

public enum PowerloadGlowColor {
    /// Interpolates smoothly between Red (0-1%) and Pure Green (100%)
    public static func color(for progress: Double) -> Color {
        let p = min(1.0, max(0.0, progress))
        // Hue sweep: 0.0 (vivid red) -> 0.333 (vivid green)
        let hue: Double = p * 0.333
        return Color(hue: hue, saturation: 0.96, brightness: 1.0)
    }

    /// Color with custom opacity for glow layers
    public static func glowColor(for progress: Double, opacity: Double = 0.8) -> Color {
        color(for: progress).opacity(opacity)
    }

    /// Multi-stop gradient along the progress bar
    public static func progressGradient(for progress: Double) -> LinearGradient {
        let p = min(1.0, max(0.01, progress))
        let endColor = color(for: p)
        let startColor = Color(hue: 0.0, saturation: 0.96, brightness: 1.0) // Red
        return LinearGradient(
            colors: [startColor, endColor],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Under Notch Glowing Progress Bar View

public struct PowerloadUnderNotchProgressBar: View {
    @ObservedObject private var engine = PowerloadDownloadEngine.shared
    @ObservedObject private var island = IslandController.shared
    public var isExpanded: Bool

    @State private var shimmerOffset: CGFloat = -1.0
    @State private var isHovered: Bool = false
    @State private var pulseScale: CGFloat = 1.0

    public init(isExpanded: Bool = false) {
        self.isExpanded = isExpanded
    }

    private var activeTask: PowerloadDownloadTask? {
        engine.activeTasks.first(where: { $0.state == .downloading || $0.state == .probing })
    }

    private var currentProgress: Double {
        guard let task = activeTask else { return 0.0 }
        return task.progress
    }

    public var body: some View {
        if let task = activeTask {
            let geom = NotchSafeAreaEngine.shared.currentGeometry
            let baseWidth: CGFloat = {
                if isExpanded {
                    return max(240, min(island.targetSize.width - 32, 540))
                } else if geom.hasPhysicalNotch {
                    return max(geom.rawNotchWidth + 8, 200)
                } else {
                    return max(island.targetSize.width - 16, 180)
                }
            }()

            VStack(spacing: 3) {
                // Main Glowing Bar Beam
                ZStack(alignment: .leading) {
                    // 1. Outer Diffuse Glow Blur (Atmospheric bloom beneath the notch)
                    Capsule(style: .continuous)
                        .fill(PowerloadGlowColor.glowColor(for: currentProgress, opacity: 0.45))
                        .frame(width: max(8, baseWidth * CGFloat(max(0.02, currentProgress))), height: 6)
                        .blur(radius: 6)
                        .offset(y: 1)

                    // 2. Secondary Intense Neon Bloom
                    Capsule(style: .continuous)
                        .fill(PowerloadGlowColor.glowColor(for: currentProgress, opacity: 0.75))
                        .frame(width: max(6, baseWidth * CGFloat(max(0.02, currentProgress))), height: 4)
                        .blur(radius: 2.5)

                    // 3. Track Bed (Subtle glass channel)
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.45))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                        .frame(width: baseWidth, height: 3.5)

                    // 4. Active Progress Fill
                    let fillWidth = max(4, baseWidth * CGFloat(max(0.01, currentProgress)))
                    Capsule(style: .continuous)
                        .fill(PowerloadGlowColor.progressGradient(for: currentProgress))
                        .frame(width: fillWidth, height: 3.5)
                        // Radiant colored drop shadow
                        .shadow(
                            color: PowerloadGlowColor.glowColor(for: currentProgress, opacity: 0.9),
                            radius: 4,
                            x: 0,
                            y: 1
                        )
                        .shadow(
                            color: PowerloadGlowColor.glowColor(for: currentProgress, opacity: 0.5),
                            radius: 10,
                            x: 0,
                            y: 2
                        )

                    // 5. Specular Shimmer Highlight
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.0),
                                    Color.white.opacity(0.65),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 30, height: 3.5)
                        .offset(x: max(0, fillWidth * shimmerOffset))
                        .mask(
                            Capsule(style: .continuous)
                                .frame(width: fillWidth, height: 3.5)
                        )

                    // 6. Leading Glowing Droplet / Orb at head of progress
                    if currentProgress > 0.01 && currentProgress < 0.999 {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 5, height: 5)
                            .overlay(
                                Circle()
                                    .stroke(PowerloadGlowColor.color(for: currentProgress), lineWidth: 1.2)
                            )
                            .shadow(
                                color: PowerloadGlowColor.glowColor(for: currentProgress, opacity: 1.0),
                                radius: 4,
                                x: 0,
                                y: 0
                            )
                            .shadow(
                                color: Color.white.opacity(0.8),
                                radius: 2,
                                x: 0,
                                y: 0
                            )
                            .scaleEffect(pulseScale)
                            .offset(x: fillWidth - 2.5)
                    }
                }
                .frame(width: baseWidth, height: 7)

                // Optional Info Tooltip Badge on Hover
                if isHovered && !isExpanded {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(PowerloadGlowColor.color(for: currentProgress))

                        Text(task.fileName)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 120)

                        Text("\(Int(currentProgress * 100))%")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(PowerloadGlowColor.color(for: currentProgress))

                        Text(task.formattedSpeed)
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(PowerloadGlowColor.color(for: currentProgress).opacity(0.35), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 4, y: 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.18)) {
                    isHovered = hovering
                }
            }
            .onTapGesture {
                IslandController.shared.setExpanded(view: .powerload, pin: true)
            }
            .onAppear {
                startShimmerLoop()
                startPulseLoop()
            }
            .animation(.linear(duration: 0.35), value: currentProgress)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    private func startShimmerLoop() {
        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            shimmerOffset = 1.0
        }
    }

    private func startPulseLoop() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseScale = 1.3
        }
    }
}
