// SPDX-License-Identifier: MIT
import AppKit
import ImageIO
import NotchCore
import Observation
import SwiftUI

/// Playback commands mediaremote-adapter's `send` understands.
public enum MediaCommand: Int, Sendable {
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
    case skipBackward = 12
    case skipForward = 13
}

/// Now playing and playback controls for whatever app the system considers the player.
///
/// The system's now-playing data lives behind MediaRemote, which macOS 15.4+ only serves to Apple
/// processes. mediaremote-adapter (BSD-3-Clause) bridges that from `/usr/bin/perl` in a child
/// process, so the private framework never loads into OpenNotch and a breakage can't take the
/// app down. If the helper dies, Music and Spotify's public notifications take over. Music and
/// Spotify also answer AppleScript (`ScriptedPlayer`), which fills in what MediaRemote leaves out
/// and, without the helper, works the controls.
@MainActor
@Observable
public final class MediaFeature: NotchFeature {
    public enum Source: Equatable, Sendable {
        /// Any app, with controls.
        case adapter
        /// Music and Spotify only; controls by AppleScript, once the user allows it.
        case fallback
    }

    public let id = FeatureID.media
    public var phase: FeaturePhase = .stopped {
        didSet {
            phase == .stopped ? stop() : start()
            updateAudio()
            if phase == .foreground { refreshScripted() }
            updateOngoing()
        }
    }
    public private(set) var nowPlaying: NowPlaying?
    public private(set) var artwork: NSImage?
    /// The cover's color, lifted to read on black; tints the seek wave, waveform, and glow.
    public private(set) var accent: RGB?
    public private(set) var source: Source
    /// Per-feature setting: raise a live activity when the track changes.
    public var announcesTracks: Bool {
        didSet { defaults.set(announcesTracks, forKey: Self.announceKey) }
    }
    /// Per-feature setting: the waveform follows what's playing, which asks to capture system audio.
    public var waveformFollowsAudio: Bool {
        didSet {
            defaults.set(waveformFollowsAudio, forKey: Self.followsAudioKey)
            updateAudio()
        }
    }
    /// Per-feature setting: what's playing stays beside the camera while the notch is closed, and
    /// for a minute after it pauses.
    public var showsInClosedNotch: Bool {
        didSet {
            defaults.set(showsInClosedNotch, forKey: Self.closedNotchKey)
            updateOngoing()
        }
    }
    /// What Music or Spotify says through AppleScript about the track playing now.
    public private(set) var scripted: ScriptedState?
    /// The player's list: Music's up next, or Spotify tracks played earlier. Nil until it's loaded.
    public private(set) var queue: PlayerQueue?
    /// Lyrics saved with the track in Music.
    public private(set) var lyrics: String?
    /// The app's output picker (the Sound tab's devices and volumes) for the app playing, by bundle
    /// identifier; nil where there's none.
    public var outputControl: ((String?) -> AnyView)?
    /// Raised when the track changes while the notch shows something else.
    @ObservationIgnored public var onActivity: ((Activity) -> Void)?
    /// Keeps what's playing beside the closed notch; nil clears it.
    @ObservationIgnored public var onOngoing: ((Activity?) -> Void)?
    /// What the waveform hears, while Media is on screen and playing.
    let audio = AudioSpectrum()

