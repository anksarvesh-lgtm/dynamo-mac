import AppKit
import IslandCore

/// Browser media (YouTube, SoundCloud, any page with <video>/<audio>) for Safari and Chromium browsers.
///
/// Uses each browser's public scripting interface to read `navigator.mediaSession` metadata and the
/// playing media element. This requires the user to enable "Allow JavaScript from Apple Events" in the
/// browser, so it is OFF by default. When unavailable, it reports nothing rather than guessing.
@MainActor
final class BrowserMediaProvider: MediaProvider {
    enum Engine { case safari, chromium }
    let bundleID: String
    let displayName: String
    let engine: Engine
    private let appName: String
    var onUpdate: ((MediaActivity?) -> Void)?
    private(set) var lastError: String?

    private var lifecycle: AppLifecycleObserver?
    private var pollTask: Task<Void, Never>?
    private var last: MediaActivity?
    private var location: (window: Int, tab: Int)?

    init(bundleID: String, appName: String, engine: Engine) {
        self.bundleID = bundleID
        self.appName = appName
        self.displayName = appName
        self.engine = engine
    }

    static func all() -> [BrowserMediaProvider] {
        [
            BrowserMediaProvider(bundleID: "com.apple.Safari", appName: "Safari", engine: .safari),
            BrowserMediaProvider(bundleID: "com.google.Chrome", appName: "Google Chrome", engine: .chromium),
            BrowserMediaProvider(bundleID: "com.brave.Browser", appName: "Brave Browser", engine: .chromium),
            BrowserMediaProvider(bundleID: "com.microsoft.edgemac", appName: "Microsoft Edge", engine: .chromium),
        ]
    }

    func start() {
        lifecycle = AppLifecycleObserver(bundleID: bundleID, onLaunch: { [weak self] in self?.startPolling() },
                                         onTerminate: { [weak self] in self?.stopPolling() })
        if isRunning { startPolling() }
    }

    func stop() {
        lifecycle = nil
        stopPolling()
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        if last != nil { last = nil; onUpdate?(nil) }
    }

    static let probeJS = """
    (function(){var els=[].slice.call(document.querySelectorAll('video,audio'));var m=els.find(function(e){return !e.paused&&!e.ended&&e.readyState>2})||els.find(function(e){return e.currentTime>0&&!e.ended});if(!m)return '';var md=navigator.mediaSession&&navigator.mediaSession.metadata;var art='';if(md&&md.artwork&&md.artwork.length){art=md.artwork[md.artwork.length-1].src}return JSON.stringify({t:(md&&md.title)||document.title,a:(md&&md.artist)||location.hostname,al:(md&&md.album)||'',art:art,p:!m.paused,c:m.currentTime,d:isFinite(m.duration)?m.duration:0})})()
    """

    private func scanScript() -> String {
        let js = Self.probeJS.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let exec = engine == .safari ? "do JavaScript \"\(js)\" in t" : "execute t javascript \"\(js)\""
        return """
        if application "\(appName)" is running then
          tell application "\(appName)"
            set wi to 0
            repeat with w in windows
              set wi to wi + 1
              set ti to 0
              repeat with t in tabs of w
                set ti to ti + 1
                if ti > 30 then exit repeat
                set r to ""
                try
                  set r to \(exec)
                end try
                if r is not missing value and r is not "" then return (wi as text) & (character id 30) & (ti as text) & (character id 30) & r
              end repeat
            end repeat
          end tell
        end if
        return ""
        """
    }

    private func poll() async {
        do {
            let out = try await ScriptRunner.run(scanScript(), timeout: 3)
            lastError = nil
            let f = out.components(separatedBy: "\u{1E}")
            guard f.count == 3, let w = Int(f[0]), let t = Int(f[1]), let data = f[2].data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if last != nil { last = nil; location = nil; onUpdate?(nil) }
                return
            }
            location = (w, t)
            let artURL = (json["art"] as? String).flatMap(URL.init(string:))
            var m = MediaActivity(sourceBundleID: bundleID, sourceName: displayName, title: json["t"] as? String ?? "",
                                  artist: json["a"] as? String ?? "", album: json["al"] as? String ?? "",
                                  artworkID: artURL?.absoluteString, playbackState: (json["p"] as? Bool) == true ? .playing : .paused,
                                  elapsed: json["c"] as? Double, positionTimestamp: Date(),
                                  duration: (json["d"] as? Double).flatMap { $0 > 0 ? $0 : nil }, controls: [.playPause, .seek])
            if let last, last.artworkID == m.artworkID { m.artwork = last.artwork }
            if let last, last.trackKey == m.trackKey, last.playbackState == m.playbackState,
               abs((last.position(at: Date()) ?? 0) - (m.elapsed ?? 0)) < 2 { return }
            last = m
            onUpdate?(m)
            if m.artwork == nil, let artURL, artURL.scheme == "https" { await loadArtwork(artURL) }
        } catch {
            lastError = String(describing: error)
        }
    }

    private func loadArtwork(_ url: URL) async {
        guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 5)),
              (response as? HTTPURLResponse)?.statusCode == 200, var m = last, m.artworkID == url.absoluteString else { return }
        m.artwork = data
        last = m
        onUpdate?(m)
    }

    func perform(_ command: MediaCommand) async throws {
        guard let loc = location else { return }
        let js: String
        switch command {
        case .togglePlayPause: js = "var m=[].slice.call(document.querySelectorAll('video,audio')).find(function(e){return e.currentTime>0||!e.paused});if(m){m.paused?m.play():m.pause()}"
        case .play: js = "var m=document.querySelector('video,audio');if(m)m.play()"
        case .pause: js = "document.querySelectorAll('video,audio').forEach(function(e){e.pause()})"
        case .seek(let t): js = "var m=[].slice.call(document.querySelectorAll('video,audio')).find(function(e){return e.currentTime>0});if(m)m.currentTime=\(max(0, t))"
        case .next, .previous: return // not exposed generically; button is disabled in the UI
        }
        let tab = "tab \(loc.tab) of window \(loc.window)"
        let exec = engine == .safari ? "do JavaScript \"\(js)\" in \(tab)" : "execute \(tab) javascript \"\(js)\""
        _ = try await ScriptRunner.run("if application \"\(appName)\" is running then tell application \"\(appName)\" to \(exec)")
        await poll()
    }
}
