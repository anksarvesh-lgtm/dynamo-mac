import Foundation

/// The two things the timer card has to work out rather than simply draw:
/// when a countdown will end, and which lengths to offer before one starts.
///
/// Pure, so both can be checked against awkward cases — a timer that ends
/// after midnight, a run of recents long enough to crowd out every default —
/// rather than by watching the card and hoping.
public enum TimerReadout {

    /// When a running countdown will finish.
    ///
    /// Rounded to the minute it will *show*: a card reading "Ends at 3:42"
    /// beside 4 minutes 40 seconds remaining is not wrong by the clock, but it
    /// is wrong to a reader, who adds the two and gets 3:43. Rounding the sum
    /// the way the reader would makes the two numbers agree.
    public static func endsAt(remaining: TimeInterval, now: Date) -> Date? {
        guard remaining.isFinite, remaining > 0 else { return nil }
        let end = now.addingTimeInterval(remaining)
        let seconds = end.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 60).rounded() * 60)
    }

    /// Whether the end time is worth showing.
    ///
    /// Under a minute it says nothing the countdown has not already said, and
    /// it would change under the reader's eyes as the rounding flips.
    public static func showsEndTime(remaining: TimeInterval) -> Bool {
        remaining.isFinite && remaining >= 60
    }

    /// The length a fresh ready card opens on, and what Start would use.
    public static func openingLength(recents: [Int], focusMinutes: Int) -> Int {
        // What they used last, or the length of their focus block — which is
        // the only other number on this card the user has ever chosen.
        recents.first { $0 > 0 } ?? max(1, focusMinutes)
    }
}
