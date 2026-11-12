//
//  NowPlayingCore.swift
//  LiquidDynamo
//
//  Pure Foundation-only logic for sandbox-safe media backend eligibility,
//  multi-player source selection with paused linger, elapsed-time interpolation,
//  metadata sanitization, and opt-in browser enumeration.
//

import Foundation

public enum MediaBackendKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case adapter
    case directMediaRemote
    case appleScript
}

public enum MediaBackendEligibility {
    public static let fallbackOrder: [MediaBackendKind] = [.adapter, .directMediaRemote, .appleScript]

    public static var isSandboxedRuntime: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    public static var currentOSVersion: (major: Int, minor: Int) {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return (version.majorVersion, version.minorVersion)
    }

    /// Direct dynamic loading of system MediaRemote APIs is strictly ineligible under App Sandbox
    /// and on macOS 15.4+ where entitlement checks reject third-party access.
    public static func directMediaRemoteEligible(osMajor: Int, osMinor: Int, isSandboxed: Bool) -> Bool {
        guard !isSandboxed else { return false }
        if osMajor != 15 { return osMajor < 15 }
        return osMinor < 4
    }

    /// Subprocess-based adapter probing is strictly ineligible inside App Sandbox or when bundled
    /// adapter resources are missing.
    public static func adapterEligible(isSandboxed: Bool, hasAdapterResources: Bool) -> Bool {
        !isSandboxed && hasAdapterResources
    }

    /// Returns true when legacy system-wide Now Playing monitoring must be treated as unavailable
    /// so LiquidDynamo routes default selection cleanly to sandbox-safe `.auto`.
    public static func shouldMarkNowPlayingDeprecated(
        isSandboxed: Bool,
        adapterProbeSucceeded: Bool,
        directMediaRemoteProbeSucceeded: Bool,
        osMajor: Int,
        osMinor: Int
    ) -> Bool {
        guard !isSandboxed else { return true }
        if adapterProbeSucceeded { return false }
        if directMediaRemoteEligible(osMajor: osMajor, osMinor: osMinor, isSandboxed: isSandboxed),
           directMediaRemoteProbeSucceeded {
            return false
        }
        return true
    }

    /// Selects the highest-priority eligible backend whose probe succeeded.
    public static func selectBackend(
        probes: [MediaBackendKind: Bool],
        isSandboxed: Bool,
        osMajor: Int,
        osMinor: Int,
        hasAdapterResources: Bool = true
    ) -> MediaBackendKind? {
        for backend in fallbackOrder {
            guard probes[backend] == true else { continue }
            switch backend {
            case .adapter:
                if adapterEligible(isSandboxed: isSandboxed, hasAdapterResources: hasAdapterResources) {
                    return .adapter
                }
            case .directMediaRemote:
                if directMediaRemoteEligible(osMajor: osMajor, osMinor: osMinor, isSandboxed: isSandboxed) {
                    return .directMediaRemote
                }
            case .appleScript:
                return .appleScript
            }
        }
        return nil
    }
}

public enum MediaSourceSelector {
    public struct SourceSnapshot: Equatable, Sendable {
        public var bundleIdentifier: String
        public var sourceName: String
        public var isPlaying: Bool
        public var title: String
        public var lastPlayingAt: Date
        public var priorityRank: Int

        public init(
            bundleIdentifier: String,
            sourceName: String,
            isPlaying: Bool,
            title: String,
            lastPlayingAt: Date,
            priorityRank: Int = 99
        ) {
            self.bundleIdentifier = bundleIdentifier
            self.sourceName = sourceName
            self.isPlaying = isPlaying
            self.title = title
            self.lastPlayingAt = lastPlayingAt
            self.priorityRank = priorityRank
        }
    }

    public static let pausedLingerDuration: TimeInterval = 10 * 60

    public static func defaultPriorityRank(for bundleIdentifier: String) -> Int {
        switch bundleIdentifier {
        case "com.apple.Music":
            return 0
        case "com.spotify.client":
            return 1
        case "com.github.th-ch.youtube-music":
            return 2
        case "org.videolan.vlc":
            return 3
        case "com.apple.Safari", "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac":
            return 4
        default:
            return 99
        }
    }

    /// Selects the active media source identifier:
    /// 1. Currently playing sources always beat paused sources.
    /// 2. Within the winning tier, the most recently active timestamp wins.
    /// 3. Paused sources linger for `pausedLinger` seconds before dropping out.
    /// 4. Ties break deterministically on `priorityRank`, then lexicographical `bundleIdentifier`.
    public static func selectActiveSource(
        from sources: [String: SourceSnapshot],
        now: Date,
        pausedLinger: TimeInterval = pausedLingerDuration
    ) -> String? {
        let valid = sources.filter { _, snapshot in
            !MediaMetadataSanitizer.sanitizedTitle(snapshot.title).isEmpty
        }

        func newest(in candidates: [String: SourceSnapshot]) -> String? {
            candidates.max { lhs, rhs in
                if lhs.value.lastPlayingAt != rhs.value.lastPlayingAt {
                    return lhs.value.lastPlayingAt < rhs.value.lastPlayingAt
                }
                if lhs.value.priorityRank != rhs.value.priorityRank {
                    return lhs.value.priorityRank > rhs.value.priorityRank
                }
                return lhs.key > rhs.key
            }?.key
        }

        let playing = valid.filter { $0.value.isPlaying }
        if let activePlaying = newest(in: playing) {
            return activePlaying
        }

        let lingering = valid.filter { _, snapshot in
            now.timeIntervalSince(snapshot.lastPlayingAt) < pausedLinger
        }
        return newest(in: lingering)
    }

