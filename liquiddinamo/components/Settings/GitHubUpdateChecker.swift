//
//  GitHubUpdateChecker.swift
//  LiquidDynamo
//
//  Direct GitHub Releases update checker and in-place auto-updater.
//  Cryptographically verifies application signatures, validates Team IDs,
//  checks strict Semantic Versions, and performs safe atomic replacements with rollback.
//

import AppKit
import Combine
import Defaults
import Foundation
import Security
import SwiftUI

// MARK: - Semantic Version 2.0 Parser & Comparator

public struct SemanticVersion: Comparable, CustomStringConvertible, Equatable, Hashable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [String]
    public let buildMetadata: String?

    public init?(_ string: String) {
        var str = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("v") || str.hasPrefix("V") {
            str.removeFirst()
        }
        str = str.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return nil }

        // 1. Separate build metadata (+...)
        let buildParts = str.components(separatedBy: "+")
        let versionAndPrerelease = buildParts[0]
        self.buildMetadata = buildParts.count > 1 ? buildParts.dropFirst().joined(separator: "+") : nil

        // 2. Separate pre-release (-...)
        let preParts = versionAndPrerelease.components(separatedBy: "-")
        let numericPart = preParts[0]
        if preParts.count > 1 {
            let preString = preParts.dropFirst().joined(separator: "-")
            self.prerelease = preString.components(separatedBy: ".").filter { !$0.isEmpty }
        } else {
            self.prerelease = []
        }

        // 3. Separate major.minor.patch
        let coreNums = numericPart.components(separatedBy: ".")
        guard let majorInt = Int(coreNums[0]), majorInt >= 0 else { return nil }
        self.major = majorInt

        if coreNums.count > 1 {
            guard let minorInt = Int(coreNums[1]), minorInt >= 0 else { return nil }
            self.minor = minorInt
        } else {
            self.minor = 0
        }

        if coreNums.count > 2 {
            guard let patchInt = Int(coreNums[2]), patchInt >= 0 else { return nil }
            self.patch = patchInt
        } else {
            self.patch = 0
        }
    }

    public var description: String {
        var res = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty {
            res += "-" + prerelease.joined(separator: ".")
        }
        if let b = buildMetadata {
            res += "+" + b
        }
        return res
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }

        // SemVer 2.0.0 Precedence rule:
        // When major, minor, and patch are equal, a normal version has higher precedence than a pre-release version:
        // Example: 1.0.0-alpha < 1.0.0, 2.8-rc.1 < 2.8
        if lhs.prerelease.isEmpty && !rhs.prerelease.isEmpty {
            return false // lhs normal (higher), rhs pre-release (lower)
        }
        if !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty {
            return true  // lhs pre-release (lower), rhs normal (higher)
        }
        if lhs.prerelease.isEmpty && rhs.prerelease.isEmpty {
            return false // both equal normal versions
        }

        // Compare pre-release identifiers dot-by-dot
        let minCount = min(lhs.prerelease.count, rhs.prerelease.count)
        for i in 0..<minCount {
            let leftId = lhs.prerelease[i]
            let rightId = rhs.prerelease[i]
            if leftId == rightId { continue }

            let leftNum = Int(leftId)
            let rightNum = Int(rightId)

            switch (leftNum, rightNum) {
            case let (.some(l), .some(r)):
                return l < r
            case (.some, .none):
                // Numeric identifier has lower precedence than non-numeric
                return true
            case (.none, .some):
                // Non-numeric identifier has higher precedence than numeric
                return false
            case (.none, .none):
                // Lexical ASCII comparison
                return leftId < rightId
            }
        }

        // Larger set of pre-release fields has higher precedence than a smaller set
        return lhs.prerelease.count < rhs.prerelease.count
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        return lhs.major == rhs.major &&
               lhs.minor == rhs.minor &&
               lhs.patch == rhs.patch &&
               lhs.prerelease == rhs.prerelease
    }
}

// MARK: - Update Security Verification Errors

