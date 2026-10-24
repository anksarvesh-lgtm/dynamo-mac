//
//  PlexoNetworkCardView.swift
//  LiquidDynamo
//
//  Compact dashboard card embedded inside NetworkTabView.
//  Displays real-time multi-network bonding status, combined download throughput,
//  and one-click launcher for Plexo Multi-Network Downloader.
//

import AppKit
import SwiftUI

public struct PlexoNetworkCardView: View {
    @ObservedObject private var netManager = PlexoNetworkManager.shared
    @ObservedObject private var engine = PlexoDownloadEngine.shared
    @ObservedObject private var coordinator = LiquidViewCoordinator.shared
    @ObservedObject private var island = IslandController.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Title & Combined Speed
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 24, height: 24)
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Plexo Multi-Network Accelerator")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("\(netManager.enabledInterfaces.count) Connections Combined")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Total Speed Readout
                HStack(spacing: 4) {
                    Circle()
                        .fill(netManager.totalDownloadSpeed > 1024 ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(PlexoFormatting.formatSpeed(netManager.totalDownloadSpeed))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            }

            // Active Adapter Chips
            HStack(spacing: 6) {
                ForEach(netManager.interfaces) { iface in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(iface.isOnline ? iface.color : Color.gray.opacity(0.6))
                            .frame(width: 6, height: 6)
                        Text(iface.effectiveName)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(iface.isOnline && iface.isEnabled ? .primary : .secondary)
                        if iface.isOnline {
                            Text(PlexoFormatting.formatSpeed(iface.downloadSpeed))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(iface.color)
                        } else {
                            Text("Ready")
                                .font(.system(size: 8.5, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(iface.isOnline && iface.isEnabled ? 0.06 : 0.02))
                    .clipShape(Capsule())
                }
            }

            Divider()
                .background(Color.white.opacity(0.08))

            // Footer: Download Status & Open Button
            HStack(alignment: .center) {
                if let active = engine.activeTasks.first(where: { $0.state == .downloading }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.cyan)
                        Text("\(active.fileName): \(active.formattedSpeed)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                } else {
                    Text("\(engine.activeTasks.count) active, \(engine.completedTasks.count) completed downloads")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    island.setExpanded(view: .plexo, pin: true)
                } label: {
                    HStack(spacing: 4) {
                        Text("Open Plexo Downloader")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.15))
                    .foregroundStyle(Color.cyan)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 18, tint: .cyan)
    }
}
