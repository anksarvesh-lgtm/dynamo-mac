import Foundation
import LedgeCore
import Testing

/// The link that opens Calendar.app at one event.
@Suite("Calendar links")
struct CalendarLinkTests {

    /// 2026-09-14 14:30:00 UTC.
    private let occurrence = Date(timeIntervalSince1970: 1_789_396_200)

    @Test("An event that happens once keeps the plain link")
    func plainLink() {
        let url = CalendarLink.url(eventID: "ABC-123")
        #expect(url?.absoluteString == "ical://ekevent/ABC-123")
    }

    /// The bug: one identifier serves every occurrence of a repeating event,
    /// so without the date the weekly standup opened on whichever instance
    /// Calendar felt like showing rather than the row that was clicked.
    @Test("A repeating event carries the occurrence that was clicked")
    func occurrenceLink() {
        let url = CalendarLink.url(eventID: "ABC-123", occurrence: occurrence)
        #expect(url?.absoluteString == "ical://ekevent/20260914T143000Z/ABC-123")
    }

    @Test("The stamp is UTC, whatever the machine's timezone is")
    func stampIsUTC() {
        #expect(CalendarLink.stamp(occurrence) == "20260914T143000Z")
        #expect(CalendarLink.stamp(Date(timeIntervalSince1970: 0)) == "19700101T000000Z")
    }

    @Test("An identifier with awkward characters survives the trip")
    func escaping() {
        let url = CalendarLink.url(eventID: "A B/C?D#E")
        #expect(url != nil)
        #expect(url?.absoluteString.contains(" ") == false)
        #expect(url?.absoluteString.contains("#") == false, "a fragment would truncate the identifier")
    }

    @Test("A row with no identifier is not a link")
    func noIdentifier() {
        #expect(CalendarLink.url(eventID: "") == nil)
        #expect(CalendarLink.url(eventID: "", occurrence: occurrence) == nil)
    }

    @Test("A nonsense date falls back to the plain link rather than a broken one")
    func nonFiniteOccurrence() {
        let url = CalendarLink.url(eventID: "ABC", occurrence: Date(timeIntervalSince1970: .infinity))
        #expect(url?.absoluteString == "ical://ekevent/ABC")
    }
}
