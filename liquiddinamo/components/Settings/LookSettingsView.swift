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

    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notch & Wings")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("Configure live telemetry streams flanking the physical notch with independent left/right selection and content-aware sizing")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                // 1. Live Notch Preview Card
                NativeSettingsCard(
                    title: "Live Notch Preview",
                    subtitle: "Real-time preview of the left and right informational streams",
                    icon: "sparkles.rectangle.stack.fill",
                    iconColor: .blue
                ) {
                    MockNotchWingsPreview(
                        leftMetric: leftWingMetric,
                        rightMetric: rightWingMetric,
                        wingWidth: wingWidth,
                        autoFit: autoFitWings
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }

                // 2. Independent Left & Right Wing Content Card
                NativeSettingsCard(
                    title: "Wing Content Selection",
                    subtitle: "Assign telemetry indicators independently to each side of the notch",
                    icon: "arrow.left.and.right.square.fill",
                    iconColor: .indigo
                ) {
                    VStack(spacing: 14) {
                        // Left Wing Selector
                        HStack(alignment: .center, spacing: 12) {
                            Label("Left Wing", systemImage: "arrow.left.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 100, alignment: .leading)

                            Spacer()

                            Picker("Left Wing Content", selection: $leftWingMetric) {
                                ForEach(WingMetric.selectableCases) { metric in
                                    Label(metric.displayName, systemImage: metric.iconName)
                                        .tag(metric)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 240)
                            .onChange(of: leftWingMetric) {
                                triggerLivePreview()
                            }
                        }

                        Divider().opacity(colorScheme == .dark ? 0.2 : 0.1)

                        // Right Wing Selector
                        HStack(alignment: .center, spacing: 12) {
                            Label("Right Wing", systemImage: "arrow.right.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 100, alignment: .leading)

                            Spacer()

                            Picker("Right Wing Content", selection: $rightWingMetric) {
                                ForEach(WingMetric.selectableCases) { metric in
                                    Label(metric.displayName, systemImage: metric.iconName)
                                        .tag(metric)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 240)
                            .onChange(of: rightWingMetric) {
                                triggerLivePreview()
                            }
                        }
                    }
                }

                // 3. Layout & Behaviour Settings Card
                NativeSettingsCard(
                    title: "Layout & Behavior",
                    subtitle: "Content-aware width expansion and display visibility",
                    icon: "slider.horizontal.2.square.on.square",
                    iconColor: .cyan
                ) {
                    VStack(spacing: 12) {
                        NativeSettingsRow(
                            "Auto-Fit Wings",
                            description: "Dynamically expand each wing to fit its rendered metric without clipping",
                            icon: "arrow.left.and.right"
                        ) {
                            Defaults.Toggle("", key: .autoFitWings)
                                .labelsHidden()
                                .onChange(of: autoFitWings) {
                                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                                    triggerLivePreview()
                                }
                        }

                        NativeSettingsRow(
                            autoFitWings ? "Minimum Wing Width" : "Wing Width",
                            description: autoFitWings ? "Base floor width for each stream" : "Fixed width flanking the notch",
                            icon: "ruler"
                        ) {
                            HStack(spacing: 6) {
                                Slider(value: $wingWidth, in: 50...160, step: 2)
                                    .frame(width: 90)
                                    .onChange(of: wingWidth) {
                                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                                        triggerLivePreview()
                                    }

                                Text("\(Int(wingWidth)) pt")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }

                        NativeSettingsRow(
                            "Hide in Full Screen",
                            description: "Automatically collapse wings when another application is full screen",
                            icon: "arrow.up.left.and.arrow.down.right"
                        ) {
                            Defaults.Toggle("", key: .hideWingsInFullScreen)
                                .labelsHidden()
                        }

                        NativeSettingsRow(
                            "Built-in Display Only",
                            description: "Show wings exclusively around the physical MacBook notch",
                            icon: "laptopcomputer"
                        ) {
                            Defaults.Toggle("", key: .wingsBuiltInDisplayOnly)
                                .labelsHidden()
                        }
                    }
                }

                // 4. Available Wing Items Showcase
                NativeSettingsCard(
                    title: "Available Wing Metrics",
                    subtitle: "Telemetry and controls supported by the Dynamic Island engine",
                    icon: "chart.bar.xaxis",
                    iconColor: .purple
                ) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                        ForEach(WingMetric.selectableCases) { metric in
                            HStack(spacing: 6) {
                                Image(systemName: metric.iconName)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle((leftWingMetric == metric || rightWingMetric == metric) ? Color.effectiveAccent : .secondary)

                                Text(metric.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle((leftWingMetric == metric || rightWingMetric == metric) ? .primary : .secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill((leftWingMetric == metric || rightWingMetric == metric) ? Color.effectiveAccent.opacity(0.12) : Color.primary.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder((leftWingMetric == metric || rightWingMetric == metric) ? Color.effectiveAccent.opacity(0.3) : Color.clear, lineWidth: 0.8)
                                    )
                            )
                        }
                    }
                }

                // 5. Liquid Appearance & Accent Card
                NativeSettingsCard(
                    title: "Liquid Appearance",
                    subtitle: "Surface opacity, collapse modes, and accent styling",
                    icon: "drop.fill",
                    iconColor: .blue
                ) {
                    VStack(spacing: 12) {
                        NativeSettingsRow("Liquid Transparency", description: "Glass body translucency and optical blur", icon: "circle.lefthalf.filled") {
                            HStack(spacing: 6) {
                                Slider(value: $islandTransparency, in: 0.0...1.0)
                                    .frame(width: 90)
                                    .onChange(of: islandTransparency) {
                                        triggerLivePreview()
                                    }

                                Text("\(Int(islandTransparency * 100))%")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }

                        NativeSettingsRow("Collapse Style", description: "Stream layout when island is collapsed", icon: "rectangle.compress.vertical") {
                            Picker("", selection: $compactMode) {
                                Text("Balanced").tag(false)
                                Text("Compact").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                            .onChange(of: compactMode) {
                                triggerLivePreview()
                            }
                        }

                        NativeSettingsRow("Window Transparency", description: "Enable translucent frosted-glass materials", icon: "macwindow") {
                            Defaults.Toggle("", key: .enableWindowTransparency)
                                .labelsHidden()
                                .onChange(of: enableWindowTransparency) {
                                    SettingsWindowController.shared.updateWindowTransparency()
                                }
                        }
                    }
                }

                // Reset Button
                HStack {
                    Spacer()
                    Button("Reset Section to Defaults", role: .destructive) {
                        resetSection()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.vertical, 8)
                    Spacer()
                }
            }
            .padding(.horizontal, NativeSettingsTheme.pagePadding)
            .padding(.vertical, 20)
        }
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

