import Foundation

/// Typed application actions. Natural-language input (user or AI) is parsed into these — never into shell commands.
public enum AppAction: Equatable, Sendable, Hashable {
    case startTimer(duration: TimeInterval, label: String)
    case media(MediaVerb)
    case webSearch(query: String)
    case openApplication(name: String)
    case findFile(query: String)
    case openURL(URL)

    public enum MediaVerb: String, Sendable, Hashable { case play, pause, toggle, next, previous }

    public var safety: SafetyLevel {
        switch self {
        case .startTimer, .media, .webSearch, .findFile: .safe
        case .openApplication, .openURL: .safe
        }
    }

    public var title: String {
        switch self {
        case .startTimer(let d, let label):
            let t = DurationFormatter.spoken(d)
            return label.isEmpty || label == "Timer" ? "Start \(t) timer" : "Start \(t) timer — \(label)"
        case .media(let v):
            switch v {
            case .play: return "Play music"
            case .pause: return "Pause music"
            case .toggle: return "Play / pause"
            case .next: return "Next track"
            case .previous: return "Previous track"
            }
        case .webSearch(let q): return "Search the web for “\(q)”"
        case .openApplication(let n): return "Open \(n)"
        case .findFile(let q): return "Find files named “\(q)”"
        case .openURL(let u): return "Open \(u.host ?? u.absoluteString)"
        }
    }

    public var symbol: String {
        switch self {
        case .startTimer: "timer"
        case .media(let v): v == .next ? "forward.fill" : v == .previous ? "backward.fill" : v == .pause ? "pause.fill" : "play.fill"
        case .webSearch: "globe"
        case .openApplication: "app"
        case .findFile: "doc.text.magnifyingglass"
        case .openURL: "link"
        }
    }
}

public enum DurationFormatter {
    /// 125 → "2:05", 3725 → "1:02:05"
    public static func clock(_ t: TimeInterval) -> String {
        let s = Int(max(0, t.isFinite ? t : 0).rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    public static func spoken(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hr") }
        if m > 0 { parts.append("\(m) min") }
        if sec > 0 || parts.isEmpty { parts.append("\(sec) sec") }
        return parts.joined(separator: " ")
    }
}
