import Foundation
import LedgeCore
import Testing

/// The transport button's optimism, and its deadline.
@Suite("Playback intent")
struct PlaybackIntentTests {

    @Test("With nothing pressed, the player speaks for itself")
    func quiet() {
        let intent = PlaybackIntent()
        #expect(intent.displayed(reported: true, at: 0))
        #expect(!intent.displayed(reported: false, at: 0))
        #expect(!intent.isSpeaking(at: 0))
    }

    @Test("A press shows what was asked for, at once")
    func optimism() {
        var intent = PlaybackIntent()
        intent.ask(for: true, at: 100)
        #expect(intent.displayed(reported: false, at: 100), "Play shows as playing immediately")
        #expect(intent.isSpeaking(at: 100))
    }

    /// The failure this type exists for. The player refuses — or is not there
    /// at all — and goes on reporting the same thing it reported before.
    @Test("A refused command gives way to the truth")
    func refusal() {
        var intent = PlaybackIntent()
        intent.ask(for: true, at: 100)
        #expect(intent.displayed(reported: false, at: 101), "still hopeful a second in")
        #expect(!intent.displayed(reported: false, at: 100 + PlaybackIntent.grace),
            "and at the deadline the player wins")
        #expect(!intent.isSpeaking(at: 100 + PlaybackIntent.grace))
    }

    @Test("A player that agrees ends the optimism early")
    func agreement() {
        var intent = PlaybackIntent()
        intent.ask(for: true, at: 100)
        intent.reported()
        #expect(intent.displayed(reported: true, at: 100.2))
        #expect(!intent.displayed(reported: false, at: 100.2), "the report is the truth, either way")
        #expect(!intent.isSpeaking(at: 100.2))
    }

    /// Pressing repeatedly is the ordinary way to find out whether a player is
    /// listening. Each press starts its own window rather than riding out the
    /// first one.
    @Test("Rapid presses each get their own deadline")
    func rapidPresses() {
        var intent = PlaybackIntent()
        intent.ask(for: true, at: 100)
        intent.ask(for: false, at: 100.3)
        intent.ask(for: true, at: 100.6)
        #expect(intent.displayed(reported: false, at: 101), "the last press is what is shown")
        #expect(intent.isSpeaking(at: 102.5), "and its own two seconds, not the first press's")
        #expect(!intent.displayed(reported: false, at: 100.6 + PlaybackIntent.grace))
    }

    @Test("The deadline is measured from the press, not from the first one")
    func windowIsNotCumulative() {
        var intent = PlaybackIntent()
        intent.ask(for: true, at: 0)
        intent.ask(for: true, at: 10)
        #expect(intent.displayed(reported: false, at: 11))
        #expect(!intent.displayed(reported: false, at: 12.1))
    }
}
