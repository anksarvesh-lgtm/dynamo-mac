// SPDX-License-Identifier: MIT
import Foundation
import NotchCore
import Testing

@testable import NotchFeatures

struct MeetingLinkTests {
    @Test(arguments: [
        ("https://us02web.zoom.us/j/81234567890?pwd=abc", "Zoom"),
        ("Join Zoom Meeting\nhttps://zoom.us/j/81234567890\nMeeting ID: 812 3456 7890", "Zoom"),
        ("Join with Google Meet: meet.google.com/abc-defg-hij", "Google Meet"),
        (
            "Join: <https://teams.microsoft.com/l/meetup-join/19%3ameeting_NjU%40thread.v2/0?context=%7b%7d>",
            "Microsoft Teams"
        ),
        ("https://teams.live.com/meet/9312345678901?p=abc", "Microsoft Teams"),
        ("https://acme.webex.com/acme/j.php?MTID=m123", "Webex"),
        ("https://whereby.com/team-standup", "Whereby"),
        ("https://meet.jit.si/NotchStandup", "Jitsi Meet"),
        ("https://facetime.apple.com/join#v=1&p=abc", "FaceTime"),
    ])
    func meetingLinksAreFoundInTheTextAroundThem(text: String, service: String) throws {
        let link = try #require(MeetingLink.find(in: [nil, text]))
        #expect(link.service == service)
    }

    @Test(arguments: [
        "https://zoom.us/pricing", "https://meet.google.com/", "https://meet.google.com/landing",
        "https://docs.google.com/document/d/1", "Room 4B, second floor", "https://www.webex.com/",
        "mailto:sam@example.com", "https://teams.microsoft.com/l/channel/19%3a",
    ])
    func otherLinksAreNotMeetings(text: String) {
        #expect(MeetingLink.find(in: [text]) == nil)
    }

    @Test func theEventsOwnLinkComesBeforeItsLocationAndNotes() throws {
        let link = try #require(MeetingLink.find(in: ["https://meet.jit.si/first", "https://zoom.us/j/1", nil]))
        #expect(link.service == "Jitsi Meet")
    }
}

@MainActor
struct MeetingCountdownTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let zoom = MeetingLink(URL(string: "https://zoom.us/j/1")!)

    private func meeting(_ id: String, in minutes: Double, link: Bool = true, declined: Bool = false) -> DayEvent {
        let start = now + minutes * 60
        return DayEvent(
            id: id, title: id, start: start, end: start + 1800, meeting: link ? zoom : nil, isDeclined: declined)
    }

    @Test func theNextMeetingIsTheSoonestOneThatCanBeJoined() {
        var allDay = meeting("all-day", in: 1)
        allDay.isAllDay = true
        let events = [
            meeting("lunch", in: 10, link: false), meeting("later", in: 120), meeting("soon", in: 30),
            meeting("declined", in: 15, declined: true), allDay, meeting("started", in: -1),
        ]
        #expect(CalendarFeature.nextMeeting(in: events, after: now, skipping: [])?.id == "soon")
        #expect(CalendarFeature.nextMeeting(in: events, after: now, skipping: ["soon"])?.id == "later", "joined")
        #expect(CalendarFeature.nextMeeting(in: [], after: now, skipping: []) == nil)
    }

    @Test func theCountdownStartsFiveMinutesAheadAndEndsWhenTheMeetingStarts() {
        #expect(CalendarFeature.nextWake(for: meeting("far", in: 60), now: now) == now + 55 * 60)
        #expect(CalendarFeature.nextWake(for: meeting("close", in: 2), now: now) == now + 120, "already counting")
        #expect(CalendarFeature.nextWake(for: nil, now: now) == now + CalendarFeature.horizon, "look again later")
    }

    @Test func theCountdownIsOnByDefaultAndTheChoicePersists() {
        let defaults = UserDefaults(suiteName: "Meetings.\(UUID().uuidString)")!
        let store = EventStore()
        #expect(CalendarFeature(eventStore: store, defaults: defaults).countsDownToMeetings)
        CalendarFeature(eventStore: store, defaults: defaults).countsDownToMeetings = false
        #expect(!CalendarFeature(eventStore: store, defaults: defaults).countsDownToMeetings)
    }

    @Test func withoutAccessNothingCountsDown() {
        // Test runners never grant EventKit access.
        let calendar = CalendarFeature(eventStore: EventStore(), defaults: UserDefaults(suiteName: "M.\(UUID())")!)
        var ongoing: [Activity?] = []
        calendar.onOngoing = { ongoing.append($0) }
        calendar.phase = .background
        #expect(!calendar.isObserving && calendar.countingDown == nil && ongoing.isEmpty)
    }
}
