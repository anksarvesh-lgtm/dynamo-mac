// SPDX-License-Identifier: MIT
import Foundation

/// A task's priority in Reminders' terms. EventKit stores 1–4 as high, 5 as medium, 6–9 as low, and
/// 0 as none; Reminders shows them as "!!!", "!!", and "!".
public enum TaskPriority: Int, CaseIterable, Comparable, Hashable, Sendable {
    case none = 0
    case low
    case medium
    case high

    init(eventKit value: Int) {
        switch value {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    var eventKitValue: Int {
        switch self {
        case .none: 0
        case .low: 9
        case .medium: 5
        case .high: 1
        }
    }

    /// "!", "!!", or "!!!", as Reminders shows it; empty for none.
    public var marks: String { String(repeating: "!", count: rawValue) }

    public var name: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How often a task repeats, for the phrases quick add understands.
public enum TaskRepeat: String, CaseIterable, Hashable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly

    public var name: String {
        switch self {
        case .daily: "Every day"
        case .weekly: "Every week"
        case .monthly: "Every month"
        case .yearly: "Every year"
        }
    }
}

/// A task typed into quick add, split into its parts: "Pay rent fri 9am !! #Home every month" is
/// "Pay rent", due Friday at 9:00, high priority, on the Home list, repeating monthly.
public struct TaskDraft: Equatable, Sendable {
    public var title: String
    public var due: Date?
    /// Whether `due` has a time of day; without one the task is due on a day.
    public var hasTime = false
    public var priority: TaskPriority = .none
    /// The list named with "#", matched against the Reminders lists when the task is saved.
    public var list: String?
    public var repeats: TaskRepeat?

    public init(title: String) {
        self.title = title
    }

    /// Whether anything besides the title was recognized.
    public var hasDetails: Bool { due != nil || priority != .none || list != nil || repeats != nil }

    // Words a date phrase leaves dangling at the end of a title: "Pay rent on" from "Pay rent on friday".
    private static let dangling: Set<String> = ["at", "on", "by", "due", "for", "from", "in", "@", "-", ",", "–"]
    // A date phrase that names a time of day, as opposed to only a day.
    private static let timePattern =
        #"\d\s*(am|pm|a\.m\.|p\.m\.)|\d:\d\d|\b(noon|midnight|morning|afternoon|evening|tonight)\b|\bat\s+\d"#

    /// Reads a quick-add line. Dates come from the system's date detector, so phrases like
    /// "tomorrow 5pm", "next friday", or "3 June" work in the user's language settings.
    public static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> TaskDraft {
        var draft = TaskDraft(title: "")
        var words: [String] = []
        for word in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            if draft.priority == .none, word.count <= 3, word.allSatisfy({ $0 == "!" }) {
                draft.priority = TaskPriority(rawValue: word.count) ?? TaskPriority.none
            } else if draft.list == nil, word.count > 1, word.hasPrefix("#") {
                draft.list = String(word.dropFirst())
            } else {
                words.append(word)
            }
        }
        var rest = words.joined(separator: " ")

        let repeatPattern = #"\b(every\s+(day|week|month|year)|daily|weekly|monthly|yearly|annually)\b"#
        let weekdayRepeat = #"\bevery(?=\s+(mon|tues|wednes|thurs|fri|satur|sun)day\b)"#
        if let match = rest.range(of: repeatPattern, options: [.regularExpression, .caseInsensitive]) {
            let phrase = rest[match].lowercased()
            if phrase == "daily" || phrase.hasSuffix("day") {
                draft.repeats = .daily
            } else if phrase == "weekly" || phrase.hasSuffix("week") {
                draft.repeats = .weekly
            } else if phrase == "monthly" || phrase.hasSuffix("month") {
                draft.repeats = .monthly
            } else {
                draft.repeats = .yearly
            }
            rest.replaceSubrange(match, with: " ")
        } else if let match = rest.range(of: weekdayRepeat, options: [.regularExpression, .caseInsensitive]) {
            // "every monday": weekly, starting on the day the date detector finds next.
            draft.repeats = .weekly
            rest.replaceSubrange(match, with: " ")
        }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let string = rest as NSString
            let whole = NSRange(location: 0, length: string.length)
            if let match = detector.firstMatch(in: rest, options: [], range: whole), let date = match.date {
                let phrase = string.substring(with: match.range)
                draft.hasTime = phrase.range(of: timePattern, options: [.regularExpression, .caseInsensitive]) != nil
                draft.due = draft.hasTime ? date : calendar.startOfDay(for: date)
                rest = string.replacingCharacters(in: match.range, with: " ")
            }
        }

        var titleWords = rest.split(whereSeparator: \.isWhitespace).map(String.init)
        while let last = titleWords.last, dangling.contains(last.lowercased()) { titleWords.removeLast() }
        draft.title = titleWords.joined(separator: " ")
        if draft.title.isEmpty { draft.title = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Reminders repeats from a due date, so a repeating task with no date starts today.
        if draft.repeats != nil, draft.due == nil { draft.due = calendar.startOfDay(for: now) }
        return draft
    }
}

/// Where a task falls in the date-grouped list.
public enum TaskGroup: Int, CaseIterable, Comparable, Hashable, Sendable {
    case overdue
    case today
    case tomorrow
    case thisWeek
    case later
    case someday

