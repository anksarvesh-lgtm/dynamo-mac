// SPDX-License-Identifier: MIT
import AppKit
import CoreServices
import NotchCore

/// Music and Spotify, through their own AppleScript dictionaries: what MediaRemote leaves out
/// (Spotify's shuffle and repeat, Music's up next and lyrics, a Spotify link to play a track again)
/// and, in the App Store edition, the controls the sandbox otherwise blocks. macOS asks once per app
/// (Privacy & Security › Automation). Nothing is sent to an app that isn't running, since `tell`
/// would launch it, and nothing is sent before the user has said yes, except to ask.
public enum ScriptedPlayer: String, Sendable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"

    public init?(bundleID: String?) {
        guard let player = bundleID.flatMap(ScriptedPlayer.init(rawValue:)) else { return nil }
        self = player
    }

    public var name: String { self == .music ? "Music" : "Spotify" }

    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty }

    /// Whether the app has repeat-one. Spotify's dictionary only has repeat on or off.
    var repeatsOne: Bool { self == .music }

    public enum Permission: Sendable {
        case granted, notAsked, denied
    }

    /// Whether ILoveNotch may script the app, asking with macOS's prompt when `ask` is set and the user
    /// hasn't answered yet. Off the main thread: the prompt waits for the answer. The app is addressed
    /// by process, not bundle ID: asked about Spotify by bundle ID, macOS never answers (observed with
    /// Spotify 1.3.3 on macOS 26.6), and nothing is sent to an app that isn't running anyway.
    func permission(ask: Bool) async -> Permission {
        guard
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).first?.processIdentifier
        else { return .denied }
        return await Task.detached(priority: .userInitiated) { () -> Permission in
            let descriptor = NSAppleEventDescriptor(processIdentifier: pid)
            guard let target = descriptor.aeDesc else { return .denied }
            // A real event, the "get" every script here sends: macOS won't prompt for a wildcard.
            let status = withExtendedLifetime(descriptor) {
                AEDeterminePermissionToAutomateTarget(target, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), ask)
            }
            switch status {
            case 0: return .granted
            case -1744: return .notAsked  // errAEEventWouldRequireUserConsent
            default: return .denied  // errAEEventNotPermitted (-1743), or the app quit (procNotFound)
            }
        }.value
    }

    // MARK: Scripts

    /// Runs `body` inside `tell application id …` on the main thread, as NSAppleScript requires, and
    /// gives up after two seconds if the app hangs. Nil when the app isn't running or the script fails.
    // ponytail: blocks the main thread for the round trip (a few ms); a hung player stalls it up to
    // the 2 s timeout. Raw AppleEvents sent from a background queue if that's ever felt.
    @MainActor @discardableResult
    func run(_ body: String) -> NSAppleEventDescriptor? {
        guard isRunning else { return nil }
        let source = "with timeout of 2 seconds\ntell application id \"\(rawValue)\"\n\(body)\nend tell\nend timeout"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            Log.features.error("\(self.name, privacy: .public) script failed: \(number, privacy: .public)")
            return nil
        }
        return result
    }

    @MainActor func playPause() { run("playpause") }

    @MainActor func next() { run("next track") }

    /// Like the button: back to the start, or to the track before when already there.
    @MainActor func previous() { run(self == .music ? "back track" : "previous track") }

    @MainActor func seek(to seconds: TimeInterval) {
        run("set player position to \(max(0, seconds))")
    }

    @MainActor func setShuffle(_ on: Bool) {
        run(self == .music ? "set shuffle enabled to \(on)" : "set shuffling to \(on)")
    }

    @MainActor func setRepeat(_ mode: RepeatMode) {
        switch self {
        case .music: run("set song repeat to \(mode)")
        case .spotify: run("set repeating to \(mode != .off)")
        }
    }

    /// Shuffle, repeat, the position, and an identifier for the track playing now.
    @MainActor func state() -> ScriptedState? {
        let script =
            switch self {
            case .music:
                """
                set r to song repeat
                if r is off then
                    set r to "off"
                else if r is one then
                    set r to "one"
                else
                    set r to "all"
                end if
                set i to ""
                try
                    set i to persistent ID of current track
                end try
                return {shuffle enabled, r, player position, i}
                """
            case .spotify:
                """
                set i to ""
                try
                    set i to spotify url of current track
                end try
                return {shuffling, repeating, player position, i}
                """
            }
        return run(script).flatMap(ScriptedState.init)
    }

    /// The cover of the track playing now, for when MediaRemote's artwork can't be read (the App Store
    /// edition). Music hands over the image itself.
    // ponytail: Spotify only offers a link to its image server, and fetching it would be the App Store
    // edition's first network request (PRIVACY.md, review notes); its cover stays the tinted stand-in.
    @MainActor func artwork() -> Data? {
        guard self == .music else { return nil }
        return run("return raw data of artwork 1 of current track")?.data
    }

    /// Music's tracks after this one in the playlist it plays from, at most 30.
    @MainActor func upNext() -> PlayerQueue? {
        guard self == .music else { return nil }
        let script = """
            set p to current playlist
            set n to count of tracks of p
            set i to index of current track
            set j to i + 30
            if j > n then set j to n
            if j ≤ i then return {name of p, {}, {}, {}, {}}
            -- A reference, so each property below is one request for the whole range.
            set s to a reference to tracks (i + 1) thru j of p
            return {name of p, persistent ID of s, name of s, artist of s, duration of s}
            """
        return run(script).flatMap(PlayerQueue.init(upNext:))
    }

    /// The lyrics saved with the track playing now, in Music; nil when it has none.
    @MainActor func lyrics() -> String? {
        guard self == .music else { return nil }
        let text = run("return lyrics of current track")?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    /// Plays a track from the list: one of Music's up next, by persistent ID, or a Spotify link.
    @MainActor func play(_ item: QueueItem) {
        let id = item.id.replacingOccurrences(of: "\"", with: "")
        switch self {
        case .music: run("play (some track of current playlist whose persistent ID is \"\(id)\")")
        case .spotify: run("play track \"\(id)\"")
        }
    }
}

