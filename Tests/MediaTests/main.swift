import Foundation

struct MediaTestsRunner {
    private var failures = 0

    mutating func expect(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
        if !condition {
            fputs("FAIL [\(file):\(line)]: \(message)\n", stderr)
            failures += 1
        }
    }

    mutating func run() {
        testBackendEligibility()
        testMultiSourceSelectionAndLinger()
        testPositionInterpolationAndFormatting()
        testMetadataSanitization()
        testBrowserOptInGating()

        if failures == 0 {
            print("MediaTests: ALL PASSED")
        } else {
            fputs("MediaTests: \(failures) FAILURE(S)\n", stderr)
            exit(1)
        }
    }

    mutating func testBackendEligibility() {
        expect(
            MediaBackendEligibility.directMediaRemoteEligible(osMajor: 14, osMinor: 6, isSandboxed: false),
            "Unsandboxed macOS 14 should allow direct MediaRemote"
        )
        expect(
            MediaBackendEligibility.directMediaRemoteEligible(osMajor: 15, osMinor: 3, isSandboxed: false),
            "Unsandboxed macOS 15.3 should allow direct MediaRemote"
        )
        expect(
            !MediaBackendEligibility.directMediaRemoteEligible(osMajor: 15, osMinor: 4, isSandboxed: false),
            "macOS 15.4 must disallow direct MediaRemote"
        )
        expect(
            !MediaBackendEligibility.directMediaRemoteEligible(osMajor: 14, osMinor: 6, isSandboxed: true),
            "App Sandbox must always disallow direct MediaRemote"
        )
        expect(
            !MediaBackendEligibility.adapterEligible(isSandboxed: true, hasAdapterResources: true),
            "App Sandbox must disallow perl adapter subprocess"
        )
        expect(
            !MediaBackendEligibility.adapterEligible(isSandboxed: false, hasAdapterResources: false),
            "Missing adapter resources must disallow adapter backend"
        )

        let sandboxedSelection = MediaBackendEligibility.selectBackend(
            probes: [.adapter: true, .directMediaRemote: true, .appleScript: true],
            isSandboxed: true,
            osMajor: 14,
            osMinor: 5
        )
        expect(sandboxedSelection == .appleScript, "Sandboxed runtime must fall back directly to .appleScript")

        let macOS154Selection = MediaBackendEligibility.selectBackend(
            probes: [.adapter: false, .directMediaRemote: true, .appleScript: true],
            isSandboxed: false,
            osMajor: 15,
            osMinor: 4
        )
        expect(macOS154Selection == .appleScript, "macOS 15.4+ without adapter must fall back to .appleScript")

        let deprecatedInSandbox = MediaBackendEligibility.shouldMarkNowPlayingDeprecated(
            isSandboxed: true,
            adapterProbeSucceeded: true,
            directMediaRemoteProbeSucceeded: true,
            osMajor: 14,
            osMinor: 5
        )
        expect(deprecatedInSandbox, "Legacy system Now Playing must be marked unavailable in App Sandbox")

        let deprecatedOnProbeError = MediaBackendEligibility.shouldMarkNowPlayingDeprecated(
            isSandboxed: false,
            adapterProbeSucceeded: false,
            directMediaRemoteProbeSucceeded: false,
            osMajor: 15,
            osMinor: 4
        )
        expect(deprecatedOnProbeError, "Failed probe without direct fallback must mark Now Playing deprecated")
    }

    mutating func testMultiSourceSelectionAndLinger() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // Playing beats paused regardless of timestamp
        let pausedNewer = MediaSourceSelector.SourceSnapshot(
            bundleIdentifier: "com.spotify.client",
            sourceName: "Spotify",
            isPlaying: false,
            title: "Track B",
            lastPlayingAt: base.addingTimeInterval(-5),
            priorityRank: 1
        )
        let playingOlder = MediaSourceSelector.SourceSnapshot(
            bundleIdentifier: "org.videolan.vlc",
            sourceName: "VLC",
            isPlaying: true,
            title: "Movie.mkv",
            lastPlayingAt: base.addingTimeInterval(-30),
            priorityRank: 3
        )
        let active1 = MediaSourceSelector.selectActiveSource(
            from: ["com.spotify.client": pausedNewer, "org.videolan.vlc": playingOlder],
            now: base
        )
        expect(active1 == "org.videolan.vlc", "Playing source must beat newer paused source")

        // Newer playing source beats older playing source
        let playingNewer = MediaSourceSelector.SourceSnapshot(
            bundleIdentifier: "com.apple.Music",
            sourceName: "Music",
            isPlaying: true,
            title: "Track A",
            lastPlayingAt: base.addingTimeInterval(-1),
            priorityRank: 0
        )
        let active2 = MediaSourceSelector.selectActiveSource(
            from: ["com.apple.Music": playingNewer, "org.videolan.vlc": playingOlder],
            now: base
        )
        expect(active2 == "com.apple.Music", "Most recently started playing source must win")

        // Paused lingers for < 600s and expires at >= 600s
        let pausedWithin = MediaSourceSelector.SourceSnapshot(
            bundleIdentifier: "com.spotify.client",
            sourceName: "Spotify",
            isPlaying: false,
            title: "Track B",
            lastPlayingAt: base.addingTimeInterval(-599),
            priorityRank: 1
        )
        let withinResult = MediaSourceSelector.selectActiveSource(
            from: ["com.spotify.client": pausedWithin],
            now: base
        )
        expect(withinResult == "com.spotify.client", "Paused source < 600s must linger")

