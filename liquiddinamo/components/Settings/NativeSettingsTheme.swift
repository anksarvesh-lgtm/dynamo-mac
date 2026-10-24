//
//  NativeSettingsTheme.swift
//  LiquidDynamo
//
//  Native macOS frosted-glass design tokens, card containers,
//  and styling components matching Apple system utility aesthetic.
//

import AppKit
import Defaults
import SwiftUI

// MARK: - Native Settings Design Tokens

enum NativeSettingsTheme {
    static let sidebarWidth: CGFloat = 240.0
    static let cardCornerRadius: CGFloat = 12.0
    static let notchCornerRadius: CGFloat = 10.0
    
    // Spacing
    static let pagePadding: CGFloat = 24.0
    static let cardPadding: CGFloat = 16.0
    static let gridSpacing: CGFloat = 16.0
    static let controlSpacing: CGFloat = 12.0
    
    // Semantic Colors
    static func cardBackground(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor).opacity(0.60)
            : Color.white.opacity(0.72)
    }
    
    static func cardBorder(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.09)
            : Color.black.opacity(0.07)
    }
    
    static func cardShadow(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.black.opacity(0.24)
            : Color.black.opacity(0.04)
    }
    
    static func previewBezelBackground(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.12, blue: 0.16)
            : Color(red: 0.88, green: 0.90, blue: 0.94)
    }
}

// MARK: - Native Settings Card Container

struct NativeSettingsCard<Content: View, HeaderAccessory: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let title: String
    let subtitle: String?
    let icon: String?
    let iconColor: Color
    let headerAccessory: HeaderAccessory
    let content: Content
    
    init(
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Card Header
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
                    radius: colorScheme == .dark ? 8 : 4,
                    x: 0,
                    y: colorScheme == .dark ? 3 : 2
                )
        )
    }
}

extension NativeSettingsCard where HeaderAccessory == EmptyView {
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

// MARK: - Native Settings Row Component

struct NativeSettingsRow<Control: View>: View {
    let label: String
    let description: String?
    let icon: String?
    let control: Control
    
    init(
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
    
    var body: some View {
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
