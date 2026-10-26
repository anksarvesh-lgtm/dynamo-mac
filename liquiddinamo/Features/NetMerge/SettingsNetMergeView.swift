//
//  SettingsNetMergeView.swift
//  LiquidDynamo
//
//  Preferences and configuration view for NetMerge Multi-Network Link Bonding.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import Defaults
import SwiftUI

public struct SettingsNetMergeView: View {
    @ObservedObject private var engine = NetMergeEngine.shared

    @Default(.netMergeEnabled) var netMergeEnabled
    @Default(.netMergeAutoStart) var netMergeAutoStart
    @Default(.netMergeSocksPort) var netMergeSocksPort
    @Default(.netMergeIPv6Mode) var netMergeIPv6Mode
    @Default(.netMergeShowNotchWidget) var netMergeShowNotchWidget
    @Default(.powerloadUseNetMergeEngine) var powerloadUseNetMergeEngine

    @State private var copiedProxyCmd: Bool = false

    public init() {}

    public var body: some View {
        Form {
            // MARK: 1. Master Engine Switch & Status
            Section {
                VStack(spacing: 12) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(statusColor.opacity(0.18))
                                .frame(width: 44, height: 44)

                            Image(systemName: "bolt.horizontal.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(statusColor)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text("NetMerge Link Bonding")
                                    .font(.headline)
                                    .fontWeight(.bold)

                                Text(engine.serviceState.rawValue)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(statusColor.opacity(0.15))
                                    .foregroundStyle(statusColor)
                                    .clipShape(Capsule())
                            }

                            Text("Aggregate Wi-Fi, Ethernet, and Mobile Hotspots for combined throughput.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { engine.isRunning },
                            set: { newValue in
                                if newValue {
                                    engine.start()
                                } else {
                                    engine.stop()
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                    }

                    // Live Throughput Hero
                    if engine.isRunning {
                        Divider()
                            .opacity(0.4)

                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("COMBINED DOWNLOAD")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Text(formatSpeed(engine.totalDownloadSpeedMbps))
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color(red: 0.18, green: 0.82, blue: 0.45))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("COMBINED UPLOAD")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Text(formatSpeed(engine.totalUploadSpeedMbps))
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.cyan)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("ACTIVE FLOWS")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Text("\(engine.totalActiveFlows)")
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Connection Aggregation")
            } footer: {
                if !engine.lastLogMessage.isEmpty {
                    Text("Engine: \(engine.lastLogMessage)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            // MARK: 2. Detected & Active Adapters
            Section {
                if engine.activeAdapters.isEmpty {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.secondary)
                        Text("No active physical network interfaces detected.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Spacer()
                        Button("Refresh") {
                            engine.refreshDetectedAdapters()
                        }
                        .controlSize(.small)
                    }
                } else {
                    ForEach(engine.activeAdapters) { adapter in
                        HStack(spacing: 12) {
                            Image(systemName: adapter.systemSymbolName)
                                .font(.system(size: 14))
                                .frame(width: 22)
                                .foregroundStyle(adapter.isUsable ? statusColor : Color.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(adapter.interfaceTypeDisplayName)
                                        .font(.subheadline.weight(.semibold))

                                    if let ip = adapter.ipv4 {
                                        Text(ip)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                HStack(spacing: 8) {
                                    Text("Weight: \(String(format: "%.2f", adapter.weight))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    Text("Flows: \(adapter.activeFlows) active / \(adapter.totalFlows) total")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 1) {
                                Text(formatSpeed(adapter.downloadSpeedMbps))
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(adapter.downloadSpeedMbps > 0 ? Color(red: 0.18, green: 0.82, blue: 0.45) : .secondary)

                                Text(formatSpeed(adapter.uploadSpeedMbps))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.cyan.opacity(0.8))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                HStack {
                    Text("Aggregated Adapters")
                    Spacer()
                    Button {
                        engine.refreshDetectedAdapters()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            } footer: {
                Text("NetMerge dynamically assigns TCP connections across adapters based on real-time measured capacity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: 3. Powerload & Application Integration
            Section {
                Toggle(isOn: $powerloadUseNetMergeEngine) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Route Powerload Turbo Downloads Through NetMerge")
                            .font(.body.weight(.medium))
                        Text("Accelerates Powerload multi-chunk downloads by bonding all available network links.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $netMergeShowNotchWidget) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show NetMerge Notch HUD Capsule")
                            .font(.body.weight(.medium))
                        Text("Live bonded bandwidth and link indicators directly in the LiquidDynamo notch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $netMergeAutoStart) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start NetMerge Engine on LiquidDynamo Launch")
                            .font(.body.weight(.medium))
                        Text("Automatically boots the SOCKS5 proxy daemon in the background.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("App & Notch Integration")
            }

            // MARK: 4. SOCKS5 Proxy Configuration
            Section {
                HStack {
                    Text("SOCKS5 Proxy Address")
                    Spacer()
                    Text("127.0.0.1:\(netMergeSocksPort)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button {
                    let cmd = "export ALL_PROXY=socks5://127.0.0.1:\(netMergeSocksPort)"
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd, forType: .string)
                    copiedProxyCmd = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedProxyCmd = false
                    }
                } label: {
                    HStack {
                        Label(copiedProxyCmd ? "Terminal Proxy Command Copied!" : "Copy Terminal Proxy Command", systemImage: copiedProxyCmd ? "checkmark.circle.fill" : "doc.on.clipboard")
                            .font(.body.weight(.medium))
                        Spacer()
                        Text("export ALL_PROXY=socks5://127.0.0.1:\(netMergeSocksPort)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("IPv6 Handling", selection: $netMergeIPv6Mode) {
                    ForEach(NetMergeIPv6Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode.flagValue)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System-Wide TUN Mode")
                            .font(.body.weight(.medium))
                        Text("Routes all system applications through virtual utun bonding (requires administrator privileges).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Request Root Mode") {
                        engine.requestSystemWideBonding()
                    }
                    .controlSize(.regular)
                }
            } header: {
                Text("Proxy & Advanced Routing")
            }
        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
    }

    private var statusColor: Color {
        switch engine.serviceState {
        case .active:
            return Color(red: 0.18, green: 0.82, blue: 0.45)
        case .degraded:
            return Color(red: 0.2, green: 0.65, blue: 0.95)
        case .starting:
            return Color.orange
        case .stopped:
            return Color.secondary
        case .error:
            return Color.red
        }
    }

    private func formatSpeed(_ mbps: Double) -> String {
        if mbps >= 1000 {
            return String(format: "%.1f Gb/s", mbps / 1000.0)
        } else if mbps >= 1.0 {
            return String(format: "%.1f Mb/s", mbps)
        } else {
            return String(format: "%.0f Kb/s", mbps * 1000.0)
        }
    }
}