        let pausedExpired = MediaSourceSelector.SourceSnapshot(
            bundleIdentifier: "com.spotify.client",
            sourceName: "Spotify",
            isPlaying: false,
            title: "Track B",
            lastPlayingAt: base.addingTimeInterval(-600),
            priorityRank: 1
        )
        let expiredResult = MediaSourceSelector.selectActiveSource(
            from: ["com.spotify.client": pausedExpired],
            now: base
        )
        expect(expiredResult == nil, "Paused source at >= 600s must expire")

        // Deterministic tie-breaking by priorityRank then bundle ID
        let tieMusic = MediaSourceSelector.SourceSnapshot(
            bundleIdentifier: "com.apple.Music",
            sourceName: "Music",
            isPlaying: true,
            title: "Song 1",
            lastPlayingAt: base,
            priorityRank: MediaSourceSelector.defaultPriorityRank(for: "com.apple.Music")
        )
        let tieSpotify = MediaSourceSelector.SourceSnapshot(
            bundleIdentifier: "com.spotify.client",
            sourceName: "Spotify",
            isPlaying: true,
            title: "Song 2",
            lastPlayingAt: base,
            priorityRank: MediaSourceSelector.defaultPriorityRank(for: "com.spotify.client")
        )
        let tieWinner = MediaSourceSelector.selectActiveSource(
            from: ["com.spotify.client": tieSpotify, "com.apple.Music": tieMusic],
            now: base
        )
        expect(tieWinner == "com.apple.Music", "Equal timestamps must break ties deterministically by priority rank")

        // Empty/placeholder titles excluded
        let idlePlaceholder = MediaSourceSelector.SourceSnapshot(
            bundleIdentifier: "com.apple.Music",
            sourceName: "Music",
            isPlaying: false,
            title: "I'm Handsome",
            lastPlayingAt: base,
            priorityRank: 0
        )
        let placeholderWinner = MediaSourceSelector.selectActiveSource(
            from: ["com.apple.Music": idlePlaceholder],
            now: base
        )
        expect(placeholderWinner == nil, "Placeholder novelty titles must not count as active sources")
    }

    mutating func testPositionInterpolationAndFormatting() {
        let clampedPlaying = MediaPositionLogic.interpolatedElapsed(
            elapsed: 195,
            duration: 200,
            playbackRate: 1.0,
            isPlaying: true,
            sinceCapture: 20
        )
        expect(clampedPlaying == 200, "Playing interpolation must clamp to track duration")

        let pausedHold = MediaPositionLogic.interpolatedElapsed(
            elapsed: 42,
            duration: 200,
            playbackRate: 1.0,
            isPlaying: false,
            sinceCapture: 30
        )
        expect(pausedHold == 42, "Paused playback must hold captured elapsed time")

        let negativeClockSkew = MediaPositionLogic.interpolatedElapsed(
            elapsed: 15,
            duration: 120,
            playbackRate: 1.0,
            isPlaying: true,
            sinceCapture: -10
        )
        expect(negativeClockSkew == 15, "Negative clock skew must not rewind playback position")

        expect(MediaPositionLogic.formattedTime(0) == "0:00", "Zero seconds formats as 0:00")
        expect(MediaPositionLogic.formattedTime(-5) == "0:00", "Negative seconds format as 0:00")
        expect(MediaPositionLogic.formattedTime(.nan) == "0:00", "NaN seconds format as 0:00")
        expect(MediaPositionLogic.formattedTime(125) == "2:05", "Seconds under an hour format as m:ss")
        expect(MediaPositionLogic.formattedTime(3665) == "1:01:05", "Seconds >= 1h format as h:mm:ss")
    }

    mutating func testMetadataSanitization() {
        expect(MediaMetadataSanitizer.sanitizedTitle("I'm Handsome") == "", "Must clear legacy placeholder title")
        expect(MediaMetadataSanitizer.sanitizedTitle("Not Playing") == "", "Must clear Not Playing placeholder")
        expect(MediaMetadataSanitizer.sanitizedTitle("Unknown") == "", "Must clear Unknown placeholder")
        expect(MediaMetadataSanitizer.sanitizedTitle("  Clair de Lune  ") == "Clair de Lune", "Must trim valid title")

        expect(MediaMetadataSanitizer.sanitizedArtist("Me", isActive: false) == "", "Must clear placeholder artist when inactive")
        expect(MediaMetadataSanitizer.sanitizedArtist("Debussy", isActive: true) == "Debussy", "Must preserve valid artist when active")
        expect(MediaMetadataSanitizer.sanitizedAlbum("Self Love", isActive: false) == "", "Must clear placeholder album when inactive")

        expect(MediaMetadataSanitizer.normalizedVLCTitle("Inception.2010.1080p.mkv") == "Inception.2010.1080p", "Must strip known video extension")
        expect(MediaMetadataSanitizer.normalizedVLCTitle("Live Radio Stream") == "Live Radio Stream", "Must keep stream titles intact")
    }

    mutating func testBrowserOptInGating() {
        let running: Set<String> = ["com.apple.Safari", "com.google.Chrome"]
        let disabled = BrowserMediaCatalog.activeTargets(runningBundleIdentifiers: running, optInEnabled: false)
        expect(disabled.isEmpty, "Browser detection must yield zero targets when opt-in is disabled")

        let enabled = BrowserMediaCatalog.activeTargets(runningBundleIdentifiers: running, optInEnabled: true)
        expect(enabled.count == 2, "Opted-in browser detection must list only running supported browsers in priority order")
        expect(enabled.first?.bundleIdentifier == "com.apple.Safari", "Safari priority comes before Chrome")
    }
}

var mediaTestsRunner = MediaTestsRunner()
mediaTestsRunner.run()
