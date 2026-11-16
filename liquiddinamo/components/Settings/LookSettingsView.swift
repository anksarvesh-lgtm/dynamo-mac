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
    @Default(.wingTransparency) private var wingTransparency
    @Default(.waterIntensity) private var waterIntensity
    @Default(.waterSagAmount) private var waterSagAmount
    @Default(.compactMode) private var compactMode
    @Default(.wingWidth) private var wingWidth
    @Default(.autoFitWings) private var autoFitWings
    @Default(.leftWingMetric) private var leftWingMetric
    @Default(.rightWingMetric) private var rightWingMetric
    @Default(.leftWingMetrics) private var leftWingMetrics
    @Default(.rightWingMetrics) private var rightWingMetrics
    @Default(.leftWingMetricOptions) private var leftWingMetricOptions
    @Default(.rightWingMetricOptions) private var rightWingMetricOptions
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
    @State private var draggedMetric: WingMetric? = nil

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
        WingItemChip(id: "ramPressure", title: "RAM Pressure", icon: "gauge.with.dots.needle.67percent", iconColor: Color(red: 0.72, green: 0.45, blue: 1.0), metric: .ramPressure),
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
                        leftMetrics: leftWingMetrics,
                        rightMetrics: rightWingMetrics,
                        wingWidth: wingWidth,
                        autoFit: autoFitWings
                    )
                    .frame(width: 320)
                }
                .padding(.bottom, 2)

                // Row 1: Left Wing Content & Right Wing Content Cards
                HStack(alignment: .top, spacing: 16) {
                    wingMetricsListCard(
                        title: "Left Wing Content",
                        subtitle: "Configure 1 to 3 items and display options for the left wing.",
                        metrics: $leftWingMetrics,
                        options: $leftWingMetricOptions,
                        isLeft: true
                    )

                    wingMetricsListCard(
                        title: "Right Wing Content",
                        subtitle: "Configure 1 to 3 items and display options for the right wing.",
                        metrics: $rightWingMetrics,
                        options: $rightWingMetricOptions,
                        isLeft: false
                    )
                }

                // Row 2: Layout & Behavior & Preview Cards
                HStack(alignment: .top, spacing: 16) {
                    // Layout & Behavior Card
                    ReferenceSettingsCard(
                        title: "Layout & Behavior",
                        subtitle: "Control how wings expand, size, and look."
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

                            ReferenceSliderRow(
                                label: "Wing transparency",
                                value: Binding(
                                    get: { CGFloat(wingTransparency * 100.0) },
                                    set: {
                                        wingTransparency = Double($0) / 100.0
                                        triggerLivePreview()
                                    }
                                ),
                                in: 20...100,
                                step: 5,
                                unit: "%"
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
                                leftMetrics: leftWingMetrics,
                                rightMetrics: rightWingMetrics,
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

                        NativeSettingsRow("Hardware Temp Probe", description: "Sample CPU thermal sensor when permitted (shows — when unavailable)", icon: "thermometer.medium") {
                            Defaults.Toggle("", key: .enableHardwareTempSensor)
                                .labelsHidden()
                        }

                        ThermalThresholdsSettingsBlock()

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

    private struct ThermalThresholdsSettingsBlock: View {
        @Default(.thermalCoolMaxC) private var coolMaxC
        @Default(.thermalNormalMaxC) private var normalMaxC
        @Default(.thermalElevatedMaxC) private var elevatedMaxC
        @Default(.thermalHighMaxC) private var highMaxC

        private var sanitized: ThermalThresholds {
            ThermalThresholds(
                coolMaxC: coolMaxC,
                normalMaxC: normalMaxC,
                elevatedMaxC: elevatedMaxC,
                highMaxC: highMaxC
            ).sanitized()
        }

        private func applyThresholds(_ updated: ThermalThresholds) {
            let clean = updated.sanitized()
            coolMaxC = clean.coolMaxC
            normalMaxC = clean.normalMaxC
            elevatedMaxC = clean.elevatedMaxC
            highMaxC = clean.highMaxC
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Thermal Color Thresholds (°C)")
                        .font(.system(size: 11.5, weight: .semibold))
                    Spacer()
                    Text("Critical (Red) > \(Int(sanitized.highMaxC))°C")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Color(
                            red: ThermalColorScale.criticalRed.r,
                            green: ThermalColorScale.criticalRed.g,
                            blue: ThermalColorScale.criticalRed.b
                        ))
                }

                thresholdRow(
                    title: "Cool (Cyan) ≤",
                    color: Color(red: ThermalColorScale.coolCyan.r, green: ThermalColorScale.coolCyan.g, blue: ThermalColorScale.coolCyan.b),
                    value: Binding(
                        get: { sanitized.coolMaxC },
                        set: { newVal in
                            var t = sanitized
                            t.coolMaxC = newVal
                            applyThresholds(t)
                        }
                    ),
                    range: 25...80
                )

                thresholdRow(
                    title: "Normal (Green) ≤",
                    color: Color(red: ThermalColorScale.normalGreen.r, green: ThermalColorScale.normalGreen.g, blue: ThermalColorScale.normalGreen.b),
                    value: Binding(
                        get: { sanitized.normalMaxC },
                        set: { newVal in
                            var t = sanitized
                            t.normalMaxC = newVal
                            applyThresholds(t)
                        }
                    ),
                    range: 35...95
                )

                thresholdRow(
                    title: "Elevated (Yellow) ≤",
                    color: Color(red: ThermalColorScale.elevatedYellow.r, green: ThermalColorScale.elevatedYellow.g, blue: ThermalColorScale.elevatedYellow.b),
                    value: Binding(
                        get: { sanitized.elevatedMaxC },
                        set: { newVal in
                            var t = sanitized
                            t.elevatedMaxC = newVal
                            applyThresholds(t)
                        }
                    ),
                    range: 45...105
                )

                thresholdRow(
                    title: "High (Orange) ≤",
                    color: Color(red: ThermalColorScale.highOrange.r, green: ThermalColorScale.highOrange.g, blue: ThermalColorScale.highOrange.b),
                    value: Binding(
                        get: { sanitized.highMaxC },
                        set: { newVal in
                            var t = sanitized
                            t.highMaxC = newVal
                            applyThresholds(t)
                        }
                    ),
                    range: 55...115
                )
            }
            .padding(10)
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)
        }

        private func thresholdRow(title: String, color: Color, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 122, alignment: .leading)
                Slider(value: value, in: range, step: 1)
                Text("\(Int(value.wrappedValue))°C")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func wingMetricsListCard(
        title: String,
        subtitle: String,
        metrics: Binding<[WingMetric]>,
        options: Binding<[String: WingMetricOptions]>,
        isLeft: Bool
    ) -> some View {
        ReferenceSettingsCard(title: title, subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 12) {
                // List of active metrics (up to 3)
                ForEach(Array(metrics.wrappedValue.enumerated()), id: \.offset) { idx, metric in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.35))
                                .frame(width: 14)
                                .help("Drag to reorder")

                            Image(systemName: metric == .cpuUsage ? "waveform.path.ecg" : metric.iconName)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(isLeft ? Color.cyan : NativeSettingsTheme.accentBlue)
                                .frame(width: 16)

                            Text(metric.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)

                            Spacer(minLength: 4)

                            // Move Up
                            Button {
                                guard idx > 0 else { return }
                                metrics.wrappedValue.swapAt(idx, idx - 1)
                                triggerLivePreview()
                            } label: {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(idx > 0 ? .white.opacity(0.8) : .white.opacity(0.2))
                            }
                            .buttonStyle(.plain)
                            .disabled(idx == 0)

                            // Move Down
                            Button {
                                guard idx < metrics.wrappedValue.count - 1 else { return }
                                metrics.wrappedValue.swapAt(idx, idx + 1)
                                triggerLivePreview()
                            } label: {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(idx < metrics.wrappedValue.count - 1 ? .white.opacity(0.8) : .white.opacity(0.2))
                            }
                            .buttonStyle(.plain)
                            .disabled(idx >= metrics.wrappedValue.count - 1)

                            // Remove
                            Button {
                                guard metrics.wrappedValue.count > 1 else { return }
                                metrics.wrappedValue.remove(at: idx)
                                triggerLivePreview()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                    .foregroundStyle(metrics.wrappedValue.count > 1 ? Color.red.opacity(0.8) : Color.white.opacity(0.2))
                            }
                            .buttonStyle(.plain)
                            .disabled(metrics.wrappedValue.count <= 1)
                        }
                        .contentShape(Rectangle())
                        .onDrag {
                            self.draggedMetric = metric
                            return NSItemProvider(object: metric.rawValue as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: WingMetricDropDelegate(
                                item: metric,
                                list: metrics,
                                draggedItem: $draggedMetric,
                                onReorder: { triggerLivePreview() }
                            )
                        )

                        // Per-metric options toggles (Icon, Value, Label, Mini Graph)
                        let opt = options.wrappedValue[metric.rawValue] ?? WingMetricOptions()
                        HStack(spacing: 12) {
                            metricTogglePill(title: "Icon", isOn: Binding(
                                get: { opt.showIcon },
                                set: {
                                    var updated = opt
                                    updated.showIcon = $0
                                    options.wrappedValue[metric.rawValue] = updated
                                    triggerLivePreview()
                                }
                            ))

                            metricTogglePill(title: "Value", isOn: Binding(
                                get: { opt.showValue },
                                set: {
                                    var updated = opt
                                    updated.showValue = $0
                                    options.wrappedValue[metric.rawValue] = updated
                                    triggerLivePreview()
                                }
                            ))

                            metricTogglePill(title: "Label", isOn: Binding(
                                get: { opt.showLabel },
                                set: {
                                    var updated = opt
                                    updated.showLabel = $0
                                    options.wrappedValue[metric.rawValue] = updated
                                    triggerLivePreview()
                                }
                            ))

                            metricTogglePill(title: "Graph", isOn: Binding(
                                get: { opt.showMiniGraph },
                                set: {
                                    var updated = opt
                                    updated.showMiniGraph = $0
                                    options.wrappedValue[metric.rawValue] = updated
                                    triggerLivePreview()
                                }
                            ))
                        }
                        .padding(.leading, 24)
                    }
                    .padding(.vertical, 4)

                    if idx < metrics.wrappedValue.count - 1 {
                        Divider().opacity(0.08)
                    }
                }

                // Add Metric Button (up to 3 items)
                if metrics.wrappedValue.count < 3 {
                    Menu {
                        let available = WingMetric.selectableCases.filter { m in
                            m != .none && !metrics.wrappedValue.contains(m)
                        }
                        ForEach(available) { m in
                            Button(m.displayName) {
                                metrics.wrappedValue.append(m)
                                triggerLivePreview()
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 11))
                            Text("Add Metric (\(metrics.wrappedValue.count)/3)")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(NativeSettingsTheme.accentBlue)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func metricTogglePill(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9))
                    .foregroundStyle(isOn.wrappedValue ? NativeSettingsTheme.accentBlue : Color.white.opacity(0.3))
                Text(title)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(isOn.wrappedValue ? .white : Color.white.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func wingChipButton(for chip: WingItemChip) -> some View {
        let isLeft = leftWingMetrics.contains(chip.metric)
        let isRight = rightWingMetrics.contains(chip.metric)
        let isSelected = isLeft || isRight

        Menu {
            Button("Assign to Left Wing") {
                if !leftWingMetrics.contains(chip.metric) {
                    if leftWingMetrics.count >= 3 {
                        leftWingMetrics[2] = chip.metric
                    } else {
                        leftWingMetrics.append(chip.metric)
                    }
                }
                triggerLivePreview()
            }
            Button("Assign to Right Wing") {
                if !rightWingMetrics.contains(chip.metric) {
                    if rightWingMetrics.count >= 3 {
                        rightWingMetrics[2] = chip.metric
                    } else {
                        rightWingMetrics.append(chip.metric)
                    }
                }
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
        Defaults[.wingTransparency] = 0.50
        Defaults[.waterIntensity] = 0.5
        Defaults[.leftWingMetric] = .cpuUsage
        Defaults[.rightWingMetric] = .netDownUp
        Defaults[.leftWingMetrics] = [.cpuUsage]
        Defaults[.rightWingMetrics] = [.netDown]
        Defaults[.wingWidth] = 100.0
        Defaults[.hideWingsInFullScreen] = true
        Defaults[.wingsBuiltInDisplayOnly] = false
        Defaults[.enableHardwareTempSensor] = true
        Defaults[.thermalCoolMaxC] = ThermalThresholds.standard.coolMaxC
        Defaults[.thermalNormalMaxC] = ThermalThresholds.standard.normalMaxC
        Defaults[.thermalElevatedMaxC] = ThermalThresholds.standard.elevatedMaxC
        Defaults[.thermalHighMaxC] = ThermalThresholds.standard.highMaxC
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

// MARK: - MockNotchWingsPreview Compatibility

public struct MockNotchWingsPreview: View {
    public let leftMetrics: [WingMetric]
    public let rightMetrics: [WingMetric]
    public let wingWidth: CGFloat
    public let autoFit: Bool

    public init(leftMetrics: [WingMetric], rightMetrics: [WingMetric], wingWidth: CGFloat, autoFit: Bool = true) {
        self.leftMetrics = leftMetrics
        self.rightMetrics = rightMetrics
        self.wingWidth = wingWidth
        self.autoFit = autoFit
    }

    public init(leftMetric: WingMetric, rightMetric: WingMetric, wingWidth: CGFloat, autoFit: Bool = true) {
        self.leftMetrics = leftMetric == .none ? [] : [leftMetric]
        self.rightMetrics = rightMetric == .none ? [] : [rightMetric]
        self.wingWidth = wingWidth
        self.autoFit = autoFit
    }

    public var body: some View {
        ReferenceNotchCapsule(
            leftMetrics: leftMetrics,
            rightMetrics: rightMetrics,
            wingWidth: wingWidth,
            autoFit: autoFit
        )
    }
}

// MARK: - Drag-to-Reorder Drop Delegate

struct WingMetricDropDelegate: DropDelegate {
    let item: WingMetric
    @Binding var list: [WingMetric]
    @Binding var draggedItem: WingMetric?
    let onReorder: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedItem,
              dragged != item,
              let from = list.firstIndex(of: dragged),
              let to = list.firstIndex(of: item) else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            list.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            onReorder()
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
