//
//  SettingsFileDroidView.swift
//  LiquidDynamo
//
//  Preferences and configuration tab for FileDroid & OpenMTP
//  Finder storage mounting, ADB path resolution, and USB options.
//

import AppKit
import Defaults
import SwiftUI

public struct SettingsFileDroidView: View {
    @ObservedObject private var engine = FileDroidEngine.shared
    @Default(.filedroidAdbPath) var adbPathSetting
    @Default(.filedroidAutoDetectAdb) var autoDetectAdb
    @Default(.filedroidAutoMountOnConnect) var autoMountOnConnect
    @Default(.filedroidAutoRevealInFinder) var autoRevealInFinder
    @Default(.filedroidDefaultMacFolder) var defaultMacFolder
    @Default(.filedroidTransferConcurrency) var transferConcurrency
    @Default(.filedroidShowHiddenFiles) var showHiddenFiles
    @Default(.filedroidNotifications) var filedroidNotifications
    @Default(.filedroidBackendType) var backendType

    @Default(.androidFilesAdbPath) var androidFilesAdbPath
    @Default(.androidFilesDefaultDownloadFolder) var androidFilesDefaultDownloadFolder
    @Default(.androidFilesThumbnailCacheSizeMB) var androidFilesThumbnailCacheSizeMB
    @Default(.androidFilesStopAdbOnQuit) var androidFilesStopAdbOnQuit

