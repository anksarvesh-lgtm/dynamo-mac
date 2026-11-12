//
//  VLCController.swift
//  LiquidDynamo
//
//  Sandbox-safe Apple Events controller for VLC media player.
//  Polls VLC only while running so macOS never auto-launches the player when idle.
//

import AppKit
import Combine
import Foundation

final class VLCController: MediaControllerProtocol {
    static let vlcBundleIdentifier = "org.videolan.vlc"

    @Published private var playbackState = PlaybackState(bundleIdentifier: VLCController.vlcBundleIdentifier)

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool { false }
    var supportsFavorite: Bool { false }

    private var workspaceTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private let pollIntervalSeconds: UInt64 = 3
    private let commandRefreshDelay: Duration = .milliseconds(150)

    init() {
        startWorkspaceObserver()
        if isActive() {
            startPolling()
        }
    }

    deinit {
        workspaceTask?.cancel()
        pollTask?.cancel()
    }

    // MARK: - MediaControllerProtocol

    func setFavorite(_ favorite: Bool) async {
        // VLC does not expose a native track favorite API via scripting.
    }

    func play() async {
        guard isActive() else { return }
        let script = """
        if application "VLC" is running then
            tell application "VLC"
                if not playing then play
            end tell
        end if
        """
        try? await AppleScriptHelper.executeVoid(script)
        try? await Task.sleep(for: commandRefreshDelay)
        await updatePlaybackInfo()
    }

    func pause() async {
        guard isActive() else { return }
        let script = """
        if application "VLC" is running then
            tell application "VLC"
                if playing then play
            end tell
        end if
        """
        try? await AppleScriptHelper.executeVoid(script)
        try? await Task.sleep(for: commandRefreshDelay)
        await updatePlaybackInfo()
    }

    func togglePlay() async {
        await executeCommand("play")
    }

    func nextTrack() async {
        await executeCommand("next")
    }

    func previousTrack() async {
        await executeCommand("previous")
    }

    func seek(to time: Double) async {
        let targetSeconds = Int(max(0, time.rounded(.down)))
        await executeCommand("set current time to \(targetSeconds)")
    }

    func toggleShuffle() async {
        // VLC scripting dictionary does not provide a toggleable shuffle state across versions.
    }

    func toggleRepeat() async {
        // VLC scripting dictionary does not expose reliable repeat-mode enumeration across versions.
    }

    func setVolume(_ level: Double) async {
        // Not advertised (`supportsVolumeControl == false`).
    }

    nonisolated func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == Self.vlcBundleIdentifier
        }
    }

    func updatePlaybackInfo() async {
        guard isActive() else {
            await resetToIdle()
            return
        }

        let script = """
        if application "VLC" is running then
            tell application "VLC"
                try
                    set itemName to name of current item
                    if itemName is missing value then return "none"
                    return (playing as text) & (character id 30) & itemName & (character id 30) & (current time as text) & (character id 30) & (duration of current item as text)
                on error
                    return "none"
                end try
            end tell
        end if
        return "none"
        """

        guard let descriptor = try? await AppleScriptHelper.execute(script),
              let raw = descriptor.stringValue else {
            return
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "none" else {
            await resetToIdle()
            return
        }

        let parts = trimmed.components(separatedBy: "\u{1E}")
        guard parts.count >= 4 else {
            await resetToIdle()
            return
        }

        let isPlaying = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
        let cleanTitle = MediaMetadataSanitizer.normalizedVLCTitle(parts[1])
        guard !cleanTitle.isEmpty else {
            await resetToIdle()
            return
        }

        let currentTime = Self.parseNumber(parts[2]) ?? 0
        let duration = max(0, Self.parseNumber(parts[3]) ?? 0)
        let now = Date()

        await MainActor.run {
            let current = self.playbackState
            let interpolatedPrevious = MediaPositionLogic.interpolatedElapsed(
                elapsed: current.currentTime,
                duration: current.duration,
                playbackRate: current.playbackRate,
                isPlaying: current.isPlaying,
                sinceCapture: now.timeIntervalSince(current.lastUpdated)
            )

            // Skip redundant churn updates when metadata, playback state, and clock stay aligned.
            if current.title == cleanTitle,
               current.isPlaying == isPlaying,
               abs(current.duration - duration) < 0.5,
               abs(interpolatedPrevious - currentTime) < 2.0 {
                return
            }

            self.playbackState = PlaybackState(
                bundleIdentifier: Self.vlcBundleIdentifier,
                isPlaying: isPlaying,
                title: cleanTitle,
                artist: "",
                album: "",
                currentTime: max(0, currentTime),
                duration: duration,
                playbackRate: isPlaying ? 1 : 0,
                isShuffled: false,
                repeatMode: .off,
                lastUpdated: now,
                artwork: nil,
                volume: current.volume,
                isFavorite: false
            )
        }
    }

    // MARK: - Private Helpers

    private func executeCommand(_ verb: String) async {
        guard isActive() else { return }
        let script = "if application \"VLC\" is running then tell application \"VLC\" to \(verb)"
        try? await AppleScriptHelper.executeVoid(script)
        try? await Task.sleep(for: commandRefreshDelay)
        await updatePlaybackInfo()
    }

    private func startWorkspaceObserver() {
        workspaceTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let launches = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.didLaunchApplicationNotification
                    )
                    for await notification in launches {
                        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                              app.bundleIdentifier == VLCController.vlcBundleIdentifier else {
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
                              app.bundleIdentifier == VLCController.vlcBundleIdentifier else {
                            continue
                        }
                        await self?.stopPollingAndReset()
                    }
                }
            }
        }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        let interval = pollIntervalSeconds
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
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
        await MainActor.run {
            let idle = PlaybackState(bundleIdentifier: Self.vlcBundleIdentifier)
            if self.playbackState != idle || self.playbackState.isPlaying || !self.playbackState.title.isEmpty {
                self.playbackState = idle
            }
        }
    }

    private static func parseNumber(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
}
