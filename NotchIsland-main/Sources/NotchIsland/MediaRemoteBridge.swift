import AppKit
import Foundation

/// The system-wide Now Playing feed, the one Control Center shows: TV, Music, Podcasts, QuickTime
/// Player, browsers, any app that publishes what it plays. Every such app is reported, each with
/// its own item and state, not only the one macOS has elected as "now playing".
///
/// Since macOS 15.4 MediaRemote answers only Apple's own processes, so the feed is read through
/// `/usr/bin/perl`, which loads the adapter dylib (`Sources/MediaRemoteAdapter`) with its DynaLoader
/// and runs it: one JSON line per change plus a heartbeat every two seconds. The process is kept
/// alive here, restarted if it dies, and replaced if it goes quiet; transport commands run the
/// same loader for one call, addressed to the app they are for.
final class MediaRemoteBridge {
    static let shared = MediaRemoteBridge()

    struct Snapshot {
        var bundleID: String
        var pid: Int32
        var name: String                 // what the feed calls the app ("TV", "Brave Browser")
        var isPlaying: Bool
        var isElected: Bool              // the app macOS itself treats as "now playing"
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval
        var elapsed: TimeInterval        // as of `receivedAt`
        var itemID: String
        var artworkKey: String
        var isVideo: Bool
        var receivedAt: Date
    }

    /// `libMediaRemoteAdapter.dylib`: in the bundle's Frameworks folder, or next to the executable
    /// for a `swift build` / `swift run` tree.
    static let adapterURL: URL? = {
        let name = "libMediaRemoteAdapter.dylib"
        var candidates: [URL] = []
        if let frameworks = Bundle.main.privateFrameworksURL { candidates.append(frameworks.appendingPathComponent(name)) }
        if let exe = Bundle.main.executableURL { candidates.append(exe.deletingLastPathComponent().appendingPathComponent(name)) }
        return candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }()

    var isAvailable: Bool { Self.adapterURL != nil }

