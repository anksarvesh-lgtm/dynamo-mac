//
//  PowerloadView.swift
//  LiquidDynamo
//
//  Complete native liquid-glass interface for Powerload Multi-Network Downloader.
//  Faithfully ports Powerload's dashboard into native SwiftUI:
//  - Multi-network speed strip with live per-adapter readouts and enable toggles
//  - Active downloads cards with multi-colored chunk progress visualization
//  - Direct link, magnet link, and .torrent file addition drawer with clipboard auto-detect
//  - Slow Mode toggle and global bandwidth management
//  - Single stream fallback notice when server has no range support
//  - Open file and Reveal in Finder actions on completion
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

public struct PowerloadView: View {
    @ObservedObject private var netManager = PowerloadNetworkManager.shared
    @ObservedObject private var engine = PowerloadDownloadEngine.shared
    @ObservedObject private var bandwidth = PowerloadBandwidthManager.shared

    @Default(.powerloadDefaultFolder) var defaultFolder
    @Default(.powerloadClipboardAutoDetect) var clipboardAutoDetect

    @State private var isAddDrawerOpen: Bool = false
    @State private var inputURL: String = ""
    @State private var selectedDestination: String = ""
    @State private var selectedInterfaceForEditing: PowerloadInterface? = nil
    @State private var editingNickname: String = ""
    @State private var clipboardDetectedURL: String? = nil

    public init() {}