public enum UpdateSecurityError: LocalizedError {
    case invalidURL(String)
    case missingBinary
    case bundleIdentifierMismatch(found: String, expected: String)
    case codeSignatureVerificationFailed(String)
    case teamIDMismatch(found: String, expected: String)
    case gatekeeperRejected(String)
    case versionNotNewer(found: String, current: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let msg):
            return "Invalid update URL: \(msg)"
        case .missingBinary:
            return "The downloaded update bundle has no executable binary in Contents/MacOS."
        case .bundleIdentifierMismatch(let found, let expected):
            return "Security violation: update bundle ID (\(found)) does not match app bundle ID (\(expected))."
        case .codeSignatureVerificationFailed(let msg):
            return "Cryptographic code signature verification failed: \(msg)"
        case .teamIDMismatch(let found, let expected):
            return "Security violation: update is signed by Team ID '\(found)', expected '\(expected)'."
        case .gatekeeperRejected(let msg):
            return "Gatekeeper assessment rejected update: \(msg)"
        case .versionNotNewer(let found, let current):
            return "Update version \(found) is not newer than current installed version \(current)."
        }
    }
}

// MARK: - High-Speed Stream Download Delegate & Thread-Safe LockBox

private final class DownloadLockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var isResumed = false

    func resumeOnce(continuation: CheckedContinuation<URL, Error>, result: Result<URL, Error>) {
        lock.lock()
        defer { lock.unlock() }
        if !isResumed {
            isResumed = true
            continuation.resume(with: result)
        }
    }
}

