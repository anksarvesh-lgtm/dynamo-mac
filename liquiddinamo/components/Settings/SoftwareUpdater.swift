//
//  SoftwareUpdater.swift
//  LiquidDynamo
//
//  Automatic update view and settings with in-place application replacement.
//

import SwiftUI
import Sparkle
import Defaults

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    @ObservedObject private var gitHubChecker = GitHubUpdateChecker.shared
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    gitHubChecker.checkForUpdates()
                    if checkForUpdatesViewModel.canCheckForUpdates {
                        updater.checkForUpdates()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if gitHubChecker.status == .checking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(gitHubChecker.status == .checking ? "Checking GitHub…" : "Check for Updates…")
                    }
                }
                .disabled(gitHubChecker.status == .checking)

                Button {
                    gitHubChecker.downloadAndInstallUpdate()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Auto-Update App")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    gitHubChecker.downloadLatestDMG()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                        Text("Get DMG File")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.subheadline)
            }

            switch gitHubChecker.status {
            case .idle:
                EmptyView()

            case .checking:
                Text("Checking GitHub Releases…")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .upToDate(let version):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("LiquidDynamo \(version) is up to date!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .updateAvailable(let newVersion, let downloadURL, _):
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.orange)
                    Text("LiquidDynamo \(newVersion) is available!")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)

                    Button("Update & Restart") {
                        gitHubChecker.downloadAndInstallUpdate(from: downloadURL)
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }

            case .downloading(let progress, let downloaded, let total):
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(width: 180)
                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button("Cancel") {
                            gitHubChecker.cancelDownload()
                        }
                        .controlSize(.mini)
                        .buttonStyle(.bordered)
                    }
                    Text("Downloading update (\(downloaded) of \(total))…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            case .extracting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Extracting liquiddynamo.app…")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }

            case .replacingAndRelaunching:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Replacing application file and restarting…")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }

            case .error(let msg):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        gitHubChecker.downloadAndInstallUpdate()
                    }
                    .controlSize(.small)

                    Button("Open Releases") {
                        gitHubChecker.openReleasesPage()
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

struct UpdaterSettingsView: View {
    private let updater: SPUUpdater

    @Default(.autoCheckUpdates) private var autoCheckUpdates
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }

    var body: some View {
        Section {
            Toggle("Automatically check for updates", isOn: $autoCheckUpdates)
                .onChange(of: autoCheckUpdates) { _, newValue in
                    automaticallyChecksForUpdates = newValue
                    updater.automaticallyChecksForUpdates = newValue
                }

            Toggle("Automatically download and replace app", isOn: $automaticallyDownloadsUpdates)
                .disabled(!autoCheckUpdates)
                .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                    updater.automaticallyDownloadsUpdates = newValue
                }
        } header: {
            HStack {
                Text("Software updates")
            }
        } footer: {
            Text("Updates are cryptographically verified and checked via https://api.github.com/repos/\(GitHubUpdateChecker.repoOwner)/\(GitHubUpdateChecker.repoName)/releases/latest.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
