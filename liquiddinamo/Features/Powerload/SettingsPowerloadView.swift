//
//  SettingsPowerloadView.swift
//  LiquidDynamo
//
//  Dedicated Preferences and Configuration tab for Powerload Multi-Network Accelerator.
//  Provides multi-network adapter management, parallel connection tuning,
//  chunk size optimization, bandwidth limits, and download storage options.
//

import AppKit
import Defaults
import SwiftUI

public struct SettingsPowerloadView: View {
    @ObservedObject private var netManager = PowerloadNetworkManager.shared
    @ObservedObject private var engine = PowerloadDownloadEngine.shared
    @ObservedObject private var bandwidth = PowerloadBandwidthManager.shared

    @Default(.powerloadDefaultFolder) var defaultFolder
    @Default(.powerloadChunkSizeMB) var chunkSizeMB
    @Default(.powerloadMaxConnectionsPerFile) var maxConnectionsPerFile
    @Default(.powerloadMaxParallelDownloads) var maxParallelDownloads
    @Default(.powerloadBandwidthLimitMbps) var bandwidthLimitMbps
    @Default(.powerloadClipboardAutoDetect) var clipboardAutoDetect
    @Default(.powerloadCompletionAlert) var completionAlert
    @Default(.powerloadTorrentAutoStart) var torrentAutoStart
    @Default(.powerloadUseMeteredConnections) var useMeteredConnections
    @Default(.powerloadUseNetMergeEngine) var useNetMergeEngine

    @ObservedObject private var netMergeEngine = NetMergeEngine.shared

