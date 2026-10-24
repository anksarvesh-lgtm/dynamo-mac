//
//  GitHubUpdateChecker.swift
//  LiquidDynamo
//
//  Direct GitHub Releases update checker and in-place auto-updater.
//  Pulls liquiddynamo.zip / liquiddynamo.app or DMG, installs to /Applications,
//  triggers Dynamic Island notifications, and displays section update banners.
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
    public static let fallbackRepoName = "dynamomac"
    public static let releasesURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases")!

    /// Permanent direct zip download link containing liquiddynamo.app
    public static let permanentZipURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/download/app/liquiddynamo.zip")!

    /// Permanent fallback DMG download link
    public static let permanentDMGURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/download/app/LiquidDynamo.dmg")!

    public static let apiLatestURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
    public static let apiFallbackLatestURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(fallbackRepoName)/releases/latest")!

    public enum UpdateStatus: Equatable {
        case idle
        case checking
        case upToDate(currentVersion: String)
        case updateAvailable(newVersion: String, downloadURL: URL, releaseNotes: String)
        case downloading(progress: Double, downloadedFormatted: String, totalFormatted: String)
        case extracting
        case replacingAndRelaunching
        case error(message: String)
    }

    @Published public private(set) var status: UpdateStatus = .idle
    @Published public private(set) var lastCheckedDate: Date?

    // Quick-access reactive flags for UI banners and Island HUD
    @Published public private(set) var isUpdateAvailable: Bool = false
    @Published public private(set) var latestVersionString: String = ""
    @Published public private(set) var releaseNotesString: String = ""
    @Published public private(set) var resolvedDownloadURL: URL? = nil
    @Published public private(set) var isDownloading: Bool = false
    @Published public private(set) var downloadProgress: Double = 0.0
    @Published public private(set) var downloadStatusFormatted: String = ""
    @Published public var isBannerDismissed: Bool = false

    private var activeDownloadTask: Task<Void, Never>?

    private init() {}

    // MARK: - 1. Check for Updates

    public func checkForUpdates(silent: Bool = false, autoInstall: Bool = false) {
        status = .checking
        if !silent {
            isBannerDismissed = false
        }

        Task {
            do {
                let releaseInfo = try await fetchLatestRelease()
                self.lastCheckedDate = Date()

                let currentVersion = Bundle.main.releaseVersionNumber ?? "2.0.0"
                let latestVersion = releaseInfo.version

                if Self.isVersion(latestVersion, greaterThan: currentVersion) {
                    let targetURL = releaseInfo.downloadURL ?? Self.permanentZipURL
                    self.isUpdateAvailable = true
                    self.latestVersionString = latestVersion
                    self.releaseNotesString = releaseInfo.body
                    self.resolvedDownloadURL = targetURL
                    self.status = .updateAvailable(newVersion: latestVersion, downloadURL: targetURL, releaseNotes: releaseInfo.body)

                    // Post update notification directly in the Dynamic Island
                    self.triggerIslandUpdateAlert(version: latestVersion)

                    if autoInstall {
                        self.downloadAndInstallUpdate(from: targetURL)
                    }
                } else {
                    self.isUpdateAvailable = false
                    self.status = .upToDate(currentVersion: currentVersion)
                }
            } catch {
                self.lastCheckedDate = Date()
                let currentVersion = Bundle.main.releaseVersionNumber ?? "2.0.0"
                if silent {
                    self.status = .upToDate(currentVersion: currentVersion)
                } else {
                    self.status = .error(message: error.localizedDescription)
                }
            }
        }
    }

    private struct ReleasePayload {
        let version: String
        let body: String
        let downloadURL: URL?
    }

    private func fetchLatestRelease() async throws -> ReleasePayload {
        // Try primary repository first, then fallback repository
        let urls = [Self.apiLatestURL, Self.apiFallbackLatestURL]

        var lastError: Error? = nil
        for url in urls {
            do {
                var request = URLRequest(url: url)
                request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
                request.setValue("LiquidDynamo/\(Bundle.main.releaseVersionNumber ?? "2.0.0")", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 12

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    continue
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    continue
                }

                let cleanVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                let body = (json["body"] as? String) ?? "A new version of LiquidDynamo is available."

                var chosenURL: URL? = nil
                if let assets = json["assets"] as? [[String: Any]] {
                    // Prioritize liquiddynamo.zip (contains liquiddynamo.app bundle)
                    if let zipAsset = assets.first(where: {
                        let name = ($0["name"] as? String)?.lowercased() ?? ""
                        return name == "liquiddynamo.zip" || name.hasSuffix(".zip")
                    }), let downloadStr = zipAsset["browser_download_url"] as? String, let url = URL(string: downloadStr) {
                        chosenURL = url
                    } else if let dmgAsset = assets.first(where: {
                        let name = ($0["name"] as? String)?.lowercased() ?? ""
                        return name.hasSuffix(".dmg")
                    }), let downloadStr = dmgAsset["browser_download_url"] as? String, let url = URL(string: downloadStr) {
                        chosenURL = url
                    }
                }

                return ReleasePayload(
                    version: cleanVersion,
                    body: body,
                    downloadURL: chosenURL ?? Self.permanentZipURL
                )
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NSError(domain: "GitHubUpdateChecker", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not find latest release on GitHub."])
    }

    // MARK: - 2. Dynamic Island Alert Notification

    public func triggerIslandUpdateAlert(version: String) {
        let payload = AlertPayload(
            id: "liquiddynamo-update-\(version)",
            kind: .custom(title: "Update Available", subtitle: "LiquidDynamo v\(version) is ready to install", icon: "arrow.down.circle.fill"),
            title: "LiquidDynamo v\(version)",
            subtitle: "Update available • Click to install",
            iconName: "arrow.down.circle.fill",
            iconColor: Color(red: 0.22, green: 0.58, blue: 1.0),
            dwellDuration: 7.0,
            action: { [weak self] in
                self?.downloadAndInstallUpdate()
            }
        )

        IslandController.shared.showAlert(payload: payload)
    }

    // MARK: - 3. Auto-Download and In-Place Replace in /Applications

    private func sanitizeDownloadURL(_ url: URL) -> URL {
        var str = url.absoluteString
        if str.contains("banksarvesh-lgtm/dynamomac") {
            str = str.replacingOccurrences(of: "banksarvesh-lgtm/dynamomac", with: "\(Self.repoOwner)/\(Self.repoName)")
        }
        return URL(string: str) ?? url
    }

    private func buildDownloadCandidates(targetURL: URL?) -> [URL] {
        var candidates: [URL] = []
        var seen = Set<String>()

        func add(_ url: URL?) {
            guard let url = url else { return }
            let sanitized = sanitizeDownloadURL(url)
            let key = sanitized.absoluteString.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                candidates.append(sanitized)
            }
        }

        // 1. Explicit target URL passed in
        add(targetURL)

        // 2. Previously resolved URL from GitHub API
        add(resolvedDownloadURL)

        // 3. Tag-specific ZIP releases across primary and fallback repos
        let version = latestVersionString.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        if !version.isEmpty {
            add(URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/download/v\(version)/liquiddynamo.zip"))
            add(URL(string: "https://github.com/\(Self.repoOwner)/\(Self.fallbackRepoName)/releases/download/v\(version)/liquiddynamo.zip"))
        }

        // 4. Permanent ZIP download link (releases/download/app/liquiddynamo.zip)
        add(Self.permanentZipURL)
        add(URL(string: "https://github.com/\(Self.repoOwner)/\(Self.fallbackRepoName)/releases/download/app/liquiddynamo.zip"))

        // 5. Tag-specific DMG releases
        if !version.isEmpty {
            add(URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/download/v\(version)/LiquidDynamo-\(version).dmg"))
            add(URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/download/v\(version)/LiquidDynamo.dmg"))
            add(URL(string: "https://github.com/\(Self.repoOwner)/\(Self.fallbackRepoName)/releases/download/v\(version)/LiquidDynamo-\(version).dmg"))
            add(URL(string: "https://github.com/\(Self.repoOwner)/\(Self.fallbackRepoName)/releases/download/v\(version)/LiquidDynamo.dmg"))
        }

        // 6. Permanent DMG fallback
        add(Self.permanentDMGURL)
        add(URL(string: "https://github.com/\(Self.repoOwner)/\(Self.fallbackRepoName)/releases/download/app/LiquidDynamo.dmg"))

        return candidates
    }

    public func downloadAndInstallUpdate(from url: URL? = nil) {
        activeDownloadTask?.cancel()

        isDownloading = true
        downloadProgress = 0.0
        downloadStatusFormatted = "Preparing download…"
        status = .downloading(progress: 0.0, downloadedFormatted: "0 B", totalFormatted: "Connecting…")

        activeDownloadTask = Task {
            // If we don't have the latest version string or resolved download URL yet, fetch release info first
            if self.latestVersionString.isEmpty || self.resolvedDownloadURL == nil {
                if let release = try? await self.fetchLatestRelease() {
                    self.latestVersionString = release.version
                    if self.resolvedDownloadURL == nil {
                        self.resolvedDownloadURL = release.downloadURL
                    }
                }
            }

            let candidates = self.buildDownloadCandidates(targetURL: url)
            guard !candidates.isEmpty else {
                self.isDownloading = false
                self.status = .error(message: "No valid download URLs found.")
                return
            }

            var lastError: Error? = nil
            var succeeded = false

            for (index, candidateURL) in candidates.enumerated() {
                if Task.isCancelled { break }

                let isZip = candidateURL.lastPathComponent.lowercased().hasSuffix(".zip") || candidateURL.absoluteString.contains(".zip")
                let tempDownloadURL = FileManager.default.temporaryDirectory.appendingPathComponent(isZip ? "liquiddynamo_update.zip" : "liquiddynamo_update.dmg")

                do {
                    if index > 0 {
                        self.downloadStatusFormatted = "Retrying download (mirror \(index + 1))…"
                    } else {
                        self.downloadStatusFormatted = "Connecting to download server…"
                    }

                    var request = URLRequest(url: candidateURL)
                    request.timeoutInterval = 120
                    request.setValue("LiquidDynamo-AutoUpdater", forHTTPHeaderField: "User-Agent")

                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw NSError(domain: "AutoUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
                    }

                    // If non-2xx (e.g. 404, 403, 500), throw to fall back to the next candidate
                    guard (200...299).contains(httpResponse.statusCode) else {
                        throw NSError(domain: "AutoUpdater", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Download server returned HTTP \(httpResponse.statusCode)."])
                    }

                    let totalBytes = httpResponse.expectedContentLength
                    var downloadedBytes: Int64 = 0

                    if FileManager.default.fileExists(atPath: tempDownloadURL.path) {
                        try? FileManager.default.removeItem(at: tempDownloadURL)
                    }
                    FileManager.default.createFile(atPath: tempDownloadURL.path, contents: nil)
                    guard let fileHandle = try? FileHandle(forWritingTo: tempDownloadURL) else {
                        throw NSError(domain: "AutoUpdater", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create temporary download file."])
                    }

                    var lastUpdate = Date()
                    var buffer = Data()
                    buffer.reserveCapacity(64 * 1024)

                    for try await byte in asyncBytes {
                        if Task.isCancelled {
                            try? fileHandle.close()
                            try? FileManager.default.removeItem(at: tempDownloadURL)
                            self.isDownloading = false
                            return
                        }

                        buffer.append(byte)
                        downloadedBytes += 1

                        if buffer.count >= 64 * 1024 {
                            fileHandle.write(buffer)
                            buffer.removeAll(keepingCapacity: true)

                            if Date().timeIntervalSince(lastUpdate) > 0.12 {
                                lastUpdate = Date()
                                let fraction = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0.0
                                let downloadedStr = Self.formatBytes(downloadedBytes)
                                let totalStr = totalBytes > 0 ? Self.formatBytes(totalBytes) : "…"
                                self.downloadProgress = fraction
                                self.downloadStatusFormatted = "\(downloadedStr) / \(totalStr)"
                                self.status = .downloading(
                                    progress: fraction,
                                    downloadedFormatted: downloadedStr,
                                    totalFormatted: totalStr
                                )
                            }
                        }
                    }

                    if !buffer.isEmpty {
                        fileHandle.write(buffer)
                    }
                    try? fileHandle.close()

                    // Verify file size is non-empty (> 1MB)
                    let downloadedFileSize = (try? FileManager.default.attributesOfItem(atPath: tempDownloadURL.path)[.size] as? Int64) ?? 0
                    guard downloadedFileSize > 1024 * 1024 else {
                        try? FileManager.default.removeItem(at: tempDownloadURL)
                        throw NSError(domain: "AutoUpdater", code: 8, userInfo: [NSLocalizedDescriptionKey: "Incomplete download file."])
                    }

                    // Download completed successfully
                    succeeded = true
                    self.status = .extracting
                    self.downloadStatusFormatted = "Extracting application…"

                    if isZip {
                        try await self.extractAndReplaceFromZip(zipURL: tempDownloadURL)
                    } else {
                        try await self.extractAndReplaceFromDMG(dmgURL: tempDownloadURL)
                    }

                    break // Successful download and trigger, exit loop

                } catch {
                    lastError = error
                    try? FileManager.default.removeItem(at: tempDownloadURL)
                    if Task.isCancelled {
                        self.isDownloading = false
                        return
                    }
                    print("⚠️ AutoUpdater download candidate \(candidateURL.absoluteString) failed: \(error.localizedDescription). Trying next candidate...")
                }
            }

            if !succeeded && !Task.isCancelled {
                self.isDownloading = false
                self.status = .error(message: lastError?.localizedDescription ?? "Download failed. Please check internet connection.")
            }
        }
    }

    public func cancelDownload() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        isDownloading = false
        status = .idle
    }

    public func dismissBanner() {
        isBannerDismissed = true
    }

    // MARK: - 4. Extraction & In-Place Replacement in /Applications

    private func extractAndReplaceFromZip(zipURL: URL) async throws {
        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent("LiquidDynamo_Staging_\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: stagingDir)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        // Unpack zip using ditto to preserve symlinks, attributes, and signatures
        let dittoProcess = Process()
        dittoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        dittoProcess.arguments = ["-x", "-k", zipURL.path, stagingDir.path]

        let pipe = Pipe()
        dittoProcess.standardError = pipe
        try dittoProcess.run()
        dittoProcess.waitUntilExit()

        try? FileManager.default.removeItem(at: zipURL)

        guard dittoProcess.terminationStatus == 0 else {
            let err = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "ditto failed"
            throw NSError(domain: "AutoUpdater", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to extract update zip: \(err)"])
        }

        // Find .app bundle inside staging directory
        let items = (try? FileManager.default.contentsOfDirectory(atPath: stagingDir.path)) ?? []
        guard let appFolder = items.first(where: { $0.hasSuffix(".app") }) else {
            throw NSError(domain: "AutoUpdater", code: 4, userInfo: [NSLocalizedDescriptionKey: "No application bundle found inside update archive."])
        }

        let stagedAppURL = stagingDir.appendingPathComponent(appFolder)
        try self.validateAndRelaunch(stagedAppURL: stagedAppURL)
    }

    private func extractAndReplaceFromDMG(dmgURL: URL) async throws {
        let attachProcess = Process()
        attachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attachProcess.arguments = ["attach", "-nobrowse", "-readonly", "-noverify", "-noautoopen", dmgURL.path]

        let pipe = Pipe()
        attachProcess.standardOutput = pipe
        attachProcess.standardError = Pipe()
        try attachProcess.run()
        attachProcess.waitUntilExit()

        let attachOutput = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var mountPoint: String? = nil
        for line in attachOutput.components(separatedBy: "\n") {
            let cols = line.components(separatedBy: "\t")
            if let last = cols.last?.trimmingCharacters(in: .whitespacesAndNewlines), last.contains("/Volumes/") {
                mountPoint = last
                break
            }
        }

        guard let volume = mountPoint, FileManager.default.fileExists(atPath: volume) else {
            throw NSError(domain: "AutoUpdater", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to mount downloaded DMG."])
        }

        let enumerator = try? FileManager.default.contentsOfDirectory(atPath: volume)
        guard let appFolder = enumerator?.first(where: { $0.hasSuffix(".app") }) else {
            Self.detachVolume(volume)
            throw NSError(domain: "AutoUpdater", code: 6, userInfo: [NSLocalizedDescriptionKey: "LiquidDynamo application not found inside DMG."])
        }

        let sourceAppURL = URL(fileURLWithPath: volume).appendingPathComponent(appFolder)
        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent("LiquidDynamo_Staging_\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: stagingDir)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stagedAppURL = stagingDir.appendingPathComponent(appFolder)

        try FileManager.default.copyItem(at: sourceAppURL, to: stagedAppURL)

        Self.detachVolume(volume)
        try? FileManager.default.removeItem(at: dmgURL)

        try self.validateAndRelaunch(stagedAppURL: stagedAppURL)
    }

    private func validateAndRelaunch(stagedAppURL: URL) throws {
        // Validate staged application binary exists
        let macosDir = stagedAppURL.appendingPathComponent("Contents/MacOS")
        let execs = (try? FileManager.default.contentsOfDirectory(atPath: macosDir.path)) ?? []
        guard !execs.isEmpty else {
            throw NSError(domain: "AutoUpdater", code: 7, userInfo: [NSLocalizedDescriptionKey: "Corrupted application binary in update bundle."])
        }

        self.status = .replacingAndRelaunching
        self.downloadStatusFormatted = "Installing update to /Applications…"
        try self.spawnRelaunchScript(stagedAppURL: stagedAppURL)
    }

    private static func detachVolume(_ volumePath: String) {
        let detach = Process()
        detach.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        detach.arguments = ["eject", volumePath]
        try? detach.run()
        detach.waitUntilExit()
    }

    private func spawnRelaunchScript(stagedAppURL: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier

        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("liquiddynamo_inplace_updater.sh")
        let scriptContent = """
        #!/bin/bash
        TARGET_PRIMARY="/Applications/liquiddynamo.app"
        TARGET_SECONDARY="/Applications/LiquidDynamo.app"
        STAGING="\(stagedAppURL.path)"
        PID="\(pid)"

        # 1. Wait up to 10 seconds for current process to cleanly exit
        COUNT=0
        while kill -0 "$PID" 2>/dev/null && [ $COUNT -lt 100 ]; do
            sleep 0.1
            COUNT=$((COUNT+1))
        done

        # 2. In-place replace both /Applications/liquiddynamo.app and /Applications/LiquidDynamo.app
        rm -rf "$TARGET_PRIMARY"
        cp -R "$STAGING" "$TARGET_PRIMARY"
        xattr -dr com.apple.quarantine "$TARGET_PRIMARY" 2>/dev/null || true

        rm -rf "$TARGET_SECONDARY"
        cp -R "$STAGING" "$TARGET_SECONDARY"
        xattr -dr com.apple.quarantine "$TARGET_SECONDARY" 2>/dev/null || true

        # Clean staging
        rm -rf "$(dirname "$STAGING")" 2>/dev/null || true

        # 3. Relaunch newly updated application
        if [ -d "$TARGET_PRIMARY" ]; then
            open "$TARGET_PRIMARY"
        else
            open "$TARGET_SECONDARY"
        fi
        """

        try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let relaunchProcess = Process()
        relaunchProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
        relaunchProcess.arguments = [scriptURL.path]
        try relaunchProcess.run()

        // Terminate old app cleanly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - 5. Utilities

    public func downloadLatestDMG(url: URL? = nil) {
        let targetURL = url ?? Self.permanentDMGURL
        NSWorkspace.shared.open(targetURL)
    }

    public func openReleasesPage() {
        NSWorkspace.shared.open(Self.releasesURL)
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    public static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        return clean1.compare(clean2, options: .numeric) == .orderedDescending
    }
}
