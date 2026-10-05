//
//  SystemStatsView.swift
//  boringNotch
//
//  Created for Boring Notch
//

import SwiftUI

struct SystemStatsView: View {
    @ObservedObject var statsService = SystemStatsService.shared

    var body: some View {
        HStack(spacing: 12) {
            // Left Card: Overall CPU & Sparkline
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("CPU LOAD")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f%%", statsService.overallCPU))
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(cpuColor(for: statsService.overallCPU))
                    }
                    Spacer()
                    // Core count badge
                    Text("\(statsService.coreUsages.count) CORES")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                        .foregroundStyle(.secondary)
                }

                // Sparkline graph
                SparklineCanvas(data: statsService.cpuHistory)
                    .frame(height: 52)
                    .padding(.vertical, 2)
            }
            .padding(12)
            .liquidGlassCard(cornerRadius: 20)
            .frame(maxWidth: .infinity)

            // Right Card: Per-Core Bars & Memory Progress
            VStack(alignment: .leading, spacing: 8) {
                // Per-Core Bars Row
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("PER-CORE ACTIVITY")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    if statsService.coreUsages.isEmpty {
                        Text("Sampling cores…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(height: 34)
                    } else {
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(Array(statsService.coreUsages.enumerated()), id: \.offset) { index, usage in
                                VStack(spacing: 2) {
                                    GeometryReader { geo in
                                        VStack {
                                            Spacer(minLength: 0)
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(cpuColor(for: usage))
                                                .frame(height: max(2, geo.size.height * CGFloat(usage / 100.0)))
                                        }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: 30)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 2))

                                    Text("\(index + 1)")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(height: 42)
                    }
                }

                // Memory Bar
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("MEMORY")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(statsService.formattedMemoryUsed) / \(statsService.formattedMemoryTotal) (\(Int(statsService.memoryPercentage))%)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [.cyan, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, geo.size.width * CGFloat(statsService.memoryPercentage / 100.0)), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
            .padding(12)
            .liquidGlassCard(cornerRadius: 20)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .onAppear {
            statsService.start()
        }
        .onDisappear {
            statsService.stop()
        }
    }

    private func cpuColor(for usage: Double) -> Color {
        if usage < 50 {
            return .cyan
        } else if usage < 80 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Sparkline Canvas

struct SparklineCanvas: View {
    let data: [Double]

    var body: some View {
        Canvas { context, size in
            guard data.count > 1 else { return }

            let width = size.width
            let height = size.height
            let stepX = width / CGFloat(max(data.count - 1, 1))

            var path = Path()
            let firstY = height - (CGFloat(min(max(data[0], 0), 100) / 100.0) * height)
            path.move(to: CGPoint(x: 0, y: firstY))

            for i in 1..<data.count {
                let x = CGFloat(i) * stepX
                let normalizedVal = CGFloat(min(max(data[i], 0), 100) / 100.0)
                let y = height - (normalizedVal * height)
                path.addLine(to: CGPoint(x: x, y: y))
            }

            // Fill area under sparkline
            var fillPath = path
            fillPath.addLine(to: CGPoint(x: CGFloat(data.count - 1) * stepX, y: height))
            fillPath.addLine(to: CGPoint(x: 0, y: height))
            fillPath.closeSubpath()

            context.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: [Color.cyan.opacity(0.35), Color.cyan.opacity(0.0)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: height)
                )
            )

            // Draw line stroke
            context.stroke(
                path,
                with: .color(.cyan),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
