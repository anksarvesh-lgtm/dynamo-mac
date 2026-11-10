//
//  SQLiteNotificationWatcher.swift
//  LiquidDynamo
//
//  Passive observer for macOS Notification Center SQLite store (WAL mode).
//  Surfaces system and application alerts to Dynamic Island without private APIs.
//  Adopted from NotchIsland's NotificationWatcher architecture.
//

import AppKit
import Combine
import Foundation
import SQLite3

public struct SystemNotificationItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let bundleID: String
    public let appName: String
    public let title: String
    public let subtitle: String
    public let body: String
    public let date: Date

    public init(id: String, bundleID: String, appName: String, title: String, subtitle: String, body: String, date: Date) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.date = date
    }
}

public final class SQLiteNotificationWatcher: ObservableObject, @unchecked Sendable {
    public static let shared = SQLiteNotificationWatcher()

    @Published public private(set) var recentNotifications: [SystemNotificationItem] = []
    @Published public private(set) var hasFullDiskAccess: Bool = false

    private static let dbPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db").path

    private let queue = DispatchQueue(label: "com.agrigence.liquiddynamo.notifs", qos: .utility)
    private var dbHandle: OpaquePointer?
    private var timer: DispatchSourceTimer?
    private var lastObservedDate: Double = Date().timeIntervalSinceReferenceDate

    private init() {
        checkAccessAndStart()
    }

    public func checkAccessAndStart() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let fd = Darwin.open(Self.dbPath, O_RDONLY)
            if fd >= 0 {
                Darwin.close(fd)
                DispatchQueue.main.async { self.hasFullDiskAccess = true }
                self.openStoreAndWatch()
            } else {
                DispatchQueue.main.async { self.hasFullDiskAccess = false }
            }
        }
    }

    private func openStoreAndWatch() {
        var db: OpaquePointer?
        if sqlite3_open_v2(Self.dbPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK {
            self.dbHandle = db

            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 1.0, repeating: 2.0)
            t.setEventHandler { [weak self] in
                self?.pollNewNotifications()
            }
            t.resume()
            self.timer = t
        }
    }

    private func pollNewNotifications() {
        guard let db = dbHandle else { return }
        let query = """
        SELECT record_id, app_id, data, delivered_date
        FROM record
        WHERE delivered_date > ?
        ORDER BY delivered_date ASC
        LIMIT 10;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_double(statement, 1, lastObservedDate)

        var newItems: [SystemNotificationItem] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let recordID = sqlite3_column_int64(statement, 0)
            let appID = String(cString: sqlite3_column_text(statement, 1))
            let deliveredDate = sqlite3_column_double(statement, 3)

            let id = "\(appID)_\(recordID)"
            var title = appID
            var body = "Notification alert"

            // Parse plist data blob if present
            if let blob = sqlite3_column_blob(statement, 2) {
                let bytes = sqlite3_column_bytes(statement, 2)
                let data = Data(bytes: blob, count: Int(bytes))
                if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                    if let req = plist["req"] as? [String: Any] {
                        title = req["titl"] as? String ?? title
                        body = req["body"] as? String ?? body
                    }
                }
            }

            let item = SystemNotificationItem(
                id: id,
                bundleID: appID,
                appName: appID.components(separatedBy: ".").last ?? appID,
                title: title,
                subtitle: "",
                body: body,
                date: Date(timeIntervalSinceReferenceDate: deliveredDate)
            )

            newItems.append(item)
            if deliveredDate > lastObservedDate {
                lastObservedDate = deliveredDate
            }
        }
        sqlite3_finalize(statement)

        if !newItems.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.recentNotifications.append(contentsOf: newItems)
                // Post to LiveActivityCenter
                for notif in newItems {
                    let activity = LiveActivity(
                        source: notif.bundleID,
                        kind: .notification,
                        priority: 80,
                        duration: 4.5,
                        payload: LiveActivityPayload(
                            title: notif.title,
                            subtitle: notif.appName,
                            iconName: "bell.fill",
                            body: notif.body
                        )
                    )
                    LiveActivityCenter.shared.submit(activity)
                }
            }
        }
    }

    deinit {
        timer?.cancel()
        if let db = dbHandle {
            sqlite3_close(db)
        }
    }
}

