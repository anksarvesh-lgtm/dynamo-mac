//
//  LookSettingsView.swift
//  LiquidDynamo
//
//  Notch & Wings settings view redesigned to match the reference UI:
//  Dark translucent frosted-glass surfaces, photorealistic notch previews,
//  independent Left & Right Wing Content cards, Layout & Behavior controls,
//  and 4x3 Available Wing Items grid.
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

    // Reference wing detail toggles
    @Default(.leftWingShowLabel) private var leftWingShowLabel
    @Default(.leftWingShowPercentage) private var leftWingShowPercentage
    @Default(.leftWingShowMiniGraph) private var leftWingShowMiniGraph
    @Default(.rightWingShowIcon) private var rightWingShowIcon
    @Default(.rightWingShowTemperature) private var rightWingShowTemperature
    @Default(.rightWingShowCondition) private var rightWingShowCondition
    @Default(.showWingSeparators) private var showWingSeparators

    @State private var showAdvancedOptions: Bool = false

    public init() {}

    private struct WingItemChip: Identifiable {
        let id: String
        let title: String
        let icon: String
        let iconColor: Color
        let metric: WingMetric
    }

    private let availableChips: [WingItemChip] = [
        WingItemChip(id: "cpuUsage", title: "CPU Usage", icon: "waveform.path.ecg", iconColor: .cyan, metric: .cpuUsage),
        WingItemChip(id: "cpuTemp", title: "CPU Temperature", icon: "thermometer.medium", iconColor: Color(red: 1.0, green: 0.38, blue: 0.38), metric: .cpuTemp),
        WingItemChip(id: "ramUsage", title: "RAM Usage", icon: "memorychip", iconColor: Color(red: 0.72, green: 0.45, blue: 1.0), metric: .ramUsage),
        WingItemChip(id: "netDownUp", title: "Network Speed", icon: "arrow.up.arrow.down", iconColor: Color(red: 0.35, green: 0.88, blue: 0.55), metric: .netDownUp),

        WingItemChip(id: "weather", title: "Weather Temperature", icon: "cloud.sun.fill", iconColor: Color(red: 1.0, green: 0.85, blue: 0.2), metric: .weather),
        WingItemChip(id: "battery", title: "Battery Status", icon: "battery.100", iconColor: Color(red: 0.35, green: 0.88, blue: 0.55), metric: .battery),
        WingItemChip(id: "bluetoothBattery", title: "Bluetooth Devices", icon: "antenna.radiowaves.left.and.right", iconColor: Color(red: 0.3, green: 0.65, blue: 1.0), metric: .bluetoothBattery),
        WingItemChip(id: "volume", title: "Volume", icon: "speaker.wave.2.fill", iconColor: .cyan, metric: .volume),

        WingItemChip(id: "mediaPlayback", title: "Media Controls", icon: "playpause.fill", iconColor: Color(red: 1.0, green: 0.42, blue: 0.38), metric: .mediaPlayback),
        WingItemChip(id: "brightness", title: "Brightness", icon: "sun.max.fill", iconColor: Color(red: 0.35, green: 0.75, blue: 1.0), metric: .brightness),
        WingItemChip(id: "clock", title: "Clock", icon: "clock.fill", iconColor: Color(red: 0.25, green: 0.85, blue: 0.75), metric: .clock),
        WingItemChip(id: "focusMode", title: "Focus Mode", icon: "moon.fill", iconColor: Color(red: 0.75, green: 0.45, blue: 0.95), metric: .clock)
    ]

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // Top Header: Page Title + Top-Right Photorealistic Notch Preview Capsule
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Notch & Wings")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)

                        Text("Customize what shows around your notch.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color(red: 0.55, green: 0.60, blue: 0.68))
                    }

                    Spacer(minLength: 12)

                    // Top-Right Header Notch Preview Capsule
                    ReferenceNotchCapsule(
                        leftMetric: leftWingMetric,
                        rightMetric: rightWingMetric,
                        wingWidth: wingWidth,
                        autoFit: autoFitWings
                    )
                    .frame(width: 320)
                }
                .padding(.bottom, 2)

                // Row 1: Left Wing Content & Right Wing Content Cards
                HStack(alignment: .top, spacing: 16) {
                    // Left Wing Content Card
                    ReferenceSettingsCard(
                        title: "Left Wing Content",
                        subtitle: "Choose what to show on the left side."
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            // Dropdown Pill Selector
                            ReferencePillPicker(
                                selection: $leftWingMetric,
                                items: WingMetric.selectableCases,
                                titleFor: { $0.displayName },
                                iconFor: { $0 == .cpuUsage ? "waveform.path.ecg" : $0.iconName },
                                iconColorFor: { _ in .cyan },
                                onSelect: { triggerLivePreview() }
                            )

                            VStack(spacing: 11) {
                                ReferenceToggleRow(
                                    symbol: "Aa",
                                    isTextSymbol: true,
                                    symbolColor: .white.opacity(0.7),
                                    title: "Show label",
                                    isOn: $leftWingShowLabel
                                )

                                ReferenceToggleRow(
                                    symbol: "%",
                                    isTextSymbol: true,
                                    symbolColor: .white.opacity(0.7),
                                    title: "Show percentage",
                                    isOn: $leftWingShowPercentage
                                )

                                ReferenceToggleRow(
                                    symbol: "chart.bar.fill",
                                    isTextSymbol: false,
                                    symbolColor: .white.opacity(0.7),
                                    title: "Show mini graph",
                                    isOn: $leftWingShowMiniGraph
                                )
                            }
                        }
                    }

                    // Right Wing Content Card
                    ReferenceSettingsCard(
                        title: "Right Wing Content",
                        subtitle: "Choose what to show on the right side."
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            // Dropdown Pill Selector
                            ReferencePillPicker(
                                selection: $rightWingMetric,
                                items: WingMetric.selectableCases,
                                titleFor: { $0.displayName },
                                iconFor: { $0 == .weather ? "cloud.sun.fill" : $0.iconName },
                                iconColorFor: { $0 == .weather ? .yellow : NativeSettingsTheme.accentBlue },
                                onSelect: { triggerLivePreview() }
                            )

                            VStack(spacing: 11) {
                                ReferenceToggleRow(
                                    symbol: "photo",
                                    isTextSymbol: false,
                                    symbolColor: .white.opacity(0.7),
                                    title: "Show icon",
                                    isOn: $rightWingShowIcon
                                )

                                ReferenceToggleRow(
                                    symbol: "thermometer.medium",
                                    isTextSymbol: false,
                                    symbolColor: Color(red: 1.0, green: 0.38, blue: 0.38),
                                    title: "Show temperature",
                                    isOn: $rightWingShowTemperature
                                )

                                ReferenceToggleRow(
                                    symbol: "cloud.fill",
                                    isTextSymbol: false,
                                    symbolColor: Color(red: 0.45, green: 0.75, blue: 1.0),
                                    title: "Show condition",
                                    isOn: $rightWingShowCondition
                                )
                            }
                        }
                    }
                }

                // Row 2: Layout & Behavior & Preview Cards
                HStack(alignment: .top, spacing: 16) {
                    // Layout & Behavior Card
                    ReferenceSettingsCard(
                        title: "Layout & Behavior",
                        subtitle: "Control how wings expand and look."
                    ) {
                        VStack(spacing: 12) {
                            ReferenceToggleRow(
                                symbol: nil,
                                title: "Automatically expand to fit content",
                                isOn: $autoFitWings
                            )
                            .onChange(of: autoFitWings) { _, _ in
                                triggerLivePreview()
                            }

                            ReferenceSliderRow(
                                label: autoFitWings ? "Minimum wing width" : "Wing width",
                                value: $wingWidth,
                                in: 50...160,
                                step: 2,
                                unit: "px"
                            ) {
                                triggerLivePreview()
                            }

                            ReferenceToggleRow(
                                symbol: nil,
                                title: "Show separators between items",
                                isOn: $showWingSeparators
                            )
                        }
                    }

                    // Preview Card
                    ReferenceSettingsCard(
                        title: "Preview",
                        subtitle: "Live preview of your notch and wings."
                    ) {
                        VStack(alignment: .center, spacing: 8) {
                            ReferenceNotchCapsule(
                                leftMetric: leftWingMetric,
                                rightMetric: rightWingMetric,
                                wingWidth: wingWidth,
                                autoFit: autoFitWings
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Row 3: Available Wing Items Grid (4 columns x 3 rows)
                ReferenceSettingsCard(
                    title: "Available Wing Items",
                    subtitle: "You can choose different items for left and right wings."
                ) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                        spacing: 10
                    ) {
                        ForEach(availableChips) { chip in
                            wingChipButton(for: chip)
                        }
                    }
                    .padding(.top, 2)
                }

                // Collapsible Advanced Settings (Preserves all existing preference controls)
                DisclosureGroup(isExpanded: $showAdvancedOptions) {
                    VStack(spacing: 12) {
                        Divider().opacity(0.12).padding(.vertical, 4)

                        NativeSettingsRow("Liquid Transparency", description: "Glass body translucency and optical blur", icon: "circle.lefthalf.filled") {
                            HStack(spacing: 6) {
                                Slider(value: $islandTransparency, in: 0.0...1.0)
                                    .frame(width: 90)
                                    .onChange(of: islandTransparency) { _, _ in
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
                            .onChange(of: compactMode) { _, _ in
                                triggerLivePreview()
                            }
                        }

                        NativeSettingsRow("Hide in Full Screen", description: "Automatically collapse wings when another application is full screen", icon: "arrow.up.left.and.arrow.down.right") {
                            Defaults.Toggle("", key: .hideWingsInFullScreen)
                                .labelsHidden()
                        }

                        NativeSettingsRow("Built-in Display Only", description: "Show wings exclusively around the physical MacBook notch", icon: "laptopcomputer") {
                            Defaults.Toggle("", key: .wingsBuiltInDisplayOnly)
                                .labelsHidden()
                        }

                        NativeSettingsRow("Window Transparency", description: "Enable translucent frosted-glass materials", icon: "macwindow") {
                            Defaults.Toggle("", key: .enableWindowTransparency)
                                .labelsHidden()
                                .onChange(of: enableWindowTransparency) { _, _ in
                                    SettingsWindowController.shared.updateWindowTransparency()
                                }
                        }

                        HStack {
                            Spacer()
                            Button("Reset Section to Defaults", role: .destructive) {
                                resetSection()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.red.opacity(0.85))
                            .padding(.vertical, 4)
                            Spacer()
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11))
                        Text("Display Visibility & Transparency Options")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color(red: 0.55, green: 0.60, blue: 0.68))
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, NativeSettingsTheme.pagePadding)
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private func wingChipButton(for chip: WingItemChip) -> some View {
        let isLeft = leftWingMetric == chip.metric
        let isRight = rightWingMetric == chip.metric
        let isSelected = isLeft || isRight

        Menu {
            Button("Assign to Left Wing") {
                leftWingMetric = chip.metric
                triggerLivePreview()
            }
            Button("Assign to Right Wing") {
                rightWingMetric = chip.metric
                triggerLivePreview()
            }
        } label: {
            HStack(spacing: 8) {
                // Distinctive colored glyph
                Image(systemName: chip.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(chip.iconColor)
                    .frame(width: 18, alignment: .center)

                Text(chip.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 2)

                if isLeft || isRight {
                    Circle()
                        .fill(NativeSettingsTheme.accentBlue)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: NativeSettingsTheme.pillCornerRadius, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: NativeSettingsTheme.pillCornerRadius, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? NativeSettingsTheme.accentBlue.opacity(0.65)
                                    : Color.white.opacity(0.08),
                                lineWidth: isSelected ? 1.2 : 0.8
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    public func resetSection() {
        Defaults[.islandTransparency] = 0.35
        Defaults[.waterIntensity] = 0.5
        Defaults[.leftWingMetric] = .cpuUsage
        Defaults[.rightWingMetric] = .netDownUp
        Defaults[.wingWidth] = 100.0
        Defaults[.hideWingsInFullScreen] = true
        Defaults[.wingsBuiltInDisplayOnly] = true
        Defaults[.compactMode] = false
        Defaults[.useCustomAccentColor] = false
        Defaults[.waterSagAmount] = 12.0
        Defaults[.enableShadow] = true
        triggerLivePreview()
    }

    private func triggerLivePreview() {
        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
    }
}

// MARK: - Legacy MockNotchWingsPreview Compatibility

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
        ReferenceNotchCapsule(
            leftMetric: leftMetric,
            rightMetric: rightMetric,
            wingWidth: wingWidth,
            autoFit: autoFit
        )
    }
}
