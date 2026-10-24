//
//  LookSettingsView.swift
//  LiquidDynamo
//
//  Look Section: transparency, liquid intensity, collapse style,
//  accent colour, and wing width with live preview in the notch.
//

import AppKit
import Defaults
import SwiftUI

public struct LookSettingsView: View {
    @Default(.islandTransparency) private var islandTransparency
    @Default(.waterIntensity) private var waterIntensity
    @Default(.waterSagAmount) private var waterSagAmount
    @Default(.compactMode) private var compactMode
    @Default(.wingWidth) private var wingWidth
    @Default(.autoFitWings) private var autoFitWings
    @Default(.leftWingMetric) private var leftWingMetric
    @Default(.rightWingMetric) private var rightWingMetric
    @Default(.hideWingsInFullScreen) private var hideWingsInFullScreen
    @Default(.wingsBuiltInDisplayOnly) private var wingsBuiltInDisplayOnly
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @Default(.customAccentColorData) private var customAccentColorData
    @Default(.enableWindowTransparency) private var enableWindowTransparency
    @Default(.enableShadow) private var enableShadow

    @State private var customColor: Color = .accentColor
    @State private var selectedPresetColor: PresetColor? = nil
    @State private var showMoreOptions: Bool = false

    public init() {}

    public enum PresetColor: String, CaseIterable, Identifiable {
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case red = "Red"
        case orange = "Orange"
        case yellow = "Yellow"
        case green = "Green"
        case graphite = "Graphite"

        public var id: String { rawValue }

        public var color: Color {
            switch self {
            case .blue: return Color(red: 0.0, green: 0.478, blue: 1.0)
            case .purple: return Color(red: 0.686, green: 0.322, blue: 0.871)
            case .pink: return Color(red: 1.0, green: 0.176, blue: 0.333)
            case .red: return Color(red: 1.0, green: 0.271, blue: 0.227)
            case .orange: return Color(red: 1.0, green: 0.584, blue: 0.0)
            case .yellow: return Color(red: 1.0, green: 0.8, blue: 0.0)
            case .green: return Color(red: 0.4, green: 0.824, blue: 0.176)
            case .graphite: return Color(red: 0.557, green: 0.557, blue: 0.576)
            }
        }
    }

    public var body: some View {
        Form {
            Section {
                MockNotchWingsPreview(
                    leftMetric: leftWingMetric,
                    rightMetric: rightWingMetric,
                    wingWidth: wingWidth,
                    autoFit: autoFitWings
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

                // MARK: 2.1 Left Wing Content Selector
                VStack(alignment: .leading, spacing: 4) {
                    Text("Left Wing Content")
                        .font(.headline)
                    Picker("Left Wing Content", selection: $leftWingMetric) {
                        ForEach(WingMetric.selectableCases) { metric in
                            Label(metric.displayName, systemImage: metric.iconName)
                                .tag(metric)
                        }
                    }
                    .labelsHidden()
                }
                .onChange(of: leftWingMetric) {
                    triggerLivePreview()
                }

                // MARK: 2.2 Right Wing Content Selector
                VStack(alignment: .leading, spacing: 4) {
                    Text("Right Wing Content")
                        .font(.headline)
                    Picker("Right Wing Content", selection: $rightWingMetric) {
                        ForEach(WingMetric.selectableCases) { metric in
                            Label(metric.displayName, systemImage: metric.iconName)
                                .tag(metric)
                        }
                    }
                    .labelsHidden()
                }
                .onChange(of: rightWingMetric) {
                    triggerLivePreview()
                }

                Defaults.Toggle("Auto-fit wing widths to content", key: .autoFitWings)
                    .onChange(of: autoFitWings) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                        triggerLivePreview()
                    }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(autoFitWings ? "Minimum Wing Width" : "Wing Width")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(wingWidth)) pt")
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $wingWidth, in: 50...160, step: 2) {
                        Text("Wing Width")
                    } minimumValueLabel: {
                        Text("50 pt")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } maximumValueLabel: {
                        Text("160 pt")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .onChange(of: wingWidth) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                        triggerLivePreview()
                    }

                    Text(autoFitWings
                         ? "Minimum width floor. Each wing dynamically expands to accommodate its selected content without clipping."
                         : "Fixed width of the left and right informational streams flanking the notch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Defaults.Toggle("Hide Wings in Full Screen", key: .hideWingsInFullScreen)
                Defaults.Toggle("Built-in Display Only", key: .wingsBuiltInDisplayOnly)
            } header: {
                Text("Notch Wings & Slots")
            } footer: {
                Text("Live telemetry and control streams flanking the notch. Each wing operates and auto-fits independently. Set a slot to 'None' to collapse that side cleanly.")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Liquid Transparency")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(islandTransparency * 100))%")
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $islandTransparency, in: 0.0...1.0) {
                        Text("Transparency")
                    } minimumValueLabel: {
                        Text("Solid")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } maximumValueLabel: {
                        Text("Clear")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .onChange(of: islandTransparency) {
                        triggerLivePreview()
                    }

                    Text("Apple obsidian glass body with seamless notch junction integration and specular highlights.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Picker("Collapse Style", selection: $compactMode) {
                    Text("Balanced Wings").tag(false)
                    Text("Compact Streams").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: compactMode) {
                    triggerLivePreview()
                }
            } header: {
                Text("Liquid Appearance")
            }

