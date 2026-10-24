//
//  NativeSettingsTheme.swift
//  LiquidDynamo
//
//  Native macOS dark frosted-glass design tokens, card containers,
//  and styling components matching the reference application aesthetic.
//

import AppKit
import Defaults
import SwiftUI

// MARK: - Native Settings Design Tokens

public enum NativeSettingsTheme {
    public static let sidebarWidth: CGFloat = 224.0
    public static let cardCornerRadius: CGFloat = 16.0
    public static let notchCornerRadius: CGFloat = 10.0
    public static let pillCornerRadius: CGFloat = 10.0
    
    // Spacing
    public static let pagePadding: CGFloat = 24.0
    public static let cardPadding: CGFloat = 18.0
    public static let gridSpacing: CGFloat = 16.0
    public static let controlSpacing: CGFloat = 12.0
    
    // Colors
    public static let accentBlue = Color(red: 0.10, green: 0.48, blue: 0.98)
    public static let windowDarkGlass = Color(red: 0.08, green: 0.10, blue: 0.13)
    
    public static func cardBackground(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.13, blue: 0.17).opacity(0.85)
            : Color.white.opacity(0.72)
    }
    
    public static func cardBorder(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.07)
    }
    
    public static func cardShadow(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.black.opacity(0.35)
            : Color.black.opacity(0.04)
    }

    public static func pillBackground(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.07, green: 0.08, blue: 0.11).opacity(0.88)
            : Color.black.opacity(0.05)
    }

    public static func pillBorder(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
    }
    
    public static func previewBezelBackground(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.06, green: 0.07, blue: 0.09)
            : Color(red: 0.88, green: 0.90, blue: 0.94)
    }
}

// MARK: - 3D Blue Liquid Water Droplet App Icon

public struct ReferenceAppIcon: View {
    public let size: CGFloat

    public init(size: CGFloat = 40) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Drop shape with 3D gradient
            Image(systemName: "drop.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size * 1.1)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.40, green: 0.80, blue: 1.0),
                            Color(red: 0.12, green: 0.52, blue: 0.98),
                            Color(red: 0.05, green: 0.28, blue: 0.82)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color(red: 0.10, green: 0.50, blue: 0.98).opacity(0.5), radius: 8, x: 0, y: 3)
                .overlay(
                    // Specular light sheen highlight
                    Image(systemName: "drop.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size * 0.55, height: size * 0.6)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.white.opacity(0.65), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .offset(x: -size * 0.12, y: -size * 0.18)
                        .blur(radius: 0.8)
                )
        }
        .frame(width: size, height: size * 1.1)
    }
}

// MARK: - Reference Settings Card Container

public struct ReferenceSettingsCard<Content: View, HeaderAccessory: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    
    public let title: String
    public let subtitle: String?
    public let headerAccessory: HeaderAccessory
    public let content: Content
    
    public init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.headerAccessory = headerAccessory()
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Card Header
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color(red: 0.55, green: 0.60, blue: 0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Spacer(minLength: 4)
                
                headerAccessory
            }
            
            // Card Body Content
            content
        }
        .padding(NativeSettingsTheme.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: NativeSettingsTheme.cardCornerRadius, style: .continuous)
                .fill(NativeSettingsTheme.cardBackground(colorScheme: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: NativeSettingsTheme.cardCornerRadius, style: .continuous)
                        .strokeBorder(NativeSettingsTheme.cardBorder(colorScheme: colorScheme), lineWidth: 1)
                )
                .shadow(
                    color: NativeSettingsTheme.cardShadow(colorScheme: colorScheme),
                    radius: 12,
                    x: 0,
                    y: 4
                )
        )
    }
}

public extension ReferenceSettingsCard where HeaderAccessory == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            headerAccessory: { EmptyView() },
            content: content
        )
    }
}

// MARK: - Reference Dropdown Pill Selector