    @State private var isShowingClearConfirm: Bool = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 36, height: 36)
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Powerload Multi-Network Accelerator")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("Multi-network chunk bonding, connection pooling, and bandwidth acceleration")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 4)

                // 1. Live Downloader Status Card
                GroupBox(label: Label("Live Downloader Status", systemImage: "bolt.fill")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Total Combined Speed")
                                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text(PowerloadFormatting.formatSpeed(netManager.totalDownloadSpeed))
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundStyle(netManager.totalDownloadSpeed > 1024 ? Color.green : .primary)
                            }

                            Divider().frame(height: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Active Transfers")
                                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text("\(engine.activeTasks.filter { $0.state == .downloading }.count) downloading (\(engine.activeTasks.count) total)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }

                            Spacer()

                            if bandwidth.settings.isSlowModeActive {
                                HStack(spacing: 4) {
                                    Image(systemName: "tortoise.fill")
                                    Text("Slow Mode Active")
                                }
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Capsule())
                            }
                        }

                        // Network Interfaces Summary Chips
                        HStack(spacing: 8) {
                            ForEach(netManager.interfaces) { iface in
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(iface.isOnline ? iface.color : Color.gray.opacity(0.6))
                                        .frame(width: 6, height: 6)
                                    Text(iface.effectiveName)
                                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                        .foregroundStyle(iface.isOnline && iface.isEnabled ? .primary : .secondary)
                                    if iface.isOnline && iface.isEnabled {
                                        Text(PowerloadFormatting.formatSpeed(iface.downloadSpeed))
                                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                            .foregroundStyle(iface.color)
                                    } else if !iface.isOnline {
                                        Text("(Inactive)")
                                            .font(.system(size: 9.5, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("(Disabled)")
                                            .font(.system(size: 9.5, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .padding(8)
                }

                // 2. Storage & Folder Settings
                GroupBox(label: Label("Download Destination", systemImage: "folder.fill")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Default Download Folder:")
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                Text(defaultFolder)
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button("Choose Folder…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.canCreateDirectories = true
                                panel.title = "Select Default Download Folder"
                                if panel.runModal() == .OK, let url = panel.url {
                                    defaultFolder = url.path
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(8)
                }

                // 3. Network Acceleration Tuning
                GroupBox(label: Label("Connection & Chunk Tuning", systemImage: "speedometer")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Chunk Allocation Size:", selection: $chunkSizeMB) {
                            Text("2 MB (Aggressive)").tag(2)
                            Text("4 MB (Fast)").tag(4)
                            Text("8 MB (Optimal)").tag(8)
                            Text("16 MB (Large files)").tag(16)
                            Text("32 MB (Gigabit network)").tag(32)
                        }
                        .pickerStyle(.menu)

                        Stepper("Max Parallel Downloads: \(maxParallelDownloads)", value: $maxParallelDownloads, in: 1...10)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))

                        Stepper("Max Connections per File: \(maxConnectionsPerFile)", value: $maxConnectionsPerFile, in: 2...16)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))

                        Text("Powerload breaks files into dynamic chunks and downloads them across all enabled network interfaces concurrently.")
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }

                // 3b. NetMerge Engine Integration
                GroupBox(label: Label("NetMerge Engine Bonding", systemImage: "bolt.horizontal.fill")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $useNetMergeEngine) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Route Powerload Downloads Through NetMerge Engine")
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                Text("Uses NetMerge's dynamic weighted scheduler to automatically balance download streams across all physical connections.")
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            Circle()
                                .fill(netMergeEngine.isRunning ? Color.green : Color.secondary)
                                .frame(width: 8, height: 8)

                            Text(netMergeEngine.isRunning ? "NetMerge SOCKS5 active on \(netMergeEngine.socksListenAddress):\(netMergeEngine.socksListenPort)" : "NetMerge Engine is currently stopped")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button(netMergeEngine.isRunning ? "Stop NetMerge" : "Start NetMerge") {
                                netMergeEngine.toggle()
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(8)
                }

                // 4. Physical Network Adapters Management
                GroupBox(label: Label("Network Interfaces", systemImage: "network")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(netManager.interfaces) { iface in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(iface.isOnline ? iface.color : Color.gray.opacity(0.6))
                                    .frame(width: 8, height: 8)

                                Image(systemName: iface.kind.iconName)
                                    .font(.system(size: 12))
                                    .foregroundStyle(iface.isOnline ? .primary : .secondary)
                                    .frame(width: 16)

                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Text(iface.effectiveName)
                                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                            .foregroundStyle(iface.isOnline ? .primary : .secondary)
                                        if !iface.isOnline {
                                            Text(iface.health.reasonText)
                                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                                .foregroundStyle(Color.orange)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.orange.opacity(0.1))
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                        } else if iface.isMetered {
                                            Text("Metered")
                                                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                                .foregroundStyle(Color.yellow)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.yellow.opacity(0.12))
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                        }
                                    }
                                    Text("\(iface.displayName) (\(iface.bsdName)) • \(iface.statusDescription)\(iface.gatewayIP != nil ? " • GW: \(iface.gatewayIP!)" : "")")
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { iface.isEnabled },
                                    set: { netManager.setInterfaceEnabled(iface.id, isEnabled: $0) }
                                ))
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: iface.color))
                                .scaleEffect(0.7)
                            }
                            .padding(.vertical, 3)

                            if iface.id != netManager.interfaces.last?.id {
                                Divider()
                            }
                        }

                        // Wi-Fi hotspot limitation note
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.top, 1)
                            Text("Note: Single Mac Wi-Fi cards cannot bond a Wi-Fi network and a personal hotspot at the same time. Connect additional networks via iPhone USB cable, Ethernet adapter, or Thunderbolt.")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    .padding(8)
                }

                // 5. Bandwidth Limits & Options
                GroupBox(label: Label("Bandwidth & Automation", systemImage: "slider.horizontal.below.rectangle")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Global Speed Limit (Mbps, 0 = Unlimited):")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            Spacer()
                            TextField("0", value: $bandwidthLimitMbps, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }

                        Toggle("Slow Mode (reduces bandwidth during calls/video)", isOn: Binding(
                            get: { bandwidth.settings.isSlowModeActive },
                            set: { _ in bandwidth.toggleSlowMode() }
                        ))
                        .tint(.orange)

                        Divider().padding(.vertical, 2)

                        Toggle("Allow metered / cellular tethering connections", isOn: $useMeteredConnections)
                            .tint(.accentColor)
                        Text("When off, mobile hotspots and cellular tethering are excluded from multi-interface bonding to protect data caps.")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)

                        Divider().padding(.vertical, 2)

                        Toggle("Auto-detect links copied to clipboard", isOn: $clipboardAutoDetect)
                            .tint(.accentColor)

                        Toggle("Show notification when download completes", isOn: $completionAlert)
                            .tint(.accentColor)

                        Toggle("Auto-start torrent downloads when added", isOn: $torrentAutoStart)
                            .tint(.accentColor)
                    }
                    .padding(8)
                }

                // 6. Maintenance & History
                GroupBox(label: Label("Download History", systemImage: "clock.arrow.circlepath")) {
                    HStack {
                        Text("\(engine.completedTasks.count) completed downloads in history")
                            .font(.system(size: 11.5, design: .rounded))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Clear History") {
                            isShowingClearConfirm = true
                        }
                        .controlSize(.small)
                        .disabled(engine.completedTasks.isEmpty)
                    }
                    .padding(8)
                }
            }
            .padding(16)
        }
        .confirmationDialog(
            "Clear Download History?",
            isPresented: $isShowingClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear All Completed", role: .destructive) {
                engine.clearCompletedTasks()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove completed items from the history list. Downloaded files on disk will not be deleted.")
        }
    }
}


// MARK: - Backward Compatibility Typealias
public typealias SettingsPlexoView = SettingsPowerloadView