            Section {
                Picker("Accent Mode", selection: $useCustomAccentColor) {
                    Text("macOS System").tag(false)
                    Text("Custom Color").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: useCustomAccentColor) {
                    broadcastAccentColorChange()
                }

                if useCustomAccentColor {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Color Presets")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            ForEach(PresetColor.allCases) { preset in
                                Button {
                                    selectedPresetColor = preset
                                    customColor = preset.color
                                    saveCustomColor(preset.color)
                                    broadcastAccentColorChange()
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(preset.color)
                                            .frame(width: 24, height: 24)

                                        if selectedPresetColor == preset {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Divider()

                        HStack {
                            Text("Pick Custom Hue")
                                .font(.subheadline)
                            Spacer()
                            ColorPicker("", selection: Binding(
                                get: { customColor },
                                set: { newC in
                                    customColor = newC
                                    selectedPresetColor = nil
                                    saveCustomColor(newC)
                                    broadcastAccentColorChange()
                                }
                            ), supportsOpacity: false)
                            .labelsHidden()
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Accent Colour")
            }

            Section {
                DisclosureGroup("More options", isExpanded: $showMoreOptions) {
                    VStack(alignment: .leading, spacing: 14) {
                        Defaults.Toggle(
                            "Window Transparency (Settings & First-Run)",
                            key: .enableWindowTransparency
                        )
                        .onChange(of: enableWindowTransparency) {
                            SettingsWindowController.shared.updateWindowTransparency()
                        }

                        Defaults.Toggle("Window Shadow", key: .enableShadow)
                    }
                    .padding(.vertical, 6)
                }
            } header: {
                Text("Advanced Appearance")
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
        .onAppear {
            loadCustomColor()
        }
    }

    public func resetSection() {
        Defaults[.islandTransparency] = 0.35
        Defaults[.waterIntensity] = 0.5
        Defaults[.leftWingMetric] = .cpuUsage
        Defaults[.rightWingMetric] = .netDownUp
        Defaults[.wingWidth] = 68.0
        Defaults[.hideWingsInFullScreen] = true
        Defaults[.wingsBuiltInDisplayOnly] = true
        Defaults[.compactMode] = false
        Defaults[.useCustomAccentColor] = false
        Defaults[.waterSagAmount] = 12.0
        Defaults[.enableShadow] = true
        broadcastAccentColorChange()
        triggerLivePreview()
    }

    private func triggerLivePreview() {
        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
    }

    private func broadcastAccentColorChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("AccentColorChanged"), object: nil)
        }
    }

    private func saveCustomColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            Defaults[.customAccentColorData] = data
        }
    }

    private func loadCustomColor() {
        if let data = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            customColor = Color(nsColor: nsColor)
            for preset in PresetColor.allCases {
                if isCloseTo(customColor, preset.color) {
                    selectedPresetColor = preset
                    break
                }
            }
        }
    }

    private func isCloseTo(_ c1: Color, _ c2: Color) -> Bool {
        let n1 = NSColor(c1).usingColorSpace(.sRGB) ?? NSColor(c1)
        let n2 = NSColor(c2).usingColorSpace(.sRGB) ?? NSColor(c2)
        return abs(n1.redComponent - n2.redComponent) < 0.02 &&
               abs(n1.greenComponent - n2.greenComponent) < 0.02 &&
               abs(n1.blueComponent - n2.blueComponent) < 0.02
    }
}