    private let lock = NSLock()
    private var latest: [Snapshot] = []
    private var artworks: [String: NSImage] = [:]
    private var lastLineAt = Date.distantPast
    private var restartDelay: TimeInterval = 1
    private var process: Process?
    private var buffer = Data()
    private var running = false
    private var exitsLogged = 0
    private var watchdog: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "NotchIsland.mediaremote", qos: .utility)
    private let logging = ProcessInfo.processInfo.environment["NOTCHISLAND_MEDIA_LOG"] != nil
    private static let staleAfter: TimeInterval = 10
    /// Three missed heartbeats: the feed is wedged or starved; a fresh process is the cure.
    private static let silenceLimit: TimeInterval = 7

    /// Loads the dylib and calls the named XSUB-shaped function: `perl -e <loader> <dylib> <function>`.
    private static let loader = """
    use DynaLoader; my ($lib, $fn) = @ARGV; \
    my $h = DynaLoader::dl_load_file($lib, 0x01) or die DynaLoader::dl_error(); \
    my $s = DynaLoader::dl_find_symbol($h, $fn) or die DynaLoader::dl_error(); \
    DynaLoader::dl_install_xsub("main::go", $s); go();
    """

    // MARK: Lifecycle

    func start() {
        guard Self.adapterURL != nil else {
            NSLog("NotchIsland media: libMediaRemoteAdapter.dylib not found; the system Now Playing feed is off")
            return
        }
        queue.async { [self] in
            guard !running else { return }
            running = true
            spawn()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 2, repeating: 2)
            timer.setEventHandler { [weak self] in self?.checkSilence() }
            timer.resume()
            watchdog = timer
        }
    }

    func stop() {
        queue.async { [self] in
            running = false
            watchdog?.cancel()
            watchdog = nil
            process?.terminate()
            process = nil
            lock.lock(); latest = []; lock.unlock()
        }
    }

    /// Every app with an item, the elected one first; empty when nothing is published or the
    /// feed has gone quiet.
    var snapshots: [Snapshot] {
        lock.lock(); defer { lock.unlock() }
        guard let first = latest.first, Date().timeIntervalSince(first.receivedAt) < Self.staleAfter else { return [] }
        return latest
    }

    func artwork(forKey key: String) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        return artworks[key]
    }

    /// play | pause | toggle | next | previous | seek:<seconds>, to the app `bundleID` names; `pid`
    /// tells twin copies apart. The adapter refuses to let it land on a different app.
    func send(_ command: String, to bundleID: String, pid: Int32 = 0) {
        guard let adapter = Self.adapterURL else { return }
        queue.async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            p.arguments = ["-e", Self.loader, adapter.path, "notchisland_mra_command"]
            var env = ProcessInfo.processInfo.environment
            env["NOTCHISLAND_MRA_COMMAND"] = command
            env["NOTCHISLAND_MRA_BUNDLE"] = bundleID
            if pid > 0 { env["NOTCHISLAND_MRA_PID"] = String(pid) }
            p.environment = env
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { NSLog("NotchIsland media: could not send %@: %@", command, error.localizedDescription); return }
            p.waitUntilExit()
            if p.terminationStatus != 0 { NSLog("NotchIsland media: %@ to %@ failed (%d)", command, bundleID, p.terminationStatus) }
        }
    }

    // MARK: Stream

    private func spawn() {
        guard running, let adapter = Self.adapterURL else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.loader, adapter.path, "notchisland_mra_stream"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = logging ? FileHandle.standardError : FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        p.terminationHandler = { [weak self] proc in
            out.fileHandleForReading.readabilityHandler = nil
            self?.queue.async { self?.exited(proc) }
        }
        do {
            try p.run()
            process = p
            buffer.removeAll()
            lock.lock(); lastLineAt = Date(); lock.unlock()
        } catch {
            NSLog("NotchIsland media: could not start the Now Playing feed: %@", error.localizedDescription)
            retryLater()
        }
    }

    /// The feed writes at least every two seconds. When it stops, end it; the next one takes over
    /// well inside the window a stream is held for, so the island does not blink.
    private func checkSilence() {
        guard running, let p = process, p.isRunning else { return }
        lock.lock(); let silent = Date().timeIntervalSince(lastLineAt); lock.unlock()
        guard silent > Self.silenceLimit else { return }
        NSLog("NotchIsland media: the Now Playing feed has been silent for %.0f s, replacing it", silent)
        kill(p.processIdentifier, SIGKILL)   // its termination handler starts the next one
    }

    private func exited(_ proc: Process) {
        guard proc === process else { return }
        process = nil
        guard running else { return }
        if exitsLogged < 3 {
            exitsLogged += 1
            NSLog("NotchIsland media: the Now Playing feed ended (status %d), restarting", proc.terminationStatus)
        }
        retryLater()
    }

    private func retryLater() {
        lock.lock()
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 30)   // reset by the next line the feed writes
        lock.unlock()
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.spawn() }
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            parse(Data(line))
        }
    }

    /// `{"ts", "elected", "clients": [{bundle, pid, name, playing, title, artist, album, duration,
    /// elapsed, rate, timestamp, mediaType, id, artworkKey, artwork, artworkMIME}, …]}`
    private func parse(_ line: Data) {
        guard let d = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let clients = d["clients"] as? [[String: Any]] else { return }
        let now = Date()
        let elected = d["elected"] as? String
        var list: [Snapshot] = []
        for c in clients {
            guard let bundleID = c["bundle"] as? String else { continue }
            let title = (c["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = (c["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !(title.isEmpty && artist.isEmpty) else { continue }   // registered, nothing to show
            let playing = (c["playing"] as? Bool) ?? false
            var elapsed = (c["elapsed"] as? NSNumber)?.doubleValue ?? 0
            let rate = (c["rate"] as? NSNumber)?.doubleValue ?? (playing ? 1 : 0)
            if playing, let stamp = (c["timestamp"] as? NSNumber)?.doubleValue {
                // MediaRemote reports the position as of its timestamp; bring it up to now.
                elapsed += max(0, now.timeIntervalSince1970 - stamp) * max(rate, 0)
            }
            let artworkKey = c["artworkKey"] as? String ?? ""
            if !artworkKey.isEmpty, let b64 = c["artwork"] as? String,
               let data = Data(base64Encoded: b64), let image = NSImage(data: data) {
                lock.lock()
                if artworks.count > 20 { artworks.removeAll() }
                artworks[artworkKey] = image
                lock.unlock()
            }
            let mediaType = (c["mediaType"] as? String ?? "").lowercased()
            list.append(Snapshot(
                bundleID: bundleID,
                pid: (c["pid"] as? NSNumber)?.int32Value ?? 0,
                name: (c["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                isPlaying: playing,
                isElected: bundleID == elected,
                title: title, artist: artist,
                album: (c["album"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                duration: (c["duration"] as? NSNumber)?.doubleValue ?? 0,
                elapsed: elapsed,
                itemID: (c["id"] as? String) ?? "",
                artworkKey: artworkKey,
                isVideo: mediaType.contains("video"),
                receivedAt: now))
        }
        lock.lock()
        latest = list
        lastLineAt = now
        restartDelay = 1
        lock.unlock()
    }
}