    /// Returns the shortest positive delay until the oldest lingering paused source expires,
    /// or `nil` if no lingering paused sources exist.
    public static func nextLingerExpiryDelay(
        from sources: [String: SourceSnapshot],
        now: Date,
        pausedLinger: TimeInterval = pausedLingerDuration
    ) -> TimeInterval? {
        let validPaused = sources.values.filter {
            !$0.isPlaying && !MediaMetadataSanitizer.sanitizedTitle($0.title).isEmpty
        }
        guard let oldestPaused = validPaused.map(\.lastPlayingAt).min() else { return nil }
        let remaining = pausedLinger - now.timeIntervalSince(oldestPaused)
        return max(0.5, remaining + 0.25)
    }
}

public enum MediaPositionLogic {
    public static func interpolatedElapsed(
        elapsed: TimeInterval,
        duration: TimeInterval,
        playbackRate: Double,
        isPlaying: Bool,
        sinceCapture: TimeInterval
    ) -> TimeInterval {
        let safeDelta = max(0, sinceCapture)
        let rate = playbackRate.isFinite ? max(0, playbackRate) : 1
        let raw = isPlaying ? (elapsed + safeDelta * rate) : elapsed
        let nonNegative = raw.isFinite ? max(0, raw) : 0
        guard duration.isFinite, duration > 0 else { return nonNegative }
        return min(nonNegative, duration)
    }

    public static func progress(
        elapsed: TimeInterval,
        duration: TimeInterval,
        playbackRate: Double,
        isPlaying: Bool,
        sinceCapture: TimeInterval
    ) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        return interpolatedElapsed(
            elapsed: elapsed,
            duration: duration,
            playbackRate: playbackRate,
            isPlaying: isPlaying,
            sinceCapture: sinceCapture
        ) / duration
    }

    public static func formattedTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

public enum MediaMetadataSanitizer {
    private static let placeholderTitles: Set<String> = [
        "",
        "i'm handsome",
        "not playing",
        "unknown",
        "no media",
        "no media playing"
    ]

    private static let placeholderSecondaryValues: Set<String> = [
        "",
        "me",
        "self love",
        "unknown"
    ]

    private static let mediaFileExtensions: Set<String> = [
        "mp4", "mkv", "mov", "avi", "m4v", "webm", "flv", "wmv",
        "mp3", "m4a", "flac", "wav", "aac", "ogg", "opus", "aiff"
    ]

    public static func isPlaceholderTitle(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return placeholderTitles.contains(normalized)
    }

    public static func sanitizedTitle(_ title: String?) -> String {
        guard let title else { return "" }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return isPlaceholderTitle(trimmed) ? "" : trimmed
    }

    public static func sanitizedArtist(_ artist: String?, isActive: Bool) -> String {
        guard isActive, let artist else { return "" }
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return placeholderSecondaryValues.contains(trimmed.lowercased()) ? "" : trimmed
    }

    public static func sanitizedAlbum(_ album: String?, isActive: Bool) -> String {
        guard isActive, let album else { return "" }
        let trimmed = album.trimmingCharacters(in: .whitespacesAndNewlines)
        return placeholderSecondaryValues.contains(trimmed.lowercased()) ? "" : trimmed
    }

    public static func normalizedVLCTitle(_ rawTitle: String) -> String {
        let trimmed = sanitizedTitle(rawTitle)
        guard !trimmed.isEmpty else { return "" }
        let ext = (trimmed as NSString).pathExtension.lowercased()
        if !ext.isEmpty, mediaFileExtensions.contains(ext) {
            let stripped = (trimmed as NSString).deletingPathExtension
            if !stripped.isEmpty {
                return stripped
            }
        }
        return trimmed
    }
}

public enum BrowserScriptingEngine: String, Equatable, Sendable {
    case safari
    case chromium
}

public struct BrowserMediaTarget: Equatable, Sendable {
    public let bundleIdentifier: String
    public let applicationName: String
    public let engine: BrowserScriptingEngine

    public init(bundleIdentifier: String, applicationName: String, engine: BrowserScriptingEngine) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.engine = engine
    }
}

public enum BrowserMediaCatalog {
    public static let supportedBrowsers: [BrowserMediaTarget] = [
        BrowserMediaTarget(bundleIdentifier: "com.apple.Safari", applicationName: "Safari", engine: .safari),
        BrowserMediaTarget(bundleIdentifier: "com.google.Chrome", applicationName: "Google Chrome", engine: .chromium),
        BrowserMediaTarget(bundleIdentifier: "com.brave.Browser", applicationName: "Brave Browser", engine: .chromium),
        BrowserMediaTarget(bundleIdentifier: "com.microsoft.edgemac", applicationName: "Microsoft Edge", engine: .chromium)
    ]

    public static func activeTargets(
        runningBundleIdentifiers: Set<String>,
        optInEnabled: Bool
    ) -> [BrowserMediaTarget] {
        guard optInEnabled else { return [] }
        return supportedBrowsers.filter { runningBundleIdentifiers.contains($0.bundleIdentifier) }
    }
}
