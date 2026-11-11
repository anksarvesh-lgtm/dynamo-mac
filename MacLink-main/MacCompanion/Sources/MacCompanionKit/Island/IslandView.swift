// SPDX-License-Identifier: MIT
import SwiftUI

@MainActor
public final class IslandViewModel: ObservableObject {
    @Published public var customHours: Int = 1
    @Published public var customMinutes: Int = 0
    @Published public var customError: String? = nil
    public init() {}
}

public struct IslandView: View {
    @ObservedObject public var state: AppState
    @ObservedObject private var islandService = IslandService.shared
    @ObservedObject private var keepAwake = KeepAwakeManager.shared
    @StateObject private var vm = IslandViewModel()

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28))
                        .foregroundColor(.accentColor)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.12))
                        .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("MacLink Island")
                            .font(.title2.bold())
                        Text("Top-of-screen dynamic notch overlay with Keep Awake and Connected Devices.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 4)

                // Master Toggle Card
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $islandService.isIslandEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Dynamic Island Overlay")
                                .font(.headline)
                            Text("Displays floating activity pill at top of screen. Ships OFF by default.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)

                if islandService.isIslandEnabled {
                    // Keep Awake Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label("Keep Awake", systemImage: "bolt.shield")
                                .font(.headline)
                            Spacer()
                            if keepAwake.isActive {
                                Text("ACTIVE · \(keepAwake.remainingFormatted)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundColor(.green)
                                    .cornerRadius(6)
                            } else {
                                Text("IDLE")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.12))
                                    .foregroundColor(.secondary)
                                    .cornerRadius(6)
                            }
                        }

                        // Mode Picker
                        Picker("Mode", selection: Binding(
                            get: { keepAwake.mode },
                            set: { keepAwake.changeMode(to: $0) }
                        )) {
                            ForEach(KeepAwakeMode.allCases) { mode in
                                Text(mode.shortTitle).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(keepAwake.mode.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Duration Presets
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick Presets")
                                .font(.subheadline.bold())

                            HStack(spacing: 8) {
                                ForEach(KeepAwakePreset.allCases, id: \.rawValue) { preset in
                                    Button(action: {
                                        keepAwake.start(mode: keepAwake.mode, duration: .preset(preset))
                                    }) {
                                        Text(preset.title)
                                            .font(.caption)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                            .background(Color.secondary.opacity(0.12))
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Actions: Extend / Stop
                        if keepAwake.isActive {
                            HStack(spacing: 12) {
                                Button(action: {
                                    keepAwake.extend(by: 15 * 60)
                                }) {
                                    Label("Extend +15m", systemImage: "plus.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                Button(action: {
                                    keepAwake.stop()
                                }) {
                                    Label("Stop", systemImage: "stop.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }

                        // Clamshell notice
                        Text(KeepAwakeManager.clamshellNote)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color.yellow.opacity(0.08))
                            .cornerRadius(6)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)

                    // Connected Devices Card (Slot 1)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Connected Devices (Slot 1)", systemImage: "iphone.and.arrow.forward")
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: $islandService.devicesSlot1Enabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        Text("Always appears first in the expanded island whenever at least one device is connected. Completely collapses to zero height when no devices are connected.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if state.isConnected, let deviceName = state.connectedDeviceName {
                            HStack {
                                Image(systemName: "iphone")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading) {
                                    Text(deviceName).font(.subheadline.bold())
                                    Text("Wi-Fi Direct · \(state.latencyMs)ms latency").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("Online")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundColor(.green)
                                    .cornerRadius(4)
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(6)
                        } else {
                            Text("No devices connected. Slot 1 is collapsed.")
                                .font(.caption.italic())
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)

                    // Clipboard History Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Clipboard History", systemImage: "doc.on.clipboard")
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: $islandService.clipboardHistoryEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        Text("Surfaces recent copied items in compact rows. Skips passwords, ConcealedType, and sensitive markers.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
            }
            .padding(24)
        }
        .navigationTitle("Island")
    }
}
