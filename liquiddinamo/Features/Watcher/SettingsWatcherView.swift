//
//  SettingsWatcherView.swift
//  LiquidDynamo
//
//  Created for LiquidDynamo Watcher (AI Agent & Coding Session Monitor)
//

import AppKit
import Defaults
import SwiftUI

/// Settings pane for LiquidDynamo Watcher (AI Agent & Coding Session Monitor).
/// Adheres to native macOS frosted-glass settings design system.
public struct SettingsWatcherView: View {
    @ObservedObject var watcher = WatcherService.shared
    @Default(.enableWatcherIntegration) var enableWatcherIntegration
    @Default(.watcherAutoApproveReads) var watcherAutoApproveReads
    @Default(.watcherNotificationOnFinished) var watcherNotificationOnFinished

    @State private var copiedHookSnippet: Bool = false

    public init() {}

    private var hookSnippet: String {
        """
        {
          "hooks": {
            "UserPromptSubmit": [
              { "type": "command", "command": "echo '{\\\"hook_event_name\\\":\\\"UserPromptSubmit\\\",\\\"prompt\\\":\\\"$PROMPT\\\"}' | nc -U /tmp/liquid_watcher.sock" }
            ]
          }
        }
        """
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Section 1: Overview & Server Status
                NativeSettingsCard(title: "Watcher AI Session Monitor", icon: "sparkles") {
                    VStack(alignment: .leading, spacing: 10) {
                        ToggleRow(
                            title: "Enable Watcher IPC Listener",
                            subtitle: "Listens for AI coding sessions (Claude Code, Antigravity, Cursor, Codex, Gemini CLI) via local Unix socket",
                            isOn: $enableWatcherIntegration
                        )
                        .onChange(of: enableWatcherIntegration) { _, enabled in
                            if enabled {
                                watcher.startServer()
                            } else {
                                watcher.stopServer()
                            }
                        }

                        Divider().opacity(0.15)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("IPC Socket Path")
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text(watcher.primarySocketPath)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(watcher.isListening ? Color.green : Color.orange)
                                    .frame(width: 6, height: 6)
                                Text(watcher.isListening ? "Listening" : "Inactive")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                        }

                        Divider().opacity(0.15)

                        HStack {
                            Button("Test Simulator Session") {
                                watcher.simulateAgentActivity()
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                            .foregroundStyle(Color.accentColor)

                            Spacer()

                            if let primary = watcher.primarySession {
                                Text("Active: \(primary.displayName) (\(primary.state.statusLabel))")
                                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }

                // Section 2: Automation & Approvals
                NativeSettingsCard(title: "Permissions & Notifications", icon: "shield.checkered") {
                    VStack(spacing: 10) {
                        ToggleRow(
                            title: "Notch Authorization Popups",
                            subtitle: "Display Allow/Deny controls directly in the notch when an agent requests tool authorization",
                            isOn: $watcherNotificationOnFinished
                        )

                        Divider().opacity(0.15)

                        ToggleRow(
                            title: "Auto-Approve Read Operations",
                            subtitle: "Automatically grant permissions for read-only tools while prompting for file writes and shell commands",
                            isOn: $watcherAutoApproveReads
                        )
                    }
                }

                // Section 3: Agent Hook Configuration Guide
                NativeSettingsCard(title: "Agent Hook Integration", icon: "terminal.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect any agent by sending newline-terminated JSON to the socket:")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)

                        Text("Socket: \(watcher.fallbackSocketPath)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.accentColor)

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(hookSnippet, forType: .string)
                            copiedHookSnippet = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                copiedHookSnippet = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: copiedHookSnippet ? "checkmark" : "doc.on.doc")
                                Text(copiedHookSnippet ? "Snippet Copied" : "Copy Example Config")
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
    }
}
