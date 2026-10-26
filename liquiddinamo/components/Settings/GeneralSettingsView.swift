//
//  GeneralSettingsView.swift
//  LiquidDynamo
//
//  Native macOS General Settings Page featuring realistic MacBook notch preview,
//  preview state switcher, and responsive 6-card configuration grid.
//

import AppKit
import Defaults
import LaunchAtLogin
import SwiftUI

public struct GeneralSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var stats = SystemStatsService.shared
    @ObservedObject private var network = NetworkThroughputService.shared
    @ObservedObject private var devices = DeviceMonitor.shared

    // General & Behavior Preferences
    @Default(.lightingEffect) private var lightingEffect
    @Default(.compactMode) private var compactMode
    @Default(.waitInterval) private var waitInterval
    @Default(.enableHaptics) private var enableHaptics
    @Default(.openNotchOnHover) private var openNotchOnHover
    @Default(.openNotchOnDrag) private var openNotchOnDrag
    @Default(.minimumHoverDuration) private var minimumHoverDuration
    @Default(.enableGestures) private var enableGestures
    @Default(.islandAnimationSpeed) private var animationSpeed
    @Default(.nonNotchHeightMode) private var nonNotchHeightMode
    @Default(.wingWidth) private var wingWidth
    @Default(.autoFitWings) private var autoFitWings

    // Appearance Preferences
    @Default(.selectedLiquidTheme) private var selectedTheme
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData
    @Default(.dockIconStyle) private var dockIconStyle

    @State private var customColor: Color = .blue
    @State private var selectedPresetColor: String = "Blue"

    public init() {}

    private let presetColors: [(name: String, color: Color)] = [
        ("Blue", Color(red: 0.0, green: 0.478, blue: 1.0)),
        ("Purple", Color(red: 0.686, green: 0.322, blue: 0.871)),
        ("Pink", Color(red: 1.0, green: 0.176, blue: 0.333)),
        ("Orange", Color(red: 1.0, green: 0.584, blue: 0.0)),
        ("Green", Color(red: 0.20, green: 0.78, blue: 0.35)),
        ("Graphite", Color(red: 0.557, green: 0.557, blue: 0.576))
    ]

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                // Responsive 6-Card Settings Grid
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 250, maximum: 400), spacing: NativeSettingsTheme.gridSpacing)
                    ],
                    spacing: NativeSettingsTheme.gridSpacing
                ) {
                    cardQuickSettings
                    cardThemeAndAppearance
                    cardAnimation
                    cardNotchPreviewMode
                    cardQuickActions
                    cardSubsystemStatus
                }
            }
            .padding(.horizontal, NativeSettingsTheme.pagePadding)
            .padding(.vertical, 20)
        }
        .onAppear {
            if !stats.isRunning { stats.start() }
            if !network.isRunning { network.start() }
        }
    }

    // MARK: - 1. Header Section
    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("General")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Configure how LiquidDynamo behaves and presents dynamic elements on your Mac")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Active Island Status Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                    .shadow(color: Color.green.opacity(0.6), radius: 3)

                Text("Island Active")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(NativeSettingsTheme.cardBackground(colorScheme: colorScheme))
                    .overlay(
                        Capsule().strokeBorder(NativeSettingsTheme.cardBorder(colorScheme: colorScheme), lineWidth: 0.8)
                    )
            )
        }
    }


    // MARK: - Card A: Quick Settings
    private var cardQuickSettings: some View {
        NativeSettingsCard(
            title: "Quick Settings",
            subtitle: "System startup and primary notch behaviors",
            icon: "slider.horizontal.3",
            iconColor: .blue
        ) {
            VStack(spacing: 11) {
                NativeSettingsRow("Launch at Login", description: "Start LiquidDynamo automatically on boot", icon: "arrow.up.circle.fill") {
                    LaunchAtLogin.Toggle("")
                        .labelsHidden()
                }

                NativeSettingsRow("Show Notch Effects", description: "Subtle specular glow and edge highlights", icon: "sparkles") {
                    Toggle("", isOn: $lightingEffect)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                NativeSettingsRow("Compact Mode", description: "Collapse wings into ultra-thin indicators", icon: "arrow.right.and.line.vertical.and.arrow.left") {
                    Toggle("", isOn: $compactMode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                NativeSettingsRow("Event Duration", description: "Hold time for alerts before smooth collapse", icon: "timer") {
                    Picker("", selection: $waitInterval) {
                        Text("2s").tag(2.0)
                        Text("3s").tag(3.0)
                        Text("4s").tag(4.0)
                        Text("5s").tag(5.0)
                    }
                    .labelsHidden()
                    .frame(width: 72)
                }

                NativeSettingsRow("Haptic Feedback", description: "Provide trackpad feedback on interaction", icon: "waveform") {
                    Toggle("", isOn: $enableHaptics)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }

    // MARK: - Card B: Theme and Appearance
    private var cardThemeAndAppearance: some View {
        NativeSettingsCard(
            title: "Theme & Appearance",
            subtitle: "Visual styling and accent color customization",
            icon: "paintpalette.fill",
            iconColor: .purple
        ) {
            VStack(spacing: 12) {
                // Theme Picker
                NativeSettingsRow("Liquid Theme", description: "Shader refraction and color palette", icon: "circle.lefthalf.filled") {
                    Picker("", selection: $selectedTheme) {
                        ForEach(LiquidTheme.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }

                // Accent Presets
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent Color")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)

                    HStack(spacing: 10) {
                        ForEach(presetColors, id: \.name) { preset in
                            Button {
                                selectedPresetColor = preset.name
                                customColor = preset.color
                                saveCustomColor(preset.color)
                                Defaults[.useCustomAccentColor] = (preset.name != "Blue")
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(preset.color)
                                        .frame(width: 22, height: 22)

                                    if selectedPresetColor == preset.name {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        ColorPicker("", selection: Binding(
                            get: { customColor },
                            set: { newC in
                                customColor = newC
                                selectedPresetColor = "Custom"
                                saveCustomColor(newC)
                                Defaults[.useCustomAccentColor] = true
                            }
                        ), supportsOpacity: false)
                        .labelsHidden()
                    }
                }

                NativeSettingsRow("Dock Icon", description: "Appearance style in macOS Dock", icon: "app.badge") {
                    Picker("", selection: $dockIconStyle) {
                        Text("3D Liquid").tag(DockIconStyle.threeD)
                        Text("Flat Minimal").tag(DockIconStyle.flat)
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }
        }
    }

    // MARK: - Card C: Motion and Animation
    private var cardAnimation: some View {
        NativeSettingsCard(
            title: "Motion & Animation",
            subtitle: "Organic spring physics and interactive expansion",
            icon: "wind",
            iconColor: .cyan
        ) {
            VStack(spacing: 11) {
                NativeSettingsRow("Spring Physics", description: "Fluid organic spring dampening", icon: "circle.dotted.and.circle") {
                    Toggle("", isOn: $enableGestures)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                NativeSettingsRow("Expand on Hover", description: "Open dashboard when cursor pauses over notch", icon: "cursorarrow.rays") {
                    Toggle("", isOn: $openNotchOnHover)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if openNotchOnHover {
                    NativeSettingsRow("Hover Delay", description: "Pause duration required to trigger opening", icon: "clock") {
                        HStack(spacing: 4) {
                            Slider(value: $minimumHoverDuration, in: 0.1...1.0, step: 0.1)
                                .frame(width: 65)
                            Text("\(minimumHoverDuration, specifier: "%.1f")s")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                NativeSettingsRow("Open on Drag", description: "Expand island when dragging files over notch", icon: "hand.draw") {
                    Toggle("", isOn: $openNotchOnDrag)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                NativeSettingsRow("Animation Speed", description: "Fluid transition rate multiplier", icon: "speedometer") {
                    HStack(spacing: 4) {
                        Slider(value: $animationSpeed, in: 0.5...2.0, step: 0.25)
                            .frame(width: 65)
                        Text("\(animationSpeed, specifier: "%.1f")x")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Card D: Notch Mode and Geometry
    private var cardNotchPreviewMode: some View {
        NativeSettingsCard(
            title: "Notch & Geometry",
            subtitle: "Physical hardware alignment and external display handling",
            icon: "display",
            iconColor: .indigo
        ) {
            VStack(spacing: 11) {
                NativeSettingsRow("Auto-Fit Wings", description: "Dynamically fit wing widths to content", icon: "arrow.left.and.right") {
                    Toggle("", isOn: $autoFitWings)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                NativeSettingsRow(autoFitWings ? "Min Wing Width" : "Wing Width", description: "Base width floor for stream readouts", icon: "ruler") {
                    HStack(spacing: 4) {
                        Slider(value: $wingWidth, in: 50...160, step: 2)
                            .frame(width: 65)
                        Text("\(Int(wingWidth))pt")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                NativeSettingsRow("Non-Notch Displays", description: "Behavior on external monitors without a cutout", icon: "display.2") {
                    Picker("", selection: $nonNotchHeightMode) {
                        Text("Menu Bar").tag(WindowHeightMode.matchMenuBar)
                        Text("Simulate Notch").tag(WindowHeightMode.matchRealNotchSize)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }
        }
    }

    // MARK: - Card E: Quick Actions
    private var cardQuickActions: some View {
        NativeSettingsCard(
            title: "Quick Actions",
            subtitle: "Simulate and preview live event triggers",
            icon: "bolt.fill",
            iconColor: .orange
        ) {
            VStack(spacing: 9) {
                testActionButton("Test Volume HUD", icon: "speaker.wave.2.fill") {
                    LiveActivitySimulator.shared.fireRapidVolumeSweep()
                }

                testActionButton("Test Media Track HUD", icon: "music.note") {
                    DynamicIslandHub.shared.triggerTrackChangeAnnouncement(title: "Starboy", artist: "The Weeknd")
                }

                testActionButton("Test Calendar Notification", icon: "calendar") {
                    LiveActivitySimulator.shared.fireUpcomingCalendarEvent()
                }

                testActionButton("Test Device Connection", icon: "airpodspro") {
                    LiveActivitySimulator.shared.fireBluetoothConnect()
                }
            }
        }
    }

    private func testActionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.effectiveAccent)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card F: Subsystem Status
    private var cardSubsystemStatus: some View {
        let isAccessibilityGranted = AXIsProcessTrusted()

        return NativeSettingsCard(
            title: "Subsystem Status",
            subtitle: "Real-time health of LiquidDynamo modules",
            icon: "waveform.path.ecg",
            iconColor: .green
        ) {
            VStack(spacing: 10) {
                statusRow(
                    label: "Accessibility",
                    status: isAccessibilityGranted ? "Granted" : "Needs Permission",
                    isGood: isAccessibilityGranted
                )

                statusRow(
                    label: "Media Controller",
                    status: Defaults[.mediaController].rawValue.capitalized,
                    isGood: true
                )

                statusRow(
                    label: "System Telemetry",
                    status: stats.isRunning ? "Active" : "Idle",
                    isGood: stats.isRunning
                )

                statusRow(
                    label: "Network Monitor",
                    status: network.isRunning ? "Active" : "Idle",
                    isGood: network.isRunning
                )

                statusRow(
                    label: "Notch Window",
                    status: "Centered",
                    isGood: true
                )
            }
        }
    }

    private func statusRow(label: String, status: String, isGood: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(isGood ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)

                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Helpers
    private func saveCustomColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            Defaults[.customAccentColorData] = data
            NotificationCenter.default.post(name: NSNotification.Name("AccentColorChanged"), object: nil)
        }
    }
}
