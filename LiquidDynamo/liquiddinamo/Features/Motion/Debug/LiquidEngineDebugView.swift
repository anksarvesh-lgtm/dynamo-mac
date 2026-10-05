//
//  LiquidEngineDebugView.swift
//  LiquidDynamo
//
//  Standalone Debug Inspector for the Liquid Island SDF Metal Shader & Lobe System.
//

import SwiftUI

public struct LiquidEngineDebugView: View {
    @State private var kSmoothing: CGFloat = 18.0
    @State private var selectedTint: LiquidIslandTintPreset = .agrigenceEmerald
    @State private var customColor: Color = Color(red: 0.06, green: 0.75, blue: 0.52)
    @State private var useCustomColor: Bool = false
    @State private var forceFallback: Bool = false
    @State private var showLayoutGuides: Bool = true

    // 3D Lighting Config
    @State private var lighting = LiquidLightingConfig()

    // 8 SDF Lobes
    // Lobe 0: Root (anchored along notch bottom lip)
    @State private var rootWidth: CGFloat = 190.0
    @State private var rootHeight: CGFloat = 14.0
    @State private var rootBulgeY: CGFloat = 16.0

    // Lobe 1: Body (content container in belowArea)
    @State private var bodyX: CGFloat = 300.0
    @State private var bodyY: CGFloat = 80.0
    @State private var bodyWidth: CGFloat = 260.0
    @State private var bodyHeight: CGFloat = 48.0
    @State private var bodyCornerRadius: CGFloat = 24.0

    // Lobe 2: Wing Left
    @State private var wingLActive: Bool = true
    @State private var wingLWidth: CGFloat = 90.0
    @State private var wingLHeight: CGFloat = 32.0

    // Lobe 3: Wing Right
    @State private var wingRActive: Bool = true
    @State private var wingRWidth: CGFloat = 90.0
    @State private var wingRHeight: CGFloat = 32.0

    // Lobe 4: Droplet
    @State private var dropletActive: Bool = true
    @State private var dropletX: CGFloat = 300.0
    @State private var dropletY: CGFloat = 46.0
    @State private var dropletRadius: CGFloat = 16.0

    // Lobe 5: Satellite Bubble
    @State private var satelliteActive: Bool = false
    @State private var satelliteX: CGFloat = 460.0
    @State private var satelliteY: CGFloat = 78.0
    @State private var satelliteRadius: CGFloat = 18.0

    // Animation Test State
    @State private var currentPhaseName: String = "Manual Controls"

    public init() {}

    private var activeTintColor: Color {
        useCustomColor ? customColor : selectedTint.color
    }

