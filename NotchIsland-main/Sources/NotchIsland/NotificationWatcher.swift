import AppKit
import SQLite3

/// One delivered system notification.
struct NotchNotification: Identifiable, Equatable {
    let id: String
    let bundleID: String
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date

    var icon: NSImage { AppIconCache.icon(for: bundleID) }
    var headline: String { title.isEmpty ? (subtitle.isEmpty ? appName : subtitle) : title }

    static func == (a: NotchNotification, b: NotchNotification) -> Bool { a.id == b.id }
}

enum AppIconCache {
    private static var icons: [String: NSImage] = [:]
    private static let lock = NSLock()

    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func name(for bundleID: String) -> String {
        if let url = url(for: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }
        return bundleID.components(separatedBy: ".").last ?? bundleID
    }

    static func icon(for bundleID: String) -> NSImage {
        lock.lock(); defer { lock.unlock() }
        if let cached = icons[bundleID] { return cached }
        let image: NSImage
        if let url = url(for: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil) ?? NSImage()
        }
        icons[bundleID] = image
        return image
    }
}

/// Watches Notification Center's own database for newly delivered notifications.
///
/// macOS offers no public API for observing other apps' notifications. The user notification
/// daemon keeps every delivered notification in an SQLite store (WAL mode) under
/// `~/Library/Group Containers/group.com.apple.usernoted/db2/db`; each row carries a binary
/// plist with the request's title / subtitle / body. We open it read-only, remember the
/// newest `delivered_date` at launch, and surface anything that lands after that.
final class NotificationWatcher {
    /// Called on the main thread for each new notification, oldest first.
    var onNotification: ((NotchNotification) -> Void)?
    /// Called once on the main thread at startup with notifications already in the Centre, newest first.
    var onHistory: (([NotchNotification]) -> Void)?
    /// Called on the main thread with the current problem (and the pane that fixes it), or nil when all is well.
    var onStatus: ((IslandHint?) -> Void)?

    static let databaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")

    /// Shown in the island and in Settings while the store can't be opened for lack of Full Disk Access.
    static let fullDiskAccessHint = IslandHint(
        text: "Notifications need Full Disk Access for NotchIsland.",
        settingsPane: PrivacyPane.fullDiskAccess)

    /// Whether this process can really read the store. The store lives in a TCC-protected folder:
    /// `access(2)` (and so `FileManager.isReadableFile`) ignores TCC and says "readable" even without
    /// Full Disk Access, so only a real `open(2)` tells the truth.
    enum StoreAccess: Equatable {
        case ok
        case needsFullDiskAccess
        case missing            // nothing has been delivered on this Mac yet, so the store doesn't exist
        case failed(String)

        var isUsable: Bool { self == .ok || self == .missing }
    }

    static func storeAccess() -> StoreAccess {
        let fd = Darwin.open(databaseURL.path, O_RDONLY)
        if fd >= 0 { Darwin.close(fd); return .ok }
        switch errno {
        case EPERM, EACCES: return .needsFullDiskAccess
        case ENOENT: return .missing
        default: return .failed(String(cString: strerror(errno)))
        }
    }

    private let queue = DispatchQueue(label: "NotchIsland.notifications", qos: .utility)
    private var db: OpaquePointer?
    private var startDate: Double = 0                // launch time; anything delivered after this is new
    private var lastDate: Double = 0                 // newest delivered_date seen (seconds since 2001)
    private var seen: [String: Double] = [:]         // uuid -> delivered_date, pruned as time moves on
    private var timer: DispatchSourceTimer?
    private var walSource: DispatchSourceFileSystemObject?
    private var retryCount = 0
    private var reported: IslandHint?
    private var reportedOnce = false

