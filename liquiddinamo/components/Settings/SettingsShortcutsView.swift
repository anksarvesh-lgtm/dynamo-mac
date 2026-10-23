//
//  SettingsShortcutsView.swift
//  LiquidDynamo
//
//  Keyboard Shortcuts Control Center: macOS system-grade key recorders
//  embedded in Liquid Glass cards with quick reset actions.
//

import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

public struct SettingsShortcutsView: View {
    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyboard Shortcuts")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Global macOS key combinations to control your notch and liquid HUDs")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Shortcuts Card
                VStack(spacing: 16) {
                    shortcutRow(
                        title: "Toggle Liquid Notch",
                        description: "Expand or collapse the Dynamic Island dashboard instantly",
                        name: .toggleNotchOpen
                    )

                    Divider().opacity(0.2)

                    shortcutRow(
                        title: "Toggle Sneak Peek HUD",
                        description: "Briefly reveal now playing track or active system HUD",
                        name: .toggleSneakPeek
                    )
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                )
                .padding(.horizontal, 24)

                Spacer(minLength: 20)
            }
        }
    }

    private func shortcutRow(title: String, description: String, name: KeyboardShortcuts.Name) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            KeyboardShortcuts.Recorder(for: name)
        }
    }
}
