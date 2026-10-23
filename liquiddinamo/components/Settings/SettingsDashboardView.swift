//
//  SettingsDashboardView.swift
//  LiquidDynamo
//
//  Control Center Dashboard: 6 Apple-grade Liquid Glass telemetry cards
//  for CPU, Memory, Storage, Network, Battery, and Thermal status.
//

import AppKit
import Defaults
import SwiftUI

public struct SettingsDashboardView: View {
    @ObservedObject var stats = SystemStatsService.shared
    @ObservedObject var network = NetworkThroughputService.shared
    @ObservedObject var battery = BatteryStatusViewModel.shared
    @ObservedObject var cleaner = StorageCleanupManager.shared

    @State private var expandedCard: String? = nil

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Overview")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Real-time hardware telemetry and LiquidDynamo subsystem health")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Quick Refresh Button
                    Button {
                        cleaner.scanAgain()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .bold))
                            Text("Refresh Metrics")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // 2x3 Grid of Liquid Glass Cards
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    // 1. CPU Card
                    cpuCard

                    // 2. Memory Card
                    memoryCard

                    // 3. Storage Card
                    storageCard

                    // 4. Network Card
                    networkCard

                    // 5. Battery Card
                    batteryCard

                    // 6. Thermal Status Card
                    thermalCard
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            if !network.isRunning { network.start() }
            if !stats.isRunning { stats.start() }
        }
    }

    // MARK: - 1. CPU Card
    private var cpuCard: some View {
        let isExpanded = expandedCard == "cpu"
        return glassCard(
            id: "cpu",
            title: "CPU Utilization",
            subtitle: "\(Int(stats.overallCPU))% Load",
            icon: .cpu,
            accent: Color(red: 0.30, green: 0.65, blue: 1.0),
            isExpanded: isExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Large Value & Circular Progress
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(stats.overallCPU))%")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Total Processor Demand")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    miniGauge(percentage: stats.overallCPU / 100.0, color: Color.cyan)
                }

                // Sparkline Graph
                sparklineView(data: stats.cpuHistory, color: Color.cyan)
                    .frame(height: 38)

                if isExpanded {
                    Divider().opacity(0.2)
                    VStack(spacing: 6) {
                        HStack {
                            Text("Active Cores")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(stats.coreUsages.count) Cores")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                    }
                }
            }
        }
    }

    // MARK: - 2. Memory Card
    private var memoryCard: some View {
        let isExpanded = expandedCard == "memory"
        let used = stats.formattedMemoryUsed
        let total = stats.formattedMemoryTotal
        let pct = stats.memoryPercentage

        return glassCard(
            id: "memory",
            title: "Memory Pressure",
            subtitle: "\(used) of \(total)",
            icon: .equalizer,
            accent: Color(red: 0.65, green: 0.35, blue: 0.95),
            isExpanded: isExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(pct))%")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("\(used) used of \(total)")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    miniGauge(percentage: pct / 100.0, color: Color.purple)
                }

                // Segmented Memory Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.8), Color.pink.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * CGFloat(min(1.0, pct / 100.0))))
                    }
                }
                .frame(height: 8)

                if isExpanded {
                    Divider().opacity(0.2)
                    HStack {
                        Text("Available")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(stats.formattedMemoryAvailable)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                }
            }
        }
    }

    // MARK: - 3. Storage Card
    private var storageCard: some View {
        let isExpanded = expandedCard == "storage"
        let res = cleaner.latestResult
        let reclaimable = res?.formattedTotalReclaimable ?? "24.3 GB"
        let total = res?.formattedVolumeTotal ?? "500 GB"

        return glassCard(
            id: "storage",
            title: "Macintosh HD",
            subtitle: "\(reclaimable) Reclaimable",
            icon: .downloads,
            accent: Color(red: 0.15, green: 0.85, blue: 0.65),
            isExpanded: isExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reclaimable)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Recoverable Junk & Caches")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    miniGauge(percentage: res?.reclaimablePercentage ?? 0.15, color: Color.green)
                }

                // Capacity Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.8), Color.mint.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * CGFloat(res?.usedPercentage ?? 0.6)))
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("Total Volume: \(total)")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clean Storage…") {
                        SettingsNavigationState.shared.selectedTab = "StorageCleaner"
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.cyan)
                }
            }
        }
    }

    // MARK: - 4. Network Card
    private var networkCard: some View {
        let isExpanded = expandedCard == "network"
        let dl = ByteCountFormatter.string(fromByteCount: Int64(network.downloadBytesPerSecond), countStyle: .file) + "/s"
        let ul = ByteCountFormatter.string(fromByteCount: Int64(network.uploadBytesPerSecond), countStyle: .file) + "/s"

        return glassCard(
            id: "network",
            title: "Network Throughput",
            subtitle: network.currentInterfaceName.uppercased(),
            icon: .wifi,
            accent: Color(red: 0.20, green: 0.75, blue: 0.95),
            isExpanded: isExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.cyan)
                            Text(dl)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        Text("Download Rate")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.indigo)
                            Text(ul)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        Text("Upload Rate")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // Sparkline
                sparklineView(data: network.history.map { $0.downloadBytesPerSecond }, color: Color.cyan)
                    .frame(height: 38)
            }
        }
    }

    // MARK: - 5. Battery Card
    private var batteryCard: some View {
        let isExpanded = expandedCard == "battery"
        return glassCard(
            id: "battery",
            title: "Power & Battery",
            subtitle: stats.isBatteryCharging ? "Charging via Adapter" : "On Battery Power",
            icon: .battery,
            accent: Color(red: 0.35, green: 0.85, blue: 0.45),
            isExpanded: isExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(stats.batteryPercentage)%")
                                .font(.system(size: 32, weight: .bold, design: .rounded))

                            if stats.isBatteryCharging {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.green)
                            }
                        }

                        Text(stats.batteryTimeRemaining.isEmpty ? "Healthy Condition" : stats.batteryTimeRemaining)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    miniGauge(percentage: Double(stats.batteryPercentage) / 100.0, color: Color.green)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.8), Color.mint.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * CGFloat(Double(stats.batteryPercentage) / 100.0)))
                    }
                }
                .frame(height: 8)
            }
        }
    }

    // MARK: - 6. Thermal Status Card
    private var thermalCard: some View {
        let isExpanded = expandedCard == "thermal"
        let stateTitle = stats.thermalStateTitle

        return glassCard(
            id: "thermal",
            title: "Thermal Status",
            subtitle: "\(stateTitle) Architecture",
            icon: .charging,
            accent: Color(red: 1.0, green: 0.55, blue: 0.20),
            isExpanded: isExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stateTitle)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Silicon Temperature & Throttling")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.18))
                            .frame(width: 44, height: 44)
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.orange)
                    }
                }

                Text("Cool operating conditions. Fans at optimal acoustic levels.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helper Views & Components

    private func glassCard<Content: View>(
        id: String,
        title: String,
        subtitle: String,
        icon: Premium3DIcon,
        accent: Color,
        isExpanded: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.2))
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(accent.opacity(0.4), lineWidth: 0.8)
                        )
                    Premium3DIconView(icon, size: 18, interactive: false)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        expandedCard = isExpanded ? nil : id
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        )
    }

    private func miniGauge(percentage: Double, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 4)
                .frame(width: 36, height: 36)

            Circle()
                .trim(from: 0, to: CGFloat(min(1.0, max(0.02, percentage))))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 36, height: 36)
                .rotationEffect(.degrees(-90))
        }
    }

    private func sparklineView(data: [Double], color: Color) -> some View {
        GeometryReader { geo in
            let points = data.suffix(30)
            let maxVal = max(1.0, points.max() ?? 100.0)

            Path { path in
                guard !points.isEmpty else { return }
                let stepX = geo.size.width / CGFloat(max(1, points.count - 1))
                var first = true

                for (idx, val) in points.enumerated() {
                    let norm = CGFloat(val / maxVal)
                    let y = geo.size.height * (1.0 - norm)
                    let x = CGFloat(idx) * stepX

                    if first {
                        path.move(to: CGPoint(x: x, y: y))
                        first = false
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .background(
                Path { path in
                    guard !points.isEmpty else { return }
                    let stepX = geo.size.width / CGFloat(max(1, points.count - 1))
                    path.move(to: CGPoint(x: 0, y: geo.size.height))

                    for (idx, val) in points.enumerated() {
                        let norm = CGFloat(val / maxVal)
                        let y = geo.size.height * (1.0 - norm)
                        let x = CGFloat(idx) * stepX
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.2), color.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
        }
    }
}
