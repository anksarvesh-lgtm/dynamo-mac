//
//  LiquidBlobDebugView.swift
//  LiquidDynamo
//
//  Step B: Interactive Debug Inspector for the multi-blob fluid renderer
//  and content-driven lobe generator with real-time sliders and CPU hit-testing verification.
//

import AppKit
import Defaults
import Foundation
import SwiftUI

public struct LiquidBlobDebugView: View {
    public enum ContentPreset: String, CaseIterable, Identifiable {
        case small = "Small (HUD / Volume)"
        case medium = "Medium (Media Alert)"
        case large = "Large (Dashboard Cluster)"
        case manual = "Manual Sliders"

        public var id: String { rawValue }
    }

    @ObservedObject private var flow = LiquidFlowCoordinator.shared
    @ObservedObject private var motion = IslandMotion.shared
    @State private var lifecycleInteractiveMode: Bool = true

    @State private var preset: ContentPreset = .medium
    @State private var emergenceProgress: CGFloat = 1.0
    @State private var kSmoothing: CGFloat = 18.0
    @State private var seed: CGFloat = 42.0
    @State private var time: CGFloat = 0.0
    @State private var isPlayingTime: Bool = true
    @State private var bgLuminance: CGFloat = 0.0
    @State private var transparency: CGFloat = 0.60
    @State private var selectedTint: Color = Color(red: 0.06, green: 0.75, blue: 0.52)
    @State private var forceFallback: Bool = false
    @State private var showHitTestOverlay: Bool = true
    @State private var showClusterGuides: Bool = true

    // Manual Blob Sliders
    @State private var manualBlobCount: Int = 4
    @State private var blob0RadiusX: CGFloat = 40.0
    @State private var blob0RadiusY: CGFloat = 20.0
    @State private var blob1RadiusX: CGFloat = 65.0
    @State private var blob1RadiusY: CGFloat = 30.0
    @State private var blob2RadiusX: CGFloat = 50.0
    @State private var blob2RadiusY: CGFloat = 28.0
    @State private var blob3RadiusX: CGFloat = 35.0
    @State private var blob3RadiusY: CGFloat = 22.0
    @State private var manualIrregularity: CGFloat = 0.20

    // Probe mouse position for CPU hit-test verification
    @State private var probeLocation: CGPoint = .zero
    @State private var probeInside: Bool = false
    @State private var probeDistance: CGFloat = 0.0

    public init() {}

    private var currentClusters: [ContentDrivenBlobGenerator.ContentCluster] {
        let centerX: CGFloat = 300.0
        let contentY: CGFloat = 32.0 + 38.0

        switch preset {
        case .small:
            return [
                .init(id: "icon", center: CGPoint(x: centerX - 35, y: contentY), size: CGSize(width: 24, height: 24), kind: .icon),
                .init(id: "text", center: CGPoint(x: centerX + 20, y: contentY), size: CGSize(width: 70, height: 18), kind: .textLine)
            ]
        case .medium:
            return [
                .init(id: "albumArt", center: CGPoint(x: centerX - 85, y: contentY), size: CGSize(width: 38, height: 38), kind: .icon),
                .init(id: "title", center: CGPoint(x: centerX, y: contentY - 8), size: CGSize(width: 110, height: 16), kind: .textLine),
                .init(id: "artist", center: CGPoint(x: centerX, y: contentY + 10), size: CGSize(width: 90, height: 14), kind: .textLine),
                .init(id: "controls", center: CGPoint(x: centerX + 85, y: contentY), size: CGSize(width: 44, height: 26), kind: .controlGroup),
                .init(id: "belly", center: CGPoint(x: centerX, y: contentY + 20), size: CGSize(width: 80, height: 20), kind: .swellingDroplet)
            ]
        case .large:
            return [
                .init(id: "mainArt", center: CGPoint(x: centerX - 120, y: contentY + 8), size: CGSize(width: 50, height: 50), kind: .icon),
                .init(id: "title", center: CGPoint(x: centerX - 20, y: contentY - 14), size: CGSize(width: 130, height: 18), kind: .textLine),
                .init(id: "stats", center: CGPoint(x: centerX - 20, y: contentY + 8), size: CGSize(width: 120, height: 16), kind: .textLine),
                .init(id: "slider", center: CGPoint(x: centerX - 10, y: contentY + 28), size: CGSize(width: 140, height: 12), kind: .sliderLevel),
                .init(id: "rightControls", center: CGPoint(x: centerX + 110, y: contentY + 8), size: CGSize(width: 75, height: 40), kind: .controlGroup),
                .init(id: "bellyDrop", center: CGPoint(x: centerX, y: contentY + 36), size: CGSize(width: 120, height: 24), kind: .swellingDroplet)
            ]
        case .manual:
            return []
        }
    }