public struct MockNotchWingsPreview: View {
    let leftMetric: WingMetric
    let rightMetric: WingMetric
    let wingWidth: CGFloat
    let autoFit: Bool

    public init(leftMetric: WingMetric, rightMetric: WingMetric, wingWidth: CGFloat, autoFit: Bool = true) {
        self.leftMetric = leftMetric
        self.rightMetric = rightMetric
        self.wingWidth = wingWidth
        self.autoFit = autoFit
    }

    public var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                // Background simulated screen bar
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.14, blue: 0.20),
                                Color(red: 0.08, green: 0.09, blue: 0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .frame(height: 64)

                // Mock display bezel line with camera & notch
                HStack(alignment: .top, spacing: 0) {
                    Spacer(minLength: 0)

                    // Left wing pill (if active)
                    if leftMetric != .none {
                        mockWingContent(for: leftMetric)
                            .padding(.horizontal, 6)
                            .frame(width: mockWidth(for: leftMetric), height: 24)
                            .background(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 0,
                                    bottomLeadingRadius: 10,
                                    bottomTrailingRadius: 6,
                                    topTrailingRadius: 0
                                )
                                .fill(Color.black.opacity(0.85))
                                .overlay(
                                    UnevenRoundedRectangle(
                                        topLeadingRadius: 0,
                                        bottomLeadingRadius: 10,
                                        bottomTrailingRadius: 6,
                                        topTrailingRadius: 0
                                    )
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                )
                            )
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }

                    // Hardware Notch Cutout
                    ZStack {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 8,
                            bottomTrailingRadius: 8,
                            topTrailingRadius: 0
                        )
                        .fill(Color.black)
                        .frame(width: 110, height: 24)

                        // Camera lens + mic hole
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(red: 0.05, green: 0.15, blue: 0.25))
                                .frame(width: 5, height: 5)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                                )
                            Circle()
                                .fill(Color.black)
                                .frame(width: 2, height: 2)
                        }
                    }

                    // Right wing pill (if active)
                    if rightMetric != .none {
                        mockWingContent(for: rightMetric)
                            .padding(.horizontal, 6)
                            .frame(width: mockWidth(for: rightMetric), height: 24)
                            .background(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 0,
                                    bottomLeadingRadius: 6,
                                    bottomTrailingRadius: 10,
                                    topTrailingRadius: 0
                                )
                                .fill(Color.black.opacity(0.85))
                                .overlay(
                                    UnevenRoundedRectangle(
                                        topLeadingRadius: 0,
                                        bottomLeadingRadius: 6,
                                        bottomTrailingRadius: 10,
                                        topTrailingRadius: 0
                                    )
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                )
                            )
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }

                    Spacer(minLength: 0)
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: leftMetric)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: rightMetric)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: wingWidth)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: autoFit)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Live Preview")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func mockWingContent(for metric: WingMetric) -> some View {
        switch metric {
        case .mediaPlayback:
            HStack(spacing: 5) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                Image(systemName: "forward.fill")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        default:
            HStack(spacing: 4) {
                Image(systemName: metric.iconName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(mockText(for: metric))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
    }

    private func mockWidth(for metric: WingMetric) -> CGFloat {
        let base = max(46, min(wingWidth * 0.75, 140))
        guard autoFit else { return base }
        switch metric {
        case .mediaPlayback:
            return max(base, 64)
        case .mediaTitle:
            return max(base, 118)
        case .ramDetails:
            return max(base, 108)
        case .netDown, .netUp:
            return max(base, 80)
        case .cpuTemp:
            return max(base, 58)
        default:
            return base
        }
    }

    private func mockText(for metric: WingMetric) -> String {
        switch metric {
        case .none: return ""
        case .cpuUsage: return "18%"
        case .cpuTemp: return "44°C"
        case .ramUsage: return "11.2G"
        case .ramDetails: return "11.2 / 16 GB"
        case .netDown: return "↓ 12.4M"
        case .netUp: return "↑ 3.2M"
        case .netDownUp: return "13.4M"
        case .battery: return "94%"
        case .bluetoothBattery: return "88%"
        case .volume: return "75%"
        case .brightness: return "80%"
        case .clock: return "09:41"
        case .weather: return "21°C"
        case .mediaPlayback: return ""
        case .mediaTitle: return "Starboy - Weeknd"
        }
    }
}

