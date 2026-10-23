//
//  SettingsAppearanceView.swift
//  LiquidDynamo
//
//  Control Center Appearance: Liquid Glass themes, blur, transparency,
//  reflections, animation speed, and corner radius tuning.
//

import AppKit
import Defaults
import SwiftUI

public struct SettingsAppearanceView: View {
    @Default(.selectedLiquidTheme) private var selectedTheme
    @Default(.islandTransparency) private var islandTransparency
    @Default(.islandBlurAmount) private var blurAmount
    @Default(.islandReflectionStrength) private var reflectionStrength
    @Default(.islandAnimationSpeed) private var animationSpeed
    @Default(.islandCornerRadius) private var cornerRadius
    @Default(.wingWidth) private var wingWidth
    @Default(.compactMode) private var compactMode
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData

    @State private var customColor: Color = .cyan

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Appearance & Shaders")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Customize the VisionOS-inspired Liquid Glass material and optical shaders")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Themes Grid
                themesSection
                    .padding(.horizontal, 24)

                // Optical Controls: Transparency, Blur, Reflection, Corner Radius, Animation Speed
                opticalControlsSection
                    .padding(.horizontal, 24)

                // Wing Width & Layout Geometry
                geometrySection
                    .padding(.horizontal, 24)

                Spacer(minLength: 20)
            }
        }
    }

    // MARK: - Themes Section
    private var themesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Liquid Themes")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                themeCard(theme: .liquidGlass, gradient: [Color.white.opacity(0.3), Color.cyan.opacity(0.2), Color.black.opacity(0.6)])
                themeCard(theme: .liquidDark, gradient: [Color(white: 0.2), Color.black.opacity(0.85)])
                themeCard(theme: .ocean, gradient: [Color.cyan.opacity(0.5), Color.blue.opacity(0.7), Color.black.opacity(0.7)])
                themeCard(theme: .aurora, gradient: [Color.green.opacity(0.5), Color.purple.opacity(0.6), Color.black.opacity(0.7)])
                themeCard(theme: .midnight, gradient: [Color.indigo.opacity(0.5), Color.blue.opacity(0.8), Color.black.opacity(0.8)])
                themeCard(theme: .crystal, gradient: [Color.white.opacity(0.4), Color.pink.opacity(0.3), Color.purple.opacity(0.4)])
            }
        }
    }

    private func themeCard(theme: LiquidTheme, gradient: [Color]) -> some View {
        let isSelected = selectedTheme == theme
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedTheme = theme
                applyThemePresets(theme)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Preview Pill
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8)
                    )
                    .overlay(
                        Group {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.white)
                                    .shadow(radius: 4)
                            }
                        }
                    )

                Text(theme.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.40))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? Color.cyan.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func applyThemePresets(_ theme: LiquidTheme) {
        switch theme {
        case .liquidGlass:
            islandTransparency = 0.50
            blurAmount = 24.0
            reflectionStrength = 0.65
        case .liquidDark:
            islandTransparency = 0.20
            blurAmount = 28.0
            reflectionStrength = 0.35
        case .ocean:
            islandTransparency = 0.55
            blurAmount = 26.0
            reflectionStrength = 0.75
        case .aurora:
            islandTransparency = 0.45
            blurAmount = 30.0
            reflectionStrength = 0.80
        case .midnight:
            islandTransparency = 0.30
            blurAmount = 32.0
            reflectionStrength = 0.50
        case .crystal:
            islandTransparency = 0.70
            blurAmount = 18.0
            reflectionStrength = 0.90
        }
        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
    }

    // MARK: - Optical Controls Section
    private var opticalControlsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Optical Shaders & Materials")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            // Transparency
            sliderRow(
                title: "Glass Transparency",
                value: Binding(get: { islandTransparency }, set: { islandTransparency = $0 }),
                range: 0.1...0.9,
                displayStr: "\(Int(islandTransparency * 100))%"
            )

            Divider().opacity(0.2)

            // Blur Amount
            sliderRow(
                title: "Backdrop Blur",
                value: $blurAmount,
                range: 10.0...50.0,
                displayStr: "\(Int(blurAmount)) pt"
            )

            Divider().opacity(0.2)

            // Reflection Strength
            sliderRow(
                title: "Liquid Reflection Strength",
                value: $reflectionStrength,
                range: 0.1...1.0,
                displayStr: "\(Int(reflectionStrength * 100))%"
            )

            Divider().opacity(0.2)

            // Animation Speed
            sliderRow(
                title: "Animation Responsiveness",
                value: $animationSpeed,
                range: 0.5...2.0,
                displayStr: "\(String(format: "%.1fx", animationSpeed))"
            )

            Divider().opacity(0.2)

            // Corner Radius
            sliderRow(
                title: "Corner Radius",
                value: $cornerRadius,
                range: 14.0...34.0,
                displayStr: "\(Int(cornerRadius)) pt"
            )
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        )
    }

    // MARK: - Geometry Section
    private var geometrySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Notch Expansion Geometry")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            sliderRow(
                title: "Informational Wing Width",
                value: Binding(get: { Double(wingWidth) }, set: { wingWidth = CGFloat($0) }),
                range: 50.0...160.0,
                displayStr: "\(Int(wingWidth)) pt"
            )

            Divider().opacity(0.2)

            HStack {
                Text("Collapse Style")
                    .font(.system(size: 12, design: .rounded))
                Spacer()
                Picker("", selection: $compactMode) {
                    Text("Balanced Wings").tag(false)
                    Text("Compact Streams").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        )
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, displayStr: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, design: .rounded))
                Spacer()
                Text(displayStr)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.cyan)
            }

            Slider(value: value, in: range)
        }
    }
}
