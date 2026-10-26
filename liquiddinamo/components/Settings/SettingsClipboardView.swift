//
//  SettingsClipboardView.swift
//  LiquidDynamo
//
//  Clipboard Control Center: Clipboard history manager settings,
//  privacy protections during screen sharing, and entry management.
//

import AppKit
import Defaults
import SwiftUI

public struct SettingsClipboardView: View {
    @ObservedObject var clipboard = ClipboardHistoryService.shared
    @Default(.showDashboardClipboard) private var showClipboardModule
    @Default(.clipboardShieldDuringScreenRecording) private var shieldDuringScreenRecording

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clipboard Manager")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Persistent clipboard history with automatic privacy shielding")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $showClipboardModule)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Status & Shield Card
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(clipboard.isScreenCaptured ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                            .frame(width: 44, height: 44)
                        Image(systemName: clipboard.isScreenCaptured ? "lock.shield.fill" : "checkmark.shield.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(clipboard.isScreenCaptured ? Color.orange : Color.green)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(clipboard.isScreenCaptured ? "Screen Recording Shield Active" : "Clipboard Security Normal")
                            .font(.system(size: 14, weight: .bold, design: .rounded))

                        Text(clipboard.isScreenCaptured
                             ? "Clipboard contents are obscured while screen recording or sharing is detected."
                             : "History is protected from unauthorized foreground capture.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                )
                .padding(.horizontal, 24)

                // Privacy Shield Setting Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Screen Recording Privacy Shield")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text("Automatically pause and obscure clipboard history during sustained screen recording or sharing (>1.5s). Screenshots remain captured.")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $shieldDuringScreenRecording)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                )
                .padding(.horizontal, 24)

                // Entries Summary & Clear Action
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stored History")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text("\(clipboard.recentEntries.count) recent items • \(clipboard.pinnedEntries.count) pinned items")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            clipboard.clearHistory()
                        } label: {
                            Text("Clear History")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.red.opacity(0.18)))
                                .foregroundStyle(Color.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
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
}