    func start() {
        queue.async { [self] in
            openDatabase()
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 1, repeating: 1.0)
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            timer = t
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel(); timer = nil
            walSource?.cancel(); walSource = nil
            if let db { sqlite3_close(db) }
            db = nil
        }
    }

    deinit {
        timer?.cancel()
        walSource?.cancel()
        if let db { sqlite3_close(db) }
    }

    // MARK: - Setup

    private func openDatabase() {
        var handle: OpaquePointer?
        let path = Self.databaseURL.path
        switch Self.storeAccess() {
        case .ok:
            break
        case .needsFullDiskAccess:
            report(Self.fullDiskAccessHint)
            return
        case .missing:
            report(nil)                     // nothing to read yet; `tick` keeps trying
            return
        case .failed(let why):
            report(IslandHint(text: "Notifications unavailable: \(why)"))
            return
        }
        let rc = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        if rc == SQLITE_OK, let handle {
            db = handle
            startDate = Date().timeIntervalSinceReferenceDate
            lastDate = startDate
            report(nil)
            loadHistory()
            if walSource == nil { watchWAL() }
        } else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            // Apple's SQLite surfaces a TCC refusal as SQLITE_AUTH ("authorization denied").
            if rc == SQLITE_AUTH || rc == SQLITE_PERM || rc == SQLITE_CANTOPEN {
                report(Self.fullDiskAccessHint)
            } else {
                report(IslandHint(text: "Notifications unavailable: \(message)"))
            }
        }
    }

    /// Writes land in the WAL file first, so watching it wakes us up well before the next 1 s poll.
    private func watchWAL() {
        let fd = Darwin.open(Self.databaseURL.path + "-wal", O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // The write we were woken by may not be committed yet; look now and again shortly after.
            self.poll()
            self.queue.asyncAfter(deadline: .now() + 0.25) { self.poll() }
            if source.data.contains(.delete) || source.data.contains(.rename) {
                source.cancel()
                self.queue.asyncAfter(deadline: .now() + 1) { self.watchWAL() }
            }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        walSource = source
    }

    private func tick() {
        if db == nil {
            // The database may appear later (first notification ever) or become readable after a permission change.
            retryCount += 1
            if retryCount % 10 == 0 { openDatabase() }
            return
        }
        poll()
    }

    private func report(_ problem: IslandHint?) {
        if !reportedOnce || problem != reported {
            reportedOnce = true
            reported = problem
            NSLog("NotchIsland notifications: %@", problem?.text ?? "ok")
        }
        DispatchQueue.main.async { self.onStatus?(problem) }
    }

    // MARK: - Reading

    /// Everything already sitting in the Centre at launch, so the shade opens populated.
    private func loadHistory() {
        guard let db else { return }
        let dayAgo = startDate - 24 * 3600
        let sql = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date, hex(r.uuid)
            FROM record r JOIN app a ON a.app_id = r.app_id
            WHERE r.delivered_date > ? AND r.delivered_date <= ?
            ORDER BY r.delivered_date DESC LIMIT 60
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, dayAgo)
        sqlite3_bind_double(stmt, 2, startDate)

        var history: [NotchNotification] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let note = decode(stmt) {
                seen[note.id] = note.date.timeIntervalSinceReferenceDate
                history.append(note)
            }
        }
        guard !history.isEmpty else { return }
        DispatchQueue.main.async { self.onHistory?(history) }
    }

    private func poll() {
        guard let db else { return }
        let sql = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date, hex(r.uuid)
            FROM record r JOIN app a ON a.app_id = r.app_id
            WHERE r.delivered_date > ?
            ORDER BY r.delivered_date ASC
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        // usernoted commits rows lazily (observed ~5 s after delivery) and not necessarily in
        // timestamp order, so look well behind the newest timestamp and dedupe by uuid.
        sqlite3_bind_double(stmt, 1, lastDate - 30)

        var fresh: [NotchNotification] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let delivered = sqlite3_column_double(stmt, 3)
            let uuid = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
                ?? "rec-\(sqlite3_column_int64(stmt, 0))"
            guard seen[uuid] == nil else { continue }
            seen[uuid] = delivered
            guard delivered > startDate else { continue }  // predates launch: remember, don't show
            lastDate = max(lastDate, delivered)
            if let note = decode(stmt) { fresh.append(note) }
        }

        let cutoff = lastDate - 120
        seen = seen.filter { $0.value > cutoff }

        guard !fresh.isEmpty else { return }
        DispatchQueue.main.async { fresh.forEach { self.onNotification?($0) } }
    }

    /// Turns the current result row into a notification, or nil if it carries no text.
    private func decode(_ stmt: OpaquePointer?) -> NotchNotification? {
        let recID = sqlite3_column_int64(stmt, 0)
        let delivered = sqlite3_column_double(stmt, 3)
        let uuid = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "rec-\(recID)"
        guard let bytes = sqlite3_column_blob(stmt, 2) else { return nil }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 2)))
        guard let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        else { return nil }
        let req = plist["req"] as? [String: Any] ?? [:]
        let title = (req["titl"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = (req["subt"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (req["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(title.isEmpty && subtitle.isEmpty && body.isEmpty) else { return nil }
        let tableID = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
        let bundleID = (plist["app"] as? String) ?? tableID
        return NotchNotification(
            id: uuid, bundleID: bundleID, appName: AppIconCache.name(for: bundleID),
            title: title, subtitle: subtitle, body: body,
            date: Date(timeIntervalSinceReferenceDate: delivered))
    }
}
