//
//  AutoMediaController.swift
//  LiquidDynamo
//
//  Sandbox-safe multi-source media hub combining Apple Music, Spotify,
//  YouTube Music, VLC, and opt-in web browsers using MediaSourceSelector.
//

import AppKit
import Combine
import Foundation

final class AutoMediaController: MediaControllerProtocol {
    private struct ChildRecord {
        let controller: any MediaControllerProtocol
        var state: PlaybackState?
        var lastPlayingAt: Date
    }

    private enum SlotKey {
        static let appleMusic = "com.apple.Music"
        static let spotify = "com.spotify.client"
        static let youtubeMusic = "com.github.th-ch.youtube-music"
        static let vlc = VLCController.vlcBundleIdentifier
        static let browser = "liquidDynamo.browserMedia"
    }

    @Published private var playbackState = PlaybackState(bundleIdentifier: "")

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        activeChildController?.supportsVolumeControl ?? false
    }

    var supportsFavorite: Bool {
        activeChildController?.supportsFavorite ?? false
    }

    private var childRecords: [String: ChildRecord] = [:]
    private var childCancellables: [AnyCancellable] = []
    private var activeSlotKey: String?
    private var lingerExpiryTask: Task<Void, Never>?
    private var terminationObserverTask: Task<Void, Never>?

    private var activeChildController: (any MediaControllerProtocol)? {
        guard let activeSlotKey else { return nil }
        return childRecords[activeSlotKey]?.controller
    }

    init() {
        registerChildren()
        startTerminationObserver()
    }

    deinit {
        childCancellables.forEach { $0.cancel() }
        lingerExpiryTask?.cancel()
        terminationObserverTask?.cancel()
    }

    // MARK: - MediaControllerProtocol

    func setFavorite(_ favorite: Bool) async {
        await activeChildController?.setFavorite(favorite)
    }

    func play() async {
        await activeChildController?.play()
    }

    func pause() async {
        await activeChildController?.pause()
    }

    func togglePlay() async {
        if let active = activeChildController {
            await active.togglePlay()
            return
        }
        // Fallback if no source is currently active: nudge the highest-priority running player.
        let orderedKeys = [
            SlotKey.appleMusic,
            SlotKey.spotify,
            SlotKey.youtubeMusic,
            SlotKey.vlc,
            SlotKey.browser
        ]
        for key in orderedKeys {
            if let record = childRecords[key], record.controller.isActive() {
                await record.controller.togglePlay()
                return
            }
        }
    }

    func nextTrack() async {
        await activeChildController?.nextTrack()
    }

    func previousTrack() async {
        await activeChildController?.previousTrack()
    }

    func seek(to time: Double) async {
        await activeChildController?.seek(to: time)
    }

    func toggleShuffle() async {
        await activeChildController?.toggleShuffle()
    }

    func toggleRepeat() async {
        await activeChildController?.toggleRepeat()
    }

    func setVolume(_ level: Double) async {
        await activeChildController?.setVolume(level)
    }

    func isActive() -> Bool {
        activeChildController != nil
            || childRecords.values.contains { $0.controller.isActive() }
    }

    func updatePlaybackInfo() async {
        if let active = activeChildController {
            await active.updatePlaybackInfo()
            return
        }
        for record in childRecords.values where record.controller.isActive() {
            await record.controller.updatePlaybackInfo()
        }
    }

    // MARK: - Registration & Aggregation

    private func registerChildren() {
        let initialControllers: [(key: String, controller: any MediaControllerProtocol)] = [
            (SlotKey.appleMusic, AppleMusicController()),
            (SlotKey.spotify, SpotifyController()),
            (SlotKey.youtubeMusic, YouTubeMusicController()),
            (SlotKey.vlc, VLCController()),
            (SlotKey.browser, BrowserMediaController())
        ]

        let now = Date()
        for entry in initialControllers {
            childRecords[entry.key] = ChildRecord(controller: entry.controller, state: nil, lastPlayingAt: now)
            let slotKey = entry.key
            let cancellable = entry.controller.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.handleChildUpdate(state, slotKey: slotKey)
                }
            childCancellables.append(cancellable)
        }
    }

    private func handleChildUpdate(_ rawState: PlaybackState, slotKey: String) {
        guard var record = childRecords[slotKey] else { return }

        let now = Date()
        let cleanTitle = MediaMetadataSanitizer.sanitizedTitle(rawState.title)
        guard !cleanTitle.isEmpty else {
            record.state = nil
            childRecords[slotKey] = record
            reselectAndPublish(now: now)
            return
        }

        let sanitizedState = PlaybackState(
            bundleIdentifier: rawState.bundleIdentifier,
            isPlaying: rawState.isPlaying,
            title: cleanTitle,
            artist: MediaMetadataSanitizer.sanitizedArtist(rawState.artist, isActive: true),
            album: MediaMetadataSanitizer.sanitizedAlbum(rawState.album, isActive: true),
            currentTime: rawState.currentTime,
            duration: rawState.duration,
            playbackRate: rawState.playbackRate,
            isShuffled: rawState.isShuffled,
            repeatMode: rawState.repeatMode,
            lastUpdated: rawState.lastUpdated,
            artwork: rawState.artwork,
            volume: rawState.volume,
            isFavorite: rawState.isFavorite
        )

        let previous = record.state
        let wasPlaying = previous?.isPlaying == true
        let trackChanged = previous?.title != sanitizedState.title
            || previous?.bundleIdentifier != sanitizedState.bundleIdentifier

        if sanitizedState.isPlaying {
            if !wasPlaying || trackChanged {
                record.lastPlayingAt = now
            }
        } else if previous == nil {
            record.lastPlayingAt = now
        }

        record.state = sanitizedState
        childRecords[slotKey] = record
        reselectAndPublish(now: now)
    }

    private func buildSnapshots() -> [String: MediaSourceSelector.SourceSnapshot] {
        var snapshots: [String: MediaSourceSelector.SourceSnapshot] = [:]
        for (slotKey, record) in childRecords {
            guard let state = record.state else { continue }
            snapshots[slotKey] = MediaSourceSelector.SourceSnapshot(
                bundleIdentifier: state.bundleIdentifier,
                sourceName: state.bundleIdentifier,
                isPlaying: state.isPlaying,
                title: state.title,
                lastPlayingAt: record.lastPlayingAt,
                priorityRank: MediaSourceSelector.defaultPriorityRank(for: state.bundleIdentifier)
            )
        }
        return snapshots
    }

    private func reselectAndPublish(now: Date) {
        let snapshots = buildSnapshots()
        let winnerKey = MediaSourceSelector.selectActiveSource(from: snapshots, now: now)
        activeSlotKey = winnerKey

        if let winnerKey, let winningState = childRecords[winnerKey]?.state {
            playbackState = winningState
        } else {
            let idle = PlaybackState(bundleIdentifier: "")
            if playbackState != idle || playbackState.isPlaying || !playbackState.title.isEmpty {
                playbackState = idle
            }
        }

        scheduleLingerExpiryIfNeeded(snapshots: snapshots, now: now)
    }

    private func scheduleLingerExpiryIfNeeded(
        snapshots: [String: MediaSourceSelector.SourceSnapshot],
        now: Date
    ) {
        lingerExpiryTask?.cancel()
        lingerExpiryTask = nil

        guard let delay = MediaSourceSelector.nextLingerExpiryDelay(from: snapshots, now: now) else {
            return
        }

        lingerExpiryTask = Task { [weak self] in
            let nanos = UInt64(max(0.5, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                let currentNow = Date()
                let cutoff = currentNow.addingTimeInterval(-MediaSourceSelector.pausedLingerDuration)
                for (key, record) in self.childRecords {
                    if let state = record.state, !state.isPlaying, record.lastPlayingAt <= cutoff {
                        var updated = record
                        updated.state = nil
                        self.childRecords[key] = updated
                    }
                }
                self.reselectAndPublish(now: currentNow)
            }
        }
    }

    private func startTerminationObserver() {
        terminationObserverTask = Task { [weak self] in
            let terminations = NSWorkspace.shared.notificationCenter.notifications(
                named: NSWorkspace.didTerminateApplicationNotification
            )
            for await notification in terminations {
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier,
                      let self else {
                    continue
                }
                await MainActor.run {
                    var didChange = false
                    for (slotKey, record) in self.childRecords {
                        let matchesSlot = slotKey == bundleID || record.state?.bundleIdentifier == bundleID
                        if matchesSlot, record.state != nil {
                            var updated = record
                            updated.state = nil
                            self.childRecords[slotKey] = updated
                            didChange = true
                        }
                    }
                    if didChange {
                        self.reselectAndPublish(now: Date())
                    }
                }
            }
        }
    }
}
