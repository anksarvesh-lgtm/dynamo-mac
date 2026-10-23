//
//  WaterPhysicsDebugView.swift
//  LiquidDynamo
//
//  Step A: Interactive Debug Inspector for the closed-loop water physics model.
//  Features draggable fake content rectangle, sliders for gravity, pressure stiffness,
//  surface tension, damping, point count, time step, slow-motion control, and
//  an overlay of points, normals, and force vectors.
//

import AppKit
import Combine
import Foundation
import SwiftUI

public struct WaterPhysicsDebugView: View {
    @ObservedObject private var sim = WaterPhysicsSimulation.shared

    @State private var showPoints: Bool = true
    @State private var showForces: Bool = true
    @State private var showNormals: Bool = false
    @State private var showContentRect: Bool = true
    @State private var showNotchExclusion: Bool = true

    // Quick size buttons
    public enum TestContentSize: String, CaseIterable, Identifiable {
        case small = "Small (120x30)"
        case medium = "Medium (240x60)"
        case large = "Large (400x120)"

        public var id: String { rawValue }

        public var size: CGSize {
            switch self {
            case .small: return CGSize(width: 120, height: 30)
            case .medium: return CGSize(width: 240, height: 60)
            case .large: return CGSize(width: 400, height: 120)
            }
        }
    }

    @State private var selectedSize: TestContentSize = .medium
    @State private var timerSubscription: AnyCancellable? = nil
    @State private var lastFrameTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()

    // Benchmark outputs for Step A reporting
    @State private var benchmarkReport: String = "Click 'Run Benchmark' to measure settling times across sizes."
    @State private var isBenchmarking: Bool = false

    public init() {}

