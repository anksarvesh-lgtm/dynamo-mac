import AppKit
import Combine
import Security

/// A published GitHub release, as far as the island cares.
struct AppRelease: Equatable {
    let version: String          // "1.2.0": the tag without its leading "v"
    let title: String            // "NotchIsland 1.2.0"
    let notes: String            // the release notes, Markdown
    let pageURL: URL
    let dmgURL: URL?
    let dmgSize: Int64
    let publishedAt: Date?

    /// Parses GitHub's `releases/latest` JSON. Nil for a draft or anything without a tag.
    static func parse(_ data: Data) -> AppRelease? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, !tag.isEmpty,
              json["draft"] as? Bool != true else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? Updater.releasesPage
        var dmgURL: URL?
        var size: Int64 = 0
        for asset in json["assets"] as? [[String: Any]] ?? [] {
            guard let name = asset["name"] as? String, name.lowercased().hasSuffix(".dmg"),
                  let link = asset["browser_download_url"] as? String, let url = URL(string: link) else { continue }
            dmgURL = url
            size = (asset["size"] as? NSNumber)?.int64Value ?? 0
            break
        }
        let published = (json["published_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return AppRelease(version: version,
                          title: (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "NotchIsland \(version)",
                          notes: json["body"] as? String ?? "",
                          pageURL: page, dmgURL: dmgURL, dmgSize: size, publishedAt: published)
    }
}

/// Dotted version strings: "1.10.0" is newer than "1.9.2"; missing or non-numeric parts count as 0.
enum Version {
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func parts(_ s: String) -> [Int] {
        s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}

/// Checks GitHub Releases for a newer NotchIsland and installs it in place.
///
/// The check is a single request to `api.github.com/repos/Edwardrem/NotchIsland/releases/latest`
/// (once a day while *Check for updates* is on, or from Settings ▸ Updates). Nothing about the user or
/// the Mac is sent. Installing downloads the release DMG, checks that the app inside is signed with the
/// same certificate as the running copy (so every permission grant carries over and nobody can slip a
/// different binary in), swaps it into place next to this bundle and relaunches. The download never
/// passes through a browser, so Gatekeeper's "could not verify" dialog does not appear.
final class Updater: ObservableObject {
    static let shared = Updater()

    static let repo = "Edwardrem/NotchIsland"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases")!
    /// `NOTCHISLAND_UPDATE_FEED=<url>` points the checker at another JSON (a `file://` one for tests).
    static let feedURL: URL = {
        if let s = ProcessInfo.processInfo.environment["NOTCHISLAND_UPDATE_FEED"], let u = URL(string: s) { return u }
        return URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    }()
    static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    static let checkInterval: TimeInterval = 24 * 3600

    enum Phase: Equatable {
        case idle
        case checking
        case downloading(Double)     // 0…1
        case installing
        case relaunching
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .checking, .downloading, .installing, .relaunching: return true
            case .idle, .failed: return false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    /// The newest published release GitHub reported (cached across launches).
    @Published private(set) var latest: AppRelease?
    @Published private(set) var lastChecked: Date?

    private let settings = AppSettings.shared
    private let persist = ProcessInfo.processInfo.environment["NOTCHISLAND_UPDATE_FEED"] == nil
    private let queue = DispatchQueue(label: "NotchIsland.updater", qos: .utility)
    private var timer: Timer?
    private var progressObservation: NSKeyValueObservation?
    private var announced: Set<String> = []
    private static let cacheKey = "updatesLatestJSON"

    init() {
        if persist, let data = UserDefaults.standard.data(forKey: Self.cacheKey) {
            latest = AppRelease.parse(data)
            let t = settings.updatesLastCheck
            lastChecked = t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
    }

    // MARK: State

    /// A release newer than this build, skipped by the user or not (Settings shows it either way).
    var newer: AppRelease? {
        guard let latest, Version.compare(latest.version, Self.currentVersion) == .orderedDescending else { return nil }
        return latest
    }

    /// A newer release the user has not skipped: what the island, the shade and the menu announce.
    var available: AppRelease? {
        guard let newer, newer.version != settings.updatesSkippedVersion else { return nil }
        return newer
    }

    var isSkipped: Bool { newer.map { $0.version == settings.updatesSkippedVersion } ?? false }

    /// In-place install needs a bundle signed with a real certificate: the download is checked
    /// against this copy's designated requirement, which an ad-hoc or unsigned build cannot satisfy.
    var canInstall: Bool {
        Permissions.isBundled
            && Permissions.codeIdentity != "unsigned"
            && !Permissions.codeIdentity.contains("cdhash")
    }

    func skip(_ skipped: Bool) {
        settings.updatesSkippedVersion = skipped ? (newer?.version ?? "") : ""
        objectWillChange.send()
    }

    func openReleasePage() {
        NSWorkspace.shared.open(newer?.pageURL ?? latest?.pageURL ?? Self.releasesPage)
    }

    // MARK: Checking

    /// Launch + daily. Previews and demo runs stay offline unless a test feed is set.
    func startSchedule() {
        let env = ProcessInfo.processInfo.environment
        if env["NOTCHISLAND_UPDATE_FEED"] == nil, env["NOTCHISLAND_PREVIEW"] != nil || env["NOTCHISLAND_DEMO"] == "1" { return }
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in self?.checkIfDue() }
        t.tolerance = 300
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.checkIfDue() }
    }

