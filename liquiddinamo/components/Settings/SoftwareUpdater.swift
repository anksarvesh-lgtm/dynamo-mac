//
//  SoftwareUpdater.swift
//  boringNotch
//
//  Created by Richard Kunkli on 09/08/2024.
//

import SwiftUI
import Sparkle

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
        VStack(alignment: .leading, spacing: 8) {
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
                    gitHubChecker.downloadLatestDMG()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                        Text("Get Latest DMG")
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
                Text("Checking https://github.com/anksarvesh-lgtm/dynamo-mac/releases...")
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

                    Button("Download Update") {
                        gitHubChecker.downloadLatestDMG(url: downloadURL)
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
            case .error(let msg):
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct UpdaterSettingsView: View {
    private let updater: SPUUpdater
    
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool
    
    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }
    
    var body: some View {
        Section {
            Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                    updater.automaticallyChecksForUpdates = newValue
                }
            
            Toggle("Automatically download updates", isOn: $automaticallyDownloadsUpdates)
                .disabled(!automaticallyChecksForUpdates)
                .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                    updater.automaticallyDownloadsUpdates = newValue
                }
        } header: {
            HStack {
                Text("Software updates")
            }
        }
    }
}