/// What Music or Spotify says about the track playing now.
public struct ScriptedState: Equatable, Sendable {
    public var shuffle: Bool
    public var repeatMode: RepeatMode
    /// Seconds into the track when it was asked.
    public var position: TimeInterval
    /// Music's persistent ID or Spotify's link, to play the track again later; nil when it has none.
    public var trackID: String?

    /// The list `ScriptedPlayer.state` returns: shuffle, repeat ("off", "one", or "all" from Music, on
    /// or off from Spotify), the position, and the track's identifier.
    init?(_ list: NSAppleEventDescriptor) {
        guard list.numberOfItems == 4, let first = list.atIndex(1), let second = list.atIndex(2),
            let third = list.atIndex(3), let fourth = list.atIndex(4)
        else { return nil }
        shuffle = first.booleanValue
        // Spotify's boolean reads as "true" or "false".
        repeatMode =
            switch second.stringValue {
            case "one": .one
            case "all", "true": .all
            default: .off
            }
        position = third.doubleValue
        trackID = fourth.stringValue.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// A track the list shows, to pick and play.
public struct QueueItem: Identifiable, Hashable, Sendable {
    /// Music's persistent ID or Spotify's link.
    public var id: String
    public var title: String
    public var artist: String?
    public var duration: TimeInterval?

    public init(id: String, title: String, artist: String? = nil, duration: TimeInterval? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
    }
}

/// The list behind the player's list button: Music's up next, or what Spotify played earlier.
public struct PlayerQueue: Equatable, Sendable {
    public var title: String
    public var items: [QueueItem]

    public init(title: String, items: [QueueItem]) {
        self.title = title
        self.items = items
    }

    /// The list `ScriptedPlayer.upNext` returns: the playlist's name, then the following tracks'
    /// persistent IDs, names, artists, and durations, each as a list.
    init?(upNext list: NSAppleEventDescriptor) {
        guard list.numberOfItems == 5, let name = list.atIndex(1)?.stringValue else { return nil }
        func column(_ index: Int) -> [NSAppleEventDescriptor] {
            guard let column = list.atIndex(index), column.numberOfItems > 0 else { return [] }
            return (1...column.numberOfItems).compactMap(column.atIndex)
        }
        let (ids, names, artists, durations) = (column(2), column(3), column(4), column(5))
        guard names.count == ids.count, artists.count == ids.count, durations.count == ids.count else { return nil }
        title = name
        items = ids.indices.compactMap { index in
            guard let id = ids[index].stringValue, let title = names[index].stringValue else { return nil }
            let artist = artists[index].stringValue
            return QueueItem(
                id: id, title: title, artist: artist?.isEmpty == false ? artist : nil,
                duration: durations[index].doubleValue)
        }
    }
}