    private func checkIfDue() {
        guard settings.updatesAutoCheck else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.checkInterval {
            announceIfNeeded()      // found on an earlier day; say so once per launch
            return
        }
        check(manual: false)
    }

    /// Asks GitHub for the latest release. `manual` (Settings, menu bar) skips the island HUD.
    func check(manual: Bool) {
        guard !phase.isBusy else { return }
        phase = .checking
        var request = URLRequest(url: Self.feedURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NotchIsland/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { self?.finishCheck(manual: manual, data: data, response: response, error: error) }
        }.resume()
    }

    private func finishCheck(manual: Bool, data: Data?, response: URLResponse?, error: Error?) {
        if let error {
            phase = .failed("Could not reach GitHub: \(error.localizedDescription)")
            return
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            phase = .failed(http.statusCode == 403 || http.statusCode == 429
                ? "GitHub is limiting requests from this network. Try again in an hour."
                : "GitHub answered with status \(http.statusCode).")
            return
        }
        guard let data, let release = AppRelease.parse(data) else {
            phase = .failed("Could not read the release list.")
            return
        }
        latest = release
        lastChecked = Date()
        if persist {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
            settings.updatesLastCheck = lastChecked?.timeIntervalSince1970 ?? 0
        }
        phase = .idle
        if !manual { announceIfNeeded() }
        // Developer aid: NOTCHISLAND_UPDATE_INSTALL=1 installs whatever a (test) feed offers, no click needed.
        if ProcessInfo.processInfo.environment["NOTCHISLAND_UPDATE_INSTALL"] == "1", newer != nil { install() }
    }

    /// One HUD per version per launch: "NotchIsland 1.3.0 is available", tap for the notes.
    private func announceIfNeeded() {
        guard settings.updatesNotify, Permissions.isBundled, let release = available,
              !announced.contains(release.version) else { return }
        announced.insert(release.version)
        ActivityCenter.shared.show(LiveActivity(
            id: "update", kind: .update, symbol: "arrow.down.circle.fill",
            title: "NotchIsland \(release.version) is available",
            subtitle: "Tap to see what's new and update", progress: nil, tint: UI.info, duration: 12))
    }

    // MARK: Installing

    /// Download → verify → swap → relaunch. Falls back to opening the DMG in Finder when this copy
    /// cannot be replaced (not in a writable folder) and to the release page when it cannot be verified.
    func install() {
        guard !phase.isBusy, let release = newer else { return }
        guard canInstall, let dmgURL = release.dmgURL else { openReleasePage(); return }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchIsland-update-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.removeItem(at: work)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        } catch {
            phase = .failed("Could not create a temporary folder: \(error.localizedDescription)")
            return
        }

        phase = .downloading(0)
        var request = URLRequest(url: dmgURL)
        request.setValue("NotchIsland/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120
        let task = URLSession.shared.downloadTask(with: request) { [weak self] tmp, response, error in
            guard let self else { return }
            if let error { self.fail("Download failed: \(error.localizedDescription)"); return }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                self.fail("Download failed: GitHub answered with status \(http.statusCode)."); return
            }
            guard let tmp else { self.fail("Download failed."); return }
            let dmg = work.appendingPathComponent("NotchIsland.dmg")
            do { try FileManager.default.moveItem(at: tmp, to: dmg) } catch {
                self.fail("Could not keep the download: \(error.localizedDescription)"); return
            }
            DispatchQueue.main.async { self.phase = .installing }
            self.queue.async { self.installDMG(dmg, work: work, release: release) }
        }
        progressObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            DispatchQueue.main.async {
                guard let self, case .downloading = self.phase else { return }
                self.phase = .downloading(progress.fractionCompleted)
            }
        }
        task.resume()
    }

