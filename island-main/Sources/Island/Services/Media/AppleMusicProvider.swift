import AppKit
import IslandCore

/// Apple Music via its public `com.apple.Music.playerInfo` distributed notification (event-driven)
/// plus Music's scripting dictionary for position, artwork and controls.
@MainActor
final class AppleMusicProvider: MediaProvider {
    let bundleID = "com.apple.Music"
    let displayName = "Music"
    var onUpdate: ((MediaActivity?) -> Void)?

    private var observer: NSObjectProtocol?
    private var lifecycle: AppLifecycleObserver?
    private var current: MediaActivity?
    private var artworkCache: (key: String, data: Data?)?
    private var refreshTask: Task<Void, Never>?
    static let controls: Set<MediaControl> = [.playPause, .next, .previous, .seek]

    func start() {
        observer = DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] n in
            let info = n.userInfo ?? [:]
            let state = info["Player State"] as? String
            let name = info["Name"] as? String
            let artist = info["Artist"] as? String
            let album = info["Album"] as? String
            let totalMs = (info["Total Time"] as? NSNumber)?.doubleValue
            MainActor.assumeIsolated { self?.handle(state: state, name: name, artist: artist, album: album, totalMs: totalMs) }
        }
        lifecycle = AppLifecycleObserver(bundleID: bundleID, onLaunch: {}, onTerminate: { [weak self] in
            self?.current = nil
            self?.onUpdate?(nil)
        })
        if isRunning { refresh() }
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        lifecycle = nil
        refreshTask?.cancel()
    }

    private func handle(state: String?, name: String?, artist: String?, album: String?, totalMs: Double?) {
        guard let state, state != "Stopped" else {
            current = nil
            onUpdate?(nil)
            return
        }
        let playback: PlaybackState = state == "Playing" ? .playing : .paused
        var m = current ?? MediaActivity(sourceBundleID: bundleID, sourceName: displayName, title: "", playbackState: playback, controls: Self.controls)
        let trackChanged = (name != nil && name != m.title) || (artist != nil && artist != m.artist)
        m.title = name ?? m.title
        m.artist = artist ?? m.artist
        m.album = album ?? m.album
        if let totalMs, totalMs > 0 { m.duration = totalMs / 1000 }
        if trackChanged { m.artwork = nil; m.artworkID = nil; m.elapsed = 0; m.positionTimestamp = Date() }
        else if m.playbackState != playback { m.elapsed = m.position(at: Date()); m.positionTimestamp = Date() }
        m.playbackState = playback
        current = m
        onUpdate?(m)
        refresh()
    }

    /// Pulls position + artwork (and the full state when launched mid-playback).
    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let sep = "(character id 30)"
            let script = """
            if application "Music" is running then
              tell application "Music"
                if player state is stopped then return "stopped"
                try
                  set t to current track
                  return (player state as text) & \(sep) & (name of t) & \(sep) & (artist of t) & \(sep) & (album of t) & \(sep) & (duration of t as text) & \(sep) & (player position as text) & \(sep) & (persistent ID of t)
                on error
                  return (player state as text) & \(sep) & (current stream title) & \(sep) & "" & \(sep) & "" & \(sep) & "0" & \(sep) & (player position as text) & \(sep) & "stream"
                end try
              end tell
            end if
            return "notrunning"
            """
            guard let out = try? await ScriptRunner.run(script) else { return }
            guard !Task.isCancelled else { return }
            if out == "stopped" || out == "notrunning" {
                self.current = nil
                self.onUpdate?(nil)
                return
            }
            let f = out.components(separatedBy: "\u{1E}")
            guard f.count >= 7 else { return }
            var m = self.current ?? MediaActivity(sourceBundleID: self.bundleID, sourceName: self.displayName, title: f[1], playbackState: .paused, controls: Self.controls)
            m.playbackState = f[0] == "playing" ? .playing : .paused
            m.title = f[1]
            m.artist = f[2]
            m.album = f[3]
            m.duration = Self.number(f[4]).flatMap { $0 > 0 ? $0 : nil }
            m.elapsed = Self.number(f[5])
            m.positionTimestamp = Date()
            let key = f[6]
            m.artworkID = "music-\(key)"
            if let cache = self.artworkCache, cache.key == key {
                m.artwork = cache.data
            } else {
                let art = try? await ScriptRunner.run("""
                tell application "Music"
                  try
                    if (count of artworks of current track) > 0 then return raw data of artwork 1 of current track
                  end try
                end tell
                return ""
                """, timeout: 4)
                let data = art.flatMap(ScriptRunner.decodeDataLiteral)
                self.artworkCache = (key, data)
                m.artwork = data
            }
            guard !Task.isCancelled else { return }
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
        // `play` may launch Music (explicit user intent); other verbs require it to be running.
        let guardRunning = command == .play ? "" : "if application \"Music\" is not running then return\n"
        _ = try await ScriptRunner.run("\(guardRunning)tell application \"Music\" to \(verb)")
        if case .seek = command { refresh() }
    }

    static func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }
}
