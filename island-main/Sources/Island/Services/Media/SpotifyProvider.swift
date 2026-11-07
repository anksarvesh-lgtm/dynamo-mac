import AppKit
import IslandCore

/// Spotify via its public `com.spotify.client.PlaybackStateChanged` distributed notification plus
/// Spotify's scripting dictionary (artwork URL, controls).
@MainActor
final class SpotifyProvider: MediaProvider {
    let bundleID = "com.spotify.client"
    let displayName = "Spotify"
    var onUpdate: ((MediaActivity?) -> Void)?

    private var observer: NSObjectProtocol?
    private var lifecycle: AppLifecycleObserver?
    private var current: MediaActivity?
    private var trackID: String?
    private var artworkTask: Task<Void, Never>?
    private var artworkCache: [String: Data] = [:]
    static let controls: Set<MediaControl> = [.playPause, .next, .previous, .seek]

    func start() {
        observer = DistributedNotificationCenter.default().addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] n in
            let info = n.userInfo ?? [:]
            let state = info["Player State"] as? String
            let name = info["Name"] as? String
            let artist = info["Artist"] as? String
            let album = info["Album"] as? String
            let durationMs = (info["Duration"] as? NSNumber)?.doubleValue
            let position = (info["Playback Position"] as? NSNumber)?.doubleValue
            let id = info["Track ID"] as? String
            MainActor.assumeIsolated {
                self?.handle(state: state, name: name, artist: artist, album: album, durationMs: durationMs, position: position, id: id)
            }
        }
        lifecycle = AppLifecycleObserver(bundleID: bundleID, onLaunch: {}, onTerminate: { [weak self] in
            self?.current = nil
            self?.onUpdate?(nil)
        })
        if isRunning { snapshot() }
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        lifecycle = nil
        artworkTask?.cancel()
    }

    private func handle(state: String?, name: String?, artist: String?, album: String?, durationMs: Double?, position: Double?, id: String?) {
        guard let state, state != "Stopped" else {
            current = nil
            onUpdate?(nil)
            return
        }
        var m = current ?? MediaActivity(sourceBundleID: bundleID, sourceName: displayName, title: "", playbackState: .paused, controls: Self.controls)
        m.playbackState = state == "Playing" ? .playing : .paused
        if let name { m.title = name }
        if let artist { m.artist = artist }
        if let album { m.album = album }
        if let durationMs, durationMs > 0 { m.duration = durationMs / 1000 }
        if let position { m.elapsed = position; m.positionTimestamp = Date() }
        if let id, id != trackID {
            trackID = id
            m.artworkID = "spotify-\(id)"
            m.artwork = artworkCache[id]
            if m.artwork == nil { loadArtwork(for: id) }
        }
        current = m
        onUpdate?(m)
    }

    private func snapshot() {
        Task { [weak self] in
            let sep = "(character id 30)"
            let script = """
            if application "Spotify" is running then
              tell application "Spotify"
                if player state is stopped then return "stopped"
                set t to current track
                return (player state as text) & \(sep) & (name of t) & \(sep) & (artist of t) & \(sep) & (album of t) & \(sep) & (duration of t as text) & \(sep) & (player position as text) & \(sep) & (id of t)
              end tell
            end if
            return "notrunning"
            """
            guard let out = try? await ScriptRunner.run(script), let self else { return }
            let f = out.components(separatedBy: "\u{1E}")
            guard f.count >= 7 else { return }
            self.handle(state: f[0] == "playing" ? "Playing" : "Paused", name: f[1], artist: f[2], album: f[3],
                        durationMs: AppleMusicProvider.number(f[4]), position: AppleMusicProvider.number(f[5]), id: f[6])
        }
    }

    private func loadArtwork(for id: String) {
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let urlString = try? await ScriptRunner.run("if application \"Spotify\" is running then tell application \"Spotify\" to return artwork url of current track"),
                  let url = URL(string: urlString), url.scheme == "https" else { return }
            var request = URLRequest(url: url, timeoutInterval: 6)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200, !Task.isCancelled, let self else { return }
            self.artworkCache[id] = data
            if self.artworkCache.count > 30 { self.artworkCache.removeAll() ; self.artworkCache[id] = data }
            guard self.trackID == id, var m = self.current else { return }
            m.artwork = data
            self.current = m
            self.onUpdate?(m)
        }
    }

    func perform(_ command: MediaCommand) async throws {
        let verb: String
        switch command {
        case .togglePlayPause: verb = "playpause"
        case .play: verb = "play"
        case .pause: verb = "pause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        case .seek(let t): verb = "set player position to \(max(0, t))"
        }
        _ = try await ScriptRunner.run("if application \"Spotify\" is running then tell application \"Spotify\" to \(verb)")
        if case .seek(let t) = command, var m = current {
            m.elapsed = t
            m.positionTimestamp = Date()
            current = m
            onUpdate?(m)
        }
    }
}