    private func installDMG(_ dmg: URL, work: URL, release: AppRelease) {
        let fm = FileManager.default
        let mount = work.appendingPathComponent("mnt", isDirectory: true)
        try? fm.createDirectory(at: mount, withIntermediateDirectories: true)
        let attach = Self.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen",
                                                   "-mountpoint", mount.path, "-quiet"])
        let newApp = mount.appendingPathComponent("NotchIsland.app")
        guard attach.status == 0, fm.fileExists(atPath: newApp.path) else {
            _ = Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-force", "-quiet"])
            try? fm.removeItem(at: work)
            fail("The disk image could not be opened" + (attach.output.isEmpty ? "." : ": \(attach.output)"))
            return
        }

        if let problem = Self.verify(newApp) {
            _ = Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-force", "-quiet"])
            try? fm.removeItem(at: work)
            fail(problem)
            return
        }

        let current = Bundle.main.bundleURL
        let folder = current.deletingLastPathComponent()
        let staged = folder.appendingPathComponent(".NotchIsland-\(release.version).app")
        let previous = folder.appendingPathComponent(".NotchIsland-previous.app")
        try? fm.removeItem(at: staged)
        try? fm.removeItem(at: previous)

        // Copy next to the destination first so the swap itself is two renames on one volume.
        let copy = Self.run("/usr/bin/ditto", [newApp.path, staged.path])
        guard copy.status == 0 else {
            try? fm.removeItem(at: staged)
            manualFallback("NotchIsland could not write into \(folder.path)" + (copy.output.isEmpty ? "." : " (\(copy.output))."),
                           dmg: dmg, mount: mount)
            return
        }
        do {
            try fm.moveItem(at: current, to: previous)
        } catch {
            try? fm.removeItem(at: staged)
            manualFallback("NotchIsland could not replace itself in \(folder.path): \(error.localizedDescription).",
                           dmg: dmg, mount: mount)
            return
        }
        do {
            try fm.moveItem(at: staged, to: current)
        } catch {
            try? fm.moveItem(at: previous, to: current)
            try? fm.removeItem(at: staged)
            manualFallback("NotchIsland could not move the new version into place: \(error.localizedDescription).",
                           dmg: dmg, mount: mount)
            return
        }
        _ = Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", current.path])
        if (try? fm.removeItem(at: previous)) == nil {
            try? fm.trashItem(at: previous, resultingItemURL: nil)
        }
        _ = Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-force", "-quiet"])
        try? fm.removeItem(at: work)
        NSLog("NotchIsland updater: installed %@ at %@, relaunching", release.version, current.path)

        DispatchQueue.main.async {
            self.phase = .relaunching
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { QuickSystem.relaunch() }
        }
    }

    /// The app in the DMG must satisfy this copy's designated requirement: same bundle id, same
    /// certificate. That is what macOS keys permission grants to, and what stops a swapped binary.
    private static func verify(_ app: URL) -> String? {
        let byHand = " Open the release page and install it by hand."
        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &newCode) == errSecSuccess, let newCode else {
            return "The downloaded app could not be read." + byHand
        }
        var selfCode: SecCode?
        var selfStatic: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
              SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic,
              SecCodeCopyDesignatedRequirement(selfStatic, [], &requirement) == errSecSuccess, let requirement else {
            return "This copy's own signature could not be read, so the download was not verified." + byHand
        }
        var errors: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(newCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures),
                                                          requirement, &errors)
        guard status == errSecSuccess else {
            let detail = errors?.takeRetainedValue().localizedDescription ?? "status \(status)"
            return "The download is not signed with the same certificate as this copy (\(detail)), so it was not installed." + byHand
        }
        return nil
    }

    /// Leaves the DMG mounted and visible in Finder so the user can drag the app over by hand.
    private func manualFallback(_ reason: String, dmg: URL, mount: URL) {
        _ = Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-force", "-quiet"])
        _ = Self.run("/usr/bin/hdiutil", ["attach", dmg.path])
        fail(reason + " The disk image is open in Finder: drag NotchIsland into Applications to replace this copy, then relaunch.")
    }

    private func fail(_ message: String) {
        NSLog("NotchIsland updater: %@", message)
        DispatchQueue.main.async { self.phase = .failed(message) }
    }

    private static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }
}
