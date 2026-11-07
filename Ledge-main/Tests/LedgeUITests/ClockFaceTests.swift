import Foundation
import LedgeCore
import Testing

@testable import LedgeUI

/// Which face of the Clock card owns what is running.
///
/// A focus session used to appear on the Timer face as well as its own, which
/// meant the same countdown was on the card twice and there was nowhere to set
/// a quick timer while a session was going.
@Suite("Clock faces")
struct ClockFaceTests {

    private func timer(
        custom: Bool,
        finished: Bool = false,
        mode: TimerPayload.Mode = .countdown
    ) -> TimerPayload {
        TimerPayload(
            label: custom ? "Timer" : "Focus",
            remaining: 300,
            total: 600,
            isFinished: finished,
            isCustom: custom,
            mode: mode
        )
    }

    private var ready: TimerPayload {
        TimerPayload(label: "Timer", remaining: 0, total: 1_500, isRunning: false, isIdle: true)
    }

    @Test("A focus leg belongs to the Focus face")
    func focusLeg() {
        #expect(TimerCardView.owner(of: timer(custom: false)) == .focus)
    }

    @Test("A quick timer belongs to the Timer face")
    func quickTimer() {
        #expect(TimerCardView.owner(of: timer(custom: true)) == .timer)
    }

    @Test("A finished leg stays on the face that ran it")
    func finishedStays() {
        #expect(TimerCardView.owner(of: timer(custom: false, finished: true)) == .focus)
        #expect(TimerCardView.owner(of: timer(custom: true, finished: true)) == .timer)
    }

    @Test("The stopwatch outranks whatever else the payload carries")
    func stopwatchWins() {
        #expect(TimerCardView.owner(of: timer(custom: false, mode: .stopwatch)) == .stopwatch)
    }

    @Test("Nothing running belongs to nobody")
    func idleOwnsNothing() {
        #expect(TimerCardView.owner(of: ready) == nil)
    }

    // MARK: - What the card shows

    @Test("With no pick, the card opens on the face that owns the session")
    func defaultsToTheOwner() {
        #expect(TimerCardView.face(for: timer(custom: false), pick: nil) == .focus)
        #expect(TimerCardView.face(for: timer(custom: true), pick: nil) == .timer)
        #expect(TimerCardView.face(for: ready, pick: nil) == .timer, "the ready card is the timer's")
    }

    /// The point of the whole thing: a focus session is running and the user
    /// has asked for the Timer face, so they get the Timer face — ready to set
    /// a quick timer, not a second copy of the session.
    @Test("A pick is honoured while a session runs elsewhere")
    func pickWins() {
        #expect(TimerCardView.face(for: timer(custom: false), pick: .timer) == .timer)
        #expect(TimerCardView.face(for: timer(custom: true), pick: .focus) == .focus)
    }
}