    @State private var customAdbInput: String = ""
    @State private var adbStatusMessage: String? = nil

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color.green, Color.teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 36, height: 36)
                        Image(systemName: "phone.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("FileDroid & OpenMTP")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("Android file management, Finder external SSD emulation, and ADB/MTP protocols")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 4)

                // 1. Live Status Card
                GroupBox(label: Label("Live Device Status", systemImage: "bolt.fill")) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let dev = engine.selectedDevice {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dev.displayName)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                    Text("\(dev.manufacturer) • \(dev.androidVersion) • \(dev.connectionType.rawValue)")
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if let batt = dev.batteryLevel {
                                    HStack(spacing: 4) {
                                        Image(systemName: dev.isCharging ? "bolt.fill" : "battery.75")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(batt <= 20 ? Color.red : Color.green)
                                        Text("\(batt)%")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(Capsule())
                                }

                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(dev.status.statusColor)
                                        .frame(width: 6, height: 6)
                                    Text(dev.status.rawValue)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                            }

                            if dev.status == .connected {
                                HStack(spacing: 16) {
                                    Text("Free Storage: \(FileDroidFormatting.formatBytes(dev.internalStorageFree)) of \(FileDroidFormatting.formatBytes(dev.internalStorageTotal))")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Button("Reveal in Finder") {
                                        engine.openMountInFinder()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                        } else {
                            HStack {
                                Image(systemName: "cable.connector.slash")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                Text("No Android device connected. Plug in a phone via USB.")
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Scan USB") {
                                    engine.scanDevices()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(8)
                }

                // 2. Transfer Backend Selection (Option B)
                GroupBox(label: Label("Transfer Backend", systemImage: "gearshape.2.fill")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Active Protocol:", selection: $backendType) {
                            Text("ADB High-Speed (Recommended)").tag("adb")
                            Text("OpenMTP (libmtp)").tag("mtp")
                        }
                        .pickerStyle(.segmented)

                        if backendType == "adb" {
                            Text("ADB uses Android Debug Bridge for up to 45 MB/s transfer speeds. Requires USB Debugging enabled on your phone.")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(engine.mtpBackend.isAvailable ? "Native libmtp detected and ready for standard MTP file transfers without USB debugging." : "libmtp tools are optional for MTP mode. If not installed, enable USB Debugging on your phone or run 'brew install libmtp'.")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }

                // 3. ADB Platform Tools Configuration
                GroupBox(label: Label("ADB Platform Tools", systemImage: "terminal.fill")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Circle()
                                .fill(engine.isAdbAvailable ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(engine.isAdbAvailable ? "ADB Detected" : "ADB Not Found")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Spacer()
                            Text(engine.adbPath ?? "None")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 8) {
                            TextField("Custom ADB Path", text: $customAdbInput)
                                .textFieldStyle(.roundedBorder)

                            Button("Browse…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = true
                                panel.canChooseDirectories = false
                                panel.title = "Select adb Executable"
                                if panel.runModal() == .OK, let path = panel.url?.path {
                                    customAdbInput = path
                                    if engine.setCustomAdbPath(path) {
                                        adbStatusMessage = "ADB verified!"
                                    } else {
                                        adbStatusMessage = "Invalid executable."
                                    }
                                }
                            }

                            Button("Auto-Detect") {
                                engine.resolveAdbPath()
                                customAdbInput = engine.adbPath ?? ""
                                adbStatusMessage = engine.isAdbAvailable ? "ADB found!" : "ADB not found."
                            }
                        }

                        if let msg = adbStatusMessage {
                            Text(msg)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(engine.isAdbAvailable ? Color.green : Color.red)
                        }
                    }
                    .padding(8)
                }

                // 4. Finder SSD Emulation & Folders
                GroupBox(label: Label("Finder Mount & Folders", systemImage: "externaldrive.fill")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Automatically mount connected Android devices in Finder", isOn: $autoMountOnConnect)
                            .tint(.accentColor)
                            .onChange(of: autoMountOnConnect) { engine.autoMountInFinder = $0 }

                        Toggle("Automatically open / reveal mounted volume in Finder upon connection", isOn: $autoRevealInFinder)
                            .tint(.accentColor)
                            .onChange(of: autoRevealInFinder) { engine.autoRevealInFinder = $0 }

                        Divider().padding(.vertical, 2)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Default Mac Download Destination:")
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                Text(defaultMacFolder)
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
                                panel.title = "Select Mac Download Destination"
                                if panel.runModal() == .OK, let url = panel.url {
                                    defaultMacFolder = url.path
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(8)
                }

                // 5. Transfer Options & Viewing
                GroupBox(label: Label("Transfers & Viewing", systemImage: "slider.horizontal.3")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Stepper("Concurrent Transfers: \(transferConcurrency)", value: $transferConcurrency, in: 1...5)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))

                        Toggle("Show hidden files and folders (.dotfiles)", isOn: $showHiddenFiles)
                            .tint(.accentColor)
                            .onChange(of: showHiddenFiles) { _ in
                                engine.fetchDirectoryContents(path: engine.currentRemotePath)
                            }

                        Toggle("Show notifications on transfer complete", isOn: $filedroidNotifications)
                            .tint(.accentColor)
                    }
                    .padding(8)
                }

                // 6. In-App Android File Manager
                GroupBox(label: Label("Android File Manager (In-App)", systemImage: "folder.badge.gearshape")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("Custom ADB Path:")
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            TextField("Inherit default / auto-detected", text: $androidFilesAdbPath)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Default Download Folder:")
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                Text(androidFilesDefaultDownloadFolder.isEmpty ? "~/Downloads/<Device Name>" : androidFilesDefaultDownloadFolder)
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Choose…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.canCreateDirectories = true
                                panel.title = "Select In-App Download Destination"
                                if panel.runModal() == .OK, let url = panel.url {
                                    androidFilesDefaultDownloadFolder = url.path
                                }
                            }
                            .controlSize(.small)
                        }

                        Stepper("Thumbnail Cache: \(androidFilesThumbnailCacheSizeMB) MB", value: $androidFilesThumbnailCacheSizeMB, in: 50...1000, step: 50)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))

                        Toggle("Stop ADB daemon server on application quit", isOn: $androidFilesStopAdbOnQuit)
                            .tint(.accentColor)
                    }
                    .padding(8)
                }
            }
            .padding(16)
        }
        .onAppear {
            customAdbInput = engine.adbPath ?? ""
        }
    }
}
