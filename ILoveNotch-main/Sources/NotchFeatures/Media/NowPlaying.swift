// SPDX-License-Identifier: MIT
import Foundation

/// What the system says is playing.
public struct NowPlaying: Equatable, Sendable {
    public var title: String
    public var artist: String?
    public var album: String?
    public var isPlaying: Bool
    public var playbackRate: Double
    /// Seconds.
    public var duration: TimeInterval?
    /// Seconds into the track at `timestamp`.
    public var elapsed: TimeInterval?
    public var timestamp: Date?
    /// Encoded artwork (JPEG or PNG), as the player supplied it.
    public var artwork: Data?
    /// The app playing it; for browsers, the browser rather than its media helper process.
    public var appBundleID: String?
    /// Whether shuffle is on; nil when the player doesn't say.
    public var shuffle: Bool?
    /// Nil when the player doesn't say.
    public var repeatMode: RepeatMode?
    /// The player skips 15 seconds back and ahead, as podcast and audiobook players do.
    public var skipsByInterval: Bool

    public init(
        title: String, artist: String? = nil, album: String? = nil, isPlaying: Bool, playbackRate: Double = 1,
        duration: TimeInterval? = nil, elapsed: TimeInterval? = nil, timestamp: Date? = nil, artwork: Data? = nil,
        appBundleID: String? = nil, shuffle: Bool? = nil, repeatMode: RepeatMode? = nil, skipsByInterval: Bool = false
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.artwork = artwork
        self.appBundleID = appBundleID
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.skipsByInterval = skipsByInterval
    }

    /// Whether `other` is a different track rather than an update to this one.
    func isDifferentTrack(from other: NowPlaying?) -> Bool {
        title != other?.title || artist != other?.artist || album != other?.album
    }

    /// The playback position at `date`, advancing at the playback rate since `timestamp` while playing.
    public func position(at date: Date) -> TimeInterval? {
        guard var position = elapsed else { return nil }
        if isPlaying, let timestamp { position += date.timeIntervalSince(timestamp) * playbackRate }
        position = max(0, position)
        return duration.map { min(position, $0) } ?? position
    }
}

/// Repeat as players offer it: off, the whole list, or the one track.
public enum RepeatMode: Sendable {
    case off, all, one

    /// What a click on repeat picks next, in Music's order. Without repeat-one (Spotify's AppleScript
    /// only has on and off), all goes back to off.
    public func next(allowsOne: Bool) -> RepeatMode {
        switch self {
        case .off: .all
        case .all: allowsOne ? .one : .off
        case .one: .off
        }
    }

    /// MediaRemote's numbers, which mediaremote-adapter passes through: 1 off, 2 the track, 3 the
    /// playlist; 0 is unknown.
    init?(remote: Int) {
        switch remote {
        case 1: self = .off
        case 2: self = .one
        case 3: self = .all
        default: return nil
        }
    }

    var remote: Int {
        switch self {
        case .off: 1
        case .one: 2
        case .all: 3
        }
    }
}

/// Folds mediaremote-adapter's `stream --micros` output, one JSON object per line, into the current
/// track. A line with `"diff": false` replaces the state; `"diff": true` merges its keys, where a
/// null value removes one. An empty payload means nothing is playing.
struct MediaStreamParser {
    private var payload: [String: Any] = [:]
    private var artworkBase64: String?
    private var artwork: Data?

    /// Applies one line and returns what's playing afterwards. Lines it doesn't understand are ignored.
    mutating func consume(_ line: String) -> NowPlaying? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            object["type"] as? String == "data",
            let changes = object["payload"] as? [String: Any]
        else { return current }
        if object["diff"] as? Bool == true {
            for (key, value) in changes { payload[key] = value is NSNull ? nil : value }
        } else {
            payload = changes
        }
        // Decode artwork only when it actually changes; it's the one large field.
        let base64 = payload["artworkData"] as? String
        if base64 != artworkBase64 {
            artworkBase64 = base64
            artwork = base64.flatMap { Data(base64Encoded: $0) }
        }
        return current
    }

    private var current: NowPlaying? {
        guard let title = payload["title"] as? String, !title.isEmpty else { return nil }
        func seconds(_ key: String) -> TimeInterval? { (payload[key] as? Double).map { $0 / 1_000_000 } }
        // MediaRemote's shuffle: 1 off, 2 albums, 3 tracks; 0 is unknown.
        let shuffle = (payload["shuffleMode"] as? Int).flatMap { $0 == 0 ? nil : $0 != 1 }
        return NowPlaying(
            title: title,
            artist: payload["artist"] as? String,
            album: payload["album"] as? String,
            isPlaying: payload["playing"] as? Bool ?? false,
            playbackRate: payload["playbackRate"] as? Double ?? 1,
            duration: seconds("durationMicros"),
            elapsed: seconds("elapsedTimeMicros"),
            timestamp: seconds("timestampEpochMicros").map(Date.init(timeIntervalSince1970:)),
            artwork: artwork,
            appBundleID: payload["parentApplicationBundleIdentifier"] as? String
                ?? payload["bundleIdentifier"] as? String,
            shuffle: shuffle,
            repeatMode: (payload["repeatMode"] as? Int).flatMap(RepeatMode.init(remote:)),
            skipsByInterval: payload["supportsRewind15Seconds"] as? Bool == true
                && payload["supportsFastForward15Seconds"] as? Bool == true)
    }
}

/// The fallback source: Music and Spotify post these public distributed notifications on every
/// change, no permission needed. They carry no artwork or position, and a pause may arrive as a
/// bare state change, so each one is merged into the previous track.
struct PlayerNotification: Equatable, Sendable {
    static let names = ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"]

    var title: String?
    var artist: String?
    var album: String?
    /// "Playing", "Paused", or "Stopped".
    var state: String?
    var milliseconds: Double?
    var appBundleID: String

    init(_ info: [AnyHashable: Any], name: String) {
        title = info["Name"] as? String
        artist = info["Artist"] as? String
        album = info["Album"] as? String
        state = info["Player State"] as? String
        // Music reports "Total Time" and Spotify "Duration", both in milliseconds.
        milliseconds = (info["Total Time"] ?? info["Duration"]) as? Double
        appBundleID = name.hasPrefix("com.spotify") ? "com.spotify.client" : "com.apple.Music"
    }

    func merge(into previous: NowPlaying?) -> NowPlaying? {
        if state == "Stopped" { return nil }
        guard let title = title ?? previous?.title else { return nil }
        let sameTrack = self.title == nil
        return NowPlaying(
            title: title,
            artist: artist ?? (sameTrack ? previous?.artist : nil),
            album: album ?? (sameTrack ? previous?.album : nil),
            isPlaying: state.map { $0 == "Playing" } ?? previous?.isPlaying ?? false,
            duration: milliseconds.map { $0 / 1000 } ?? (sameTrack ? previous?.duration : nil),
            appBundleID: appBundleID)
    }
}
