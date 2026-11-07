import AppKit
import IslandCore

/// Universal media hub. Aggregates every provider into ONE `media` activity:
/// the source that most recently started playing wins; a paused source lingers (low priority) and is
/// dropped after a while. Switching from Music to Spotify updates the same activity, so the Island
/// morphs in place instead of creating anything new.
@MainActor
final class MediaService {
    struct SourceState {
        var media: MediaActivity
        var lastPlayingAt: Date
    }

    static let activityID = "media"
    static let pausedLinger = MediaSourceSelector.pausedLinger

    private let sink: (ActivityUpdate) -> Void
    private let bus: EventBus
    private(set) var providers: [MediaProvider] = []
    private(set) var states: [String: SourceState] = [:]
    private(set) var currentSource: String?
    private var lingerTask: Task<Void, Never>?
    private(set) var lastError: String?

    init(bus: EventBus, sink: @escaping (ActivityUpdate) -> Void) {
        self.bus = bus
        self.sink = sink
    }

    func register(_ provider: MediaProvider) {
        guard !providers.contains(where: { $0.bundleID == provider.bundleID }) else { return }
        provider.onUpdate = { [weak self, weak provider] media in
            guard let self, let provider else { return }
            self.receive(media, from: provider.bundleID)
        }
        providers.append(provider)
        provider.start()
    }

    func unregister(bundleID: String) {
        guard let idx = providers.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        providers[idx].stop()
        providers.remove(at: idx)
        receive(nil, from: bundleID)
    }

    func stopAll() { providers.forEach { $0.stop() } }

    // MARK: Aggregation

    func receive(_ media: MediaActivity?, from bundleID: String) {
        let now = Date()
        if let media {
            let wasPlaying = states[bundleID]?.media.playbackState == .playing
            let lastPlaying = media.playbackState == .playing ? now : (states[bundleID]?.lastPlayingAt ?? now)
            states[bundleID] = SourceState(media: media, lastPlayingAt: lastPlaying)
            if media.playbackState == .playing, !wasPlaying { bus.publish(.mediaStarted(source: media.sourceName)) }
        } else {
            states[bundleID] = nil
        }
        publish(now: now)
    }

    static func select(from states: [String: SourceState], now: Date) -> String? {
        MediaSourceSelector.select(states.mapValues { .init(state: $0.media.playbackState, lastPlayingAt: $0.lastPlayingAt) }, now: now)
    }

    private func publish(now: Date) {
        currentSource = Self.select(from: states, now: now)
        guard let source = currentSource, let state = states[source] else {
            sink(.remove(id: Self.activityID))
            return
        }
        let playing = state.media.playbackState == .playing
        sink(.upsert(Activity(id: Self.activityID, kind: .media, priority: playing ? .normal : .low, content: .media(state.media))))
        scheduleLinger(now: now)
    }

    private func scheduleLinger(now: Date) {
        lingerTask?.cancel()
        guard let oldestPaused = states.values.filter({ $0.media.playbackState != .playing }).map(\.lastPlayingAt).min() else { return }
        let delay = max(1, Self.pausedLinger - now.timeIntervalSince(oldestPaused) + 1)
        lingerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            let cutoff = Date().addingTimeInterval(-Self.pausedLinger)
            self.states = self.states.filter { $0.value.media.playbackState == .playing || $0.value.lastPlayingAt > cutoff }
            self.publish(now: Date())
        }
    }

    // MARK: Commands

    func perform(_ command: MediaCommand, source: String?) {
        let target = source ?? currentSource
        guard let target, let provider = providers.first(where: { $0.bundleID == target }) else {
            // Nothing known is playing: fall back to the system media keys (requires Accessibility).
            switch command {
            case .togglePlayPause, .play, .pause: SystemMediaProvider.send(.playPause)
            case .next: SystemMediaProvider.send(.next)
            case .previous: SystemMediaProvider.send(.previous)
            case .seek: break
            }
            return
        }
        // Optimistic play/pause so the button responds instantly; the provider's next event corrects it.
        if case .togglePlayPause = command, var s = states[target] {
            s.media.elapsed = s.media.position(at: Date())
            s.media.positionTimestamp = Date()
            s.media.playbackState = s.media.playbackState == .playing ? .paused : .playing
            if s.media.playbackState == .playing { s.lastPlayingAt = Date() }
            states[target] = s
            publish(now: Date())
        }
        Task { [weak self] in
            do {
                try await provider.perform(command)
                self?.lastError = nil
            } catch {
                self?.lastError = "\(provider.displayName): \(error)"
                NSLog("Island media command failed: %@", String(describing: error))
            }
        }
    }

    /// "play music" with nothing active → start Apple Music (explicit user request).
    func playDefault() {
        if currentSource != nil { perform(.play, source: nil); return }
        if let music = providers.first(where: { $0.bundleID == "com.apple.Music" }) {
            Task { try? await music.perform(.play) }
        }
    }
}