    private static let announceKey = "media.announcesTracks"
    private static let followsAudioKey = "media.waveformFollowsAudio"
    private static let closedNotchKey = "media.showsInClosedNotch"
    /// How long a paused track stays in the closed notch.
    nonisolated static let linger: TimeInterval = 60
    /// What macOS answered when asked whether ILoveNotch may script each player.
    private var permissions: [ScriptedPlayer: ScriptedPlayer.Permission] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let adapter: MediaAdapter?
    @ObservationIgnored private var stream: Process?
    @ObservationIgnored private var startedAt = Date.distantPast
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    /// When the track last paused, for how long it lingers in the closed notch.
    @ObservationIgnored private var pausedAt: Date?
    @ObservationIgnored private var lingering: Task<Void, Never>?
    @ObservationIgnored private var shownOngoing: Activity?
    /// The cover, small enough for the closed notch.
    @ObservationIgnored private var tinyArtwork: Data?
    /// Spotify tracks that played, newest first, to play again from the list.
    // ponytail: kept since launch only; save it if people want it across restarts.
    @ObservationIgnored private var history: [QueueItem] = []
    /// The cover AppleScript read for a track, by `key(for:)`, while the helper can't supply one.
    @ObservationIgnored private var fallbackArtwork: (key: String, data: Data?)?
    // ponytail: artwork is downsampled to thumbnails and at most 16 recent tracks are kept.
    @ObservationIgnored private let artworkCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 16
        return cache
    }()

    public init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        adapter = MediaAdapter.bundled(in: bundle)
        source = adapter == nil ? .fallback : .adapter
        announcesTracks = defaults.object(forKey: Self.announceKey) as? Bool ?? true
        waveformFollowsAudio = defaults.object(forKey: Self.followsAudioKey) as? Bool ?? true
        showsInClosedNotch = defaults.object(forKey: Self.closedNotchKey) as? Bool ?? true
    }

    /// The audio tap runs only while its bars can be seen moving: Media on screen, something playing,
    /// the setting on, and Reduce Motion off.
    nonisolated static func listensToAudio(phase: FeaturePhase, enabled: Bool, playing: Bool, reduceMotion: Bool)
        -> Bool
    {
        phase == .foreground && enabled && playing && !reduceMotion
    }

    private func updateAudio() {
        let listens = Self.listensToAudio(
            phase: phase, enabled: waveformFollowsAudio, playing: nowPlaying?.isPlaying == true,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        listens ? audio.start() : audio.stop()
    }

    public var view: some View { MediaView(media: self) }

    /// Whether a now-playing source (helper process or notifications) is running.
    var isListening: Bool { stream != nil || !notificationTokens.isEmpty }

    // MARK: What the player offers

    /// Music or Spotify, when it's what's playing: they answer AppleScript.
    public var scriptedPlayer: ScriptedPlayer? { ScriptedPlayer(bundleID: nowPlaying?.appBundleID) }

    /// The buttons work: through the helper, or by scripting Music or Spotify.
    public var hasControls: Bool { source == .adapter || scriptedPlayer != nil }

    public var shuffle: Bool? { nowPlaying?.shuffle ?? scripted?.shuffle }

    public var repeatMode: RepeatMode? { nowPlaying?.repeatMode ?? scripted?.repeatMode }

    /// Shuffle and repeat show when the player reports them, or when it can be asked.
    public var hasModes: Bool { nowPlaying?.shuffle != nil || nowPlaying?.repeatMode != nil || scriptedPlayer != nil }

    /// The user said no to ILoveNotch scripting the app playing now.
    public var automationDenied: Bool { scriptedPlayer.map { permissions[$0] == .denied } ?? false }

    // MARK: Controls

    public func send(_ command: MediaCommand) {
        if source == .adapter, let adapter {
            // `send` waits up to 2 s for the player, so it runs off the main thread; the stream reports
            // the outcome.
            Task { _ = await Subprocess.run(MediaAdapter.perl, adapter.arguments(["send", "\(command.rawValue)"])) }
            return
        }
        guard let player = scriptedPlayer else { return }
        scripting(player) { player in
            switch command {
            case .togglePlayPause: player.playPause()
            case .nextTrack: player.next()
            case .previousTrack: player.previous()
            case .skipBackward, .skipForward: break  // only podcast players skip by time, through the helper
            }
        }
    }

    /// Jumps to a point in the track. The stream, or the player's state read back, reports the new position.
    public func seek(to seconds: TimeInterval) {
        if source == .adapter, let adapter {
            Task { _ = await Subprocess.run(MediaAdapter.perl, adapter.arguments(MediaAdapter.seek(to: seconds))) }
            return
        }
        guard let player = scriptedPlayer else { return }
        scripting(player) { $0.seek(to: seconds) }
    }

    public func toggleShuffle() {
        if source == .adapter, let adapter, let on = nowPlaying?.shuffle {
            Task { _ = await Subprocess.run(MediaAdapter.perl, adapter.arguments(["shuffle", on ? "1" : "3"])) }
            return
        }
        guard let player = scriptedPlayer else { return }
        scripting(player) { player in
            player.setShuffle(!(player.state()?.shuffle ?? false))
        }
    }

    /// Off, then the whole list, then the one track (where the player has repeat-one), then off.
    public func cycleRepeat() {
        if source == .adapter, let adapter, let mode = nowPlaying?.repeatMode {
            let next = mode.next(allowsOne: true)
            Task { _ = await Subprocess.run(MediaAdapter.perl, adapter.arguments(["repeat", "\(next.remote)"])) }
            return
        }
        guard let player = scriptedPlayer else { return }
        scripting(player) { player in
            let mode = player.state()?.repeatMode ?? .off
            player.setRepeat(mode.next(allowsOne: player.repeatsOne))
        }
    }

    /// Loads the list for the app playing now, asking to script it the first time.
    public func loadList() {
        guard let player = scriptedPlayer else { return }
        scripting(player) { [weak self] player in
            guard let self else { return }
            switch player {
            case .music:
                queue = player.upNext() ?? PlayerQueue(title: "", items: [])
            case .spotify:
                let current = player.state()?.trackID
                queue = PlayerQueue(title: "Recently Played", items: history.filter { $0.id != current })
            }
        }
    }

    /// Plays a track picked from the list.
    public func play(_ item: QueueItem) {
        guard let player = scriptedPlayer else { return }
        scripting(player) { $0.play(item) }
    }

    /// Brings the playing app forward.
    public func openPlayer() {
        guard let bundleID = nowPlaying?.appBundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: AppleScript

    /// Runs `work` once the user lets ILoveNotch script `player`, asking the first time, then reads
    /// the player's state again.
    private func scripting(_ player: ScriptedPlayer, _ work: @escaping @MainActor (ScriptedPlayer) -> Void) {
        Task {
            let permission = await player.permission(ask: true)
            permissions[player] = permission
            guard permission == .granted else { return }
            work(player)
            readScripted(player)
        }
    }

    /// Reads shuffle, repeat, and the position from Music or Spotify, when the user has already let
    /// ILoveNotch script it. It never asks by itself; pressing a control does.
    private func refreshScripted() {
        guard let player = scriptedPlayer, phase != .stopped else {
            scripted = nil
            return
        }
        switch permissions[player] {
        case .granted:
            readScripted(player)
        case nil:
            Task {
                let permission = await player.permission(ask: false)
                permissions[player] = permission
                if permission == .granted, scriptedPlayer == player { readScripted(player) }
            }
        case .notAsked, .denied:
            scripted = nil
        }
    }

    private func readScripted(_ player: ScriptedPlayer) {
        guard scriptedPlayer == player else { return }
        let state = player.state()
        scripted = state
        switch player {
        case .music:
            lyrics = player.lyrics()
        case .spotify:
            if let id = state?.trackID, let now = nowPlaying {
                remember(QueueItem(id: id, title: now.title, artist: now.artist, duration: now.duration))
            }
        }
        // Without the helper, the position and the cover come from the player itself.
        guard source == .fallback, var now = nowPlaying, let state else { return }
        now.elapsed = state.position
        now.timestamp = .now
        receive(now)
        let key = Self.key(for: now)
        guard fallbackArtwork?.key != key else { return }
        let data = player.artwork()
        fallbackArtwork = (key, data)
        now.artwork = data
        receive(now)
    }

    /// Keeps a Spotify track that played, newest first, to play again from the list.
    private func remember(_ item: QueueItem) {
        history.removeAll { $0.id == item.id }
        history.insert(item, at: 0)
        if history.count > 30 { history.removeLast() }
    }

    nonisolated static func key(for now: NowPlaying) -> String {
        "\(now.title)|\(now.artist ?? "")|\(now.album ?? "")"
    }

    // MARK: Colors

    /// The cover's average color, lifted so it reads on the black notch: vivid covers keep their hue
    /// at a floor of saturation and brightness, and grey ones stay grey instead of turning pink.
    /// Computed once per track from the 256 px thumbnail.
    nonisolated static func accent(of image: CGImage) -> RGB? {
        var pixel: [UInt8] = [0, 0, 0, 0]
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        let average = NSColor(
            srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        let saturation = average.saturationComponent < 0.12 ? 0 : max(average.saturationComponent, 0.45)
        let lifted = NSColor(
            hue: average.hueComponent, saturation: saturation, brightness: max(average.brightnessComponent, 0.78),
            alpha: 1)
        guard let sRGB = lifted.usingColorSpace(.sRGB) else { return nil }
        return RGB(red: sRGB.redComponent, green: sRGB.greenComponent, blue: sRGB.blueComponent)
    }

    // MARK: Sources

    private func start() {
        guard stream == nil, notificationTokens.isEmpty else { return }
        startedAt = Date()
        if source == .adapter, let adapter, startStream(adapter) { return }
        source = .fallback
        startNotifications()
    }

    private func stop() {
        let stream = stream
        self.stream = nil  // marks the exit as expected
        stream?.terminate()
        notificationTokens.forEach(DistributedNotificationCenter.default().removeObserver)
        notificationTokens = []
        receive(nil)
    }

    private func startStream(_ adapter: MediaAdapter) -> Bool {
        let process = adapter.process(["stream", "--micros"])
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] ended in
            let status = ended.terminationStatus
            Task { @MainActor in self?.streamEnded(ended, status: status) }
        }
        do {
            try process.run()
        } catch {
            Log.features.error("Media helper didn't start: \(error.localizedDescription, privacy: .public)")
            return false
        }
        stream = process
        let lines = output.fileHandleForReading.bytes.lines
        Task.detached { [weak self] in
            var parser = MediaStreamParser()
            do {
                for try await line in lines {
                    let now = parser.consume(line)
                    await self?.receive(now)
                }
            } catch {
                // The pipe closes when the helper exits; streamEnded handles that.
            }
        }
        Log.features.info("Media helper streaming")
        return true
    }

    private func streamEnded(_ process: Process, status: Int32) {
        guard process === stream else { return }  // stopped on purpose
        stream = nil
        // Upstream advises against restarting a helper that exited on its own: fall back instead.
        Log.features.error("Media helper exited with status \(status, privacy: .public); using the fallback")
        source = .fallback
        startNotifications()
    }

    private func startNotifications() {
        let center = DistributedNotificationCenter.default()
        notificationTokens = PlayerNotification.names.map { name in
            center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                let update = PlayerNotification(note.userInfo ?? [:], name: name)
                MainActor.assumeIsolated {
                    guard let self else { return }
                    var now = update.merge(into: self.nowPlaying)
                    // Notifications carry no cover: keep the one fetched for this track.
                    if let art = self.fallbackArtwork, let track = now, Self.key(for: track) == art.key {
                        now?.artwork = art.data
                    }
                    self.receive(now)
                    self.refreshScripted()  // the position, shuffle, and repeat, when allowed
                }
            }
        }
    }

    // MARK: Updates

    func receive(_ now: NowPlaying?) {
        guard now != nowPlaying else { return }
        let previous = nowPlaying
        nowPlaying = now
        if now?.isPlaying != previous?.isPlaying { updateAudio() }
        if now?.isPlaying == true {
            pausedAt = nil
        } else if previous?.isPlaying == true {
            pausedAt = .now
        }
        let newTrack = now?.isDifferentTrack(from: previous) == true
        if now?.artwork != previous?.artwork || newTrack {
            artwork = now.flatMap(thumbnail(for:))
            accent = artwork?.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap(Self.accent(of:))
            tinyArtwork = now?.artwork.flatMap { Self.encodedThumbnail(of: $0, side: 36) }
        }
        if newTrack || now?.appBundleID != previous?.appBundleID {
            scripted = nil
            queue = nil
            lyrics = nil
            refreshScripted()
        }
        let settled = Date().timeIntervalSince(startedAt) > 1.5  // the first payloads are the current state
        if announcesTracks, Self.shouldAnnounce(now, after: previous, settled: settled, phase: phase), let now {
            onActivity?(Activity(feature: .media, symbol: "music.note", title: now.title, duration: .seconds(3)))
        }
        updateOngoing()
    }

    /// A new track is worth a live activity, unless it's just the state at startup or Media is on screen.
    static func shouldAnnounce(_ now: NowPlaying?, after previous: NowPlaying?, settled: Bool, phase: FeaturePhase)
        -> Bool
    {
        guard let now, settled, phase == .background else { return false }
        return now.isDifferentTrack(from: previous)
    }

    /// Whether the closed notch shows `now`: while it plays, and for `linger` after it pauses.
    nonisolated static func showsOngoing(_ now: NowPlaying?, pausedAt: Date?, at date: Date, enabled: Bool) -> Bool {
        guard enabled, let now else { return false }
        return now.isPlaying || pausedAt.map { date.timeIntervalSince($0) < linger } ?? false
    }

    /// Keeps the closed notch's tab in step with what's playing. It changes with the track, the cover,
    /// and play or pause, never with the position, so it costs nothing while a song plays.
    private func updateOngoing() {
        lingering?.cancel()
        lingering = nil
        let shows = Self.showsOngoing(
            nowPlaying, pausedAt: pausedAt, at: .now, enabled: showsInClosedNotch && phase != .stopped)
        let activity =
            shows
            ? nowPlaying.map {
                Activity(
                    feature: .media, symbol: $0.isPlaying ? "music.note" : "pause.fill", title: $0.title,
                    duration: .seconds(3), artwork: tinyArtwork)
            } : nil
        if activity != shownOngoing {
            shownOngoing = activity
            onOngoing?(activity)
        }
        if shows, let pausedAt {
            let left = Self.linger - Date.now.timeIntervalSince(pausedAt)
            lingering = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, left)))
                guard !Task.isCancelled else { return }
                self?.updateOngoing()
            }
        }
    }

    private func thumbnail(for now: NowPlaying) -> NSImage? {
        guard let data = now.artwork else { return nil }
        let key = "\(now.title)|\(now.artist ?? "")|\(now.album ?? "")|\(data.count)" as NSString
        if let cached = artworkCache.object(forKey: key) { return cached }
        guard let image = Self.downsample(data, side: 256) else { return nil }
        let thumbnail = NSImage(cgImage: image, size: .zero)
        artworkCache.setObject(thumbnail, forKey: key)
        return thumbnail
    }

    nonisolated private static func downsample(_ data: Data, side: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The cover as a small PNG, for the closed notch.
    nonisolated static func encodedThumbnail(of data: Data, side: Int) -> Data? {
        downsample(data, side: side).flatMap {
            NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:])
        }
    }
}

/// The bundled mediaremote-adapter: its perl script and framework, run by the system perl.
struct MediaAdapter: Sendable {
    static let perl = "/usr/bin/perl"
    let script: URL
    let framework: URL

    static func bundled(in bundle: Bundle) -> MediaAdapter? {
        guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let framework = bundle.privateFrameworksURL?.appending(path: "MediaRemoteAdapter.framework"),
            FileManager.default.fileExists(atPath: framework.path),
            FileManager.default.isExecutableFile(atPath: perl)
        else { return nil }
        return MediaAdapter(script: script, framework: framework)
    }

    /// perl's arguments for one adapter command.
    func arguments(_ command: [String]) -> [String] { [script.path, framework.path] + command }

    /// The adapter's `seek` command takes whole microseconds.
    static func seek(to seconds: TimeInterval) -> [String] {
        ["seek", String(Int((max(0, seconds) * 1_000_000).rounded()))]
    }

    func process(_ command: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(filePath: Self.perl)
        process.arguments = arguments(command)
        return process
    }
}
