//
//  PowerloadNetworkCardView.swift
//  LiquidDynamo
//
//  Compact dashboard card embedded inside NetworkTabView.
//  Displays real-time multi-network bonding status, combined download throughput,
//  and one-click launcher for Powerload Multi-Network Downloader.
//  Rebranded and extended from Plexo (https://github.com/anmolkapil/plexo).
//

import AppKit
import SwiftUI

public struct PowerloadNetworkCardView: View {
    @ObservedObject private var netManager = PowerloadNetworkManager.shared
    @ObservedObject private var engine = PowerloadDownloadEngine.shared
    @ObservedObject private var coordinator = LiquidViewCoordinator.shared
    @ObservedObject private var island = IslandController.shared

    public init() {}

    private var activeCount: Int {
        netManager.interfaces.filter { $0.isEnabled && $0.isOnline }.count
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Title & Combined Speed
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 26, height: 26)
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("Powerload Multi-Network Accelerator")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        if activeCount > 1 {
                            Text("BONDING ACTIVE")
                                .font(.system(size: 8, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.green.opacity(0.2))
                                .foregroundStyle(Color.green)
                                .clipShape(Capsule())
                        }
                    }

                    if activeCount > 1 {
                        Text("\(activeCount) Connections Combined for Maximum Speed")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else if activeCount == 1 {
                        Text("1 Active Connection • Plug in Ethernet or USB iPhone to Bond")
                            .font(.system(size: 9.5, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No active connections available")
                            .font(.system(size: 9.5, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Total Speed Readout
                HStack(spacing: 4) {
                    Circle()
                        .fill(netManager.totalDownloadSpeed > 1024 ? Color.green : (activeCount > 0 ? Color.cyan : Color.gray))
                        .frame(width: 6, height: 6)
                    Text(PowerloadFormatting.formatSpeed(netManager.totalDownloadSpeed))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            }

            // Horizontally Scrollable Active / Available Adapter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(netManager.interfaces) { iface in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(iface.hasIP ? iface.color : (iface.isLinkActive ? Color.orange : Color.gray.opacity(0.45)))
                                .frame(width: 6, height: 6)

                            Image(systemName: iface.kind.iconName)
                                .font(.system(size: 10))
                                .foregroundStyle(iface.isOnline ? iface.color : .secondary)

                            Text(iface.effectiveName)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(iface.isOnline && iface.isEnabled ? .primary : .secondary)

                            if iface.isOnline && iface.downloadSpeed > 1024 {
                                Text(PowerloadFormatting.formatSpeed(iface.downloadSpeed))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(iface.color)
                            } else if iface.hasIP {
                                Text(iface.ipAddress ?? "Active")
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            } else if iface.isLinkActive {
                                Text("Link Up")
                                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.orange)
                            } else {
                                Text("Available")
                                    .font(.system(size: 8.5, design: .rounded))
                                    .foregroundStyle(.secondary.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4.5)
                        .background(Color.white.opacity(iface.isOnline && iface.isEnabled ? 0.08 : 0.03))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(iface.isOnline ? iface.color.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                    }
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
                    HStack(spacing: 5) {
                        Image(systemName: "network")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Multi-stream acceleration ready")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    openPowerloadDownloader()
                } label: {
                    HStack(spacing: 4) {
                        Text("Open Powerload")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 9))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(LinearGradient(colors: [Color.cyan.opacity(0.25), Color.blue.opacity(0.25)], startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(Color.cyan)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 18, tint: .cyan)
    }

    private func openPowerloadDownloader() {
        coordinator.currentView = .powerload
        IslandController.shared.setExpanded(view: .powerload, pin: true)
    }
}

// MARK: - Backward Compatibility Typealias
public typealias PlexoNetworkCardView = PowerloadNetworkCardView