    private var generatedLobes: [LiquidIslandLobe] {
        let canvasMidX: CGFloat = 300.0
        let notchH: CGFloat = 32.0

        return [
            // 0. Root
            LiquidIslandLobe(
                id: 0,
                name: "Root (Notch Anchor)",
                centerX: canvasMidX,
                centerY: rootBulgeY,
                halfWidth: rootWidth / 2.0,
                halfHeight: rootHeight / 2.0,
                cornerRadius: min(rootHeight / 2.0, 10.0),
                isActive: true
            ),
            // 1. Body
            LiquidIslandLobe(
                id: 1,
                name: "Body (Container)",
                centerX: bodyX,
                centerY: bodyY,
                halfWidth: bodyWidth / 2.0,
                halfHeight: bodyHeight / 2.0,
                cornerRadius: bodyCornerRadius,
                isActive: true
            ),
            // 2. Wing Left
            LiquidIslandLobe(
                id: 2,
                name: "Wing Left",
                centerX: canvasMidX - (rootWidth / 2.0) - (wingLWidth / 2.0),
                centerY: notchH / 2.0,
                halfWidth: wingLWidth / 2.0,
                halfHeight: wingLHeight / 2.0,
                cornerRadius: min(wingLHeight / 2.0, 14.0),
                isActive: wingLActive
            ),
            // 3. Wing Right
            LiquidIslandLobe(
                id: 3,
                name: "Wing Right",
                centerX: canvasMidX + (rootWidth / 2.0) + (wingRWidth / 2.0),
                centerY: notchH / 2.0,
                halfWidth: wingRWidth / 2.0,
                halfHeight: wingRHeight / 2.0,
                cornerRadius: min(wingRHeight / 2.0, 14.0),
                isActive: wingRActive
            ),
            // 4. Droplet
            LiquidIslandLobe(
                id: 4,
                name: "Droplet",
                centerX: dropletX,
                centerY: dropletY,
                halfWidth: dropletRadius,
                halfHeight: dropletRadius,
                cornerRadius: dropletRadius,
                isActive: dropletActive
            ),
            // 5. Satellite
            LiquidIslandLobe(
                id: 5,
                name: "Satellite",
                centerX: satelliteX,
                centerY: satelliteY,
                halfWidth: satelliteRadius,
                halfHeight: satelliteRadius,
                cornerRadius: satelliteRadius,
                isActive: satelliteActive
            )
        ]
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left: Real-time Metal Shader Canvas
            VStack(spacing: 12) {
                HStack {
                    Text("Liquid Island Metal SDF View")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    Text("Phase: \(currentPhaseName)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // The Metal Shader Canvas Area
                ZStack(alignment: .top) {
                    // Dark background representing desktop wallpaper
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.12), Color(white: 0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )

                    // Hardware Notch Silhouette (The hole that must NEVER contain content!)
                    if showLayoutGuides {
                        ZStack(alignment: .top) {
                            // Hardware Notch shape
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: rootWidth, height: 32)
                                .overlay(
                                    Rectangle()
                                        .strokeBorder(Color.red.opacity(0.6), lineWidth: 1.5)
                                )
                                .overlay(
                                    Text("NOTCH HOLE (NO CONTENT)")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.red.opacity(0.8))
                                )

                            // Safe Left Slot Guide
                            Rectangle()
                                .strokeBorder(Color.cyan.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .frame(width: wingLWidth, height: 32)
                                .offset(x: -(rootWidth / 2.0) - (wingLWidth / 2.0))

                            // Safe Right Slot Guide
                            Rectangle()
                                .strokeBorder(Color.cyan.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .frame(width: wingRWidth, height: 32)
                                .offset(x: (rootWidth / 2.0) + (wingRWidth / 2.0))
                        }
                    }

                    // Metal Shader Canvas
                    LiquidIslandCanvasView(
                        lobes: generatedLobes,
                        k: kSmoothing,
                        lighting: lighting,
                        tintColor: activeTintColor,
                        forceFallback: forceFallback
                    )
                    .frame(width: 600, height: 180)
                    .clipped()
                }
                .frame(width: 600, height: 180)
                .padding(.horizontal, 16)

                // Quick Animation Trigger Buttons
                HStack(spacing: 8) {
                    Button("1. Swell") { triggerSwellPhase() }
                    Button("2. Birth & Fall") { triggerBirthPhase() }
                    Button("3. Bloom") { triggerBloomPhase() }
                    Button("4. Collapse (Absorb)") { triggerAbsorbPhase() }
                    Button("5. Evaporate") { triggerEvaporatePhase() }
                    Spacer()
                    Button("Reset") { resetToDefaults() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.horizontal, 16)

                Divider()

                // Bottom: Renderer & Display Options
                HStack(spacing: 16) {
                    Toggle("Show Guides", isOn: $showLayoutGuides)
                    Toggle("Force Canvas Fallback", isOn: $forceFallback)
                    Spacer()
                    Text("Renderer: \(forceFallback ? "Canvas Fallback" : "Metal Shader (macOS 14+)")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(forceFallback ? .orange : .green)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .frame(width: 630)

            Divider()

            // Right: Tuning Control Sliders (Tabbed / Categorized)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tuning Controls")
                        .font(.system(size: 16, weight: .bold))

                    // MARK: - Fluid Smooth Minimum (k)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Smoothing Radius k (Viscosity)")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(String(format: "%.1f pt", kSmoothing))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $kSmoothing, in: 0.0...40.0)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))

                    // MARK: - Tint Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fluid Tint Color")
                            .font(.system(size: 12, weight: .semibold))

                        HStack(spacing: 8) {
                            ForEach(LiquidIslandTintPreset.allCases) { preset in
                                Button(action: {
                                    selectedTint = preset
                                    useCustomColor = false
                                }) {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(preset.color)
                                            .frame(width: 10, height: 10)
                                        Text(preset.rawValue)
                                            .font(.system(size: 11))
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(selectedTint == preset && !useCustomColor ? preset.color : .secondary)
                            }
                        }

                        HStack {
                            Toggle("Custom Color", isOn: $useCustomColor)
                            if useCustomColor {
                                ColorPicker("", selection: $customColor)
                                    .labelsHidden()
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))

                    // MARK: - Lobe 1 (Body)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Body Lobe (Main Container)")
                            .font(.system(size: 12, weight: .semibold))

                        sliderRow(label: "Width", value: $bodyWidth, in: 100...480, unit: "pt")
                        sliderRow(label: "Height", value: $bodyHeight, in: 24...120, unit: "pt")
                        sliderRow(label: "Corner Radius", value: $bodyCornerRadius, in: 6...40, unit: "pt")
                        sliderRow(label: "Center Y (Offset)", value: $bodyY, in: 40...140, unit: "pt")
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))

                    // MARK: - Lobe 4 (Droplet)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Droplet Lobe (Gooey Neck)")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Toggle("", isOn: $dropletActive).labelsHidden()
                        }

                        if dropletActive {
                            sliderRow(label: "Droplet Y", value: $dropletY, in: 20...120, unit: "pt")
                            sliderRow(label: "Radius", value: $dropletRadius, in: 4...30, unit: "pt")
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))

                    // MARK: - Lobe 0 (Root Bulge)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Root Lobe (Notch Bottom Anchor)")
                            .font(.system(size: 12, weight: .semibold))

                        sliderRow(label: "Root Width", value: $rootWidth, in: 140...260, unit: "pt")
                        sliderRow(label: "Root Height (Bulge)", value: $rootHeight, in: 4...28, unit: "pt")
                        sliderRow(label: "Root Y", value: $rootBulgeY, in: 8...24, unit: "pt")
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))

                    // MARK: - Wings & Satellite
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Wings & Satellite Lobes")
                            .font(.system(size: 12, weight: .semibold))

                        HStack {
                            Toggle("Left Wing", isOn: $wingLActive)
                            Toggle("Right Wing", isOn: $wingRActive)
                            Toggle("Satellite Bubble", isOn: $satelliteActive)
                        }

                        if wingLActive || wingRActive {
                            sliderRow(label: "Wing Width", value: $wingLWidth, in: 40...140, unit: "pt")
                        }
                        if satelliteActive {
                            sliderRow(label: "Satellite X", value: $satelliteX, in: 380...520, unit: "pt")
                            sliderRow(label: "Satellite Radius", value: $satelliteRadius, in: 8...30, unit: "pt")
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))

