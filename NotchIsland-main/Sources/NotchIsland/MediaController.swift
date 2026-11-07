import AppKit
import Combine
import CoreGraphics

/// A snapshot of one stream: a desktop player, or one browser tab with media in it. Every stream
/// the controller can see is its own `NowPlaying`; `sourceKey` identifies it from poll to poll.
struct NowPlaying: Equatable {
    /// An app NotchIsland can read: a scriptable desktop player, a Chromium browser or Safari.
    struct Player: Hashable {
        enum Kind: Hashable { case music, spotify, vlc, chromium, safari, system }

        let bundleID: String
        let kind: Kind
        let name: String      // "Google Chrome": for "Open …" and the card caption
        let label: String     // "Chrome": for chips and hints

        var isBrowser: Bool { kind == .chromium || kind == .safari }
        /// Read from the system Now Playing feed rather than scripted: TV, Podcasts, QuickTime Player…
        var isSystem: Bool { kind == .system }

        /// Any app the system feed names; the display name comes from the running process.
        static func system(bundleID: String, pid: Int32) -> Player {
            var name = NSRunningApplication(processIdentifier: pid)?.localizedName
            if name == nil, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                name = url.deletingPathExtension().lastPathComponent
            }
            let display = name ?? String(bundleID.split(separator: ".").last ?? Substring(bundleID))
            return Player(bundleID: bundleID, kind: .system, name: display, label: display)
        }

        /// Where the browser keeps its "Allow JavaScript from Apple Events" switch.
        var javaScriptSwitch: String { kind == .safari ? "Develop ▸ Developer Settings" : "View ▸ Developer" }

        static let music = Player(bundleID: "com.apple.Music", kind: .music, name: "Music", label: "Music")
        static let spotify = Player(bundleID: "com.spotify.client", kind: .spotify, name: "Spotify", label: "Spotify")
        static let vlc = Player(bundleID: "org.videolan.vlc", kind: .vlc, name: "VLC", label: "VLC")
        static let safari = Player(bundleID: "com.apple.Safari", kind: .safari, name: "Safari", label: "Safari")
        static let chrome = Player(bundleID: "com.google.Chrome", kind: .chromium, name: "Google Chrome", label: "Chrome")
        static let brave = Player(bundleID: "com.brave.Browser", kind: .chromium, name: "Brave Browser", label: "Brave")
        static let edge = Player(bundleID: "com.microsoft.edgemac", kind: .chromium, name: "Microsoft Edge", label: "Edge")

        /// Everything that is polled, in display order. Every Chromium browser shares Chrome's
        /// scripting dictionary, so each channel of Chrome, Brave and Edge plus Arc, Vivaldi, Opera
        /// and Chromium are read the same way. Firefox has no scripting bridge at all.
        static let known: [Player] = [
            music, spotify, vlc, safari, chrome, brave, edge,
            Player(bundleID: "company.thebrowser.Browser", kind: .chromium, name: "Arc", label: "Arc"),
            Player(bundleID: "com.vivaldi.Vivaldi", kind: .chromium, name: "Vivaldi", label: "Vivaldi"),
            Player(bundleID: "com.operasoftware.Opera", kind: .chromium, name: "Opera", label: "Opera"),
            Player(bundleID: "com.operasoftware.OperaGX", kind: .chromium, name: "Opera GX", label: "Opera GX"),
            Player(bundleID: "org.chromium.Chromium", kind: .chromium, name: "Chromium", label: "Chromium"),
            Player(bundleID: "com.google.Chrome.beta", kind: .chromium, name: "Google Chrome Beta", label: "Chrome Beta"),
            Player(bundleID: "com.google.Chrome.dev", kind: .chromium, name: "Google Chrome Dev", label: "Chrome Dev"),
            Player(bundleID: "com.google.Chrome.canary", kind: .chromium, name: "Google Chrome Canary", label: "Chrome Canary"),
            Player(bundleID: "com.brave.Browser.beta", kind: .chromium, name: "Brave Browser Beta", label: "Brave Beta"),
            Player(bundleID: "com.brave.Browser.nightly", kind: .chromium, name: "Brave Browser Nightly", label: "Brave Nightly"),
            Player(bundleID: "com.microsoft.edgemac.Beta", kind: .chromium, name: "Microsoft Edge Beta", label: "Edge Beta"),
            Player(bundleID: "com.microsoft.edgemac.Dev", kind: .chromium, name: "Microsoft Edge Dev", label: "Edge Dev"),
            Player(bundleID: "com.microsoft.edgemac.Canary", kind: .chromium, name: "Microsoft Edge Canary", label: "Edge Canary"),
        ]
    }

    var player: Player
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var elapsed: TimeInterval
    var duration: TimeInterval
    var trackID: String
    var artworkHint: String      // Spotify/browser: artwork URL; VLC: file path
    var artwork: NSImage?
    var sampledAt: Date
    var isMuted = false          // browser: the element is muted, so it ranks under audible streams
    var sourceTabID: String = "" // browser: the tab to send commands to (Safari: "windowID:index")
    var sourceHost: String = ""  // browser: the page's host ("youtube.com"), to tell twin tabs apart
    var sourcePID: Int32 = 0     // system feed: the process the item belongs to
    var isElected = false        // system feed: the app macOS sends transport commands to

    /// Identifies the stream across polls: the app, plus the tab for browsers.
    var sourceKey: String { "\(player.bundleID)|\(sourceTabID)" }
    var icon: NSImage { AppIconCache.icon(for: player.bundleID) }

    /// Elapsed time extrapolated from the last sample, so the progress bar moves between polls.
    var liveElapsed: TimeInterval {
        guard isPlaying else { return elapsed }
        let value = elapsed + Date().timeIntervalSince(sampledAt)
        return duration > 0 ? min(value, duration) : value
    }

    var subtitle: String {
        [artist, album].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    static func == (a: NowPlaying, b: NowPlaying) -> Bool {
        a.player == b.player && a.trackID == b.trackID && a.title == b.title &&
        a.artist == b.artist && a.album == b.album && a.isPlaying == b.isPlaying &&
        a.isMuted == b.isMuted && a.sourceTabID == b.sourceTabID &&
        Int(a.elapsed) == Int(b.elapsed) && Int(a.duration) == Int(b.duration) &&
        a.artwork === b.artwork
    }
}

