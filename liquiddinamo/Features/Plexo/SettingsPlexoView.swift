//
//  SettingsPlexoView.swift
//  LiquidDynamo
//
//  Dedicated Preferences and Configuration tab for Plexo Turbo Downloader.
//  Provides multi-network adapter management, parallel connection tuning,
//  chunk size optimization, bandwidth limits, and download storage options.
//

import AppKit
import Defaults
import SwiftUI

public struct SettingsPlexoView: View {
    @ObservedObject private var netManager = PlexoNetworkManager.shared
    @ObservedObject private var engine = PlexoDownloadEngine.shared
    @ObservedObject private var bandwidth = PlexoBandwidthManager.shared

    @Default(.plexoDefaultFolder) var defaultFolder
    @Default(.plexoChunkSizeMB) var chunkSizeMB
    @Default(.plexoMaxConnectionsPerFile) var maxConnectionsPerFile
    @Default(.plexoMaxParallelDownloads) var maxParallelDownloads
    @Default(.plexoBandwidthLimitMbps) var bandwidthLimitMbps
    @Default(.plexoClipboardAutoDetect) var clipboardAutoDetect
    @Default(.plexoCompletionAlert) var completionAlert
    @Default(.plexoTorrentAutoStart) var torrentAutoStart

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
                        Text("Plexo Turbo Downloader")
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
                                Text(PlexoFormatting.formatSpeed(netManager.totalDownloadSpeed))
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
                                        .fill(iface.color)
                                        .frame(width: 6, height: 6)
                                    Text(iface.effectiveName)
                                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                    if iface.isEnabled {
                                        Text(PlexoFormatting.formatSpeed(iface.downloadSpeed))
                                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                            .foregroundStyle(iface.color)
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

                        Text("Plexo breaks files into dynamic chunks and downloads them across all enabled network interfaces concurrently.")
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }

                // 4. Physical Network Adapters Management
                GroupBox(label: Label("Network Interfaces", systemImage: "network")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(netManager.interfaces) { iface in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(iface.color)
                                    .frame(width: 8, height: 8)

                                Image(systemName: iface.kind.iconName)
                                    .font(.system(size: 12))
                                    .frame(width: 16)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(iface.effectiveName)
                                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    Text("\(iface.displayName) (\(iface.bsdName)) • \(iface.ipAddress ?? "No IP")")
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
