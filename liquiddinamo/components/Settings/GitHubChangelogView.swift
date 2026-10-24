//
//  GitHubChangelogView.swift
//  LiquidDynamo
//
//  Displays release changelogs and version notes dynamically fetched from GitHub Releases.
//

import SwiftUI

public struct GitHubReleaseItem: Identifiable, Decodable {
    public let id: Int
    public let tagName: String
    public let name: String?
    public let body: String?
    public let publishedAt: String?
    public let htmlUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case body
        case publishedAt = "published_at"
        case htmlUrl = "html_url"
    }

    public var formattedDate: String {
        guard let publishedAt = publishedAt else { return "" }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: publishedAt) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .none
            return displayFormatter.string(from: date)
        }
        return publishedAt
    }
}

@MainActor
public final class GitHubChangelogViewModel: ObservableObject {
    @Published public var releases: [GitHubReleaseItem] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    public init() {}

    public func fetchReleases() async {
        guard releases.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        let endpoints = [
            "https://api.github.com/repos/anksarvesh-lgtm/dynamo-mac/releases",
            "https://api.github.com/repos/anksarvesh-lgtm/dynamomac/releases"
        ]

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.setValue("LiquidDynamo/\(Bundle.main.releaseVersionNumber ?? "2.0.0")", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    continue
                }

                let decoder = JSONDecoder()
                let fetchedReleases = try decoder.decode([GitHubReleaseItem].self, from: data)
                if !fetchedReleases.isEmpty {
                    self.releases = fetchedReleases
                    self.isLoading = false
                    return
                }
            } catch {
                // Try fallback repository
            }
        }

        self.isLoading = false
        if self.releases.isEmpty {
            self.errorMessage = "Unable to load release notes from GitHub. Please check your internet connection."
        }
    }
}

public struct GitHubChangelogView: View {
    @StateObject private var viewModel = GitHubChangelogViewModel()
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Release Changelog")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("Updates and new features from GitHub Releases")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.primary.opacity(0.04))

            Divider()

            // Content
            Group {
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Fetching release notes from GitHub…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 40)

                        HStack(spacing: 12) {
                            Button("Retry") {
                                Task { await viewModel.fetchReleases() }
                            }
                            .controlSize(.small)

                            Link("Open GitHub Releases", destination: URL(string: "https://github.com/anksarvesh-lgtm/dynamo-mac/releases")!)
                                .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(Array(viewModel.releases.enumerated()), id: \.element.id) { index, release in
                                ReleaseCard(release: release, isLatest: index == 0)
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
        .frame(minWidth: 540, minHeight: 460)
        .task {
            await viewModel.fetchReleases()
        }
    }
}

private struct ReleaseCard: View {
    let release: GitHubReleaseItem
    let isLatest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(release.tagName)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                if isLatest {
                    Text("Latest")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                if !release.formattedDate.isEmpty {
                    Text("•  \(release.formattedDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let urlStr = release.htmlUrl, let url = URL(string: urlStr) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Text("View on GitHub")
                                .font(.caption.weight(.medium))
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                        }
                    }
                }
            }

            if let body = release.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isLatest ? Color.blue.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: isLatest ? 1.5 : 1)
        )
    }
}
