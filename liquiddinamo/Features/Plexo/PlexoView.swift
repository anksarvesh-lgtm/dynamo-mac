//
//  PlexoView.swift
//  LiquidDynamo
//
//  Complete native liquid-glass interface for Plexo Multi-Network Downloader.
//  Faithfully ports Plexo's React/Electron dashboard into native SwiftUI:
//  - Multi-network speed strip with live per-adapter readouts and enable toggles
//  - Active downloads cards with multi-colored chunk progress visualization
//  - Direct link, magnet link, and .torrent file addition drawer
//  - Slow Mode toggle and global bandwidth management
//

import AppKit
import SwiftUI

public struct PlexoView: View {
    @ObservedObject private var netManager = PlexoNetworkManager.shared
    @ObservedObject private var engine = PlexoDownloadEngine.shared
    @ObservedObject private var bandwidth = PlexoBandwidthManager.shared

    @State private var isAddDrawerOpen: Bool = false
    @State private var inputURL: String = ""
    @State private var selectedDestination: String = PlexoDownloadEngine.defaultDownloadDirectory
    @State private var selectedInterfaceForEditing: PlexoInterface? = nil
    @State private var editingNickname: String = ""
    @State private var isShowingCompleted: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            headerBar
            multiNetworkStrip

            if isAddDrawerOpen {
                addDownloadDrawer
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }

