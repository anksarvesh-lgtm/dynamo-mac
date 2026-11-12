//
//  BrowserMediaController.swift
//  LiquidDynamo
//
//  Opt-in Apple Events controller for active web browser media tabs
//  (Safari, Google Chrome, Brave Browser, Microsoft Edge).
//  Disabled by default because browsers require user opt-in for JavaScript Apple Events.
//

import AppKit
import Combine
import Defaults
import Foundation

final class BrowserMediaController: MediaControllerProtocol {
    @Published private var playbackState = PlaybackState(bundleIdentifier: "")

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool { false }
    var supportsFavorite: Bool { false }

    private(set) var lastErrorMessage: String?

    private var activeTarget: BrowserMediaTarget?
    private var activeTabLocation: (window: Int, tab: Int)?
    private var lastArtworkURLString: String?
    private var artworkTask: Task<Void, Never>?

    private var preferenceCancellable: AnyCancellable?
    private var workspaceTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private let pollIntervalSeconds: UInt64 = 4
    private let commandRefreshDelay: Duration = .milliseconds(150)

    init() {
        preferenceCancellable = Defaults.publisher(.enableBrowserMediaDetection)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                Task { await self?.handleOptInChanged(enabled) }
            }

        startWorkspaceObserver()
        if Defaults[.enableBrowserMediaDetection], !runningSupportedBrowsers().isEmpty {
            startPolling()
        }
    }

    deinit {
        preferenceCancellable?.cancel()
        workspaceTask?.cancel()
        pollTask?.cancel()
        artworkTask?.cancel()
    }

    // MARK: - MediaControllerProtocol

    func setFavorite(_ favorite: Bool) async {}

    func play() async {
        await executeTabJavaScript(
            "var m=[].slice.call(document.querySelectorAll('video,audio')).find(function(e){return e.currentTime>0||!e.ended});if(m)m.play();"
        )
    }

    func pause() async {
        await executeTabJavaScript(
            "document.querySelectorAll('video,audio').forEach(function(e){e.pause();});"
        )
    }

    func togglePlay() async {
        await executeTabJavaScript(
            "var m=[].slice.call(document.querySelectorAll('video,audio')).find(function(e){return e.currentTime>0||!e.paused});if(m){m.paused?m.play():m.pause();}"
        )
    }

    func nextTrack() async {
        // Generic HTML5 media elements do not expose a uniform next-track command across sites.
    }

    func previousTrack() async {
        // Generic HTML5 media elements do not expose a uniform previous-track command across sites.
    }

    func seek(to time: Double) async {
        let clamped = max(0, time)
        await executeTabJavaScript(
            "var m=[].slice.call(document.querySelectorAll('video,audio')).find(function(e){return e.currentTime>0||!e.paused});if(m)m.currentTime=\(clamped);"
        )
    }

    func toggleShuffle() async {}
    func toggleRepeat() async {}
    func setVolume(_ level: Double) async {}

    nonisolated func isActive() -> Bool {
        guard Defaults[.enableBrowserMediaDetection] else { return false }
        return !runningSupportedBrowsers().isEmpty
    }

    func updatePlaybackInfo() async {
        guard Defaults[.enableBrowserMediaDetection] else {
            await resetToIdle()
            return
        }

        let targets = runningSupportedBrowsers()
        guard !targets.isEmpty else {
            await resetToIdle()
            return
        }

        var playingCandidate: (target: BrowserMediaTarget, window: Int, tab: Int, json: [String: Any])?
        var pausedCandidate: (target: BrowserMediaTarget, window: Int, tab: Int, json: [String: Any])?

        for target in targets {
            guard let match = await probeBrowser(target) else { continue }
            let isPlaying = (match.json["p"] as? Bool) == true
            if isPlaying {
                playingCandidate = (target, match.window, match.tab, match.json)
                break
            } else if pausedCandidate == nil {
                pausedCandidate = (target, match.window, match.tab, match.json)
            }
        }

        guard let chosen = playingCandidate ?? pausedCandidate else {
            await resetToIdle()
            return
        }

        let title = MediaMetadataSanitizer.sanitizedTitle(chosen.json["t"] as? String)
        guard !title.isEmpty else {
            await resetToIdle()
            return
        }

        let isPlaying = (chosen.json["p"] as? Bool) == true
        let artist = MediaMetadataSanitizer.sanitizedArtist(chosen.json["a"] as? String, isActive: true)
        let album = MediaMetadataSanitizer.sanitizedAlbum(chosen.json["al"] as? String, isActive: true)
        let elapsed = max(0, chosen.json["c"] as? Double ?? 0)
        let rawDuration = chosen.json["d"] as? Double ?? 0
        let duration = rawDuration.isFinite && rawDuration > 0 ? rawDuration : 0
        let artworkURLString = (chosen.json["art"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let now = Date()

        await MainActor.run {
            self.activeTarget = chosen.target
            self.activeTabLocation = (chosen.window, chosen.tab)
            self.lastErrorMessage = nil

            let existing = self.playbackState
            let cachedArtwork: Data? = (artworkURLString == self.lastArtworkURLString) ? existing.artwork : nil
            let interpolatedPrevious = MediaPositionLogic.interpolatedElapsed(
                elapsed: existing.currentTime,
                duration: existing.duration,
                playbackRate: existing.playbackRate,
                isPlaying: existing.isPlaying,
                sinceCapture: now.timeIntervalSince(existing.lastUpdated)
            )

            let unchanged = existing.bundleIdentifier == chosen.target.bundleIdentifier
                && existing.title == title
                && existing.artist == artist
                && existing.album == album
                && existing.isPlaying == isPlaying
                && abs(existing.duration - duration) < 0.5
                && abs(interpolatedPrevious - elapsed) < 2.0

            if !unchanged {
                self.playbackState = PlaybackState(
                    bundleIdentifier: chosen.target.bundleIdentifier,
                    isPlaying: isPlaying,
                    title: title,
                    artist: artist,
                    album: album,
                    currentTime: elapsed,
                    duration: duration,
                    playbackRate: isPlaying ? 1 : 0,
                    isShuffled: false,
                    repeatMode: .off,
                    lastUpdated: now,
                    artwork: cachedArtwork,
                    volume: existing.volume,
                    isFavorite: false
                )
            }
        }

        if !artworkURLString.isEmpty,
           artworkURLString != lastArtworkURLString,
           let url = URL(string: artworkURLString),
           url.scheme?.lowercased() == "https" {
            fetchArtworkIfNeeded(from: url, expectedTitle: title, bundleIdentifier: chosen.target.bundleIdentifier)
        }
    }

    // MARK: - Private Helpers

    private static let probeJavaScript = """
    (function(){var els=[].slice.call(document.querySelectorAll('video,audio'));var m=els.find(function(e){return !e.paused&&!e.ended&&e.readyState>2})||els.find(function(e){return e.currentTime>0&&!e.ended});if(!m)return '';var md=navigator.mediaSession&&navigator.mediaSession.metadata;var art='';if(md&&md.artwork&&md.artwork.length){art=md.artwork[md.artwork.length-1].src}return JSON.stringify({t:(md&&md.title)||document.title,a:(md&&md.artist)||location.hostname,al:(md&&md.album)||'',art:art,p:!m.paused,c:m.currentTime,d:isFinite(m.duration)?m.duration:0})})()
    """

    private func probeBrowser(_ target: BrowserMediaTarget) async -> (window: Int, tab: Int, json: [String: Any])? {
        let escapedJS = Self.probeJavaScript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let execLine = target.engine == .safari
            ? "do JavaScript \"\(escapedJS)\" in t"
            : "execute t javascript \"\(escapedJS)\""

        let script = """
        if application "\(target.applicationName)" is running then
            tell application "\(target.applicationName)"
                set wi to 0
                repeat with w in windows
                    set wi to wi + 1
                    set ti to 0
                    repeat with t in tabs of w
                        set ti to ti + 1
                        if ti > 30 then exit repeat
                        set res to ""
                        try
                            set res to \(execLine)
                        end try
                        if res is not missing value and res is not "" then
                            return (wi as text) & (character id 30) & (ti as text) & (character id 30) & res
                        end if
                    end repeat
                end repeat
            end tell
        end if
        return ""
        """

        do {
            guard let descriptor = try await AppleScriptHelper.execute(script),
                  let output = descriptor.stringValue,
                  !output.isEmpty else {
                return nil
            }
            let fields = output.components(separatedBy: "\u{1E}")
            guard fields.count == 3,
                  let windowIndex = Int(fields[0]),
                  let tabIndex = Int(fields[1]),
                  let data = fields[2].data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return (windowIndex, tabIndex, json)
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    private func executeTabJavaScript(_ jsBody: String) async {
        guard Defaults[.enableBrowserMediaDetection],
              let target = activeTarget,
              let location = activeTabLocation else {
            return
        }
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == target.bundleIdentifier
        }
        guard running else { return }

        let escapedJS = jsBody
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let tabRef = "tab \(location.tab) of window \(location.window)"
        let execLine = target.engine == .safari
            ? "do JavaScript \"\(escapedJS)\" in \(tabRef)"
            : "execute \(tabRef) javascript \"\(escapedJS)\""

        let script = """
        if application "\(target.applicationName)" is running then
            tell application "\(target.applicationName)"
                \(execLine)
            end tell
        end if
        """
        try? await AppleScriptHelper.executeVoid(script)
        try? await Task.sleep(for: commandRefreshDelay)
        await updatePlaybackInfo()
    }

    private func fetchArtworkIfNeeded(from url: URL, expectedTitle: String, bundleIdentifier: String) {
        artworkTask?.cancel()
        let urlString = url.absoluteString
        artworkTask = Task { [weak self] in
            guard let data = try? await ImageService.shared.fetchImageData(from: url) else { return }
            await MainActor.run {
                guard let self,
                      self.playbackState.bundleIdentifier == bundleIdentifier,
                      self.playbackState.title == expectedTitle else {
                    return
                }
                self.lastArtworkURLString = urlString
                var updated = self.playbackState
                updated.artwork = data
                self.playbackState = updated
            }
        }
    }

    private nonisolated func runningSupportedBrowsers() -> [BrowserMediaTarget] {
        let runningIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
        return BrowserMediaCatalog.activeTargets(
            runningBundleIdentifiers: runningIDs,
            optInEnabled: Defaults[.enableBrowserMediaDetection]
        )
    }

    private func handleOptInChanged(_ enabled: Bool) async {
        if enabled {
            if !runningSupportedBrowsers().isEmpty {
                startPolling()
            }
            await updatePlaybackInfo()
        } else {
            await stopPollingAndReset()
        }
    }

    private func startWorkspaceObserver() {
        let supportedBundleIDs = Set(BrowserMediaCatalog.supportedBrowsers.map(\.bundleIdentifier))
        workspaceTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let launches = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.didLaunchApplicationNotification
                    )
                    for await notification in launches {
                        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                              let bundleID = app.bundleIdentifier,
                              supportedBundleIDs.contains(bundleID),
                              Defaults[.enableBrowserMediaDetection] else {
                            continue
                        }
                        self?.startPolling()
                    }
                }

                group.addTask {
                    let terminations = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.didTerminateApplicationNotification
                    )
                    for await notification in terminations {
                        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                              let bundleID = app.bundleIdentifier,
                              supportedBundleIDs.contains(bundleID) else {
                            continue
                        }
                        guard let self else { return }
                        if self.runningSupportedBrowsers().isEmpty {
                            await self.stopPollingAndReset()
                        } else if self.activeTarget?.bundleIdentifier == bundleID {
                            await self.updatePlaybackInfo()
                        }
                    }
                }
            }
        }
    }

    private func startPolling() {
        guard Defaults[.enableBrowserMediaDetection], pollTask == nil else { return }
        let interval = pollIntervalSeconds
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, Defaults[.enableBrowserMediaDetection] else { return }
                await self.updatePlaybackInfo()
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
            }
        }
    }

    private func stopPollingAndReset() async {
        pollTask?.cancel()
        pollTask = nil
        await resetToIdle()
    }

    private func resetToIdle() async {
        artworkTask?.cancel()
        await MainActor.run {
            self.activeTarget = nil
            self.activeTabLocation = nil
            self.lastArtworkURLString = nil
            let idle = PlaybackState(bundleIdentifier: "")
            if self.playbackState != idle || self.playbackState.isPlaying || !self.playbackState.title.isEmpty {
                self.playbackState = idle
            }
        }
    }
}