                    // MARK: - 3D Lighting & Specular
                    VStack(alignment: .leading, spacing: 6) {
                        Text("3D Lighting & Shading")
                            .font(.system(size: 12, weight: .semibold))

                        sliderRow(label: "Key Light X", value: Binding(get: { CGFloat(lighting.lightDirX) }, set: { lighting.lightDirX = Float($0) }), in: -2.0...2.0, unit: "")
                        sliderRow(label: "Key Light Y", value: Binding(get: { CGFloat(lighting.lightDirY) }, set: { lighting.lightDirY = Float($0) }), in: -2.0...2.0, unit: "")
                        sliderRow(label: "Tight Specular Power", value: Binding(get: { CGFloat(lighting.tightPower) }, set: { lighting.tightPower = Float($0) }), in: 4.0...64.0, unit: "")
                        sliderRow(label: "Tight Specular Intensity", value: Binding(get: { CGFloat(lighting.tightSpecIntensity) }, set: { lighting.tightSpecIntensity = Float($0) }), in: 0.0...1.5, unit: "")
                        sliderRow(label: "Broad Sheen Intensity", value: Binding(get: { CGFloat(lighting.broadSpecIntensity) }, set: { lighting.broadSpecIntensity = Float($0) }), in: 0.0...1.0, unit: "")
                        sliderRow(label: "Fresnel Rim Intensity", value: Binding(get: { CGFloat(lighting.fresnelIntensity) }, set: { lighting.fresnelIntensity = Float($0) }), in: 0.0...1.5, unit: "")
                        sliderRow(label: "Inner Depth Shadow", value: Binding(get: { CGFloat(lighting.innerDepthIntensity) }, set: { lighting.innerDepthIntensity = Float($0) }), in: 0.0...1.0, unit: "")
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                }
                .padding(16)
            }
            .frame(width: 380)
        }
        .frame(width: 1010, height: 420)
    }

    private func sliderRow(label: String, value: Binding<CGFloat>, in range: ClosedRange<CGFloat>, unit: String) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f %@", value.wrappedValue, unit))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    // MARK: - Interactive Lifecycle Animations

    private func triggerSwellPhase() {
        currentPhaseName = "1. Swell (~0.12s)"
        withAnimation(.easeIn(duration: 0.12)) {
            rootHeight = 22.0
            rootBulgeY = 20.0
            kSmoothing = 26.0
            dropletActive = true
            dropletY = 28.0
            dropletRadius = 14.0
            bodyWidth = 100.0
            bodyHeight = 24.0
            bodyY = 32.0
        }
    }

    private func triggerBirthPhase() {
        currentPhaseName = "2. Birth & Fall (~0.24s)"
        withAnimation(.easeOut(duration: 0.24)) {
            rootHeight = 14.0
            rootBulgeY = 16.0
            kSmoothing = 22.0
            dropletY = 64.0
            dropletRadius = 16.0
            bodyWidth = 160.0
            bodyHeight = 36.0
            bodyY = 70.0
        }
    }

    private func triggerBloomPhase() {
        currentPhaseName = "3. Bloom (~0.40s)"
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            kSmoothing = 12.0
            dropletActive = false
            bodyWidth = 320.0
            bodyHeight = 52.0
            bodyCornerRadius = 26.0
            bodyY = 82.0
        }
    }

    private func triggerAbsorbPhase() {
        currentPhaseName = "6. Collapse: Absorb into Notch"
        withAnimation(.easeIn(duration: 0.15)) {
            bodyWidth = 120.0
            bodyHeight = 30.0
            dropletActive = true
            dropletY = 60.0
            kSmoothing = 24.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.20)) {
                bodyWidth = 40.0
                bodyHeight = 16.0
                bodyY = 28.0
                dropletY = 22.0
                rootHeight = 20.0
                kSmoothing = 28.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                withAnimation(.easeOut(duration: 0.12)) {
                    self.resetToDefaults()
                }
            }
        }
    }

    private func triggerEvaporatePhase() {
        currentPhaseName = "6. Collapse: Evaporate"
        withAnimation(.easeOut(duration: 0.30)) {
            bodyWidth = 20.0
            bodyHeight = 10.0
            dropletRadius = 2.0
            kSmoothing = 4.0
            lighting.tightSpecIntensity = 0.0
            lighting.fresnelIntensity = 0.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            self.resetToDefaults()
        }
    }

    private func resetToDefaults() {
        currentPhaseName = "Manual Controls"
        rootWidth = 190.0
        rootHeight = 14.0
        rootBulgeY = 16.0
        bodyX = 300.0
        bodyY = 80.0
        bodyWidth = 260.0
        bodyHeight = 48.0
        bodyCornerRadius = 24.0
        dropletActive = true
        dropletX = 300.0
        dropletY = 46.0
        dropletRadius = 16.0
        satelliteActive = false
        kSmoothing = 18.0
        lighting = LiquidLightingConfig()
    }
}
