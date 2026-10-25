//
//  BehaviorSettingsView.swift
//  LiquidDynamo
//
//  Behavior Section: hover vs click, displays, system OSD popup overrides,
//  shortcuts, and launch at login.
//

import AppKit
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

public struct BehaviorSettingsView: View {
    @ObservedObject var coordinator = LiquidViewCoordinator.shared
    @ObservedObject var interceptor = MediaKeyInterceptor.shared

    @Default(.openNotchOnHover) private var openNotchOnHover
    @Default(.openNotchOnDrag) private var openNotchOnDrag
    @Default(.minimumHoverDuration) private var minimumHoverDuration
    @Default(.nonNotchHeightMode) private var nonNotchHeightMode
    @Default(.nonNotchHeight) private var nonNotchHeight
    @Default(.hideSystemOSD) private var hideSystemOSD
    @Default(.enableHaptics) private var enableHaptics
    @Default(.extendHoverArea) private var extendHoverArea
    @Default(.showOnLockScreen) private var showOnLockScreen
    @Default(.hideFromScreenRecording) private var hideFromScreenRecording
    @Default(.showLayoutGuides) private var showLayoutGuides

    @State private var showMoreOptions: Bool = false

    public init() {}

    public var body: some View {
        Form {
            Section {
                Toggle("Open on hover", isOn: $openNotchOnHover)
                    .onChange(of: openNotchOnHover) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }

                if openNotchOnHover {
                    HStack {
                        Text("Hover delay")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $minimumHoverDuration, in: 0.0...1.0, step: 0.1)
                } else {
                    Text("When hover is off, click the notch, press the keyboard shortcut, or click the menu bar icon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Open on dragging file over notch", isOn: $openNotchOnDrag)
                Text("Dragging a file over the notch area opens the island so the dropper can immediately accept the drop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LaunchAtLogin.Toggle("Launch at login")
            } header: {
                Text("Interaction & Startup")
            }

            Section {
                Picker("Macs without a physical notch", selection: $nonNotchHeightMode) {
                    Text("Match menu bar height").tag(WindowHeightMode.matchMenuBar)
                    Text("Match standard notch size").tag(WindowHeightMode.matchRealNotchSize)
                }
                .onChange(of: nonNotchHeightMode) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
            } header: {
                Text("Displays")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hide default macOS volume and brightness popups")
                                .font(.headline)
                            Text("Replaces macOS center square bezels with fluid notch droplets.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { hideSystemOSD },
                            set: { val in
                                hideSystemOSD = val
                                Defaults[.hudReplacement] = val
                                Task {
                                    if val {
                                        await interceptor.start(promptIfNeeded: true)
                                    } else {
                                        interceptor.stop()
                                    }
                                }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }
            } header: {
                Text("System Popup Overrides")
            }

            Section {
                KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
                KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek)
            } header: {
                Text("Keyboard Shortcuts")
            }

            Section {
                DisclosureGroup("More options", isExpanded: $showMoreOptions) {
                    VStack(alignment: .leading, spacing: 12) {
                        Defaults.Toggle("Haptic feedback on interaction", key: .enableHaptics)
                        Defaults.Toggle("Extend cursor hover hit area", key: .extendHoverArea)
                        Defaults.Toggle("Show notch on lock screen", key: .showOnLockScreen)
                        Defaults.Toggle("Hide notch during screen recording", key: .hideFromScreenRecording)
                        #if DEBUG
                        Defaults.Toggle("Show notch layout guides (Debug)", key: .showLayoutGuides)
                        #endif
                    }
                    .padding(.vertical, 6)
                }
            } header: {
                Text("Advanced Behavior")
            }

            Section {
                Button("Reset this section to defaults", role: .destructive) {
                    resetSection()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
    }

    public func resetSection() {
        Defaults[.openNotchOnHover] = true
        Defaults[.openNotchOnDrag] = true
        Defaults[.minimumHoverDuration] = 0.3
        Defaults[.showOnAllDisplays] = true
        Defaults[.automaticallySwitchDisplay] = true
        Defaults[.nonNotchHeightMode] = .matchMenuBar
        Defaults[.enableHaptics] = true
        Defaults[.extendHoverArea] = false
        Defaults[.showOnLockScreen] = false
        Defaults[.hideFromScreenRecording] = false
        Defaults[.showLayoutGuides] = false
        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
    }
}
