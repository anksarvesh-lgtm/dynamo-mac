//
//  SpeedTestView.swift
//  boringNotch
//
//  Created for Boring Notch
//

import Charts
import SwiftUI

/// On-demand Speed Test View featuring Apple's built-in `networkQuality`.
///
/// Principles:
/// - Never starts automatically: User must explicitly click "Run speed test".
/// - Explanatory warning: Informs the user that it utilizes full connection bandwidth and reaches Apple's servers.
/// - Live execution & cancellation: Progress indicator with an instant "Cancel" button.
/// - Sandbox notification: Explicitly surfaces App Sandbox execution restrictions and proposes architectural options.
/// - History: Displays up to 20 recorded results with visual metrics, a mini chart, and "Clear history".
public struct SpeedTestView: View {
    @ObservedObject private var service = SpeedTestService.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
            explanationNotice
            actionControls
            sandboxWarningSection
            resultsSection
            historySection
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 20, tint: .cyan)
    }

    // MARK: - Subsections

    private var headerSection: some View {
        HStack {
            HStack(spacing: 6) {
                Premium3DIconView(.equalizer, size: 14)
                Text("SPEED TEST")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
        }
    }

    private var explanationNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Running a speed test uses the whole connection for a short time and contacts Apple's servers.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var actionControls: some View {
        HStack(spacing: 10) {
            if service.isRunning {
                Button(role: .cancel) {
                    service.cancelTest()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Cancel Test")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.red.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Testing capacity...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    service.startTest()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Run speed test")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                if let iface = ConnectionStatusService.shared.primaryInterfaceName {
                    Text("Interface: \(iface)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var sandboxWarningSection: some View {
        switch service.state {
        case .sandboxBlocked(let message, let options):
            sandboxWarningView(message: message, options: options)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if let result = service.currentResult {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    MetricCard(
                        title: "DOWNLOAD",
                        value: String(format: "%.1f", result.downloadMbps),
                        unit: "Mbps",
                        systemImage: "arrow.down.circle.fill",
                        tintColor: .green
                    )
                    MetricCard(
                        title: "UPLOAD",
                        value: String(format: "%.1f", result.uploadMbps),
                        unit: "Mbps",
                        systemImage: "arrow.up.circle.fill",
                        tintColor: .purple
                    )
                }

                HStack(spacing: 8) {
                    MetricCard(
                        title: "RESPONSIVENESS",
                        value: String(format: "%.0f", result.responsivenessRPM),
                        unit: "RPM (\(result.responsivenessRating))",
                        systemImage: "gauge.medium",
                        tintColor: .blue
                    )
                    MetricCard(
                        title: "IDLE LATENCY",
                        value: String(format: "%.1f", result.idleLatencyMs),
                        unit: "ms",
                        systemImage: "timer",
                        tintColor: .orange
                    )
                }

                HStack {
                    if let endpoint = result.serverEndpoint {
                        Label(endpoint, systemImage: "server.rack")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(result.interfaceName) • \(result.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !service.history.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                    .overlay(Color.white.opacity(0.08))

                HStack {
                    Label("HISTORY (\(service.history.count)/20)", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        service.clearHistory()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Clear history")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }

                if service.history.count >= 2 {
                    historyMiniChart
                        .frame(height: 65)
                        .padding(.vertical, 4)
                }

                VStack(spacing: 6) {
                    ForEach(service.history.prefix(5)) { item in
                        historyRow(item)
                    }
                }
            }
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        switch service.state {
        case .idle:
            Text("READY")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        case .running:
            HStack(spacing: 4) {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
                Text("TESTING")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
            }
        case .completed:
            Text("COMPLETED")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.green)
        case .cancelled:
            Text("CANCELLED")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        case .failed:
            Text("FAILED")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
        case .sandboxBlocked:
            Text("SANDBOX RESTRICTED")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.yellow)
        }
    }

    // MARK: - Sandbox Alert View

    private func sandboxWarningView(message: String, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.yellow)
                Text("Tool Execution Blocked by App Sandbox")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Available Architectural Options:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))

                ForEach(options, id: \.self) { opt in
                    HStack(alignment: .top, spacing: 4) {
                        Text("•")
                            .foregroundStyle(.yellow)
                        Text(opt)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Notice: In accordance with privacy rules, no third-party speed test servers are used as fallback.")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.8))
                .italic()
        }
        .padding(10)
        .background(Color.yellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Mini History Chart

    private var historyMiniChart: some View {
        let reversedHistory = Array(service.history.prefix(10).reversed())
        return Chart {
            ForEach(Array(reversedHistory.enumerated()), id: \.offset) { index, item in
                BarMark(
                    x: .value("Index", "\(index + 1)"),
                    y: .value("Download (Mbps)", item.downloadMbps)
                )
                .foregroundStyle(Color.green.gradient)

                BarMark(
                    x: .value("Index", "\(index + 1)"),
                    y: .value("Upload (Mbps)", item.uploadMbps)
                )
                .foregroundStyle(Color.purple.opacity(0.7).gradient)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    .foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let intVal = value.as(Int.self) {
                        Text("\(intVal)M")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - History Row

    private func historyRow(_ item: SpeedTestResult) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.date.formatted(date: .numeric, time: .shortened))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
                Text(item.interfaceName)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)
                    Text("\(String(format: "%.1f", item.downloadMbps))M")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }

                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.purple)
                    Text("\(String(format: "%.1f", item.uploadMbps))M")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }

                Text("\(String(format: "%.0f", item.responsivenessRPM)) RPM")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Metric Card Component

private struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Premium3DIconView(name: systemImage, size: 14)
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}
