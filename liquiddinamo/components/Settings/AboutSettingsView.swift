//
//  AboutSettingsView.swift
//  LiquidDynamo
//
//  About Section: version, licenses, links, diagnostics, and Run setup again.
//

import AppKit
import Defaults
import Sparkle
import SwiftUI

public struct AboutSettingsView: View {
    let updaterController: SPUStandardUpdaterController?

    @State private var copiedDiagnostics: Bool = false
    @State private var showLicenseSheet: Bool = false
    @State private var showChangelogSheet: Bool = false

    public init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    public var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("LiquidDynamo")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("v\(Bundle.main.releaseVersionNumber ?? "2.0.0")")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        Text("Version \(Bundle.main.releaseVersionNumber ?? "2.0.0") (Build \(Bundle.main.buildVersionNumber ?? "13"))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Fluid Liquid Notch Experience for macOS")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Developed by Agrigence")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Button {
                    AppDelegate.shared?.showOnboardingWindow(step: .welcome)
                } label: {
                    Label("Run setup again", systemImage: "sparkles")
                        .font(.body.weight(.medium))
                }
                .controlSize(.regular)
            } header: {
                Text("First-Run Setup")
            } footer: {
                Text("Re-runs the guided 4-step setup flow to pick modules, behavior, and permissions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.releaseVersionNumber ?? "2.0.0")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Text("Build Number")
                    Spacer()
                    Text(Bundle.main.buildVersionNumber ?? "13")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Text("Release")
                    Spacer()
                    Text("LiquidDynamo \(Bundle.main.releaseVersionNumber ?? "2.0.0")")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let updater = updaterController?.updater {
                    CheckForUpdatesView(updater: updater)
                }
            } header: {
                Text("Version info")
            }

            Section {
                Button {
                    showChangelogSheet = true
                } label: {
                    HStack {
                        Label("Release Changelog (GitHub)", systemImage: "sparkles.rectangle.stack")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Link(destination: URL(string: "https://github.com/anksarvesh-lgtm/dynamo-mac")!) {
                    HStack {
                        Label("GitHub Repository", systemImage: "link")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Link(destination: URL(string: "https://github.com/anksarvesh-lgtm/dynamo-mac/releases")!) {
                    HStack {
                        Label("GitHub Releases", systemImage: "arrow.down.circle")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    showLicenseSheet = true
                } label: {
                    HStack {
                        Label("Open Source Licenses", systemImage: "doc.plaintext")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    copyDiagnostics()
                } label: {
                    HStack {
                        Label(copiedDiagnostics ? "Diagnostics Copied!" : "Copy Diagnostics", systemImage: copiedDiagnostics ? "checkmark.circle.fill" : "doc.on.clipboard")
                        Spacer()
                    }
                }
            } header: {
                Text("Links & Diagnostics")
            }

            Section {
                VStack(spacing: 3) {
                    Text("Copyright © 2026 Agrigence. All rights reserved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Based on Boring Notch by TheBoredTeam under GPL-3.0")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
        .sheet(isPresented: $showChangelogSheet) {
            GitHubChangelogView()
        }
        .sheet(isPresented: $showLicenseSheet) {
            VStack(spacing: 0) {
                HStack {
                    Text("Licenses")
                        .font(.title2.bold())
                    Spacer()
                    Button("Done") {
                        showLicenseSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding()

                Divider()

                LicenseView()
                    .padding()
            }
            .frame(minWidth: 500, minHeight: 400)
        }
    }

    private func copyDiagnostics() {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let screens = NSScreen.screens.map { "\($0.localizedName) (\(Int($0.frame.width))x\(Int($0.frame.height)))" }.joined(separator: ", ")
        let diag = """
        LiquidDynamo Diagnostics:
        Version: \(Bundle.main.releaseVersionNumber ?? "1.7.0") (\(Bundle.main.buildVersionNumber ?? "8"))
        macOS: \(osVersion)
        Displays: \(screens)
        Transparency: \(Defaults[.islandTransparency])
        Hover: \(Defaults[.openNotchOnHover])
        Active Modules: Media=\(Defaults[.showMedia]), HUD=\(Defaults[.showNotchOSD]), Battery=\(Defaults[.showBatteryIndicator]), Cal=\(Defaults[.showCalendar]), Shelf=\(Defaults[.liquidShelf])
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diag, forType: .string)
        copiedDiagnostics = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedDiagnostics = false
        }
    }
}