    private var activeBlobs: [LiquidBlobLobe] {
        let centerX: CGFloat = 300.0
        let notchLipY: CGFloat = 32.0

        if preset == .manual {
            var list: [LiquidBlobLobe] = []
            list.append(LiquidBlobLobe(id: 0, name: "Stream Source", centerX: centerX, centerY: notchLipY + 4, radiusX: blob0RadiusX, radiusY: blob0RadiusY, weight: 1.1, irregularity: manualIrregularity))
            if manualBlobCount >= 2 {
                list.append(LiquidBlobLobe(id: 1, name: "Stream Body", centerX: centerX, centerY: notchLipY + 40, radiusX: blob1RadiusX, radiusY: blob1RadiusY, weight: 1.0, irregularity: manualIrregularity))
            }
            if manualBlobCount >= 3 {
                list.append(LiquidBlobLobe(id: 2, name: "Left Lobe", centerX: centerX - 70, centerY: notchLipY + 50, radiusX: blob2RadiusX, radiusY: blob2RadiusY, weight: 1.0, irregularity: manualIrregularity))
            }
            if manualBlobCount >= 4 {
                list.append(LiquidBlobLobe(id: 3, name: "Right Lobe", centerX: centerX + 70, centerY: notchLipY + 50, radiusX: blob3RadiusX, radiusY: blob3RadiusY, weight: 1.0, irregularity: manualIrregularity))
            }
            return list
        } else {
            return ContentDrivenBlobGenerator.generateLobes(
                clusters: currentClusters,
                notchLipY: notchLipY,
                notchCenterX: centerX,
                notchWidth: 170.0,
                emergenceProgress: emergenceProgress,
                seed: seed,
                time: time
            )
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LiquidDynamo Multi-Blob Liquid Inspector")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Step B & C: Analytic Ellipse Metaball Renderer & Fluid Flow Lifecycle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Inspector Mode", selection: $lifecycleInteractiveMode) {
                    Text("Flow Lifecycle (Step C)").tag(true)
                    Text("Static Shapes (Step B)").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Button("Randomize Seed") {
                    seed = CGFloat(Int.random(in: 1...9999))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(white: 0.12))

            Divider()

            HSplitView {
                // Left: Live Viewport
                VStack(spacing: 12) {
                    ZStack {
                        // Background simulator (dark window, white window, or bright wallpaper)
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(white: Double(bgLuminance)),
                                        Color(white: Double(max(0, bgLuminance - 0.15)))
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )

                        // Hardware notch simulator at top
                        VStack(spacing: 0) {
                            HStack {
                                Spacer()
                                Rectangle()
                                    .fill(Color.black)
                                    .frame(width: 170, height: 32)
                                    .overlay(
                                        Text("HARDWARE NOTCH (EMPTY)")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.gray.opacity(0.6))
                                    )
                                Spacer()
                            }
                            Spacer()
                        }

                        if lifecycleInteractiveMode {
                            // Step C Interactive Flow Container
                            LiquidFlowContainerView(tintColor: selectedTint) {
                                HStack(spacing: 12) {
                                    Image(systemName: "drop.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 24, height: 24)
                                        .foregroundStyle(selectedTint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Liquid Stream Emergence")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(.white)
                                        Text("Phase: \(flow.phase.rawValue.uppercased())")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                    Spacer()
                                    Circle()
                                        .fill(flow.isHovering ? Color.orange : Color.green)
                                        .frame(width: 8, height: 8)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .frame(width: 280)
                            }
                            .frame(width: 600, height: 260)
                        } else {
                            // Step B Static Blob Canvas View
                            LiquidBlobCanvasView(
                                blobs: activeBlobs,
                                k: kSmoothing,
                                tintColor: selectedTint,
                                notchLipY: 32.0,
                                seed: seed,
                                time: time,
                                transparency: transparency,
                                bgLuminance: bgLuminance,
                                forceFallback: forceFallback
                            )
                            .frame(width: 600, height: 260)

                            // Content Guides
                            if showClusterGuides && preset != .manual {
                                ForEach(currentClusters, id: \.id) { c in
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.cyan.opacity(0.4), lineWidth: 1)
                                        .frame(width: c.size.width, height: c.size.height)
                                        .position(c.center)
                                }
                            }

                            // CPU Hit-Test Outline Overlay
                            if showHitTestOverlay {
                                LiquidBlobShape(blobs: activeBlobs, k: kSmoothing, seed: seed, time: time)
                                    .stroke(Color.yellow.opacity(0.65), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                                    .frame(width: 600, height: 260)
                            }

                            // Probe Mouse Indicator
                            Circle()
                                .fill(probeInside ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                                .position(probeLocation)
                        }
                    }
                    .frame(width: 600, height: 260)
                    .clipped()
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            probeLocation = loc
                            probeInside = LiquidBlobFieldEvaluator.evaluate(
                                point: loc,
                                blobs: activeBlobs,
                                k: kSmoothing,
                                seed: seed,
                                time: time
                            ) <= 0.0
                            probeDistance = LiquidBlobFieldEvaluator.evaluate(
                                point: loc,
                                blobs: activeBlobs,
                                k: kSmoothing,
                                seed: seed,
                                time: time
                            )
                        case .ended:
                            break
                        }
                    }

                    // Probe Readout Bar
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(probeInside ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(probeInside ? "Hit-Test: INSIDE LIQUID" : "Hit-Test: OUTSIDE (EMPTY SPACE)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(probeInside ? .green : .red)
                        }

                        Text("Distance: \(String(format: "%.1f", probeDistance)) pt")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("Active Lobes: \(activeBlobs.filter { $0.isActive }.count)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
                .padding()

                // Right: Controls & Sliders Panel
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if lifecycleInteractiveMode {
                            // Step C Interactive Flow Controls
                            VStack(alignment: .leading, spacing: 12) {
                                Text("FLOW LIFECYCLE (STEP C)")
                                    .font(.caption).bold().foregroundStyle(.secondary)

                                HStack {
                                    Text("Phase:")
                                        .font(.caption)
                                    Spacer()
                                    Text(flow.phase.rawValue.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(phaseColor(flow.phase).opacity(0.2))
                                        .foregroundStyle(phaseColor(flow.phase))
                                        .clipShape(Capsule())
                                }

                                Divider()

                                Button(action: {
                                    flow.emerge(
                                        activityId: "debug-test",
                                        clusters: currentClusters,
                                        dwellDuration: 4.0
                                    )
                                }) {
                                    Label("Emerge (Stream -> Swell)", systemImage: "arrow.down.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)

                                Button(action: {
                                    flow.drain()
                                }) {
                                    Label("Drain (Contract -> Absorb)", systemImage: "arrow.up.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)

                                Button(action: {
                                    if flow.phase == .drain || flow.phase == .absorb || flow.phase == .resting {
                                        flow.emerge(activityId: "debug-interrupt", clusters: currentClusters, dwellDuration: 4.0)
                                    } else {
                                        flow.drain()
                                    }
                                }) {
                                    Label("Interrupt Mid-Flow", systemImage: "bolt.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                Divider()

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("SPEED / SLOW-MO TUNING")
                                        .font(.caption).bold().foregroundStyle(.secondary)
                                    HStack(spacing: 6) {
                                        Button("1.0x") {
                                            motion.speedMultiplier = 1.0
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(motion.speedMultiplier == 1.0 ? .blue : .secondary)

                                        Button("0.5x") {
                                            motion.speedMultiplier = 0.5
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(motion.speedMultiplier == 0.5 ? .blue : .secondary)

                                        Button("0.25x (Slow)") {
                                            motion.speedMultiplier = 0.25
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(motion.speedMultiplier == 0.25 ? .blue : .secondary)
                                    }
                                }

                                Toggle("Force Reduce Motion", isOn: $motion.isReduceMotionForced)
                                    .font(.caption)

                                Divider()

                                Text("PHYSICS READOUTS")
                                    .font(.caption).bold().foregroundStyle(.secondary)
                                Group {
                                    readoutRow(label: "Emergence Progress", value: "\(Int(flow.emergenceProgress * 100))%")
                                    readoutRow(label: "Stream Thickness", value: String(format: "%.2f", flow.streamThickness))
                                    readoutRow(label: "Droplet Mass Scale", value: String(format: "%.2f", flow.massScale))
                                    readoutRow(label: "Content Alpha", value: String(format: "%.2f", flow.contentAlpha))
                                    readoutRow(label: "Absorption Ripple", value: String(format: "%.2f", flow.absorptionRipple))
                                    readoutRow(label: "Hover Pause Active", value: flow.isHovering ? "PAUSED" : "NO")
                                }
                            }
                        } else {
                            // Preset Picker
                            VStack(alignment: .leading, spacing: 4) {
                                Text("CONTENT PRESET")
                                    .font(.caption).bold().foregroundStyle(.secondary)
                                Picker("", selection: $preset) {
                                    ForEach(ContentPreset.allCases) { p in
                                        Text(p.rawValue).tag(p)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            Divider()

                            // Emergence Progress
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Emergence Progress")
                                    Spacer()
                                    Text("\(Int(emergenceProgress * 100))%")
                                }
                                .font(.caption)
                                Slider(value: $emergenceProgress, in: 0.0...1.0)
                            }

                            // Smoothing k
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Metaball Blend Smoothing (k)")
                                    Spacer()
                                    Text(String(format: "%.1f pt", kSmoothing))
                                }
                                .font(.caption)
                                Slider(value: $kSmoothing, in: 4.0...36.0)
                            }

                            // Background Brightness
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Background Luminance")
                                    Spacer()
                                    Text(bgLuminance > 0.6 ? "White Window" : (bgLuminance > 0.2 ? "Bright Wallpaper" : "Dark Window"))
                                }
                                .font(.caption)
                                Slider(value: $bgLuminance, in: 0.0...1.0)
                            }

                            // Transparency
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Liquid Transparency")
                                    Spacer()
                                    Text("\(Int(transparency * 100))%")
                                }
                                .font(.caption)
                                Slider(value: $transparency, in: 0.1...0.95)
                            }

                            Divider()

                            // Manual Sliders when in manual preset
                            if preset == .manual {
                                Text("MANUAL LOBE RADII")
                                    .font(.caption).bold().foregroundStyle(.secondary)

                                Stepper("Active Lobes: \(manualBlobCount)", value: $manualBlobCount, in: 1...4)
                                    .font(.caption)

                                VStack(spacing: 6) {
                                    sliderRow(label: "Stream Source (rx / ry)", val1: $blob0RadiusX, val2: $blob0RadiusY)
                                    sliderRow(label: "Stream Neck (rx / ry)", val1: $blob1RadiusX, val2: $blob1RadiusY)
                                    sliderRow(label: "Left Drop (rx / ry)", val1: $blob2RadiusX, val2: $blob2RadiusY)
                                    sliderRow(label: "Right Drop (rx / ry)", val1: $blob3RadiusX, val2: $blob3RadiusY)
                                }
                            }

                            Divider()

                            // Toggles
                            Toggle("Show CPU Hit-Test Outline (Yellow)", isOn: $showHitTestOverlay)
                            Toggle("Show Content Guides (Cyan)", isOn: $showClusterGuides)
                            Toggle("Force Canvas Fallback", isOn: $forceFallback)
                        }
                    }
                    .padding()
                }
                .frame(minWidth: 280, maxWidth: 340)
            }
        }
        .frame(minWidth: 920, minHeight: 460)
        .onAppear {
            startTimeTicker()
        }
    }

    private func sliderRow(label: String, val1: Binding<CGFloat>, val2: Binding<CGFloat>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Slider(value: val1, in: 10...120)
                Slider(value: val2, in: 8...80)
            }
        }
    }

    private func phaseColor(_ phase: LiquidFlowPhase) -> Color {
        switch phase {
        case .resting: return .gray
        case .stream: return .blue
        case .swell: return .cyan
        case .hold: return .green
        case .drain: return .orange
        case .absorb: return .purple
        }
    }

    private func readoutRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospaced()).bold()
        }
    }

    private func startTimeTicker() {
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            if isPlayingTime {
                time += 1.0 / 60.0
            }
        }
    }
}