            downloadsContent
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isAddDrawerOpen)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: engine.activeTasks.count)
        .sheet(item: $selectedInterfaceForEditing) { iface in
            interfaceEditSheet(for: iface)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            // Title & Icon
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 28, height: 28)
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Plexo Turbo Downloader")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Multi-Network Acceleration")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Combined Speed Readout
            HStack(spacing: 5) {
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

            // Slow Mode Button
            Button {
                bandwidth.toggleSlowMode()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tortoise.fill")
                        .font(.system(size: 10))
                    Text("Slow Mode")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(bandwidth.settings.isSlowModeActive ? Color.orange.opacity(0.2) : Color.white.opacity(0.06))
                .foregroundStyle(bandwidth.settings.isSlowModeActive ? Color.orange : Color.secondary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Add Download Button
            Button {
                isAddDrawerOpen.toggle()
            } label: {
                Image(systemName: isAddDrawerOpen ? "xmark" : "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.cyan.opacity(0.8))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Multi-Network Interface Strip

    private var multiNetworkStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(netManager.interfaces) { iface in
                    HStack(spacing: 8) {
                        // Custom colored status indicator
                        Circle()
                            .fill(iface.color)
                            .frame(width: 8, height: 8)

                        Image(systemName: iface.kind.iconName)
                            .font(.system(size: 11))
                            .foregroundStyle(iface.isEnabled ? .primary : .secondary)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(iface.effectiveName)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(iface.isEnabled ? .primary : .secondary)
                            Text(PlexoFormatting.formatSpeed(iface.downloadSpeed))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(iface.isEnabled ? iface.color : .secondary)
                        }

                        // Toggle
                        Toggle("", isOn: Binding(
                            get: { iface.isEnabled },
                            set: { netManager.setInterfaceEnabled(iface.id, isEnabled: $0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: iface.color))
                        .scaleEffect(0.65)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(iface.isEnabled ? 0.08 : 0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(iface.isEnabled ? iface.color.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
                    .onTapGesture {
                        editingNickname = iface.userNickname ?? ""
                        selectedInterfaceForEditing = iface
                    }
                }
            }
        }
    }

    // MARK: - Add Download Drawer

    private var addDownloadDrawer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add URL, Magnet Link, or Torrent")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                TextField("https://... or magnet:?xt=...", text: $inputURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Paste from Clipboard Button
                Button {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        inputURL = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                // Pick .torrent file
                Button {
                    pickTorrentFile()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.doc.fill")
                            .font(.system(size: 10))
                        Text(".torrent File")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                // Start Download Button
                Button {
                    let clean = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !clean.isEmpty else { return }
                    engine.addDownload(urlString: clean, destinationDirectory: selectedDestination, autoStart: true)
                    inputURL = ""
                    isAddDrawerOpen = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11))
                        Text("Start Turbo Download")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Downloads Content List

    private var downloadsContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                if engine.activeTasks.isEmpty && engine.completedTasks.isEmpty {
                    emptyStateView
                } else {
                    ForEach(engine.activeTasks) { task in
                        downloadTaskCard(for: task)
                    }

                    if !engine.completedTasks.isEmpty {
                        completedSection
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func downloadTaskCard(for task: PlexoDownloadTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top Row: Filename, State, and Action Buttons
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: task.isTorrent ? "point.3.filled.connected.trianglepath.dotted" : "doc.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.cyan)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.fileName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 6) {
                        Text(task.state.displayText)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(task.state == .downloading ? Color.cyan : .secondary)

                        Text("•")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)

                        Text("\(task.formattedDownloadedSize) of \(task.totalBytes > 0 ? task.formattedTotalSize : "—")")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)

                        if task.state == .downloading {
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text("ETA: \(task.timeRemainingString)")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Actions: Pause / Resume / Cancel
                HStack(spacing: 6) {
                    if task.state == .downloading {
                        Button {
                            engine.pauseDownload(id: task.id)
                        } label: {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    } else if task.state == .paused {
                        Button {
                            engine.resumeDownload(id: task.id)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.cyan.opacity(0.8))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        engine.cancelDownload(id: task.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Multi-Network Chunk Progress Bar
            multiNetworkProgressBar(for: task)

            // Per-Network Speed Badges
            if task.state == .downloading && !task.perInterfaceSpeeds.isEmpty {
                HStack(spacing: 8) {
                    ForEach(netManager.interfaces) { iface in
                        if let ifaceSpeed = task.perInterfaceSpeeds[iface.id], ifaceSpeed > 1024 {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(iface.color)
                                    .frame(width: 5, height: 5)
                                Text("\(iface.effectiveName): \(PlexoFormatting.formatSpeed(ifaceSpeed))")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(iface.color)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(iface.color.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                    Spacer()
                    Text(task.formattedSpeed)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.green)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func multiNetworkProgressBar(for task: PlexoDownloadTask) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 7)

                // Segmented or continuous progress
                if !task.chunks.isEmpty {
                    HStack(spacing: 1) {
                        ForEach(task.chunks) { chunk in
                            let ifaceColor = chunk.assignedInterfaceId.flatMap { id in
                                netManager.interfaces.first(where: { $0.id == id })?.color
                            } ?? Color.cyan

                            RoundedRectangle(cornerRadius: 2)
                                .fill(chunk.isCompleted ? ifaceColor : ifaceColor.opacity(0.3))
                                .frame(width: max(2, (geo.size.width / CGFloat(task.chunks.count)) - 1), height: 7)
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geo.size.width * CGFloat(task.progress)), height: 7)
                }
            }
        }
        .frame(height: 7)
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isShowingCompleted.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isShowingCompleted ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("Completed Downloads (\(engine.completedTasks.count))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isShowingCompleted {
                ForEach(engine.completedTasks) { task in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                        Text(task.fileName)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(task.formattedTotalSize)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)

                        // Open in Finder
                        Button {
                            let url = URL(fileURLWithPath: task.destinationFilePath)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        // Remove
                        Button {
                            engine.removeCompleted(id: task.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.top, 4)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 28))
                .foregroundStyle(Color.cyan.opacity(0.6))
            Text("No Active Turbo Downloads")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Click + above to paste an HTTP/HTTPS URL, magnet link, or select a .torrent file to accelerate across all internet connections simultaneously.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Interface Edit Sheet

    private func interfaceEditSheet(for iface: PlexoInterface) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Customize \(iface.displayName) (\(iface.bsdName))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Button("Done") {
                    selectedInterfaceForEditing = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.cyan)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Nickname")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. iPhone Hotspot, Home 5G", text: $editingNickname)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onSubmit {
                        netManager.setInterfaceNickname(iface.id, nickname: editingNickname)
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Accent Color")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    let colors = ["#00E5FF", "#00E676", "#FF9100", "#D500F9", "#2979FF", "#FF1744", "#FFEA00"]
                    ForEach(colors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex) ?? .cyan)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().stroke(Color.white, lineWidth: iface.colorHex == hex ? 2 : 0)
                            )
                            .onTapGesture {
                                netManager.setInterfaceColor(iface.id, colorHex: hex)
                            }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
    }

    private func pickTorrentFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "torrent") ?? .data]

        if panel.runModal() == .OK, let url = panel.url {
            if let meta = try? PlexoTorrentEngine.parseTorrentFile(at: url) {
                engine.addDownload(urlString: url.absoluteString, destinationDirectory: selectedDestination, autoStart: true)
                isAddDrawerOpen = false
            }
        }
    }
}
