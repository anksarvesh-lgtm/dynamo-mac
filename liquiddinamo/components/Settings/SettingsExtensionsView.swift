//
//  SettingsExtensionsView.swift
//  LiquidDynamo
//
//  Island Extensions & System: JavaScriptCore community plugins, SQLite notification watcher,
//  BetterDisplay DDC bridge, permissions status, updates, and About.
//

import AppKit
import Defaults
import Sparkle
import SwiftUI

public struct SettingsExtensionsView: View {
    @ObservedObject private var jsRuntime = JavaScriptExtensionRuntime.shared
    @ObservedObject private var notifWatcher = SQLiteNotificationWatcher.shared
    @ObservedObject private var betterDisplay = BetterDisplayBridge.shared
    @ObservedObject private var updateChecker = GitHubUpdateChecker.shared

    public let updaterController: SPUStandardUpdaterController?

    public init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Extensions & System Integrations")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("Community plugins, background watchers, monitor bridges, and app updates")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                // Section 1: Community Extensions
                extensionsCard

                // Section 2: SQLite Notification Watcher & DDC Monitor
                systemIntegrationsCard

                // Section 3: App Updates & Version Info
                appInfoCard
            }
            .padding(24)
        }
    }

    private var extensionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "puzzlepiece.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.purple)
                Text("JavaScriptCore Community Extensions")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                Spacer()
                Text("\(jsRuntime.installedExtensions.count) Loaded")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.purple.opacity(0.15)))
            }

            VStack(spacing: 8) {
                ForEach(jsRuntime.installedExtensions) { ext in
                    HStack(spacing: 12) {
                        Image(systemName: ext.icon ?? "puzzlepiece.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.08)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(ext.name)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Color.white)
                            Text(ext.description)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color.white.opacity(0.55))
                        }

                        Spacer()

                        Text("v\(ext.version)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.12).opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    private var notifStatusColor: Color {
        notifWatcher.hasFullDiskAccess ? Color.green : Color.orange
    }

    private var notifStatusText: String {
        notifWatcher.hasFullDiskAccess ? "Watching DB2" : "Needs Full Disk Access"
    }

    private var betterDisplayStatusColor: Color {
        betterDisplay.isBetterDisplayRunning ? Color.green : Color.gray
    }

    private var betterDisplayStatusText: String {
        betterDisplay.isBetterDisplayRunning ? "Bridge Active" : "App Not Found"
    }

    private var notifWatcherTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(Color.blue)
                Text("Notification Watcher")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            Text("Direct WAL monitoring of ~/Library/Group Containers/group.com.apple.usernoted")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.55))
            HStack(spacing: 4) {
                Circle().fill(notifStatusColor).frame(width: 6, height: 6)
                Text(notifStatusText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(notifStatusColor)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }

    private var betterDisplayTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "display.2")
                    .foregroundStyle(Color.green)
                Text("BetterDisplay DDC")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            Text("Distributed notification bridge for external monitor brightness & volume")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.55))
            HStack(spacing: 4) {
                Circle().fill(betterDisplayStatusColor).frame(width: 6, height: 6)
                Text(betterDisplayStatusText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(betterDisplayStatusColor)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }

    private var systemIntegrationsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Background Watchers & Hardware Bridges")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white)

            HStack(spacing: 14) {
                notifWatcherTile
                betterDisplayTile
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.12).opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    private var appInfoCard: some View {
        HStack(spacing: 16) {
            ReferenceAppIcon(size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text("LiquidDynamo & MacLink")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                Text("Version 2.3.6 • Universal Apple Silicon / Intel")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
            }

            Spacer()

            Button {
                updaterController?.updater.checkForUpdates()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Check for Updates")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.12).opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }
}
