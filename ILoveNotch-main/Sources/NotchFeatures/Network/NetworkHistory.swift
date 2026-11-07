// SPDX-License-Identifier: MIT
import Foundation
import NotchCore
import SQLite3

/// Bytes down and up.
public struct Traffic: Hashable, Sendable {
    public var down: Int64
    public var up: Int64

    public init(down: Int64 = 0, up: Int64 = 0) {
        self.down = down
        self.up = up
    }

    public static func + (a: Traffic, b: Traffic) -> Traffic { Traffic(down: a.down + b.down, up: a.up + b.up) }
    public static func += (a: inout Traffic, b: Traffic) { a = a + b }
    public var total: Int64 { down + up }
}

/// What the history chart shows: the last 24 hours by the hour, the last 7 or 30 days by the day,
/// or the last 12 months by the month.
public enum HistoryRange: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, year

    public var id: Self { self }

    public var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    public var shortTitle: String {
        switch self {
        case .day: "24h"
        case .week: "7d"
        case .month: "30d"
        case .year: "1y"
        }
    }

    public var caption: String {
        switch self {
        case .day: "Last 24 hours"
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .year: "Last 12 months"
        }
    }

    /// What one bar covers.
    var unit: Calendar.Component {
        switch self {
        case .day: .hour
        case .week, .month: .day
        case .year: .month
        }
    }

    var bucketCount: Int {
        switch self {
        case .day: 24
        case .week: 7
        case .month: 30
        case .year: 12
        }
    }

    /// Groups rows into bars in SQL, on the local clock, so a day is the user's midnight to midnight.
    fileprivate var groupFormat: String {
        switch self {
        case .day: "%Y-%m-%d %H"
        case .week, .month: "%Y-%m-%d"
        case .year: "%Y-%m"
        }
    }
}

/// One bar of the history chart.
public struct TrafficBucket: Hashable, Identifiable, Sendable {
    public var start: Date
    public var traffic: Traffic
    public var id: Date { start }
}

/// The history in SQLite: one row per hour of the local clock (its start, bytes down, bytes up), or
/// about 9,000 rows and 250 KB a year. Writing an hour again adds to it, so a partial hour saved on
/// sleep and the rest saved later add up. NetSpeed kept a row a minute, 60 times as many, and never
/// drew anything finer than an hour.
final class NetworkHistory {
    private var db: OpaquePointer?

    init(url: URL) {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            Log.features.error(
                "Network history didn't open: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            sqlite3_close(db)
            db = nil
            return
        }
        // WAL writes each hour as a page appended to the log, and survives a crash.
        exec("PRAGMA journal_mode=WAL")
        exec("CREATE TABLE IF NOT EXISTS hours (start INTEGER PRIMARY KEY, down INTEGER NOT NULL, up INTEGER NOT NULL)")
    }

    deinit { sqlite3_close(db) }

    @discardableResult
    private func exec(_ sql: String) -> Bool { sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK }

    var isEmpty: Bool { query("SELECT COUNT(*) FROM hours").first.map { $0[0] == 0 } ?? true }

    /// Adds each hour's traffic to what's stored for it, in one transaction.
    func add(_ hours: [Date: Traffic]) {
        guard db != nil, !hours.isEmpty else { return }
        let sql = """
            INSERT INTO hours (start, down, up) VALUES (?, ?, ?)
            ON CONFLICT(start) DO UPDATE SET down = down + excluded.down, up = up + excluded.up
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        exec("BEGIN")
        for (hour, traffic) in hours {
            sqlite3_bind_int64(statement, 1, Int64(hour.timeIntervalSince1970))
            sqlite3_bind_int64(statement, 2, traffic.down)
            sqlite3_bind_int64(statement, 3, traffic.up)
            sqlite3_step(statement)
            sqlite3_reset(statement)
        }
        exec("COMMIT")
    }

    /// The range's bars, oldest first and ending with the one `now` is in, with empty periods as zeros
    /// so the chart keeps its shape.
    func buckets(for range: HistoryRange, now: Date = .now, calendar: Calendar = .current) -> [TrafficBucket] {
        guard let current = calendar.dateInterval(of: range.unit, for: now)?.start else { return [] }
        let starts = (0..<range.bucketCount).reversed().compactMap {
            calendar.date(byAdding: range.unit, value: -$0, to: current)
        }
        guard let first = starts.first else { return [] }
        // Each group's earliest hour lands in its bar, whatever time zone the rows were written in.
        let sql = """
            SELECT MIN(start), SUM(down), SUM(up) FROM hours WHERE start >= \(Int64(first.timeIntervalSince1970))
            GROUP BY strftime('\(range.groupFormat)', start, 'unixepoch', 'localtime')
            """
        var totals: [Date: Traffic] = [:]
        for row in query(sql) {
            let date = Date(timeIntervalSince1970: TimeInterval(row[0]))
            guard let start = calendar.dateInterval(of: range.unit, for: date)?.start else { continue }
            totals[start, default: Traffic()] += Traffic(down: row[1], up: row[2])
        }
        return starts.map { TrafficBucket(start: $0, traffic: totals[$0] ?? Traffic()) }
    }

    /// Everything ever recorded.
    func total() -> Traffic {
        query("SELECT IFNULL(SUM(down), 0), IFNULL(SUM(up), 0) FROM hours").first.map {
            Traffic(down: $0[0], up: $0[1])
        } ?? Traffic()
    }

    func clear() { exec("DELETE FROM hours") }

    /// Adds NetSpeed's history (a row a minute, `samples(ts, down, up)`) by the hour of the local clock.
    /// Returns how many hours it added.
    func importNetSpeed(from url: URL, calendar: Calendar = .current) -> Int {
        var source: OpaquePointer?
        defer { sqlite3_close(source) }
        guard FileManager.default.fileExists(atPath: url.path),
            sqlite3_open_v2(url.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
        else { return 0 }
        let sql = """
            SELECT MIN(ts), SUM(down), SUM(up) FROM samples
            GROUP BY strftime('%Y-%m-%d %H', ts, 'unixepoch', 'localtime')
            """
        var hours: [Date: Traffic] = [:]
        for row in Self.query(sql, in: source) {
            let minute = Date(timeIntervalSince1970: TimeInterval(row[0]))
            guard let hour = calendar.dateInterval(of: .hour, for: minute)?.start else { continue }
            hours[hour, default: Traffic()] += Traffic(down: row[1], up: row[2])
        }
        add(hours)
        return hours.count
    }

    private func query(_ sql: String) -> [[Int64]] { Self.query(sql, in: db) }

    /// Every row of integer columns.
    private static func query(_ sql: String, in db: OpaquePointer?) -> [[Int64]] {
        var statement: OpaquePointer?
        guard db != nil, sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [[Int64]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(statement)).map { sqlite3_column_int64(statement, $0) })
        }
        return rows
    }
}