/// Reads and controls what's playing, and the system output volume.
///
/// Scriptable desktop players (Music, Spotify, VLC) are read directly over AppleScript. Browsers
/// are read by running a little JavaScript in every tab, which the user must allow once (Chromium:
/// View ▸ Developer ▸ Allow JavaScript from Apple Events; Safari: Develop ▸ Developer Settings);
/// until then the island shows a hint. Everything else (TV, Podcasts, QuickTime Player, any app
/// that publishes to Control Center) comes from the system Now Playing feed through
/// `MediaRemoteBridge`, which also stands in for a scripted app that cannot be reached.
///
/// Every stream found is published in `sources`. The island follows the *active* one: whichever
/// stream started playing most recently, audible before muted; when nothing plays it stays on the
/// stream it was showing. Picking a chip in the card pins that stream until a new one starts.
final class MediaController: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    /// Every stream found on the last poll, in player order; the cards list them for switching.
    @Published private(set) var sources: [NowPlaying] = []
    @Published private(set) var problem: String?
    /// System output volume, 0...1. Global: it moves whatever is making sound, browser included.
    @Published var systemVolume: Double = 0.5

    private let queue = DispatchQueue(label: "NotchIsland.media", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var tick = 0
    private var scripts: [String: NSAppleScript] = [:]
    private var artworkCache: [String: NSImage?] = [:]
    private var pendingArtwork: [String: Data] = [:]
    private var denied: Set<NowPlaying.Player> = []        // Automation permission declined
    private var browserJS: [NowPlaying.Player: Bool] = [:] // nil unknown, false off, true on
    private var reportedErrors: Set<Int> = []
    private var resetObserver: Any?
    private var pendingVolume: Int?
    private var volumeHeldUntil = Date.distantPast
    private var volumeInitialized = false
    // Which stream the island follows (all touched on `queue` only).
    private var playingSince: [String: Date] = [:]  // sourceKey → when it last went from paused to playing
    private var lastActive: [String: Date] = [:]    // sourceKey → when it was last seen playing
    private var lastSeen: [String: Date] = [:]      // sourceKey → when it was last seen at all
    private var currentKey: String?
    private var pinned: (key: String, at: Date)?    // the user's pick, until a newer stream starts
    private var lastPick: NowPlaying?
    private var lastList: [NowPlaying] = []
    private var lastLog = ""
    private let logging = ProcessInfo.processInfo.environment["NOTCHISLAND_MEDIA_LOG"] != nil
    private let bridge = MediaRemoteBridge.shared
    private var systemPlayers: [String: NowPlaying.Player] = [:]   // bundle id → player, by name lookup once
    /// Fired (main thread) when the system volume changes from outside the island, e.g. the volume keys.
    var onVolumeChanged: ((Double) -> Void)?

    /// How long a stream may be missing from a poll before it is forgotten. One AppleScript hiccup
    /// must not make a long-running stream look freshly started and steal the island.
    private static let graceInterval: TimeInterval = 15
    /// How long the island keeps showing a stream that a poll missed before it moves on. A browser
    /// whose walk failed this second (a tab was closing, a page hung) must not flip the island.
    private static let holdInterval: TimeInterval = 2.5

    func start() {
        queue.async { [self] in
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: 1.0)
            t.setEventHandler { [weak self] in self?.poll() }
            t.resume()
            timer = t
        }
        bridge.start()
        if resetObserver == nil {
            // After `tccutil reset`, a player that was "declined" may be allowed on the next try.
            resetObserver = NotificationCenter.default.addObserver(forName: .notchPermissionsReset, object: nil, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    self.denied.removeAll()
                    self.browserJS.removeAll()
                    self.reportedErrors.removeAll()
                    DispatchQueue.main.async { self.problem = nil }
                }
            }
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            bridge.stop()
            DispatchQueue.main.async {
                self.nowPlaying = nil
                self.sources = []
            }
        }
    }

    deinit { timer?.cancel() }

    // MARK: - Transport (call on the main thread)

    /// Shows `source` in the island and keeps it there until another stream starts playing.
    func select(_ source: NowPlaying) {
        guard source.sourceKey != nowPlaying?.sourceKey else { return }
        nowPlaying = source                                // optimistic; the next poll adds artwork
        queue.async { [self] in
            pinned = (source.sourceKey, Date())
            currentKey = source.sourceKey
            poll()
        }
    }

    func togglePlayPause() {
        guard var np = nowPlaying else { return }
        np.elapsed = np.liveElapsed
        np.sampledAt = Date()
        np.isPlaying.toggle()
        nowPlaying = np                                    // optimistic; the next poll confirms
        if np.player.isSystem {
            sendSystem("toggle", for: np)
        } else if np.player.isBrowser {
            runBrowserCommand(np, js: Self.toggleJS)
        } else {
            send(np.player == .vlc ? "play" : "playpause", to: np.player)
        }
    }

    func next() {
        guard let np = nowPlaying else { return }
        if np.player.isSystem { sendSystem("next", for: np) }
        else if np.player.isBrowser { SystemMediaKey.post(SystemMediaKey.next) }
        else { send(np.player == .vlc ? "next" : "next track", to: np.player) }
    }

    func previous() {
        guard let np = nowPlaying else { return }
        if np.player.isSystem { sendSystem("previous", for: np) }
        else if np.player.isBrowser { SystemMediaKey.post(SystemMediaKey.previous) }
        else { send(np.player == .vlc ? "previous" : "previous track", to: np.player) }
    }

    func seek(to seconds: TimeInterval) {
        guard var np = nowPlaying else { return }
        np.elapsed = seconds
        np.sampledAt = Date()
        nowPlaying = np
        let value = Int(seconds)
        if np.player.isSystem {
            sendSystem("seek:\(value)", for: np)
        } else if np.player.isBrowser {
            runBrowserCommand(np, js: "(function(){var e=[].slice.call(document.querySelectorAll('video,audio'));var m=e.filter(function(x){return !x.paused;})[0]||e.filter(function(x){return x.readyState>2;})[0];if(m){m.currentTime=\(value);}})()")
        } else {
            send(np.player == .vlc ? "set current time to \(value)" : "set player position to \(value)",
                 to: np.player, cache: false)
        }
    }

    /// Brings the player forward; for a browser stream, the tab it plays in.
    func openPlayer() {
        guard let np = nowPlaying else { return }
        if np.player.isBrowser, !np.sourceTabID.isEmpty {
            queue.async { [self] in run(Self.revealTabScript(for: np), cacheKey: nil, player: np.player) }
        }
        guard let url = AppIconCache.url(for: np.player.bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    /// Transport for a system-feed stream. MediaRemote delivers a command from NotchIsland's helper
    /// to the app macOS has elected, whichever app it names, so the feed carries commands for that
    /// app only. The TV app and QuickTime Player take the same commands by AppleScript otherwise
    /// (Automation permission, asked once); any other app cannot be reached then and is left alone.
    private func sendSystem(_ command: String, for np: NowPlaying) {
        if np.isElected {
            bridge.send(command, to: np.player.bundleID, pid: np.sourcePID)
            queue.asyncAfter(deadline: .now() + 0.5) { self.poll() }
        } else if let verb = Self.scriptedVerb(for: command, stream: np) {
            send(verb, to: np.player, cache: !command.hasPrefix("seek:"))
        } else {
            NSLog("NotchIsland media: %@ not sent to %@: it is not the app macOS has elected", command, np.player.label)
        }
    }

    /// The AppleScript for a feed command (play | pause | toggle | next | previous | seek:<s>), for
    /// the apps that have a dictionary for it.
    private static func scriptedVerb(for command: String, stream np: NowPlaying) -> String? {
        let seek = command.hasPrefix("seek:") ? String(command.dropFirst(5)) : nil
        switch np.player.bundleID {
        case "com.apple.TV":
            if let seek = seek { return "set player position to \(seek)" }
            return ["play": "play", "pause": "pause", "toggle": "playpause",
                    "next": "next track", "previous": "previous track"][command]
        case "com.apple.QuickTimePlayerX":
            if let seek = seek { return "set current time of document 1 to \(seek)" }
            return ["play": "play document 1", "pause": "pause document 1",
                    "toggle": np.isPlaying ? "pause document 1" : "play document 1"][command]
        default:
            return nil
        }
    }

    private func send(_ verb: String, to player: NowPlaying.Player, cache: Bool = true) {
        queue.async { [self] in
            run("tell application \"\(player.name)\" to \(verb)",
                cacheKey: cache ? "cmd:\(player.bundleID):\(verb)" : nil, player: player)
            queue.asyncAfter(deadline: .now() + 0.3) { self.poll() }
        }
    }

    private func runBrowserCommand(_ np: NowPlaying, js: String) {
        guard !np.sourceTabID.isEmpty else { return }
        let player = np.player
        queue.async { [self] in
            run(Self.browserCommandScript(for: np, js: js), cacheKey: nil, player: player)
            queue.asyncAfter(deadline: .now() + 0.3) { self.poll() }
        }
    }

    // MARK: - Polling

    private func poll() {
        tick &+= 1
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var found: [NowPlaying] = []
        for player in NowPlaying.Player.known where running.contains(player.bundleID) && !denied.contains(player) {
            if player.isBrowser {
                found += pollBrowser(player)
            } else if let np = query(player) {
                found.append(np)
            }
        }
        // Whatever else the system feed names (TV, Podcasts, QuickTime Player, a browser whose
        // JavaScript switch is off, Music without Automation…), unless that app was read the
        // richer way above.
        for np in systemStreams() where !found.contains(where: { $0.player.bundleID == np.player.bundleID }) {
            found.append(np)
        }

        var (pick, list) = choose(from: found)
        if let chosen = pick, chosen.artwork == nil {
            pick?.artwork = artwork(for: chosen)
            lastPick?.artwork = pick?.artwork
        }
        if logging { log(list, pick) }
        DispatchQueue.main.async {
            if self.sources != list { self.sources = list }
            if self.nowPlaying != pick { self.nowPlaying = pick }
        }
        updateProblem(running: running)
        pollVolume()
    }

    /// The stream the island follows, with the list to show as chips. Rules, in order: hold the
    /// current stream through a missed poll; the user's pick while it exists and nothing newer has
    /// started; the playing stream that started most recently (audible before muted); the stream
    /// shown so far, if it is still there; the stream that played most recently.
    private func choose(from found: [NowPlaying]) -> (NowPlaying?, [NowPlaying]) {
        let now = Date()
        var present = Set<String>()
        for np in found {
            let key = np.sourceKey
            present.insert(key)
            lastSeen[key] = now
            if np.isPlaying {
                if playingSince[key] == nil { playingSince[key] = now }
                lastActive[key] = now
            } else {
                playingSince[key] = nil
            }
        }
        for (key, seen) in lastSeen where now.timeIntervalSince(seen) > Self.graceInterval {
            lastSeen[key] = nil
            lastActive[key] = nil
            playingSince[key] = nil
        }

        if let key = currentKey, !present.contains(key), let held = lastPick,
           let seen = lastSeen[key], now.timeIntervalSince(seen) < Self.holdInterval {
            return (held, lastList)
        }

        func since(_ np: NowPlaying) -> Date { playingSince[np.sourceKey] ?? now }
        var pick: NowPlaying?
        if let pin = pinned {
            let newer = found.contains { $0.isPlaying && $0.sourceKey != pin.key && since($0) > pin.at }
            if !present.contains(pin.key) || newer {
                pinned = nil
            } else {
                pick = found.first { $0.sourceKey == pin.key }
            }
        }
        if pick == nil {
            let playing = found.filter(\.isPlaying)
            if !playing.isEmpty {
                pick = playing.max { a, b in (a.isMuted ? 0 : 1, since(a)) < (b.isMuted ? 0 : 1, since(b)) }
            } else if let key = currentKey, let same = found.first(where: { $0.sourceKey == key }) {
                pick = same
            } else {
                pick = found.max { a, b in
                    (lastActive[a.sourceKey] ?? .distantPast) < (lastActive[b.sourceKey] ?? .distantPast)
                } ?? found.first
            }
        }
        currentKey = pick?.sourceKey
        lastPick = pick
        lastList = found
        return (pick, found)
    }

    private func log(_ found: [NowPlaying], _ pick: NowPlaying?) {
        let list = found.map {
            "\($0.player.label)#\($0.sourceTabID.isEmpty ? "app" : $0.sourceTabID) \($0.isPlaying ? "playing" : "paused")\($0.isMuted ? " muted" : "") \"\($0.title)\""
        }.joined(separator: " | ")
        let text = "sources [\(list)] -> \(pick.map { "\($0.player.label) \"\($0.title)\"" } ?? "none")\(pinned == nil ? "" : " (pinned)")\(pick != nil && !found.contains { $0.sourceKey == pick?.sourceKey } ? " (held)" : "")"
        if text != lastLog {
            lastLog = text
            NSLog("NotchIsland media: %@", text)
        }
    }

    // MARK: - System feed

    /// Every item on the system Now Playing feed as a stream of its own, one per app, the app
    /// macOS elected first. Empty when nothing is published.
    private func systemStreams() -> [NowPlaying] {
        var streams: [NowPlaying] = []
        for s in bridge.snapshots {
            let bundleID = s.bundleID
            guard bundleID != Bundle.main.bundleIdentifier,
                  !streams.contains(where: { $0.player.bundleID == bundleID }) else { continue }
            let player: NowPlaying.Player
            if let known = systemPlayers[bundleID] {
                player = known
            } else {
                player = NowPlaying.Player.known.first { $0.bundleID == bundleID }
                    .map { NowPlaying.Player(bundleID: $0.bundleID, kind: .system, name: $0.name, label: $0.label) }
                    ?? .system(bundleID: bundleID, pid: s.pid)
                systemPlayers[bundleID] = player
            }
            var np = NowPlaying(player: player, title: s.title.isEmpty ? player.name : s.title, artist: s.artist,
                                album: s.album, isPlaying: s.isPlaying, elapsed: s.elapsed, duration: s.duration,
                                trackID: s.itemID.isEmpty ? s.title : s.itemID,
                                artworkHint: s.artworkKey.isEmpty ? "" : "mr:" + s.artworkKey,
                                artwork: nil, sampledAt: s.receivedAt)
            np.sourcePID = s.pid
            np.isElected = s.isElected
            streams.append(np)
        }
        return streams
    }

    // MARK: - App players

    private func query(_ player: NowPlaying.Player) -> NowPlaying? {
        guard let output = run(Self.statusScript(for: player),
                               cacheKey: "status:\(player.bundleID)", player: player)?.stringValue
        else { return nil }
        let lines = output.components(separatedBy: "\n")
        guard lines.count >= 8, lines[0] != "stopped" else { return nil }
        var duration = Self.number(lines[5])
        if player == .spotify { duration /= 1000 }
        return NowPlaying(player: player, title: lines[1], artist: lines[2], album: lines[3],
                          isPlaying: lines[0] == "playing",
                          elapsed: Self.number(lines[4]), duration: duration,
                          trackID: lines[6].isEmpty ? lines[1] : lines[6],
                          artworkHint: lines[7], artwork: nil, sampledAt: Date())
    }

    // MARK: - Browser players

    /// Runs the status JavaScript in every tab of the browser and returns one stream per tab that
    /// has media. The first line of the script's answer counts the tabs that ran JavaScript; the
    /// rest are "<tab id> <json>" lines, or "! <code> <message>" for tabs that refused.
    private func pollBrowser(_ player: NowPlaying.Player) -> [NowPlaying] {
        // While the browser's JavaScript switch is off, look again every few seconds so the hint
        // clears as soon as the user turns it on.
        guard browserJS[player] != false || tick % 4 == 0 else { return [] }
        guard let output = run(Self.browserStatusScript(for: player),
                               cacheKey: "status:\(player.bundleID)", player: player)?.stringValue
        else { return [] }

        var lines = output.components(separatedBy: "\n")
        let ran = Int(lines.removeFirst().trimmingCharacters(in: .whitespaces)) ?? 0
        var streams: [NowPlaying] = []
        var switchedOff = false
        for line in lines where !line.isEmpty {
            if line.hasPrefix("! ") {
                if Self.isJavaScriptOff(line) { switchedOff = true }
                continue
            }
            guard let space = line.firstIndex(of: " ") else { continue }
            let tab = String(line[..<space])
            let json = String(line[line.index(after: space)...])
            if let np = Self.parseBrowserStream(json, player: player, tab: tab) { streams.append(np) }
        }
        if ran > 0 { browserJS[player] = true } else if switchedOff { browserJS[player] = false }
        return streams
    }

    private static func parseBrowserStream(_ json: String, player: NowPlaying.Player, tab: String) -> NowPlaying? {
        guard let data = json.data(using: .utf8),
              let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let title = (d["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let artist = (d["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let album = (d["album"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let playing = (d["playing"] as? Bool) ?? false
        let muted = (d["muted"] as? Bool) ?? false
        let pos = (d["pos"] as? NSNumber)?.doubleValue ?? 0
        let dur = (d["dur"] as? NSNumber)?.doubleValue ?? 0
        let art = (d["art"] as? String) ?? ""
        let host = (d["host"] as? String) ?? ""
        return NowPlaying(player: player, title: title, artist: artist, album: album,
                          isPlaying: playing, elapsed: pos, duration: dur,
                          trackID: "\(tab)|\(title)", artworkHint: art, artwork: nil,
                          sampledAt: Date(), isMuted: muted, sourceTabID: tab, sourceHost: host)
    }

    /// Chromium: "Executing JavaScript through AppleScript is turned off. … View > Developer > Allow
    /// JavaScript from Apple Events". Safari: "You must enable 'Allow JavaScript from Apple Events'
    /// in the Developer section of Safari Settings to use 'do JavaScript'."
    private static func isJavaScriptOff(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("javascript") && (lower.contains("turned off") || lower.contains("apple events"))
    }

    // MARK: - Artwork

    private func artwork(for np: NowPlaying) -> NSImage? {
        if np.player.isSystem {
            // The feed carries the image itself (sent once per key); the app's icon stands in until then.
            let key = np.artworkHint.hasPrefix("mr:") ? String(np.artworkHint.dropFirst(3)) : ""
            return (key.isEmpty ? nil : bridge.artwork(forKey: key)) ?? np.icon
        }
        // A track whose duration is still unknown has not finished loading (streaming), and Music
        // may still report the previous cover for it; keying on that re-fetches once it loads.
        let key = "\(np.player.bundleID)|\(np.trackID)|\(np.duration > 0)"
        if let cached = artworkCache[key] { return cached }
        var image: NSImage?
        var confirmed = true
        if np.player == .music {
            // Music fills in a new track's artwork asynchronously; only cache once two fetches agree.
            let data = run("tell application \"Music\" to get data of artwork 1 of current track",
                           cacheKey: "art:music", player: .music)?.data ?? Data()
            image = data.isEmpty ? nil : NSImage(data: data)
            confirmed = pendingArtwork[key] == data
            if pendingArtwork.count > 8 { pendingArtwork.removeAll() }
            pendingArtwork[key] = data
        } else if np.artworkHint.hasPrefix("http"), let url = URL(string: np.artworkHint),
                  let data = download(url) {
            image = NSImage(data: data)
        } else if !np.artworkHint.isEmpty, FileManager.default.fileExists(atPath: np.artworkHint) {
            image = NSWorkspace.shared.icon(forFile: np.artworkHint)
        }
        guard confirmed else { return image }
        pendingArtwork[key] = nil
        if artworkCache.count > 40 { artworkCache.removeAll() }
        artworkCache[key] = .some(image)
        return image
    }

    private func download(_ url: URL) -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let done = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            result = data
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 6)
        return result
    }

    // MARK: - System volume (global)

    private func pollVolume() {
        guard Date() >= volumeHeldUntil, pendingVolume == nil else { return }
        guard let desc = run("output volume of (get volume settings)",
                             cacheKey: "volume:get", player: .music) else { return }
        let muted = run("output muted of (get volume settings)", cacheKey: "volume:muted", player: .music)?.booleanValue ?? false
        let value = muted ? 0.0 : Double(desc.int32Value) / 100.0
        DispatchQueue.main.async {
            let changed = abs(self.systemVolume - value) > 0.001
            if changed { self.systemVolume = value }
            if changed, self.volumeInitialized { self.onVolumeChanged?(value) }
            self.volumeInitialized = true
        }
    }

    /// Call on the main thread while dragging the volume slider.
    func setSystemVolume(_ fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        systemVolume = clamped                               // optimistic
        volumeHeldUntil = Date().addingTimeInterval(0.6)
        let value = Int((clamped * 100).rounded())
        queue.async { [self] in
            let wasIdle = pendingVolume == nil
            pendingVolume = value
            guard wasIdle else { return }                    // a flush is already scheduled
            queue.asyncAfter(deadline: .now() + 0.06) { self.flushVolume() }
        }
    }

    private func flushVolume() {
        guard let value = pendingVolume else { return }
        pendingVolume = nil
        run("set volume output volume \(value)", cacheKey: nil, player: .music)
    }

    // MARK: - AppleScript plumbing

    @discardableResult
    private func run(_ source: String, cacheKey: String?, player: NowPlaying.Player) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let cacheKey, let cached = scripts[cacheKey] {
            script = cached
        } else {
            guard let fresh = NSAppleScript(source: source) else { return nil }
            script = fresh
            if let cacheKey { scripts[cacheKey] = script }
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            handle(code: errorInfo[NSAppleScript.errorNumber] as? Int ?? 0,
                   message: errorInfo[NSAppleScript.errorMessage] as? String ?? "",
                   player: player)
            return nil
        }
        return result
    }

    private func handle(code: Int, message: String, player: NowPlaying.Player) {
        if player.isBrowser, Self.isJavaScriptOff(message) {
            browserJS[player] = false   // the user hasn't allowed JS from Apple Events yet
            return
        }
        switch code {
        case -1743:   // errAEEventNotPermitted: the user declined the Automation prompt
            denied.insert(player)
            let text = "Allow NotchIsland to control \(player.label) in System Settings → Privacy & Security → Automation."
            DispatchQueue.main.async { self.problem = text }
        case -600, -609, -1712, -1719, -1728, -10000:
            // Not running / connection invalid / timed out / no window / no current item / internal:
            // transient, nothing to tell the user.
            break
        default:
            if reportedErrors.insert(code).inserted {
                NSLog("NotchIsland: AppleScript error %d talking to %@: %@", code, player.name, message)
            }
        }
    }

    /// Builds the hint shown in the island: Automation first, then the browser JS switch.
    private func updateProblem(running: Set<String>) {
        var text: String?
        if !denied.isEmpty {
            let names = denied.map(\.label).sorted().joined(separator: ", ")
            text = "Allow NotchIsland to control \(names) in System Settings → Privacy & Security → Automation."
        } else {
            let off = NowPlaying.Player.known.filter {
                $0.isBrowser && running.contains($0.bundleID) && browserJS[$0] == false
            }
            if !off.isEmpty {
                let names = off.map(\.label).joined(separator: " or ")
                let paths = off.count == 1
                    ? off[0].javaScriptSwitch
                    : off.map { "\($0.label): \($0.javaScriptSwitch)" }.joined(separator: " · ")
                text = "Playing in \(names)? Turn on ‘Allow JavaScript from Apple Events’ (\(paths))."
            }
        }
        DispatchQueue.main.async {
            if self.problem != text { self.problem = text }
        }
    }

    private static func number(_ text: String) -> Double {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    // MARK: - Scripts

    /// JS (no double quotes, so it nests inside the AppleScript string) that toggles the page's media.
    static let toggleJS = "(function(){var e=[].slice.call(document.querySelectorAll('video,audio'));var m=e.filter(function(x){return !x.paused;})[0]||e.filter(function(x){return x.readyState>2;})[0];if(m){if(m.paused){m.play();}else{m.pause();}}})()"

    /// JS that reports the page's main media element as compact JSON, or '' when the page has no
    /// stream worth showing. Elements that never played are skipped (YouTube's hover previews, blocked
    /// autoplay), as are muted looping decorations without controls (landing-page hero videos).
    /// Among the rest: audible playing, then muted playing, then paused with the most progress.
    static let statusJS = "(function(){var e=[].slice.call(document.querySelectorAll('video,audio'));var best=null,bs=-1;for(var i=0;i<e.length;i++){var x=e[i];var ct=x.currentTime||0;var playing=!x.paused&&!x.ended&&ct>0;var muted=!!(x.muted||x.volume===0);if(!playing&&!(ct>0))continue;if(playing&&muted&&x.loop&&!x.controls)continue;var sc=(playing?(muted?2:3):1)*1e9+Math.min(ct,1e8);if(sc>bs){bs=sc;best=x;}}if(!best)return '';var m=best;var s=(navigator.mediaSession&&navigator.mediaSession.metadata)||{};var a='';try{if(s.artwork&&s.artwork.length){a=s.artwork[s.artwork.length-1].src;}}catch(err){}var d=isFinite(m.duration)?Math.floor(m.duration):0;var h=(location.hostname||'');if(h.indexOf('www.')===0){h=h.slice(4);}return JSON.stringify({playing:!m.paused&&!m.ended,muted:!!(m.muted||m.volume===0),pos:Math.floor(m.currentTime||0),dur:d,title:(s.title||document.title||''),artist:(s.artist||''),album:(s.album||''),art:a,host:h});})()"

    /// Walks every tab of the browser and answers: a count of tabs that ran JavaScript, then one
    /// "<tab id> <json>" line per tab with media (or "! <code> <message>" for a tab that refused).
    /// Each tab gets at most 3 s, so one stuck page cannot freeze the island for a minute.
    static func browserStatusScript(for player: NowPlaying.Player) -> String {
        if player.kind == .safari {
            return """
            tell application id "com.apple.Safari"
                set okCount to 0
                set out to ""
                with timeout of 3 seconds
                    repeat with w in windows
                        try
                            set wid to id of w
                            set i to 0
                            repeat with t in tabs of w
                                set i to i + 1
                                try
                                    set r to do JavaScript "\(statusJS)" in t
                                    set okCount to okCount + 1
                                    if r is not missing value and r is not "" then
                                        set out to out & (wid as text) & ":" & i & " " & r & linefeed
                                    end if
                                on error errMsg number errNum
                                    set out to out & "! " & errNum & " " & errMsg & linefeed
                                end try
                            end repeat
                        end try
                    end repeat
                end timeout
                return (okCount as text) & linefeed & out
            end tell
            """
        }
        return """
        tell application id "\(player.bundleID)"
            set okCount to 0
            set out to ""
            with timeout of 3 seconds
                repeat with w in windows
                    try
                        repeat with t in tabs of w
                            try
                                set r to execute t javascript "\(statusJS)"
                                set okCount to okCount + 1
                                if r is not missing value and r is not "" then
                                    set out to out & ((id of t) as text) & " " & r & linefeed
                                end if
                            on error errMsg number errNum
                                set out to out & "! " & errNum & " " & errMsg & linefeed
                            end try
                        end repeat
                    end try
                end repeat
            end timeout
            return (okCount as text) & linefeed & out
        end tell
        """
    }

    /// Runs `js` in the stream's own tab.
    static func browserCommandScript(for np: NowPlaying, js: String) -> String {
        if np.player.kind == .safari {
            let (wid, index) = safariTab(np.sourceTabID)
            return "tell application id \"com.apple.Safari\" to do JavaScript \"\(js)\" in tab \(index) of window id \(wid)"
        }
        return """
        tell application id "\(np.player.bundleID)"
            with timeout of 3 seconds
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if ((id of t) as text) is "\(np.sourceTabID)" then
                                execute t javascript "\(js)"
                                return
                            end if
                        end try
                    end repeat
                end repeat
            end timeout
        end tell
        """
    }

    /// Makes the stream's tab the active one in its window and brings that window forward.
    static func revealTabScript(for np: NowPlaying) -> String {
        if np.player.kind == .safari {
            let (wid, index) = safariTab(np.sourceTabID)
            return """
            tell application id "com.apple.Safari"
                set w to window id \(wid)
                set current tab of w to tab \(index) of w
                set index of w to 1
            end tell
            """
        }
        return """
        tell application id "\(np.player.bundleID)"
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    try
                        if ((id of t) as text) is "\(np.sourceTabID)" then
                            set active tab index of w to i
                            set index of w to 1
                            return
                        end if
                    end try
                end repeat
            end repeat
        end tell
        """
    }

    /// Safari tabs have no id, so a stream is keyed "windowID:tabIndex".
    private static func safariTab(_ key: String) -> (Int, Int) {
        let parts = key.split(separator: ":").map { Int($0) ?? 1 }
        return (parts.first ?? 1, parts.count > 1 ? parts[1] : 1)
    }

    /// Each app script answers eight linefeed-separated fields:
    /// state, title, artist, album, position (s), duration (s; Spotify: ms), track id, artwork hint.
    private static func statusScript(for player: NowPlaying.Player) -> String {
        switch player.kind {
        case .music:
            return """
            tell application "Music"
                set playerState to (player state as text)
                if playerState is "stopped" then return "stopped"
                set t to current track
                set nm to ""
                set ar to ""
                set al to ""
                set pos to "0"
                set dur to "0"
                set tid to ""
                try
                    set nm to name of t
                end try
                try
                    set ar to artist of t
                end try
                try
                    set al to album of t
                end try
                try
                    set pos to (player position) as text
                end try
                try
                    set dur to (duration of t) as text
                end try
                try
                    set tid to persistent ID of t
                end try
                return playerState & linefeed & nm & linefeed & ar & linefeed & al & linefeed & pos & linefeed & dur & linefeed & tid & linefeed & ""
            end tell
            """
        case .spotify:
            return """
            tell application "Spotify"
                set playerState to (player state as text)
                if playerState is "stopped" then return "stopped"
                set t to current track
                set nm to ""
                set ar to ""
                set al to ""
                set pos to "0"
                set dur to "0"
                set tid to ""
                set art to ""
                try
                    set nm to name of t
                end try
                try
                    set ar to artist of t
                end try
                try
                    set al to album of t
                end try
                try
                    set pos to (player position) as text
                end try
                try
                    set dur to (duration of t) as text
                end try
                try
                    set tid to id of t
                end try
                try
                    set art to artwork url of t
                end try
                return playerState & linefeed & nm & linefeed & ar & linefeed & al & linefeed & pos & linefeed & dur & linefeed & tid & linefeed & art
            end tell
            """
        default:   // VLC
            return """
            tell application "VLC"
                set nm to ""
                try
                    set nm to (name of current item) as text
                on error
                    set nm to ""
                end try
                if nm is "" then return "stopped"
                set playerState to "paused"
                try
                    if playing then set playerState to "playing"
                end try
                set pos to "0"
                set dur to "0"
                set pth to ""
                try
                    set pos to (current time) as text
                end try
                try
                    set dur to (duration of current item) as text
                end try
                try
                    set pth to (path of current item) as text
                end try
                return playerState & linefeed & nm & linefeed & "" & linefeed & "" & linefeed & pos & linefeed & dur & linefeed & pth & linefeed & pth
            end tell
            """
        }
    }
}

/// Posts the hardware media keys (next / previous / play) as system-defined events. Used for
/// browser next/previous, which page JavaScript can't do reliably; most media sites honour them.
/// Needs Accessibility permission, which the app already requests for the ⌥Space hotkey.
enum SystemMediaKey {
    static let playPause: Int32 = 16
    static let next: Int32 = 17
    static let previous: Int32 = 18

    static func post(_ key: Int32) {
        func event(_ down: Bool) -> CGEvent? {
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            let ns = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                subtype: 8, data1: data1, data2: -1)
            return ns?.cgEvent
        }
        event(true)?.post(tap: .cghidEventTap)
        event(false)?.post(tap: .cghidEventTap)
    }
}