    public var body: some View {
        HSplitView {
            // MARK: - Left: Interactive Simulation Canvas
            ZStack(alignment: .topLeading) {
                // Background & Grid
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()

                CanvasGridBackground()

                // Notch lip reference line and physical notch blocked zone
                if showNotchExclusion {
                    Rectangle()
                        .fill(Color.black.opacity(0.85))
                        .frame(width: sim.notchWidth, height: sim.notchLipY)
                        .position(x: sim.canvasSize.width * 0.5, y: sim.notchLipY * 0.5)
                        .overlay {
                            VStack(spacing: 2) {
                                Text("PHYSICAL NOTCH")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.7))
                                Text("CLEARANCE ZONE (0 points)")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.red.opacity(0.8))
                            }
                            .position(x: sim.canvasSize.width * 0.5, y: sim.notchLipY * 0.5)
                        }

                    // Notch lip boundary line
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: sim.notchLipY))
                        p.addLine(to: CGPoint(x: sim.canvasSize.width, y: sim.notchLipY))
                    }
                    .stroke(Color.red.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                // Rendered Water Body
                sim.currentPath
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.72, blue: 0.52).opacity(0.45),
                                Color(red: 0.02, green: 0.50, blue: 0.38).opacity(0.65)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                sim.currentPath
                    .stroke(
                        Color(red: 0.10, green: 0.90, blue: 0.65),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )

                // Draggable Fake Content Rectangle
                if showContentRect {
                    draggableContentRectangle
                }

                // Overlays: Force vectors, Normals, and Particles
                overlaysView
            }
            .frame(minWidth: 540, minHeight: 460)
            .clipped()
            .onAppear {
                startSimulationLoop()
            }
            .onDisappear {
                timerSubscription?.cancel()
            }
            .onTapGesture { location in
                sim.sendRipple(at: location, impulse: 7.0)
            }

            // MARK: - Right: Controls & Metrics Panel
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerSection
                    Divider()
                    metricsSection
                    Divider()
                    presetsAndSizesSection
                    Divider()
                    slidersSection
                    Divider()
                    overlayTogglesSection
                    Divider()
                    benchmarkSection
                }
                .padding(14)
            }
            .frame(width: 380)
        }
        .frame(minWidth: 940, minHeight: 520)
    }

    // MARK: - Simulation Frame Loop

    private func startSimulationLoop() {
        timerSubscription = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                let now = CFAbsoluteTimeGetCurrent()
                let dt = min(now - lastFrameTime, 0.05)
                lastFrameTime = now
                sim.step(deltaTime: dt)
            }
    }

    // MARK: - Draggable Content Rectangle

    private var draggableContentRectangle: some View {
        let rect = sim.contentRect
        return ZStack {
            // Dotted boundary box
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.3))
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // Safe padding halo
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.yellow.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: rect.width + sim.contentPadding * 2, height: rect.height + sim.contentPadding * 2)
                .position(x: rect.midX, y: rect.midY)

            // Content label & Drag handle
            VStack(spacing: 3) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.yellow)
                Text("Fake Content (\(Int(rect.width)) × \(Int(rect.height)))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Drag to test real-time fluid slosh")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .position(x: rect.midX, y: rect.midY)
        }
        .opacity(sim.contentAlpha)
        .gesture(
            DragGesture()
                .onChanged { val in
                    sim.isInteracting = true
                    var newX = val.location.x
                    var newY = val.location.y
                    // Clamp inside canvas and below notch lip
                    newX = max(rect.width * 0.5 + 20, min(sim.canvasSize.width - rect.width * 0.5 - 20, newX))
                    newY = max(sim.notchLipY + rect.height * 0.5 + 10, min(sim.canvasSize.height - rect.height * 0.5 - 20, newY))
                    sim.contentRect = CGRect(
                        x: newX - rect.width * 0.5,
                        y: newY - rect.height * 0.5,
                        width: rect.width,
                        height: rect.height
                    )
                }
                .onEnded { _ in
                    sim.isInteracting = false
                }
        )
    }

    // MARK: - Overlays: Points, Forces, Normals

    private var overlaysView: some View {
        Canvas { context, size in
            let particles = sim.particles

            // 1. Draw Force Vectors
            if showForces {
                for p in particles {
                    guard !p.isPinned else { continue }
                    let start = p.position
                    let forceScale: CGFloat = 0.015
                    let end = CGPoint(
                        x: start.x + p.acceleration.x * forceScale,
                        y: start.y + p.acceleration.y * forceScale
                    )
                    var line = Path()
                    line.move(to: start)
                    line.addLine(to: end)
                    context.stroke(line, with: .color(.orange.opacity(0.7)), lineWidth: 1.0)
                }
            }

            // 2. Draw Normals
            if showNormals {
                for p in particles {
                    let start = p.position
                    let end = CGPoint(
                        x: start.x + p.normal.x * 12.0,
                        y: start.y + p.normal.y * 12.0
                    )
                    var line = Path()
                    line.move(to: start)
                    line.addLine(to: end)
                    context.stroke(line, with: .color(.cyan.opacity(0.6)), lineWidth: 1.0)
                }
            }

            // 3. Draw Boundary Points
            if showPoints {
                for (idx, p) in particles.enumerated() {
                    let rect = CGRect(x: p.position.x - 2.5, y: p.position.y - 2.5, width: 5.0, height: 5.0)
                    if p.isPinned {
                        context.fill(Path(ellipseIn: rect), with: .color(.red))
                    } else if idx % 4 == 0 {
                        context.fill(Path(ellipseIn: rect), with: .color(.white))
                    } else {
                        context.fill(Path(ellipseIn: rect), with: .color(.green.opacity(0.8)))
                    }
                }
            }
        }
    }

    // MARK: - Right Controls Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Water Physics Engine Inspector")
                .font(.headline)
            Text("Verlet integration closed-loop volume model (Step A)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Diagnostics & Live Settling")
                    .font(.caption.bold())
                Spacer()
                Text(sim.metrics.isSleeping ? "💤 SLEEPING (0% CPU)" : "🌊 SIMULATING")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(sim.metrics.isSleeping ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                    .foregroundStyle(sim.metrics.isSleeping ? .blue : .green)
                    .clipShape(Capsule())
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Lifecycle Phase:")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text(sim.lifecycleState.rawValue)
                            .fontWeight(.semibold)
                            .foregroundStyle(lifecycleColor(sim.lifecycleState))
                        Text("(\(Int(sim.flowProgress * 100))%)")
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("Content Alpha:")
                        .foregroundStyle(.secondary)
                    Text("\(Int(sim.contentAlpha * 100))%")
                        .fontWeight(.semibold)
                }
                GridRow {
                    Text("Settling Time:")
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.3f", sim.metrics.settlingTimeSeconds)) s")
                        .fontWeight(.semibold)
                }
                GridRow {
                    Text("Overshoot:")
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", sim.metrics.overshootPercentage)) %")
                        .fontWeight(.semibold)
                        .foregroundStyle(sim.metrics.overshootPercentage <= 12.0 ? .green : .orange)
                }
                GridRow {
                    Text("Enclosed Area:")
                        .foregroundStyle(.secondary)
                    Text("\(Int(sim.metrics.currentArea)) pt² (Target: \(Int(sim.metrics.targetArea)))")
                }
                GridRow {
                    Text("Kinetic Energy:")
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.4f", sim.metrics.kineticEnergy))")
                }
                GridRow {
                    Text("Oscillations:")
                        .foregroundStyle(.secondary)
                    Text("\(sim.metrics.oscillationCount) zero crossings")
                }
            }
            .font(.caption)
        }
    }

    private var presetsAndSizesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lifecycle & Flow Controls (Step C)")
                .font(.caption.bold())

            HStack(spacing: 8) {
                Button("Open (Source)") {
                    sim.open()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)

                Button("Close (Drain)") {
                    sim.close()
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.small)

                Button("Toggle") {
                    sim.toggleLifecycle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                Button("Test Interrupt (Mid-Flow)") {
                    if sim.lifecycleState == .closed {
                        sim.open()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            sim.close()
                        }
                    } else {
                        sim.close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            sim.open()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Toggle("Auto Sync", isOn: $sim.autoLifecycleObserver)
                    .font(.caption2)
            }

            Divider()

            Text("Physics Presets")
                .font(.caption.bold())

            Picker("Preset", selection: $sim.preset) {
                ForEach(WaterPhysicsPreset.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)

            Text(sim.preset.description)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Text("Target Content Size Quick-Picks")
                .font(.caption.bold())

            HStack(spacing: 8) {
                ForEach(TestContentSize.allCases) { sizePreset in
                    Button(sizePreset.rawValue) {
                        selectedSize = sizePreset
                        resizeContent(to: sizePreset.size)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Slow Motion Multiplier
            HStack {
                Text("Speed Multiplier:")
                    .font(.caption)
                Spacer()
                Picker("", selection: $sim.speedMultiplier) {
                    Text("1.0x").tag(CGFloat(1.0))
                    Text("0.5x (2x slow)").tag(CGFloat(0.5))
                    Text("0.25x (4x slow)").tag(CGFloat(0.25))
                    Text("0.1x (10x slow)").tag(CGFloat(0.1))
                }
                .labelsHidden()
                .controlSize(.small)
            }
        }
    }

    private var slidersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Verlet Physics Sliders")
                .font(.caption.bold())

            sliderRow(title: "Gravity", value: $sim.gravity, in: 50...800, format: "%.0f")
            sliderRow(title: "Pressure Stiffness", value: $sim.pressureStiffness, in: 400...3500, format: "%.0f")
            sliderRow(title: "Surface Tension", value: $sim.surfaceTension, in: 50...1000, format: "%.0f")
            sliderRow(title: "Damping", value: $sim.damping, in: 0.005...0.25, format: "%.3f")
            sliderRow(title: "Boundary Springs", value: $sim.springStiffness, in: 100...1500, format: "%.0f")

            HStack {
                Text("Point Count (\(sim.pointCount)):")
                    .font(.caption)
                Spacer()
                Stepper("", value: $sim.pointCount, in: 64...96, step: 4)
                    .labelsHidden()
            }

            HStack {
                Text("Time Step (\(Int(1.0 / sim.timeStep)) Hz):")
                    .font(.caption)
                Spacer()
                Picker("", selection: $sim.timeStep) {
                    Text("1/120 s").tag(CGFloat(1.0 / 120.0))
                    Text("1/240 s (Default)").tag(CGFloat(1.0 / 240.0))
                    Text("1/480 s").tag(CGFloat(1.0 / 480.0))
                }
                .labelsHidden()
                .controlSize(.small)
            }
        }
    }

    private var overlayTogglesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Inspection Overlays")
                .font(.caption.bold())

            Toggle("Show Boundary Particles", isOn: $showPoints)
            Toggle("Show Force Vectors", isOn: $showForces)
            Toggle("Show Surface Normals", isOn: $showNormals)
            Toggle("Show Content Rectangle & Halo", isOn: $showContentRect)
            Toggle("Show Physical Notch Exclusion Line", isOn: $showNotchExclusion)
            Toggle("Enable Cursor Push & Ripples", isOn: $sim.cursorPushEnabled)
        }
        .font(.caption)
    }

    private var benchmarkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Step A Automated Benchmark")
                    .font(.caption.bold())
                Spacer()
                Button(isBenchmarking ? "Running..." : "Run Benchmark") {
                    runBenchmarkSuite()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isBenchmarking)
            }

            Text(benchmarkReport)
                .font(.system(size: 10, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sliderRow(title: String, value: Binding<CGFloat>, in range: ClosedRange<CGFloat>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func resizeContent(to size: CGSize) {
        let topY = max(sim.notchLipY + 8.0, sim.contentRect.minY)
        let center = CGPoint(x: sim.contentRect.midX, y: topY + size.height * 0.5)
        sim.contentRect = CGRect(
            x: center.x - size.width * 0.5,
            y: center.y - size.height * 0.5,
            width: size.width,
            height: size.height
        )
    }

    private func runBenchmarkSuite() {
        isBenchmarking = true
        benchmarkReport = "Benchmarking Small, Medium, Large sizes..."

        Task {
            var lines: [String] = []

            // Test 1: Small (120x30)
            await MainActor.run {
                resizeContent(to: CGSize(width: 120, height: 30))
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            let smallSettling = sim.metrics.settlingTimeSeconds
            let smallOvershoot = sim.metrics.overshootPercentage
            lines.append("Small (120x30): Settled in \(String(format: "%.3f", smallSettling))s, Overshoot: \(String(format: "%.1f", smallOvershoot))%")

            // Test 2: Medium (240x60)
            await MainActor.run {
                resizeContent(to: CGSize(width: 240, height: 60))
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            let medSettling = sim.metrics.settlingTimeSeconds
            let medOvershoot = sim.metrics.overshootPercentage
            lines.append("Medium (240x60): Settled in \(String(format: "%.3f", medSettling))s, Overshoot: \(String(format: "%.1f", medOvershoot))%")

            // Test 3: Large (400x120)
            await MainActor.run {
                resizeContent(to: CGSize(width: 400, height: 120))
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            let largeSettling = sim.metrics.settlingTimeSeconds
            let largeOvershoot = sim.metrics.overshootPercentage
            lines.append("Large (400x120): Settled in \(String(format: "%.3f", largeSettling))s, Overshoot: \(String(format: "%.1f", largeOvershoot))%")

            await MainActor.run {
                benchmarkReport = lines.joined(separator: "\n")
                isBenchmarking = false
            }
        }
    }

    private func lifecycleColor(_ state: WaterLifecycleState) -> Color {
        switch state {
        case .open: return .green
        case .opening: return .blue
        case .closing: return .orange
        case .closed: return .gray
        }
    }
}

// MARK: - Canvas Grid Background

private struct CanvasGridBackground: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 20.0
            var grid = Path()
            var x: CGFloat = 0
            while x < size.width {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(grid, with: .color(.primary.opacity(0.04)), lineWidth: 0.5)
        }
    }
}