    public var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .thisWeek: "Next 7 Days"
        case .later: "Later"
        case .someday: "No Date"
        }
    }

    /// A task due at a time is overdue once that time passes; one due on a day, once the day ends.
    public init(due: Date?, hasTime: Bool, now: Date, calendar: Calendar = .current) {
        guard let due else {
            self = .someday
            return
        }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: due)
        if hasTime ? due < now : day < today {
            self = .overdue
        } else if day == today {
            self = .today
        } else if calendar.dateComponents([.day], from: today, to: day).day == 1 {
            self = .tomorrow
        } else if (calendar.dateComponents([.day], from: today, to: day).day ?? .max) < 7 {
            self = .thisWeek
        } else {
            self = .later
        }
    }

    public static func < (lhs: TaskGroup, rhs: TaskGroup) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Short, human due dates: "Today 9:00 AM", "Tomorrow", "Friday", "3 Jun".
public enum DueLabel {
    public static func text(for due: Date, hasTime: Bool, now: Date = .now, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let offset = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: due)).day ?? 0
        let day: String =
            switch offset {
            case 0: "Today"
            case 1: "Tomorrow"
            case -1: "Yesterday"
            case 2..<7: due.formatted(.dateTime.weekday(.wide))
            default:
                calendar.component(.year, from: due) == calendar.component(.year, from: now)
                    ? due.formatted(.dateTime.day().month(.abbreviated))
                    : due.formatted(.dateTime.day().month(.abbreviated).year())
            }
        return hasTime ? "\(day) \(due.formatted(date: .omitted, time: .shortened))" : day
    }
}

/// An event typed into the Calendar tab: "Lunch with Sam tomorrow 1pm for 90 min".
public struct EventDraft: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var duration: TimeInterval
    public var isAllDay: Bool

    private static let durationPattern =
        #"\bfor\s+(\d+(?:\.\d+)?)\s*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes)\b"#

    /// Nil when there's no date or time in the text: an event needs to know when it happens.
    public static func parse(_ text: String, defaultDuration: TimeInterval = 3600, calendar: Calendar = .current)
        -> EventDraft?
    {
        var rest = text
        var duration: TimeInterval?
        if let match = rest.range(of: durationPattern, options: [.regularExpression, .caseInsensitive]) {
            let phrase = rest[match].lowercased()
            let digits = phrase.drop { !$0.isNumber }.prefix { $0.isNumber || $0 == "." }
            if let amount = Double(digits) {
                let unit = phrase.drop { !$0.isLetter }.dropFirst(3).drop { !$0.isLetter }
                duration = unit.hasPrefix("h") ? amount * 3600 : amount * 60
            }
            rest.replaceSubrange(match, with: " ")
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let string = rest as NSString
        guard
            let match = detector.firstMatch(in: rest, options: [], range: NSRange(location: 0, length: string.length)),
            let date = match.date
        else { return nil }
        let phrase = string.substring(with: match.range)
        let timePattern = #"\d\s*(am|pm|a\.m\.|p\.m\.)|\d:\d\d|\b(noon|midnight|tonight)\b|\bat\s+\d"#
        let hasTime = phrase.range(of: timePattern, options: [.regularExpression, .caseInsensitive]) != nil
        rest = string.replacingCharacters(in: match.range, with: " ")
        var titleWords = rest.split(whereSeparator: \.isWhitespace).map(String.init)
        let dangling: Set<String> = ["at", "on", "from", "in", "@", "-", ",", "–"]
        while let last = titleWords.last, dangling.contains(last.lowercased()) { titleWords.removeLast() }
        let title = titleWords.joined(separator: " ")
        let detected = match.duration > 0 ? match.duration : nil
        return EventDraft(
            title: title.isEmpty ? "New Event" : title,
            start: hasTime ? date : calendar.startOfDay(for: date),
            duration: hasTime ? (duration ?? detected ?? defaultDuration) : 86_400,
            isAllDay: !hasTime)
    }
}
