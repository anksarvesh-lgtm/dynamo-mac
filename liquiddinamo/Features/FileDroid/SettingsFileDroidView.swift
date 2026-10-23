//
//  SettingsFileDroidView.swift
//  LiquidDynamo
//
//  Preferences and configuration tab for FileDroid & OpenMTP
//  Finder storage mounting, ADB path resolution, and USB options.
//

import AppKit
import SwiftUI

public struct SettingsFileDroidView: View {
    @ObservedObject private var engine = FileDroidEngine.shared
    @State private var customAdbInput: String = ""
    @State private var adbStatusMessage: String? = nil

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color.green, Color.teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 38, height: 38)
                        Image(systemName: "phone.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("FileDroid & OpenMTP Settings")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("Configure Android USB storage mounting in macOS Finder, ADB paths, and transfer parameters")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 6)

                // 1. Finder Storage Mount Options
                GroupBox(label: Label("Finder External SSD Emulation", systemImage: "externaldrive.fill")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Automatically mount connected Android devices in Finder", isOn: $engine.autoMountInFinder)
                            .tint(.accentColor)

                        Toggle("Automatically open / reveal mounted volume in Finder upon connection", isOn: $engine.autoRevealInFinder)
                            .tint(.accentColor)

                        Text("When enabled, connecting any Android phone via USB creates an external SSD volume on your Desktop and in Finder with custom drive icons, storage stats, and real-time drag-and-drop syncing.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)

                        if let dev = engine.selectedDevice, dev.status == .connected {
                            HStack {
                                Text("Active Volume: \(dev.mountPath ?? "Not mounted")")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Button("Reveal in Finder") {
                                    engine.openMountInFinder()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(8)
                }

                // 2. Android Debug Bridge (ADB) Configuration
                GroupBox(label: Label("ADB Platform Tools", systemImage: "terminal.fill")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle()
                                .fill(engine.isAdbAvailable ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(engine.isAdbAvailable ? "ADB Detected & Active" : "ADB Not Found")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Spacer()
                            Text(engine.adbPath ?? "No path configured")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 8) {
                            TextField("Custom ADB Path (e.g. /opt/homebrew/bin/adb)", text: $customAdbInput)
                                .textFieldStyle(.roundedBorder)

                            Button("Browse…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = true
                                panel.canChooseDirectories = false
                                panel.title = "Select adb Executable"
                                if panel.runModal() == .OK, let path = panel.url?.path {
                                    customAdbInput = path
                                    if engine.setCustomAdbPath(path) {
                                        adbStatusMessage = "ADB path verified successfully!"
                                    } else {
                                        adbStatusMessage = "File exists but is not a valid adb executable."
                                    }
                                }
                            }

                            Button("Apply") {
                                if engine.setCustomAdbPath(customAdbInput) {
                                    adbStatusMessage = "ADB path saved!"
                                } else {
                                    adbStatusMessage = "Invalid executable path."
                                }
                            }
                            .disabled(customAdbInput.isEmpty)
                        }

                        if let msg = adbStatusMessage {
                            Text(msg)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(engine.isAdbAvailable ? Color.green : Color.red)
                        }
                    }
                    .padding(8)
                }

                // 3. Connection Guidance
                GroupBox(label: Label("How to Connect Your Phone", systemImage: "info.circle")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("1.")
                                .font(.system(size: 11, weight: .bold))
                            Text("Connect your Android phone to this Mac using a USB-C or USB-A data cable.")
                                .font(.system(size: 11))
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("2.")
                                .font(.system(size: 11, weight: .bold))
                            Text("On your phone, pull down the notification shade and select 'File Transfer / Android Auto' (MTP mode).")
                                .font(.system(size: 11))
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("3.")
                                .font(.system(size: 11, weight: .bold))
                            Text("For maximum speed, enable Developer Options > USB Debugging. When prompted on your phone, tap 'Always allow from this computer'.")
                                .font(.system(size: 11))
                        }
                    }
                    .padding(8)
                }
            }
            .padding(20)
        }
    }
}
