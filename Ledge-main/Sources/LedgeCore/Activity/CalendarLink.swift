import Foundation

/// The `ical://` link that opens Calendar.app at one event.
///
/// A recurring event has a single identifier for every one of its occurrences,
/// so an identifier-only link opens *the series* — in practice whichever
/// instance Calendar decides on, which for a weekly standup is rarely the one
/// that was clicked. Calendar accepts the occurrence's own start time in front
/// of the identifier, and that is what pins the link to the row.
///
/// Built here rather than in the view because it is a string with a format, an
/// encoding and a timezone in it, and all three can be wrong in ways a
/// screenshot will not show.
///
/// The scheme is undocumented. The occurrence form is therefore used *only*
/// where it is needed — an event that actually repeats — so a non-repeating
/// event keeps the link it has always had rather than sharing the risk.
public enum CalendarLink {

    /// `20260912T143000Z`: UTC, because the link is read by another process
    /// whose timezone is not ours to assume.
    static let occurrenceFormat = "yyyyMMdd'T'HHmmss'Z'"

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        // Fixed locale and calendar: a Gregorian, ASCII-digit timestamp, even
        // for somebody whose region formats dates another way entirely.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = occurrenceFormat
        return formatter
    }()

    public static func stamp(_ date: Date) -> String { formatter.string(from: date) }

    /// - Parameters:
    ///   - eventID: EventKit's `calendarItemIdentifier`. Empty means the row
    ///     came from a fixture or an older payload and is not a link at all.
    ///   - occurrence: the start of the instance that was clicked, for a
    ///     repeating event. Nil for anything that happens once.
    public static func url(eventID: String, occurrence: Date? = nil) -> URL? {
        guard !eventID.isEmpty else { return nil }
        let escaped = eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventID
        guard let occurrence, occurrence.timeIntervalSince1970.isFinite else {
            return URL(string: "ical://ekevent/\(escaped)")
        }
        return URL(string: "ical://ekevent/\(stamp(occurrence))/\(escaped)")
    }
}
