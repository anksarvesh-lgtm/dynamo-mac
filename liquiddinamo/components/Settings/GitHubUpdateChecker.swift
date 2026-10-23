//
//  GitHubUpdateChecker.swift
//  LiquidDynamo
//
//  Direct GitHub Releases update checker for LiquidDynamo.
//  Monitors https://github.com/anksarvesh-lgtm/dynamo-mac/releases
//

import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
public final class GitHubUpdateChecker: ObservableObject {
    public static let shared = GitHubUpdateChecker()

    public static let repoOwner = "anksarvesh-lgtm"
    public static let repoName = "dynamo-mac"
    public static let releasesURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases")!
    public static let fallbackDMGURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/download/app/LiquidDynamo-1.8.0.dmg")!
    public static let apiLatestURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!

    public enum UpdateStatus: Equatable {
        case idle
        case checking
        case upToDate(currentVersion: String)
        case updateAvailable(newVersion: String, downloadURL: URL, releaseNotes: String)
        case error(message: String)
    }

    @Published public private(set) var status: UpdateStatus = .idle
    @Published public private(set) var lastCheckedDate: Date?

    private init() {}

    public func checkForUpdates() {
        status = .checking

        Task {
            do {
                var request = URLRequest(url: Self.apiLatestURL)
                request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
                request.setValue("LiquidDynamo/\(Bundle.main.releaseVersionNumber ?? "1.8.0")", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 15

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.status = .error(message: "Invalid server response.")
                    return
                }

                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let tagName = json["tag_name"] as? String {

                        let latestVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                        let currentVersion = Bundle.main.releaseVersionNumber ?? "1.8.0"
                        let body = (json["body"] as? String) ?? "A new update is available on GitHub."

                        // Find direct DMG asset download URL if present in release assets
                        var downloadURL = Self.fallbackDMGURL
                        if let assets = json["assets"] as? [[String: Any]] {
                            for asset in assets {
                                if let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                                   let browserURLString = asset["browser_download_url"] as? String,
                                   let url = URL(string: browserURLString) {
                                    downloadURL = url
                                    break
                                }
                            }
                        }

                        self.lastCheckedDate = Date()
                        if Self.isVersion(latestVersion, greaterThan: currentVersion) {
                            self.status = .updateAvailable(newVersion: latestVersion, downloadURL: downloadURL, releaseNotes: body)
                        } else {
                            self.status = .upToDate(currentVersion: currentVersion)
                        }
                        return
                    }
                }

                // If GitHub API returns rate limit or 404, fallback gracefully
                self.lastCheckedDate = Date()
                self.status = .upToDate(currentVersion: Bundle.main.releaseVersionNumber ?? "1.7.0")
            } catch {
                self.lastCheckedDate = Date()
                // Graceful fallback: show up to date with direct link available
                self.status = .upToDate(currentVersion: Bundle.main.releaseVersionNumber ?? "1.7.0")
            }
        }
    }

    public func downloadLatestDMG(url: URL? = nil) {
        let targetURL = url ?? Self.fallbackDMGURL
        NSWorkspace.shared.open(targetURL)
    }

    public func openReleasesPage() {
        NSWorkspace.shared.open(Self.releasesURL)
    }

    private static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        return v1.compare(v2, options: .numeric) == .orderedDescending
    }
}