private final class HighSpeedDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double, Int64, Int64) -> Void
    private let onFinish: @Sendable (Result<URL, Error>) -> Void
    private let lastUpdateLock = NSLock()
    private var lastUpdateTime = Date.distantPast

    init(
        onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void,
        onFinish: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        self.onProgress = onProgress
        self.onFinish = onFinish
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = Date()
        lastUpdateLock.lock()
        let shouldUpdate = now.timeIntervalSince(lastUpdateTime) >= 0.08 || totalBytesWritten == totalBytesExpectedToWrite
        if shouldUpdate {
            lastUpdateTime = now
        }
        lastUpdateLock.unlock()

        if shouldUpdate {
            let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
            onProgress(progress, totalBytesWritten, totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tempTarget = FileManager.default.temporaryDirectory.appendingPathComponent("ld_dl_\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: tempTarget)
            onFinish(.success(tempTarget))
        } catch {
            onFinish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onFinish(.failure(error))
        }
    }
}

// MARK: - GitHubUpdateChecker

@MainActor
public final class GitHubUpdateChecker: ObservableObject {
    public static let shared = GitHubUpdateChecker()

    public static let repoOwner = "anksarvesh-lgtm"
    public static let repoName = "dynamo-mac"
    public static let releasesURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases")!
    public static let apiLatestURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!

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
    private var periodicCheckTimer: Timer?

    private init() {}

    // MARK: - 1. Check for Updates

    public func startBackgroundUpdateScheduler(interval: TimeInterval = 1800) {
        periodicCheckTimer?.invalidate()
        periodicCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if Defaults[.autoCheckUpdates] {
                    self.checkForUpdates(silent: true, autoInstall: Defaults[.autoDownloadAndInstallUpdates])
                }
            }
        }
    }

    public func checkForUpdates(silent: Bool = false, autoInstall: Bool = false) {
        let effectiveAutoInstall = autoInstall || Defaults[.autoDownloadAndInstallUpdates]

        // Enforce user privacy preference: skip background checks when disabled
        if silent && !Defaults[.autoCheckUpdates] {
            return
        }

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
                    guard let targetURL = releaseInfo.downloadURL else {
                        throw NSError(domain: "GitHubUpdateChecker", code: 404, userInfo: [NSLocalizedDescriptionKey: "Release has no download assets."])
                    }
                    self.isUpdateAvailable = true
                    self.latestVersionString = latestVersion
                    self.releaseNotesString = releaseInfo.body
                    self.resolvedDownloadURL = targetURL
                    self.status = .updateAvailable(newVersion: latestVersion, downloadURL: targetURL, releaseNotes: releaseInfo.body)

                    // Post update notification directly in the Dynamic Island
                    self.triggerIslandUpdateAlert(version: latestVersion)

                    if effectiveAutoInstall {
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
        var request = URLRequest(url: Self.apiLatestURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("LiquidDynamo/\(Bundle.main.releaseVersionNumber ?? "2.0.0")", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tagName = json["tag_name"] as? String {
                let cleanVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                let body = (json["body"] as? String) ?? "A new version of LiquidDynamo is available."

                var chosenURL: URL? = nil
                if let assets = json["assets"] as? [[String: Any]] {
                    // Prioritize liquiddynamo.zip (contains application bundle)
                    if let zipAsset = assets.first(where: {
                        let name = ($0["name"] as? String)?.lowercased() ?? ""
                        return name == "liquiddynamo.zip" || name.hasSuffix(".zip")
                    }), let downloadStr = zipAsset["browser_download_url"] as? String, let url = URL(string: downloadStr) {
                        if (try? Self.validateDownloadURL(url)) != nil {
                            chosenURL = url
                        }
                    } else if let dmgAsset = assets.first(where: {
                        let name = ($0["name"] as? String)?.lowercased() ?? ""
                        return name.hasSuffix(".dmg")
                    }), let downloadStr = dmgAsset["browser_download_url"] as? String, let url = URL(string: downloadStr) {
                        if (try? Self.validateDownloadURL(url)) != nil {
                            chosenURL = url
                        }
                    }
                }

                if chosenURL == nil && !cleanVersion.isEmpty {
                    chosenURL = URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/download/v\(cleanVersion)/liquiddynamo.zip")
                }

                return ReleasePayload(
                    version: cleanVersion,
                    body: body,
                    downloadURL: chosenURL
                )
            }
        } catch {
            // Fall through to unauthenticated HTML redirect fallback
        }

        // Fallback: Query GitHub releases/latest redirect URL (bypasses unauthenticated API rate limits completely)
        var headRequest = URLRequest(url: URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/latest")!)
        headRequest.httpMethod = "HEAD"
        headRequest.setValue("LiquidDynamo/\(Bundle.main.releaseVersionNumber ?? "2.0.0")", forHTTPHeaderField: "User-Agent")
        headRequest.timeoutInterval = 12

        let (_, redirectResponse) = try await URLSession.shared.data(for: headRequest)
        if let finalURL = redirectResponse.url {
            let lastComponent = finalURL.lastPathComponent
            let cleanVersion = lastComponent.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            if !cleanVersion.isEmpty && SemanticVersion(cleanVersion) != nil {
                let targetZip = URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/download/v\(cleanVersion)/liquiddynamo.zip")
                return ReleasePayload(
                    version: cleanVersion,
                    body: "LiquidDynamo v\(cleanVersion) is available with performance and security enhancements.",
                    downloadURL: targetZip
                )
            }
        }

        throw NSError(domain: "GitHubUpdateChecker", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not fetch release from GitHub API or release mirrors."])
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

    // MARK: - 3. Download Candidates & Strict HTTPS Verification

    public static func validateDownloadURL(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            throw UpdateSecurityError.invalidURL("Insecure protocol: '\(url.scheme ?? "none")'. Strict HTTPS is required.")
        }
        guard let host = url.host?.lowercased(),
              host == "github.com" || host.hasSuffix(".github.com") || host == "objects.githubusercontent.com" else {
            throw UpdateSecurityError.invalidURL("Untrusted download host '\(url.host ?? "unknown")'. Only official GitHub hosts are permitted.")
        }
    }

    private func buildDownloadCandidates(targetURL: URL?) -> [URL] {
        var candidates: [URL] = []
        var seen = Set<String>()

        func add(_ url: URL?) {
            guard let url = url else { return }
            guard (try? Self.validateDownloadURL(url)) != nil else { return }
            let key = url.absoluteString.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                candidates.append(url)
            }
        }

        // 1. Explicit target URL passed in (must be HTTPS from official release)
        add(targetURL)

        // 2. Previously resolved URL from GitHub API
        add(resolvedDownloadURL)

        // 3. Strict version-pinned release assets from official repository
        let version = latestVersionString.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        if !version.isEmpty {
            add(URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/download/v\(version)/liquiddynamo.zip"))
            add(URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/download/v\(version)/LiquidDynamo-\(version).dmg"))
            add(URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/download/v\(version)/LiquidDynamo.dmg"))
        }

        return candidates
    }

    public func downloadAndInstallUpdate(from url: URL? = nil) {
        activeDownloadTask?.cancel()

        isDownloading = true
        downloadProgress = 0.0
        downloadStatusFormatted = "Preparing download…"
        status = .downloading(progress: 0.0, downloadedFormatted: "0 B", totalFormatted: "Connecting…")

        activeDownloadTask = Task {
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
                self.status = .error(message: "No valid secure download URLs found.")
                return
            }

            var lastError: Error? = nil
            var succeeded = false

            for (index, candidateURL) in candidates.enumerated() {
                if Task.isCancelled { break }

                let isZip = candidateURL.lastPathComponent.lowercased().hasSuffix(".zip") || candidateURL.absoluteString.contains(".zip")
                let tempDownloadURL = FileManager.default.temporaryDirectory.appendingPathComponent(isZip ? "liquiddynamo_update_\(UUID().uuidString).zip" : "liquiddynamo_update_\(UUID().uuidString).dmg")

                do {
                    if index > 0 {
                        self.downloadStatusFormatted = "Retrying download (mirror \(index + 1))…"
                    } else {
                        self.downloadStatusFormatted = "Connecting to download server…"
                    }

                    var request = URLRequest(url: candidateURL)
                    request.timeoutInterval = 60
                    request.setValue("LiquidDynamo-AutoUpdater", forHTTPHeaderField: "User-Agent")

                    let lockBox = DownloadLockBox()
                    let downloadedTempURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                        let delegate = HighSpeedDownloadDelegate(
                            onProgress: { [weak self] progress, downloadedBytes, totalBytes in
                                Task { @MainActor [weak self] in
                                    guard let self = self else { return }
                                    self.downloadProgress = progress
                                    let downloadedStr = Self.formatBytes(downloadedBytes)
                                    let totalStr = totalBytes > 0 ? Self.formatBytes(totalBytes) : "…"
                                    self.downloadStatusFormatted = "\(downloadedStr) / \(totalStr)"
                                    self.status = .downloading(
                                        progress: progress,
                                        downloadedFormatted: downloadedStr,
                                        totalFormatted: totalStr
                                    )
                                }
                            },
                            onFinish: { result in
                                lockBox.resumeOnce(continuation: continuation, result: result)
                            }
                        )

                        let sessionConfig = URLSessionConfiguration.default
                        sessionConfig.timeoutIntervalForRequest = 20
                        sessionConfig.timeoutIntervalForResource = 300
                        sessionConfig.waitsForConnectivity = true
                        sessionConfig.httpMaximumConnectionsPerHost = 8
                        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData

                        let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
                        let downloadTask = session.downloadTask(with: request)
                        downloadTask.resume()
                    }

                    if FileManager.default.fileExists(atPath: tempDownloadURL.path) {
                        try? FileManager.default.removeItem(at: tempDownloadURL)
                    }
                    try FileManager.default.moveItem(at: downloadedTempURL, to: tempDownloadURL)

                    let downloadedFileSize = (try? FileManager.default.attributesOfItem(atPath: tempDownloadURL.path)[.size] as? Int64) ?? 0
                    guard downloadedFileSize > 1024 * 1024 else {
                        try? FileManager.default.removeItem(at: tempDownloadURL)
                        throw NSError(domain: "AutoUpdater", code: 8, userInfo: [NSLocalizedDescriptionKey: "Downloaded file is incomplete (less than 1 MB)."])
                    }

                    succeeded = true
                    self.status = .extracting
                    self.downloadStatusFormatted = "Verifying and staging application…"

                    if isZip {
                        try await self.extractAndReplaceFromZip(zipURL: tempDownloadURL)
                    } else {
                        try await self.extractAndReplaceFromDMG(dmgURL: tempDownloadURL)
                    }

                    break

                } catch {
                    lastError = error
                    try? FileManager.default.removeItem(at: tempDownloadURL)
                    if Task.isCancelled {
                        self.isDownloading = false
                        return
                    }
                    print("⚠️ AutoUpdater candidate failed: \(error.localizedDescription)")
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
        // Checksum verification is strictly preserved by omitting '-noverify'
        attachProcess.arguments = ["attach", "-nobrowse", "-readonly", "-noautoopen", dmgURL.path]

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
            throw NSError(domain: "AutoUpdater", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to mount downloaded DMG with verification."])
        }

        let enumerator = try? FileManager.default.contentsOfDirectory(atPath: volume)
        guard let appFolder = enumerator?.first(where: { $0.hasSuffix(".app") }) else {
            Self.detachVolume(volume)
            throw NSError(domain: "AutoUpdater", code: 6, userInfo: [NSLocalizedDescriptionKey: "LiquidDynamo application bundle not found inside DMG volume."])
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

    // MARK: - 5. Cryptographic Security & Integrity Verification

    public static func verifyCodeSignature(at appURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", appURL.path]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit code \(process.terminationStatus)"
            throw UpdateSecurityError.codeSignatureVerificationFailed(errMsg)
        }
    }

    public static func extractTeamID(from appURL: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode = staticCode else {
            return nil
        }
        var infoCF: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess,
              let info = infoCF as? [String: Any] else {
            return nil
        }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }

    public static func currentTeamID() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code = code else {
            return nil
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode = staticCode else {
            return nil
        }
        var infoCF: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess,
              let info = infoCF as? [String: Any] else {
            return nil
        }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }

    public static func verifyGatekeeperAssessment(at appURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
        process.arguments = ["--assess", "--type", "execute", appURL.path]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit code \(process.terminationStatus)"
            throw UpdateSecurityError.gatekeeperRejected(errMsg)
        }
    }

    public func validateStagedApp(stagedAppURL: URL) throws {
        // 1. Validate executable binary exists inside MacOS directory
        let macosDir = stagedAppURL.appendingPathComponent("Contents/MacOS")
        let execs = (try? FileManager.default.contentsOfDirectory(atPath: macosDir.path)) ?? []
        guard !execs.isEmpty else {
            throw UpdateSecurityError.missingBinary
        }

        // 2. Validate Bundle Identifier matches running application
        let expectedBundleID = Bundle.main.bundleIdentifier ?? "com.sarvesh.LiquidDynamo"
        let stagedInfoURL = stagedAppURL.appendingPathComponent("Contents/Info.plist")
        guard let stagedDict = NSDictionary(contentsOf: stagedInfoURL) as? [String: Any],
              let stagedBundleID = stagedDict["CFBundleIdentifier"] as? String else {
            throw UpdateSecurityError.bundleIdentifierMismatch(found: "unknown", expected: expectedBundleID)
        }
        guard stagedBundleID == expectedBundleID else {
            throw UpdateSecurityError.bundleIdentifierMismatch(found: stagedBundleID, expected: expectedBundleID)
        }

        // 3. Validate Version is greater than or equal to current installed version
        let stagedVersionStr = (stagedDict["CFBundleShortVersionString"] as? String) ?? ""
        let currentVersionStr = Bundle.main.releaseVersionNumber ?? "2.0.0"
        if let stagedVer = SemanticVersion(stagedVersionStr),
           let currentVer = SemanticVersion(currentVersionStr) {
            if stagedVer < currentVer {
                throw UpdateSecurityError.versionNotNewer(found: stagedVersionStr, current: currentVersionStr)
            }
        }

        // 4. Verify cryptographic code signature
        try Self.verifyCodeSignature(at: stagedAppURL)

        // 5. Team ID Verification & Gatekeeper Assessment
        let runningTeam = Self.currentTeamID()
        let stagedTeam = Self.extractTeamID(from: stagedAppURL)

        if let expectedTeam = runningTeam {
            guard let foundTeam = stagedTeam, foundTeam == expectedTeam else {
                throw UpdateSecurityError.teamIDMismatch(found: stagedTeam ?? "none", expected: expectedTeam)
            }
            // Enforce Gatekeeper when signed with developer Team ID
            try Self.verifyGatekeeperAssessment(at: stagedAppURL)
        }
    }

    private func validateAndRelaunch(stagedAppURL: URL) throws {
        try validateStagedApp(stagedAppURL: stagedAppURL)

        self.status = .replacingAndRelaunching
        self.downloadStatusFormatted = "Installing verified update to /Applications…"
        try self.spawnRelaunchScript(stagedAppURL: stagedAppURL)
    }

    private static func detachVolume(_ volumePath: String) {
        let detach = Process()
        detach.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        detach.arguments = ["eject", volumePath]
        try? detach.run()
        detach.waitUntilExit()
    }

    // MARK: - 6. Safe Atomic Replacement with Rollback

    private func spawnRelaunchScript(stagedAppURL: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier

        // Determine destination target application path
        let targetAppURL: URL
        if Bundle.main.bundleURL.pathExtension == "app" {
            targetAppURL = Bundle.main.bundleURL
        } else {
            targetAppURL = URL(fileURLWithPath: "/Applications/LiquidDynamo.app")
        }

        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("liquiddynamo_atomic_updater.sh")
        let scriptContent = """
        #!/bin/bash
        set -e
        TARGET="\(targetAppURL.path)"
        STAGING="\(stagedAppURL.path)"
        PID="\(pid)"

        # 1. Wait up to 10 seconds for running process to cleanly exit
        COUNT=0
        while kill -0 "$PID" 2>/dev/null && [ $COUNT -lt 100 ]; do
            sleep 0.1
            COUNT=$((COUNT+1))
        done

        # 2. Stage new app beside TARGET in the same filesystem for atomic rename
        TARGET_DIR="$(dirname "$TARGET")"
        RAND_SUFFIX="$$_\(UUID().uuidString.prefix(8))"
        TEMP_INSTALL="${TARGET_DIR}/.LiquidDynamo_Updating_${RAND_SUFFIX}.app"
        BACKUP="${TARGET_DIR}/.LiquidDynamo_Backup_${RAND_SUFFIX}.app"

        rm -rf "$TEMP_INSTALL" "$BACKUP" 2>/dev/null || true

        # Copy verified staging to temporary install in target directory
        if ! cp -R "$STAGING" "$TEMP_INSTALL"; then
            echo "Failed to copy staged application to target directory"
            rm -rf "$TEMP_INSTALL" 2>/dev/null || true
            exit 1
        fi

        # Atomic rename: move current app to backup
        BACKUP_EXISTS=0
        if [ -d "$TARGET" ]; then
            if mv "$TARGET" "$BACKUP"; then
                BACKUP_EXISTS=1
            else
                echo "Failed to backup existing application"
                rm -rf "$TEMP_INSTALL" 2>/dev/null || true
                exit 1
            fi
        fi

        # Atomic rename: move temporary install into target position
        if mv "$TEMP_INSTALL" "$TARGET"; then
            # Success: clean up backup and staging
            rm -rf "$BACKUP" 2>/dev/null || true
            rm -rf "$(dirname "$STAGING")" 2>/dev/null || true
            open "$TARGET"
            exit 0
        else
            echo "Failed to install new application, rolling back..."
            if [ $BACKUP_EXISTS -eq 1 ] && [ -d "$BACKUP" ]; then
                mv "$BACKUP" "$TARGET" 2>/dev/null || true
            fi
            rm -rf "$TEMP_INSTALL" 2>/dev/null || true
            exit 1
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

    // MARK: - 7. Utilities

    public func downloadLatestDMG(url: URL? = nil) {
        let targetURL = url ?? Self.releasesURL
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
        if let sem1 = SemanticVersion(v1), let sem2 = SemanticVersion(v2) {
            return sem1 > sem2
        }
        let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        return clean1.compare(clean2, options: .numeric) == .orderedDescending
    }
}
