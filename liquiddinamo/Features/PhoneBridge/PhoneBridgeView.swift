//
//  PhoneBridgeView.swift
//  LiquidDynamo
//
//  Native Liquid Glass interface for Phone Bridge & OpenMTP.
//  Provides dual-pane file browsing, drag & drop push/pull,
//  Finder external SSD mount reveal, and live device telemetry.
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

public struct PhoneBridgeView: View {
    @ObservedObject private var engine = PhoneBridgeEngine.shared
    @State private var selectedFileIDs: Set<String> = []
    @State private var isShowingNewFolderDialog: Bool = false
    @State private var newFolderName: String = ""
    @State private var isShowingRenameDialog: Bool = false
    @State private var itemToRename: AndroidFileItem? = nil
    @State private var renameInput: String = ""
    @State private var isShowingDeleteConfirm: Bool = false
    @State private var pathsToDelete: [String] = []
    @State private var isTargetedForDrop: Bool = false
    @State private var isMultiSelectMode: Bool = false
    @State private var copiedBrewCommand: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 10) {
            headerBar

            if !engine.isAdbAvailable && engine.activeBackend.backendType == .adb {
                adbMissingHelpCard
            } else if let dev = engine.selectedDevice {
                switch dev.status {
                case .connected:
                    quickAccessRow
                    breadcrumbAndToolbar
                    fileListView
                case .unauthorized:
                    unauthorizedStateCard(dev: dev)
                case .offline:
                    offlineStateCard(dev: dev)
                case .connecting:
                    connectingStateCard(dev: dev)
                }
            } else {
                disconnectedStateView
            }

            if engine.isTransferring || !engine.activeTransfers.isEmpty {
                transfersDrawer
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: engine.selectedDevice)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: engine.currentFiles.count)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isMultiSelectMode)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers: providers)
        }
        .sheet(isPresented: $isShowingNewFolderDialog) {
            newFolderSheet
        }
        .sheet(isPresented: $isShowingRenameDialog) {
            renameSheet
        }
        .confirmationDialog(
            "Delete from Android Device?",
            isPresented: $isShowingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                engine.deleteItems(paths: pathsToDelete)
                selectedFileIDs.removeAll()
                pathsToDelete.removeAll()
            }
            Button("Cancel", role: .cancel) {
                pathsToDelete.removeAll()
            }
        } message: {
            Text("Are you sure you want to delete \(pathsToDelete.count == 1 ? "this item" : "\(pathsToDelete.count) items")? This cannot be undone.")
        }
    }

    // MARK: - Header Bar & Device Switcher

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.green, Color.teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 26, height: 26)
                    Image(systemName: "phone.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    if engine.connectedDevices.count > 1 {
                        Menu {
                            ForEach(engine.connectedDevices) { dev in
                                Button(dev.displayName) {
                                    engine.selectDevice(serial: dev.serial)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(engine.selectedDevice?.displayName ?? "Android")
                                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .menuStyle(.borderlessButton)
                    } else if let dev = engine.selectedDevice {
                        Text(dev.displayName)
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    } else {
                        Text("Phone Bridge")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(engine.selectedDevice?.status.statusColor ?? .secondary)
                            .frame(width: 5, height: 5)
                        Text(engine.selectedDevice?.status.rawValue ?? "No Device")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if let dev = engine.selectedDevice, dev.status == .connected {
                if let batt = dev.batteryLevel {
                    HStack(spacing: 4) {
                        Image(systemName: dev.isCharging ? "bolt.fill" : "battery.75")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(batt <= 20 ? Color.red : Color.green)
                        Text("\(batt)%")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }

                Button {
                    engine.syncStorage(forced: true)
                } label: {
                    HStack(spacing: 4) {
                        if engine.isSyncingStorage {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Circle()
                                .fill(dev.storageUsedPercentage > 0.9 ? Color.red : Color.cyan)
                                .frame(width: 5, height: 5)
                        }
                        Text(PhoneBridgeFormatting.formatBytes(dev.internalStorageFree) + " free")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(engine.isSyncingStorage)
                .help("Click to sync Android storage status")

                Button {
                    engine.openMountInFinder()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Finder")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(LinearGradient(colors: [Color.accentColor.opacity(0.4), Color.blue.opacity(0.3)], startPoint: .top, endPoint: .bottom))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.accentColor.opacity(0.6), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .help("Open phone as external SSD storage volume in Finder")
            } else {
                Button {
                    engine.scanDevices()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Refresh")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - ADB Missing Help Card

    private var adbMissingHelpCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.orange)
                Text("Android Debug Bridge (adb) Required")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Text("Install ADB platform-tools via Homebrew or locate an existing binary on your Mac.")
                .font(.system(size: 10.5, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("brew install android-platform-tools")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install android-platform-tools", forType: .string)
                    copiedBrewCommand = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        copiedBrewCommand = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copiedBrewCommand ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                        Text(copiedBrewCommand ? "Copied" : "Copy")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Choose ADB Path…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.title = "Select adb Executable"
                    if panel.runModal() == .OK, let path = panel.url?.path {
                        _ = engine.setCustomAdbPath(path)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Device State Cards (Unauthorized, Offline, Connecting)

    private func unauthorizedStateCard(dev: AndroidDevice) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.orange)

            Text("Allow USB Debugging on Phone")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Unlock your \(dev.displayName) and tap 'Allow USB debugging'. Check 'Always allow from this computer'.")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button {
                engine.scanDevices()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                    Text("Check Again")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.3))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func offlineStateCard(dev: AndroidDevice) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "cable.connector.slash")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)

            Text("\(dev.displayName) is Offline")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Reconnect your USB cable or toggle USB Debugging in Developer Options.")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Refresh Connection") {
                engine.scanDevices()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func connectingStateCard(dev: AndroidDevice) -> some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Connecting to \(dev.displayName)…")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    // MARK: - Quick Access Navigation Row

    private var quickAccessRow: some View {
        let isMtp = engine.selectedDevice?.connectionType == .mtp
        let rootPrefix = isMtp ? "" : "/sdcard"
        let rootPath = isMtp ? "/" : "/sdcard"

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                quickAccessButton(title: "Internal", path: rootPath, icon: "internaldrive")
                quickAccessButton(title: "DCIM", path: "\(rootPrefix)/DCIM", icon: "camera.fill")
                quickAccessButton(title: "Downloads", path: "\(rootPrefix)/Download", icon: "arrow.down.circle.fill")
                quickAccessButton(title: "Pictures", path: "\(rootPrefix)/Pictures", icon: "photo.stack.fill")
                quickAccessButton(title: "Documents", path: "\(rootPrefix)/Documents", icon: "doc.fill")
                quickAccessButton(title: "Music", path: "\(rootPrefix)/Music", icon: "music.note")
                quickAccessButton(title: "Movies", path: "\(rootPrefix)/Movies", icon: "film.fill")
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
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(isCurrent ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isCurrent ? Color.accentColor : Color.white.opacity(0.12), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Breadcrumb & Action Toolbar

    private var breadcrumbAndToolbar: some View {
        HStack(spacing: 6) {
            Button {
                engine.navigateUp()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(engine.selectedDevice?.connectionType == .mtp ? engine.currentRemotePath == "/" : (engine.currentRemotePath == "/sdcard" || engine.currentRemotePath == "/"))

            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Text(engine.currentRemotePath)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Color.black.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            if isMultiSelectMode {
                HStack(spacing: 4) {
                    Button(selectedFileIDs.count == engine.currentFiles.count ? "Deselect All" : "Select All") {
                        if selectedFileIDs.count == engine.currentFiles.count {
                            selectedFileIDs.removeAll()
                        } else {
                            selectedFileIDs = Set(engine.currentFiles.map { $0.id })
                        }
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .buttonStyle(.plain)

                    Button {
                        let selectedItems = engine.currentFiles.filter { selectedFileIDs.contains($0.id) && !$0.isDirectory }
                        engine.downloadFiles(remoteFiles: selectedItems)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 9.5))
                            Text("Download (\(selectedFileIDs.count))")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.3))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedFileIDs.isEmpty)

                    Button {
                        let paths = engine.currentFiles.filter { selectedFileIDs.contains($0.id) }.map { $0.remotePath }
                        pathsToDelete = paths
                        isShowingDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color.red)
                            .frame(width: 22, height: 22)
                            .background(Color.red.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedFileIDs.isEmpty)

                    Button {
                        isMultiSelectMode = false
                        selectedFileIDs.removeAll()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 4) {
                    Button {
                        isMultiSelectMode = true
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Multi-Select Mode")

                    Button {
                        isShowingNewFolderDialog = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Create New Folder")

                    Button {
                        promptForUploadFiles()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.green)
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Upload files to current folder")

                    Button {
                        engine.openMacDownloadsFolder()
                    } label: {
                        Image(systemName: "folder.fill.badge.gearshape")
                            .font(.system(size: 10))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Open Mac Downloads Folder")

                    Button {
                        engine.fetchDirectoryContents(path: engine.currentRemotePath)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Refresh")
                }
            }
        }
    }

    // MARK: - File List Table

    private var fileListView: some View {
        VStack(spacing: 0) {
            if engine.currentFiles.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    Text("This folder is empty")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(engine.currentFiles) { file in
                            fileRow(file: file)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .frame(maxHeight: 240)
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

        HStack(spacing: 8) {
            if isMultiSelectMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }

            Image(systemName: file.iconSymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(file.iconColor)
                .frame(width: 16)

            Text(file.name)
                .font(.system(size: 11, weight: file.isDirectory ? .semibold : .regular, design: .rounded))
                .foregroundStyle(file.isDirectory ? Color.primary : Color.primary.opacity(0.9))
                .lineLimit(1)

            Spacer()

            Text(file.formattedSize)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            // Inline Rename
            Button {
                itemToRename = file
                renameInput = file.name
                isShowingRenameDialog = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Rename")

            // Inline Download
            if !file.isDirectory {
                Button {
                    engine.downloadFiles(remoteFiles: [file])
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Download to Mac")
            }

            // Inline Delete (with confirmation)
            Button {
                pathsToDelete = [file.remotePath]
                isShowingDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if file.isDirectory {
                engine.navigateTo(path: file.remotePath)
            } else {
                engine.downloadFiles(remoteFiles: [file])
            }
        }
        .onTapGesture {
            if isMultiSelectMode {
                if selectedFileIDs.contains(file.id) {
                    selectedFileIDs.remove(file.id)
                } else {
                    selectedFileIDs.insert(file.id)
                }
            } else {
                selectedFileIDs = [file.id]
            }
        }
    }

    // MARK: - Active Transfers Drawer

    private var transfersDrawer: some View {
        VStack(spacing: 5) {
            HStack {
                Text("Transfers")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear Finished") {
                    engine.clearFinishedTransfers()
                }
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            ForEach(engine.activeTransfers.suffix(3)) { item in
                HStack(spacing: 7) {
                    Image(systemName: item.direction == .uploadToAndroid ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(item.direction == .uploadToAndroid ? Color.green : Color.cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.fileName)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        if let err = item.errorMessage {
                            Text(err)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.red)
                        } else {
                            Text("\(item.formattedProgress) • \(item.formattedSpeed)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if item.status == .inProgress {
                        Button {
                            engine.cancelTransfer(id: item.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else if item.status == .failed {
                        Button {
                            engine.retryTransfer(id: item.id)
                        } label: {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.orange)
                        }
                        .buttonStyle(.plain)
                        .help("Retry Transfer")
                    } else if item.status == .completed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.green)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(7)
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Disconnected Standby View

    private var disconnectedStateView: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 48, height: 48)
                Image(systemName: "cable.connector.horizontal")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.cyan)
            }

            VStack(spacing: 3) {
                Text("No Android Device Connected")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Connect your phone via USB cable.\nEnsure USB Debugging or File Transfer (MTP) is selected.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                Button {
                    engine.scanDevices()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                        Text("Refresh USB")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.3))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.accentColor.opacity(0.6), lineWidth: 0.75))
                }
                .buttonStyle(.plain)

                Button {
                    let alert = NSAlert()
                    alert.messageText = "Phone Bridge Finder Mount"
                    alert.informativeText = "When any Android device connects, Phone Bridge automatically creates an External Storage volume right on your Desktop and in Finder!\n\nYou can browse DCIM photos, Downloads, and drag files into your phone just like a normal external SSD."
                    alert.runModal()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                        Text("How Finder Mount Works")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Sheets

    private var newFolderSheet: some View {
        VStack(spacing: 12) {
            Text("Create Folder")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))

            TextField("Folder Name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            HStack(spacing: 10) {
                Button("Cancel") {
                    isShowingNewFolderDialog = false
                    newFolderName = ""
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    engine.createFolder(named: newFolderName)
                    isShowingNewFolderDialog = false
                    newFolderName = ""
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
    }

    private var renameSheet: some View {
        VStack(spacing: 12) {
            Text("Rename Item")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))

            TextField("New Name", text: $renameInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

            HStack(spacing: 10) {
                Button("Cancel") {
                    isShowingRenameDialog = false
                    itemToRename = nil
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    if let item = itemToRename {
                        engine.renameItem(from: item.remotePath, to: renameInput)
                    }
                    isShowingRenameDialog = false
                    itemToRename = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(renameInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
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

// MARK: - Backward Compatibility Aliases
public typealias FileDroidView = PhoneBridgeView
