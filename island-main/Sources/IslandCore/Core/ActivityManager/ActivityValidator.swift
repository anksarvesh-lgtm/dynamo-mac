import Foundation

/// Sanitises provider input so malformed activities can never crash or corrupt the manager.
public enum ActivityValidator {
    public static let maxStringLength = 300

    public enum Rejection: Error, Equatable, CustomStringConvertible {
        case emptyID, kindMismatch(ActivityKind), alreadyExpired
        public var description: String {
            switch self {
            case .emptyID: "empty activity id"
            case .kindMismatch(let k): "content does not match kind \(k.rawValue)"
            case .alreadyExpired: "activity already expired"
            }
        }
    }

    public static func sanitize(_ activity: Activity, now: Date) -> Result<Activity, Rejection> {
        var a = activity
        guard !a.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.emptyID) }
        if let exp = a.expiresAt, exp <= now { return .failure(.alreadyExpired) }
        guard contentMatchesKind(a.content, a.kind) else { return .failure(.kindMismatch(a.kind)) }
        a.content = sanitizeContent(a.content)
        return .success(a)
    }

    static func contentMatchesKind(_ content: ActivityContent, _ kind: ActivityKind) -> Bool {
        switch content {
        case .media: kind == .media
        case .timer: kind == .timer
        case .download: kind == .download
        case .recording: kind == .recording
        case .battery: kind == .battery
        case .network: kind == .network
        case .device: kind == .device
        case .calendar: kind == .calendar
        case .clipboard: kind == .clipboard
        case .event: true
        }
    }

    static func clean(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return trimmed.count > maxStringLength ? String(trimmed.prefix(maxStringLength)) + "…" : trimmed
    }

    static func finite(_ v: Double?) -> Double? {
        guard let v, v.isFinite else { return nil }
        return v
    }

    static func sanitizeContent(_ content: ActivityContent) -> ActivityContent {
        switch content {
        case .media(var m):
            m.title = clean(m.title)
            m.artist = clean(m.artist)
            m.album = clean(m.album)
            m.elapsed = finite(m.elapsed).map { max(0, $0) }
            m.duration = finite(m.duration).flatMap { $0 > 0 ? $0 : nil }
            if m.title.isEmpty { m.title = m.sourceName.isEmpty ? "Unknown" : m.sourceName }
            return .media(m)
        case .timer(var t):
            t.label = clean(t.label)
            t.duration = finite(t.duration).map { max(0, $0) } ?? 0
            return .timer(t)
        case .download(var d):
            d.filename = clean(d.filename)
            d.fraction = finite(d.fraction).map { min(1, max(0, $0)) }
            d.completedBytes = max(0, d.completedBytes)
            if let total = d.totalBytes, total <= 0 { d.totalBytes = nil }
            d.bytesPerSecond = finite(d.bytesPerSecond).flatMap { $0 >= 0 ? $0 : nil }
            d.estimatedTimeRemaining = finite(d.estimatedTimeRemaining).flatMap { $0 >= 0 ? $0 : nil }
            return .download(d)
        case .battery(var b):
            b.level = min(100, max(0, b.level))
            return .battery(b)
        case .device(var d):
            d.name = clean(d.name)
            return .device(d)
        case .calendar(var c):
            c.title = clean(c.title)
            if c.end < c.start { c.end = c.start }
            return .calendar(c)
        case .clipboard(var c):
            c.preview = clean(c.preview)
            return .clipboard(c)
        case .event(var e):
            e.title = clean(e.title)
            e.subtitle = e.subtitle.map(clean)
            if e.symbol.isEmpty { e.symbol = "info.circle" }
            return .event(e)
        case .recording, .network:
            return content
        }
    }
}
