//
//  GitHubUpdateChecker.swift
//  LiquidDynamo
//
//  Direct GitHub Releases update checker and in-place auto-updater.
//  Always uses the permanent release download link:
//  https://github.com/anksarvesh-lgtm/dynamo-mac/releases/download/app/LiquidDynamo.dmg
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
    
    /// Permanent download link that is guaranteed to stay the same across all releases
    public static let permanentDMGURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/download/app/LiquidDynamo.dmg")!
    
    public static let apiLatestURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
    public static let apiAppTagURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/tags/app")!

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
    
    private var activeDownloadTask: Task<Void, Never>?

    private init() {}

    // MARK: - 1. Check for Updates

    public func checkForUpdates(autoInstall: Bool = false) {
        status = .checking

        Task {
            do {
                var request = URLRequest(url: Self.apiLatestURL)
                request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
                request.setValue("LiquidDynamo/\(Bundle.main.releaseVersionNumber ?? "1.9.6")", forHTTPHeaderField: "User-Agent")
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
                        let currentVersion = Bundle.main.releaseVersionNumber ?? "1.9.6"
                        let body = (json["body"] as? String) ?? "A new update is available on GitHub."

                        self.lastCheckedDate = Date()
                        if Self.isVersion(latestVersion, greaterThan: currentVersion) {
                            self.status = .updateAvailable(newVersion: latestVersion, downloadURL: Self.permanentDMGURL, releaseNotes: body)
                            if autoInstall {
                                self.downloadAndInstallUpdate(from: Self.permanentDMGURL)
                            }
                        } else {
                            self.status = .upToDate(currentVersion: currentVersion)
                        }
                        return
                    }
                }

                self.lastCheckedDate = Date()
                self.status = .upToDate(currentVersion: Bundle.main.releaseVersionNumber ?? "1.9.6")
            } catch {
                self.lastCheckedDate = Date()
                self.status = .upToDate(currentVersion: Bundle.main.releaseVersionNumber ?? "1.9.6")
            }
        }
    }

    // MARK: - 2. Auto-Download and In-Place Replace

    public func downloadAndInstallUpdate(from url: URL? = nil) {
        let downloadTarget = url ?? Self.permanentDMGURL
        activeDownloadTask?.cancel()

        status = .downloading(progress: 0.0, downloadedFormatted: "0 B", totalFormatted: "Calculating…")

        activeDownloadTask = Task {
            do {
                var request = URLRequest(url: downloadTarget)
                request.timeoutInterval = 120
                request.setValue("LiquidDynamo-AutoUpdater", forHTTPHeaderField: "User-Agent")

                let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    throw NSError(domain: "AutoUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: "Download server returned invalid status."])
                }

                let totalBytes = httpResponse.expectedContentLength
                var downloadedBytes: Int64 = 0

                let tempDMGURL = FileManager.default.temporaryDirectory.appendingPathComponent("LiquidDynamo_Update.dmg")
                if FileManager.default.fileExists(atPath: tempDMGURL.path) {
                    try? FileManager.default.removeItem(at: tempDMGURL)
                }
                FileManager.default.createFile(atPath: tempDMGURL.path, contents: nil)
                guard let fileHandle = try? FileHandle(forWritingTo: tempDMGURL) else {
                    throw NSError(domain: "AutoUpdater", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create temporary file for update."])
                }

                var lastUpdate = Date()
                var buffer = Data()
                buffer.reserveCapacity(64 * 1024)

                for try await byte in asyncBytes {
                    if Task.isCancelled {
                        try? fileHandle.close()
                        try? FileManager.default.removeItem(at: tempDMGURL)
                        return
                    }

                    buffer.append(byte)
                    downloadedBytes += 1

                    if buffer.count >= 64 * 1024 {
                        fileHandle.write(buffer)
                        buffer.removeAll(keepingCapacity: true)

                        if Date().timeIntervalSince(lastUpdate) > 0.15 {
                            lastUpdate = Date()
                            let fraction = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0.0
                            self.status = .downloading(
                                progress: fraction,
                                downloadedFormatted: Self.formatBytes(downloadedBytes),
                                totalFormatted: totalBytes > 0 ? Self.formatBytes(totalBytes) : "…"
                            )
                        }
                    }
                }

                if !buffer.isEmpty {
                    fileHandle.write(buffer)
                }
                try? fileHandle.close()

                // Download completed, extract application
                self.status = .extracting
                try await self.extractAndReplaceApplication(dmgURL: tempDMGURL)

            } catch {
                if !Task.isCancelled {
                    self.status = .error(message: error.localizedDescription)
                }
            }
        }
    }

    public func cancelDownload() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        status = .idle
    }

    // MARK: - 3. DMG Extraction and In-Place App Replacement

    private func extractAndReplaceApplication(dmgURL: URL) async throws {
        // Run hdiutil attach to mount the DMG
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
            throw NSError(domain: "AutoUpdater", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to mount downloaded DMG."])
        }

        // Locate LiquidDynamo.app inside the volume
        let enumerator = try? FileManager.default.contentsOfDirectory(atPath: volume)
        guard let appFolder = enumerator?.first(where: { $0.hasSuffix(".app") }) else {
            // Unmount before throwing
            Self.detachVolume(volume)
            throw NSError(domain: "AutoUpdater", code: 4, userInfo: [NSLocalizedDescriptionKey: "LiquidDynamo.app not found inside DMG."])
        }

        let sourceAppURL = URL(fileURLWithPath: volume).appendingPathComponent(appFolder)
        let stagingAppURL = FileManager.default.temporaryDirectory.appendingPathComponent("LiquidDynamo_Staging.app")

        if FileManager.default.fileExists(atPath: stagingAppURL.path) {
            try? FileManager.default.removeItem(at: stagingAppURL)
        }

        // Copy application out of mounted DMG to staging directory
        try FileManager.default.copyItem(at: sourceAppURL, to: stagingAppURL)

        // Detach volume and cleanup DMG
        Self.detachVolume(volume)
        try? FileManager.default.removeItem(at: dmgURL)

        // Validate staged application
        let execURL = stagingAppURL.appendingPathComponent("Contents/MacOS/LiquidDynamo")
        guard FileManager.default.isExecutableFile(atPath: execURL.path) else {
            throw NSError(domain: "AutoUpdater", code: 5, userInfo: [NSLocalizedDescriptionKey: "Corrupted application binary in update."])
        }

        self.status = .replacingAndRelaunching
        try self.spawnRelaunchScript(stagedAppURL: stagingAppURL)
    }

    private static func detachVolume(_ volumePath: String) {
        let detach = Process()
        detach.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        detach.arguments = ["eject", volumePath]
        try? detach.run()
        detach.waitUntilExit()
    }

    private func spawnRelaunchScript(stagedAppURL: URL) throws {
        let currentAppURL = Bundle.main.bundleURL
        let targetAppPath = currentAppURL.path.hasSuffix(".app") ? currentAppURL.path : "/Applications/LiquidDynamo.app"
        let pid = ProcessInfo.processInfo.processIdentifier

        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("liquiddynamo_updater.sh")
        let scriptContent = """
        #!/bin/bash
        TARGET="\(targetAppPath)"
        STAGING="\(stagedAppURL.path)"
        PID="\(pid)"

        # Wait up to 10 seconds for current process to cleanly exit
        COUNT=0
        while kill -0 "$PID" 2>/dev/null && [ $COUNT -lt 100 ]; do
            sleep 0.1
            COUNT=$((COUNT+1))
        done

        # In-place replace the application bundle
        rm -rf "$TARGET"
        cp -R "$STAGING" "$TARGET"
        xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
        rm -rf "$STAGING"

        # Relaunch newly updated application
        open "$TARGET"
        """

        try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let relaunchProcess = Process()
        relaunchProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
        relaunchProcess.arguments = [scriptURL.path]
        try relaunchProcess.run()

        // Terminate old app to let the updater replace it and relaunch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - 4. Utilities

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

    private static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        return v1.compare(v2, options: .numeric) == .orderedDescending
    }
}