public struct ReferencePillPicker<T: Hashable & Identifiable>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: T
    public let items: [T]
    public let titleFor: (T) -> String
    public let iconFor: (T) -> String
    public let iconColorFor: (T) -> Color
    public var onSelect: (() -> Void)? = nil

    public init(
        selection: Binding<T>,
        items: [T],
        titleFor: @escaping (T) -> String,
        iconFor: @escaping (T) -> String,
        iconColorFor: @escaping (T) -> Color = { _ in NativeSettingsTheme.accentBlue },
        onSelect: (() -> Void)? = nil
    ) {
        self._selection = selection
        self.items = items
        self.titleFor = titleFor
        self.iconFor = iconFor
        self.iconColorFor = iconColorFor
        self.onSelect = onSelect
    }

    public var body: some View {
        Menu {
            ForEach(items) { item in
                Button {
                    selection = item
                    onSelect?()
                } label: {
                    Label(titleFor(item), systemImage: iconFor(item))
                }
            }
        } label: {
            HStack(spacing: 8) {
                // Leading Icon
                ZStack {
                    Circle()
                        .fill(iconColorFor(selection).opacity(0.18))
                        .frame(width: 22, height: 22)
                    
                    Image(systemName: iconFor(selection))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(iconColorFor(selection))
                }

                Text(titleFor(selection))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: NativeSettingsTheme.pillCornerRadius, style: .continuous)
                    .fill(NativeSettingsTheme.pillBackground(colorScheme: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: NativeSettingsTheme.pillCornerRadius, style: .continuous)
                            .strokeBorder(NativeSettingsTheme.pillBorder(colorScheme: colorScheme), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reference Toggle Row with Custom Symbol

public struct ReferenceToggleRow: View {
    public let symbol: String?
    public let isTextSymbol: Bool
    public let symbolColor: Color
    public let title: String
    @Binding public var isOn: Bool

    public init(
        symbol: String? = nil,
        isTextSymbol: Bool = false,
        symbolColor: Color = .white.opacity(0.7),
        title: String,
        isOn: Binding<Bool>
    ) {
        self.symbol = symbol
        self.isTextSymbol = isTextSymbol
        self.symbolColor = symbolColor
        self.title = title
        self._isOn = isOn
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let symbol = symbol {
                Group {
                    if isTextSymbol {
                        Text(symbol)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .foregroundStyle(symbolColor)
                .frame(width: 20, alignment: .center)
            }

            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: NativeSettingsTheme.accentBlue))
                .labelsHidden()
        }
    }
}

// MARK: - Reference Slider Row

public struct ReferenceSliderRow: View {
    public let label: String
    @Binding public var value: CGFloat
    public let range: ClosedRange<CGFloat>
    public let step: CGFloat
    public let unit: String
    public var onChange: (() -> Void)? = nil

    public init(
        label: String,
        value: Binding<CGFloat>,
        in range: ClosedRange<CGFloat> = 50...160,
        step: CGFloat = 2,
        unit: String = "px",
        onChange: (() -> Void)? = nil
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.onChange = onChange
    }

    public var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            Slider(value: $value, in: range, step: step)
                .tint(NativeSettingsTheme.accentBlue)
                .frame(width: 130)
                .onChange(of: value) {
                    onChange?()
                }

            Text("\(Int(value)) \(unit)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

// MARK: - Reference Photorealistic Notch & Wings Preview Capsule

public struct ReferenceNotchCapsule: View {
    public let leftMetric: WingMetric
    public let rightMetric: WingMetric
    public let wingWidth: CGFloat
    public let autoFit: Bool

    public init(
        leftMetric: WingMetric = .cpuUsage,
        rightMetric: WingMetric = .weather,
        wingWidth: CGFloat = 80,
        autoFit: Bool = true
    ) {
        self.leftMetric = leftMetric
        self.rightMetric = rightMetric
        self.wingWidth = wingWidth
        self.autoFit = autoFit
    }

    public var body: some View {
        ZStack {
            // Outer Capsule Glass Body
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.06, blue: 0.08).opacity(0.95),
                            Color(red: 0.02, green: 0.03, blue: 0.05).opacity(0.98)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    // Glossy border highlight
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.20),
                                    Color.white.opacity(0.05),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.6), radius: 10, x: 0, y: 4)

            // Content inside capsule
            HStack(spacing: 0) {
                // Left Wing Section
                HStack(spacing: 6) {
                    // Cyan Waveform or Metric Icon
                    ZStack {
                        Circle()
                            .fill(Color.cyan.opacity(0.20))
                            .frame(width: 22, height: 22)

                        Image(systemName: leftMetric == .cpuUsage ? "waveform.path.ecg" : leftMetric.iconName)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.cyan)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(leftMetric == .cpuUsage ? "CPU" : (leftMetric == .none ? "Idle" : leftMetric.displayName))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)

                        HStack(spacing: 4) {
                            Text(leftMetric == .cpuUsage ? "12%" : "Active")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.7))

                            if leftMetric == .cpuUsage {
                                // Mini blue progress bar
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(width: 28, height: 3)
                                    Capsule()
                                        .fill(NativeSettingsTheme.accentBlue)
                                        .frame(width: 10, height: 3)
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 12)

                Spacer(minLength: 8)

                // Center Notch & Blue Specular Sheen
                ZStack {
                    // Physical Notch Bezel
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 8,
                        bottomTrailingRadius: 8,
                        topTrailingRadius: 0
                    )
                    .fill(Color.black)
                    .frame(width: 68, height: 20)
                    .overlay(
                        // Camera lens dot
                        Circle()
                            .fill(Color(red: 0.1, green: 0.2, blue: 0.35))
                            .frame(width: 4, height: 4)
                            .offset(y: -2)
                    )

                    // Blue Specular Neon Wave Flare
                    Ellipse()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.cyan.opacity(0.7),
                                    NativeSettingsTheme.accentBlue.opacity(0.5),
                                    Color.clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 42, height: 5)
                        .blur(radius: 2)
                        .offset(x: 10, y: 7)
                }

                Spacer(minLength: 8)

                // Right Wing Section
                HStack(spacing: 6) {
                    // Sun / Weather or Metric Icon
                    ZStack {
                        Circle()
                            .fill(Color.yellow.opacity(0.20))
                            .frame(width: 22, height: 22)

                        Image(systemName: rightMetric == .weather ? "cloud.sun.fill" : rightMetric.iconName)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(rightMetric == .weather ? Color.yellow : NativeSettingsTheme.accentBlue)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(rightMetric == .weather ? "28°" : (rightMetric == .none ? "Idle" : "Live"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)

                        Text(rightMetric == .weather ? "Partly Cloudy" : rightMetric.displayName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .padding(.trailing, 12)
            }
        }
        .frame(height: 44)
    }
}

// MARK: - Legacy Native Settings Card & Row (Compatibility Layer)

public struct NativeSettingsCard<Content: View, HeaderAccessory: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    
    public let title: String
    public let subtitle: String?
    public let icon: String?
    public let iconColor: Color
    public let headerAccessory: HeaderAccessory
    public let content: Content
    
    public init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        iconColor: Color = .blue,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.headerAccessory = headerAccessory()
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                if let icon = icon {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(iconColor.opacity(colorScheme == .dark ? 0.22 : 0.14))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer(minLength: 4)
                
                headerAccessory
            }
            
            Divider()
                .opacity(colorScheme == .dark ? 0.25 : 0.15)
            
            content
        }
        .padding(NativeSettingsTheme.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: NativeSettingsTheme.cardCornerRadius, style: .continuous)
                .fill(NativeSettingsTheme.cardBackground(colorScheme: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: NativeSettingsTheme.cardCornerRadius, style: .continuous)
                        .strokeBorder(NativeSettingsTheme.cardBorder(colorScheme: colorScheme), lineWidth: 1)
                )
                .shadow(
                    color: NativeSettingsTheme.cardShadow(colorScheme: colorScheme),
                    radius: colorScheme == .dark ? 8 : 4,
                    x: 0,
                    y: colorScheme == .dark ? 3 : 2
                )
        )
    }
}

public extension NativeSettingsCard where HeaderAccessory == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        iconColor: Color = .blue,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            icon: icon,
            iconColor: iconColor,
            headerAccessory: { EmptyView() },
            content: content
        )
    }
}

public struct NativeSettingsRow<Control: View>: View {
    public let label: String
    public let description: String?
    public let icon: String?
    public let control: Control
    
    public init(
        _ label: String,
        description: String? = nil,
        icon: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.label = label
        self.description = description
        self.icon = icon
        self.control = control()
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .center)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                
                if let description = description {
                    Text(description)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Spacer(minLength: 8)
            
            control
        }
    }
}

