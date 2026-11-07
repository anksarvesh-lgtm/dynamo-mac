import Foundation

/// Parses short natural-language commands into typed `AppAction`s. Deterministic and offline.
/// Output is only ever a suggestion the user (or a safe automation) can run through `CommandRouter`.
public enum ActionRouter {
    public static func parse(_ raw: String) -> [AppAction] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        guard !lower.isEmpty else { return [] }
        var out: [AppAction] = []

        // Timers: "set timer 20 minutes", "timer 1h30m tea", "25 min focus timer", "remind me in 10 minutes"
        if lower.contains("timer") || lower.hasPrefix("remind me in") || lower.hasPrefix("countdown") {
            if let d = DurationParser.parse(lower), d > 0 {
                out.append(.startTimer(duration: d, label: timerLabel(from: text)))
            }
        }

        // Media
        let media: [(String, AppAction.MediaVerb)] = [
            ("next track", .next), ("next song", .next), ("skip", .next), ("previous track", .previous), ("previous song", .previous),
            ("play music", .play), ("play", .play), ("resume music", .play), ("pause music", .pause), ("pause", .pause), ("play pause", .toggle),
        ]
        for (phrase, verb) in media where lower == phrase || lower == phrase + " music" {
            out.append(.media(verb))
            break
        }

        // Web search
        for prefix in ["search web for ", "search the web for ", "web search ", "google ", "search for ", "look up "] where lower.hasPrefix(prefix) {
            let q = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !q.isEmpty { out.append(.webSearch(query: q)) }
            break
        }

        // Open application
        for prefix in ["open ", "launch ", "start "] where lower.hasPrefix(prefix) {
            let name = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if let url = URL(string: name), let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) {
                out.append(.openURL(url))
            } else if !name.isEmpty, !name.lowercased().contains("timer") {
                out.append(.openApplication(name: name))
            }
            break
        }

        // Find file
        for prefix in ["find file ", "find files ", "find ", "locate "] where lower.hasPrefix(prefix) {
            let q = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !q.isEmpty { out.append(.findFile(query: q)) }
            break
        }
        return out
    }

    static func timerLabel(from text: String) -> String {
        var s = text.lowercased()
        for w in ["set a ", "set ", "start a ", "start ", "remind me in", "countdown", "timer", "for "] { s = s.replacingOccurrences(of: w, with: " ") }
        s = s.replacingOccurrences(of: DurationParser.pattern, with: " ", options: .regularExpression)
        let cleaned = s.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Timer" : cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }
}

/// "20 minutes", "1h 30m", "90s", "1.5 hours", "an hour", "half an hour", bare "20" (minutes).
public enum DurationParser {
    static let pattern = "(\\d+(?:\\.\\d+)?)\\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\\b"

    public static func parse(_ text: String) -> TimeInterval? {
        let l = text.lowercased()
        if l.contains("half an hour") { return 1800 }
        if l.range(of: "\\ban hour\\b", options: .regularExpression) != nil { return 3600 }
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = l as NSString
        var total: TimeInterval = 0
        var matched = false
        for m in regex.matches(in: l, range: NSRange(location: 0, length: ns.length)) {
            guard let v = Double(ns.substring(with: m.range(at: 1))) else { continue }
            let unit = ns.substring(with: m.range(at: 2))
            matched = true
            if unit.hasPrefix("h") { total += v * 3600 } else if unit.hasPrefix("m") { total += v * 60 } else { total += v }
        }
        if matched { return total > 0 && total <= 86_400 ? total : nil }
        if let r = l.range(of: "\\b(\\d{1,3})\\b", options: .regularExpression), let v = Double(l[r]), v > 0 { return v * 60 }
        return nil
    }
}
