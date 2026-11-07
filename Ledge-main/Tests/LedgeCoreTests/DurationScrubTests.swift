import CoreGraphics
import Foundation
import LedgeCore
import Testing

/// Dragging the duration sideways.
///
/// The rate is deliberately not linear, which is exactly the kind of rule that
/// looks right in a screenshot and is wrong at the ends, at the seams between
/// two step sizes, and when a drag runs past the range and comes back.
@Suite("Scrubbing a duration")
struct DurationScrubTests {

    private let detent = DurationScrub.pointsPerDetent

    // MARK: - Direction and rate

    @Test("Dragging right makes the timer longer, left shorter")
    func direction() {
        #expect(DurationScrub.minutes(anchor: 5, translation: detent, fine: false) == 6)
        #expect(DurationScrub.minutes(anchor: 5, translation: -detent, fine: false) == 4)
    }

    @Test("A drag that has not moved leaves the number exactly as it was")
    func noMovement() {
        #expect(DurationScrub.minutes(anchor: 23, translation: 0, fine: false) == 23)
        #expect(DurationScrub.minutes(anchor: 23, translation: detent * 0.4, fine: false) == 23)
    }

    /// The point of the ladder: the same movement is worth a minute at five
    /// minutes, five at half an hour, and a quarter of an hour at two.
    @Test("One detent is worth more as the timer gets longer")
    func stepGrowsWithTheValue() {
        #expect(DurationScrub.minutes(anchor: 5, translation: detent, fine: false) == 6)
        #expect(DurationScrub.minutes(anchor: 30, translation: detent, fine: false) == 35)
        #expect(DurationScrub.minutes(anchor: 90, translation: detent, fine: false) == 105)
    }

    @Test("The seams between step sizes are single detents, not jumps")
    func seams() {
        #expect(DurationScrub.minutes(anchor: 9, translation: detent, fine: false) == 10)
        #expect(DurationScrub.minutes(anchor: 10, translation: -detent, fine: false) == 9)
        #expect(DurationScrub.minutes(anchor: 60, translation: detent, fine: false) == 75)
        #expect(DurationScrub.minutes(anchor: 75, translation: -detent, fine: false) == 60)
    }

    @Test("Half a detent rounds as the pointer crosses it, not after")
    func rounding() {
        #expect(DurationScrub.minutes(anchor: 5, translation: detent * 0.49, fine: false) == 5)
        #expect(DurationScrub.minutes(anchor: 5, translation: detent * 0.51, fine: false) == 6)
    }

    // MARK: - Option, for the values in between

    @Test("Option gives a detent per minute, wherever you are")
    func fineSteps() {
        #expect(DurationScrub.minutes(anchor: 30, translation: detent, fine: true) == 31)
        #expect(DurationScrub.minutes(anchor: 120, translation: detent * 3, fine: true) == 123)
    }

    @Test("Every minute in range is reachable with Option")
    func fineReachesEverything() {
        #expect(DurationScrub.fine.count == DurationDial.range.count)
        #expect(DurationScrub.fine.first == 1)
        #expect(DurationScrub.fine.last == 180)
    }

    // MARK: - The ends

    @Test("A drag cannot leave the range, however far it goes")
    func clamped() {
        #expect(DurationScrub.minutes(anchor: 25, translation: 100_000, fine: false) == 180)
        #expect(DurationScrub.minutes(anchor: 25, translation: -100_000, fine: false) == 1)
    }

    /// Coming back from the end must cost one detent, not the whole overshoot.
    @Test("Overshooting an end does not bank travel")
    func noBankedOvershoot() {
        let steps = CGFloat(DurationScrub.coarse.count)
        let far = detent * (steps + 40)
        #expect(DurationScrub.minutes(anchor: 25, translation: far, fine: false) == 180)
        #expect(DurationScrub.minutes(anchor: 25, translation: far - detent * 40, fine: false) == 180)
    }

    @Test("Nonsense from the gesture leaves the number alone")
    func nonFinite() {
        #expect(DurationScrub.minutes(anchor: 25, translation: .nan, fine: false) == 25)
        #expect(DurationScrub.minutes(anchor: 25, translation: .infinity, fine: false) == 25)
    }

    // MARK: - Starting between two detents

    /// A length can arrive off the ladder — Option-dragged, or a recent timer.
    /// It is kept until the drag moves, then joins the ladder from the nearest
    /// detent rather than from wherever the arithmetic would land.
    @Test("A drag that starts between detents joins at the nearest one")
    func offLadderAnchor() {
        #expect(DurationScrub.minutes(anchor: 23, translation: detent, fine: false) == 30)
        #expect(DurationScrub.minutes(anchor: 23, translation: -detent, fine: false) == 20)
    }

    // MARK: - Shape of the ladder

    @Test("The whole range is one sweep of the card")
    func sweepIsReasonable() {
        let travel = CGFloat(DurationScrub.coarse.count - 1) * detent
        #expect(travel < 400, "1 to 180 in one comfortable drag")
        #expect(DurationScrub.coarse.first == 1)
        #expect(DurationScrub.coarse.last == 180)
    }

    @Test("The ladder only ever goes up")
    func ladderIsMonotonic() {
        #expect(DurationScrub.coarse == DurationScrub.coarse.sorted())
        #expect(Set(DurationScrub.coarse).count == DurationScrub.coarse.count)
    }

    /// Whatever the drag does, the number may not go backwards while the
    /// pointer goes forwards — the flicker that makes a scrubber feel broken.
    @Test("The number never goes backwards while the pointer goes forwards")
    func monotonicUnderASweep() {
        var last = 0
        for points in stride(from: -600.0, through: 600.0, by: 2.0) {
            let value = DurationScrub.minutes(anchor: 25, translation: CGFloat(points), fine: false)
            #expect(value >= last)
            last = value
        }
    }
}