    public var body: some View {
        VStack(spacing: 10) {
            headerBar
            multiNetworkStrip

            if let clipURL = clipboardDetectedURL, isAddDrawerOpen == false {
                clipboardDetectedBanner(url: clipURL)
            }

            if isAddDrawerOpen {
                addDownloadDrawer
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }

            downloadsContent
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isAddDrawerOpen)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: engine.activeTasks.count)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: clipboardDetectedURL)
        .onAppear {
            if selectedDestination.isEmpty {
                selectedDestination = defaultFolder
            }
            checkClipboardForURL()
        }
        .sheet(item: $selectedInterfaceForEditing) { iface in
            interfaceEditSheet(for: iface)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 26, height: 26)
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Powerload Accelerator")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Multi-Network Acceleration")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Combined Speed Readout
            HStack(spacing: 4) {
                Circle()
                    .fill(netManager.totalDownloadSpeed > 1024 ? Color.green : Color.gray)
                    .frame(width: 5, height: 5)
                Text(PowerloadFormatting.formatSpeed(netManager.totalDownloadSpeed))
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())

            // Slow Mode Button
            Button {
                bandwidth.toggleSlowMode()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "tortoise.fill")
                        .font(.system(size: 9.5))
                    Text("Slow Mode")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
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
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.cyan.opacity(0.8))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Clipboard Auto-Detect Banner

    private func clipboardDetectedBanner(url: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.cyan)

            VStack(alignment: .leading, spacing: 1) {
                Text("Link copied to clipboard")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(url)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Download") {
                inputURL = url
                isAddDrawerOpen = true
                clipboardDetectedURL = nil
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)

            Button {
                clipboardDetectedURL = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.cyan.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.25), lineWidth: 0.8))
    }

    // MARK: - Multi-Network Interface Strip

    private var multiNetworkStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(netManager.interfaces) { iface in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(iface.isOnline ? iface.color : Color.gray.opacity(0.6))
                            .frame(width: 6, height: 6)

                        Image(systemName: iface.kind.iconName)
                            .font(.system(size: 10))
                            .foregroundStyle(iface.isOnline && iface.isEnabled ? .primary : .secondary)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(iface.effectiveName)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(iface.isOnline && iface.isEnabled ? .primary : .secondary)
                            if iface.isOnline {
                                Text(PowerloadFormatting.formatSpeed(iface.downloadSpeed))
                                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(iface.isEnabled ? iface.color : .secondary)
                            } else {
                                Text("Offline")
                                    .font(.system(size: 8, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Toggle("", isOn: Binding(
                            get: { iface.isEnabled },
                            set: { netManager.setInterfaceEnabled(iface.id, isEnabled: $0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: iface.color))
                        .scaleEffect(0.6)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(iface.isOnline && iface.isEnabled ? 0.08 : 0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(iface.isOnline && iface.isEnabled ? iface.color.opacity(0.3) : Color.clear, lineWidth: 0.8)
                    )
                    .onTapGesture {
                        editingNickname = iface.userNickname ?? ""
                        selectedInterfaceForEditing = iface
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Add Download Drawer

    private var addDownloadDrawer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add URL, Magnet Link, or Torrent")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                TextField("https://... or magnet:?xt=...", text: $inputURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, design: .rounded))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        inputURL = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Paste from Clipboard")
            }

            HStack(spacing: 8) {
                Button {
                    pickTorrentFile()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.doc.fill")
                            .font(.system(size: 9.5))
                        Text(".torrent File")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.canCreateDirectories = true
                    panel.title = "Select Destination Folder"
                    if panel.runModal() == .OK, let url = panel.url {
                        selectedDestination = url.path
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .font(.system(size: 9.5))
                        Text((selectedDestination as NSString).lastPathComponent)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    let clean = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !clean.isEmpty else { return }
                    engine.addDownload(urlString: clean, destinationDirectory: selectedDestination, autoStart: true)
                    inputURL = ""
                    isAddDrawerOpen = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10))
                        Text("Start Turbo")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .background(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.cyan.opacity(0.2), lineWidth: 0.8))
    }

    // MARK: - Downloads Content List

    private var downloadsContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
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
        .frame(maxHeight: 260)
    }

    private func downloadTaskCard(for task: PowerloadDownloadTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: task.isTorrent ? "point.3.filled.connected.trianglepath.dotted" : "doc.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.cyan)

                VStack(alignment: .leading, spacing: 1) {
                    Text(task.fileName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 5) {
                        Text(task.state.displayText)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(task.state == .downloading ? Color.cyan : .secondary)

                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)

                        Text("\(task.formattedDownloadedSize) of \(task.totalBytes > 0 ? task.formattedTotalSize : "—")")
                            .font(.system(size: 9.5, design: .rounded))
                            .foregroundStyle(.secondary)

                        if task.state == .downloading {
                            Text("•")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                            Text("ETA: \(task.timeRemainingString)")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        if !task.supportsRange && task.state == .downloading {
                            Text("• Single Stream (No Range Support)")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.orange)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 5) {
                    if task.state == .downloading {
                        Button {
                            engine.pauseDownload(id: task.id)
                        } label: {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    } else if task.state == .paused {
                        Button {
                            engine.resumeDownload(id: task.id)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.cyan.opacity(0.8))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        engine.cancelDownload(id: task.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            multiNetworkProgressBar(for: task)

            if task.state == .downloading && !task.perInterfaceSpeeds.isEmpty {
                HStack(spacing: 6) {
                    ForEach(netManager.interfaces) { iface in
                        if let ifaceSpeed = task.perInterfaceSpeeds[iface.id], ifaceSpeed > 1024 {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(iface.color)
                                    .frame(width: 4, height: 4)
                                Text("\(iface.effectiveName): \(PowerloadFormatting.formatSpeed(ifaceSpeed))")
                                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(iface.color)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(iface.color.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                    Spacer()
                    Text(task.formattedSpeed)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.green)
                }
            }
        }
        .padding(9)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func multiNetworkProgressBar(for task: PowerloadDownloadTask) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 6)

                if task.chunks.isEmpty {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.cyan)
                        .frame(width: max(0, geo.size.width * CGFloat(task.progressFraction)), height: 6)
                } else {
                    HStack(spacing: 1) {
                        ForEach(task.chunks) { chunk in
                            let fraction = CGFloat(chunk.rangeEnd - chunk.rangeStart + 1) / CGFloat(max(1, task.totalBytes))
                            let chunkWidth = max(2, geo.size.width * fraction)
                            let ifaceColor = netManager.interfaces.first(where: { $0.id == chunk.assignedInterfaceId })?.color ?? Color.cyan

                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(chunk.isCompleted ? ifaceColor : ifaceColor.opacity(0.25))
                                .frame(width: chunkWidth, height: 6)
                        }
                    }
                }
            }
        }
        .frame(height: 6)
    }

    // MARK: - Completed Tasks Section

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Completed Downloads")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear History") {
                    engine.clearCompletedTasks()
                }
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            ForEach(engine.completedTasks) { task in
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.green)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.fileName)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Text(PowerloadFormatting.formatBytes(task.totalBytes))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        engine.openFile(taskID: task.id)
                    } label: {
                        Text("Open")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        engine.revealInFinder(taskID: task.id)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")

                    Button {
                        engine.removeCompleted(id: task.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 26))
                .foregroundStyle(Color.cyan.opacity(0.8))

            Text("No Active Downloads")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Paste any download link, magnet link, or .torrent file to accelerate with multi-network bonding.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button {
                isAddDrawerOpen = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9.5, weight: .bold))
                    Text("Add Download")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4.5)
                .background(Color.cyan.opacity(0.3))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
    }

    // MARK: - Clipboard Checker

    private func checkClipboardForURL() {
        guard clipboardAutoDetect else { return }
        if let string = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if string.hasPrefix("http://") || string.hasPrefix("https://") || string.hasPrefix("magnet:") {
                if !engine.activeTasks.contains(where: { $0.urlString == string }) {
                    clipboardDetectedURL = string
                }
            }
        }
    }

    private func pickTorrentFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        panel.title = "Select .torrent File"
        if panel.runModal() == .OK, let url = panel.url {
            if let meta = try? PowerloadTorrentEngine.parseTorrentFile(at: url) {
                engine.addDownload(urlString: url.absoluteString, destinationDirectory: selectedDestination, autoStart: true)
                isAddDrawerOpen = false
            } else {
                engine.addDownload(urlString: url.absoluteString, destinationDirectory: selectedDestination, autoStart: true)
                isAddDrawerOpen = false
            }
        }
    }

    // MARK: - Interface Edit Sheet

    private func interfaceEditSheet(for iface: PowerloadInterface) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(iface.isOnline ? iface.color : Color.gray.opacity(0.6))
                    .frame(width: 10, height: 10)
                Text(iface.effectiveName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text(iface.isOnline ? "Online" : "Not Connected")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(iface.isOnline ? Color.green : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(iface.isOnline ? Color.green.opacity(0.12) : Color.white.opacity(0.06))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Device: \(iface.displayName) (\(iface.bsdName))")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let ip = iface.ipAddress {
                    Text("IPv4: \(ip)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let mask = iface.netmask {
                    Text("Subnet: \(mask)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let mac = iface.macAddress {
                    Text("MAC: \(mac)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text("Custom Nickname")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                TextField(iface.displayName, text: $editingNickname)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Theme Color")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                HStack(spacing: 8) {
                    let palette = ["#00E5FF", "#00E676", "#FFD600", "#FF4081", "#7C4DFF", "#2979FF"]
                    ForEach(palette, id: \.self) { hex in
                        colorCircle(hex: hex, selectedHex: iface.colorHex, ifaceId: iface.id)
                    }
                }
            }

            HStack {
                Button("Done") {
                    netManager.setInterfaceNickname(iface.id, nickname: editingNickname.isEmpty ? nil : editingNickname)
                    selectedInterfaceForEditing = nil
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.small)

                Spacer()

                Button("Cancel") {
                    selectedInterfaceForEditing = nil
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    @ViewBuilder
    private func colorCircle(hex: String, selectedHex: String, ifaceId: String) -> some View {
        let isChosen = (hex == selectedHex)
        let fill = Color(hex: hex) ?? Color.cyan
        Circle()
            .fill(fill)
            .frame(width: 22, height: 22)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: isChosen ? 2.0 : 0.0)
            )
            .onTapGesture {
                netManager.setInterfaceColor(ifaceId, colorHex: hex)
            }
    }
}


// MARK: - Backward Compatibility Typealias
public typealias PlexoView = PowerloadView
