//
//  FileDroidView.swift
//  LiquidDynamo
//
//  Native Liquid Glass interface for FileDroid & OpenMTP.
//  Provides dual-pane file browsing, drag & drop push/pull,
//  Finder external SSD mount reveal, and live device telemetry.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct FileDroidView: View {
    @ObservedObject private var engine = FileDroidEngine.shared
    @State private var selectedFileIDs: Set<String> = []
    @State private var isShowingNewFolderDialog: Bool = false
    @State private var newFolderName: String = ""
    @State private var isTargetedForDrop: Bool = false
    @State private var searchQuery: String = ""
    @State private var isShowingDeleteConfirm: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            headerBar

            if let dev = engine.selectedDevice, dev.status == .connected {
                quickAccessRow
                breadcrumbAndToolbar
                fileListView
            } else {
                disconnectedStateView
            }

            if engine.isTransferring || !engine.activeTransfers.isEmpty {
                transfersDrawer
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: engine.selectedDevice)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: engine.currentFiles.count)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Header Bar & Device Hardware Badge

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            // Icon & Device Name
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.green, Color.teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 28, height: 28)
                    Image(systemName: "phone.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    if let dev = engine.selectedDevice {
                        Text(dev.displayName)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(dev.androidVersion) • \(dev.connectionType.rawValue)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("FileDroid & OpenMTP")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Android Storage Bridge")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if let dev = engine.selectedDevice, dev.status == .connected {
                // Battery Badge
                if let batt = dev.batteryLevel {
                    HStack(spacing: 4) {
                        Image(systemName: dev.isCharging ? "bolt.fill" : "battery.75")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(batt <= 20 ? Color.red : Color.green)
                        Text("\(batt)%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                        if let temp = dev.batteryTemperature {
                            Text(String(format: "%.0f°C", temp))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }

                // Storage Used Pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(dev.storageUsedPercentage > 0.9 ? Color.red : Color.cyan)
                        .frame(width: 6, height: 6)
                    Text(FileDroidFormatting.formatBytes(dev.internalStorageFree) + " free")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())

                // "Open in Finder (SSD)" Button
                Button {
                    engine.openMountInFinder()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Open in Finder")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(LinearGradient(colors: [Color.accentColor.opacity(0.4), Color.blue.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.accentColor.opacity(0.6), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .help("Show Android device mounted as external SSD storage in Finder")
            } else {
                Button {
                    engine.scanDevices()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Scan USB")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Quick Access Navigation Row

    private var quickAccessRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickAccessButton(title: "Internal Storage", path: "/sdcard", icon: "internaldrive")
                quickAccessButton(title: "Camera", path: "/sdcard/DCIM/Camera", icon: "camera.fill")
                quickAccessButton(title: "Downloads", path: "/sdcard/Download", icon: "arrow.down.circle.fill")
                quickAccessButton(title: "Pictures", path: "/sdcard/Pictures", icon: "photo.stack.fill")
                quickAccessButton(title: "Documents", path: "/sdcard/Documents", icon: "doc.fill")
                quickAccessButton(title: "Music", path: "/sdcard/Music", icon: "music.note")
                quickAccessButton(title: "Movies", path: "/sdcard/Movies", icon: "film.fill")
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func quickAccessButton(title: String, path: String, icon: String) -> some View {
        let isCurrent = engine.currentRemotePath == path
        Button {
            engine.navigateTo(path: path)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(isCurrent ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isCurrent ? Color.accentColor : Color.white.opacity(0.12), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Breadcrumb & Action Toolbar

    private var breadcrumbAndToolbar: some View {
        HStack(spacing: 8) {
            // Up Button
            Button {
                engine.navigateUp()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(engine.currentRemotePath == "/sdcard" || engine.currentRemotePath == "/")

            // Breadcrumb path display
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(engine.currentRemotePath)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            // New Folder Button
            Button {
                isShowingNewFolderDialog = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Create New Folder")
            .sheet(isPresented: $isShowingNewFolderDialog) {
                newFolderSheet
            }

            // Upload Button
            Button {
                promptForUploadFiles()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.green)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Upload files from Mac to current phone directory")

            // Refresh Button
            Button {
                engine.fetchDirectoryContents(path: engine.currentRemotePath)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Refresh Directory")
        }
    }

    // MARK: - File List Table

    private var fileListView: some View {
        VStack(spacing: 0) {
            if engine.currentFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("This folder is empty or protected")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(engine.currentFiles) { file in
                            fileRow(file: file)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 280)
            }
        }
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isTargetedForDrop ? Color.accentColor : Color.white.opacity(0.08), lineWidth: isTargetedForDrop ? 2 : 0.75)
        )
    }

    @ViewBuilder
    private func fileRow(file: AndroidFileItem) -> some View {
        let isSelected = selectedFileIDs.contains(file.id)

        HStack(spacing: 10) {
            // Icon
            Image(systemName: file.iconSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(file.iconColor)
                .frame(width: 18)

            // Name
            Text(file.name)
                .font(.system(size: 11.5, weight: file.isDirectory ? .semibold : .regular, design: .rounded))
                .foregroundStyle(file.isDirectory ? .primary : .primary.opacity(0.9))
                .lineLimit(1)

            Spacer()

            // File Size
            Text(file.formattedSize)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .trailing)

            // Date
            Text(file.formattedDate)
                .font(.system(size: 9.5, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.8))
                .frame(width: 80, alignment: .trailing)

            // Action: Download
            if !file.isDirectory {
                Button {
                    downloadFileToMac(file: file)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Download to Mac")
            }

            // Action: Delete
            Button {
                engine.deleteItems(paths: [file.remotePath])
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Delete from Phone")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if file.isDirectory {
                engine.navigateTo(path: file.remotePath)
            } else {
                downloadFileToMac(file: file)
            }
        }
        .onTapGesture {
            if selectedFileIDs.contains(file.id) {
                selectedFileIDs.remove(file.id)
            } else {
                selectedFileIDs.insert(file.id)
            }
        }
    }

    // MARK: - Active Transfers Drawer

    private var transfersDrawer: some View {
        VStack(spacing: 6) {
            ForEach(engine.activeTransfers.suffix(3)) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.direction == .uploadToAndroid ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(item.direction == .uploadToAndroid ? Color.green : Color.cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.fileName)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Text("\(item.formattedProgress) • \(item.formattedSpeed)")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if item.status == .inProgress {
                        Button {
                            engine.cancelTransfer(id: item.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else if item.status == .completed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.green)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Disconnected Standby View

    private var disconnectedStateView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 54, height: 54)
                Image(systemName: "cable.connector.horizontal")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.cyan)
            }

            VStack(spacing: 4) {
                Text("No Android Device Connected")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Connect your Android phone via USB cable.\nEnsure USB Debugging or File Transfer (MTP) is selected.")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button {
                    engine.scanDevices()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                        Text("Refresh USB")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.3))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.accentColor.opacity(0.6), lineWidth: 0.8))
                }
                .buttonStyle(.plain)

                // Finder Mount Guide
                Button {
                    let alert = NSAlert()
                    alert.messageText = "FileDroid & OpenMTP Finder Mount"
                    alert.informativeText = "When any Android device connects, FileDroid automatically creates an External Storage SSD volume right in macOS Finder!\n\nYou can browse DCIM photos, Downloads, and drag files into your phone just like a normal SSD external drive."
                    alert.runModal()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                        Text("How Finder Mount Works")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Dialogs & User Interactions

    private var newFolderSheet: some View {
        VStack(spacing: 14) {
            Text("Create Folder")
                .font(.system(size: 13, weight: .bold, design: .rounded))

            TextField("Folder Name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

            HStack(spacing: 12) {
                Button("Cancel") {
                    isShowingNewFolderDialog = false
                    newFolderName = ""
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    if !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty {
                        engine.createFolder(named: newFolderName.trimmingCharacters(in: .whitespaces))
                    }
                    isShowingNewFolderDialog = false
                    newFolderName = ""
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
    }

    private func promptForUploadFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.title = "Select Files to Upload to Phone"
        if panel.runModal() == .OK {
            engine.uploadFiles(localURLs: panel.urls, destinationRemotePath: engine.currentRemotePath)
        }
    }

    private func downloadFileToMac(file: AndroidFileItem) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        engine.downloadFiles(remoteFiles: [file], destinationLocalURL: downloads)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var droppedURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    droppedURLs.append(url)
                } else if let url = item as? URL {
                    droppedURLs.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            if !droppedURLs.isEmpty {
                self.engine.uploadFiles(localURLs: droppedURLs, destinationRemotePath: self.engine.currentRemotePath)
            }
        }
        return true
    }
}
