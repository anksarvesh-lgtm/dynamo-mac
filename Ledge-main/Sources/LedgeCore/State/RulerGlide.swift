import CoreGraphics
import Foundation

/// What the duration rule does after the hand lets go.
///
/// A rule that stops dead on release is a rule you have to drag the whole way:
/// three hours at six points a minute is a long way. A flick should carry, the
/// way a scroll view carries, and then settle.
///
/// The arithmetic is here rather than in the view because it is where this
/// kind of thing goes wrong — a flick that never stops, one that stops so
/// abruptly it may as well not have glided, a bounce at the end of the range,
/// a value that keeps moving after the card has gone. Pure and clockless: the
/// caller supplies each step's elapsed time.
public struct RulerGlide: Equatable, Sendable {

    /// How much speed survives each second of gliding.
    ///
    /// The same shape as a scroll view's deceleration, tuned shorter: this is
    /// a control being set, not a page being read, and a long coast between
    /// the flick and the number settling makes the value feel out of reach.
    /// At 0.002 a flick has spent 99.8% of its speed after a second.
    public static let decay: Double = 0.002

    /// Below this the glide is over: a twelfth of a minute per second, which
    /// no longer moves the number.
    public static let restingSpeed: Double = DurationDial.pointsPerMinute / 12

    /// Under this, a release was a stop rather than a flick. Without it every
    /// careful adjustment ends with a small unwanted drift.
    public static let flickSpeed: Double = DurationDial.pointsPerMinute * 1.5

    /// The speed a release is carrying, from the two accounts of it.
    ///
    /// SwiftUI reports a velocity of its own, computed from the event stream
    /// rather than from the handful of values it chose to hand the view, and
    /// on a fast flick those are not the same number: the view may be told
    /// about the last inch of travel in one update, leaving nothing to measure
    /// a speed across. So the reported figure is the one to believe when there
    /// is one.
    ///
    /// It is absent — zero — for a gesture the system saw end at rest, which
    /// is also what a hand that stopped before letting go should produce, so
    /// consulting the measured estimate there costs nothing and covers the
    /// case where no velocity is reported at all.
    ///
    /// - Parameters:
    ///   - reported: the platform's own figure, points per second.
    ///   - measured: this view's estimate from its own samples.
    public static func release(reported: Double, measured: Double) -> Double {
        let sane = { (value: Double) in value.isFinite ? value : 0 }
        let believed = sane(reported)
        return believed == 0 ? sane(measured) : believed
    }

    /// Points per second at the moment of release, positive rightwards.
    public private(set) var velocity: Double

    /// Whether anything is still moving.
    public var isGliding: Bool { abs(velocity) >= Self.restingSpeed }

    /// - Parameter velocity: points per second, as measured over the last few
    ///   events of the drag.
    public init(velocity: Double) {
        self.velocity = abs(velocity) >= Self.flickSpeed && velocity.isFinite ? velocity : 0
    }

    /// Advances the glide by `elapsed` seconds.
    ///
    /// - Returns: how far the rule should move in that step, in points. Zero
    ///   once it has settled, so a caller that keeps stepping cannot creep.
    public mutating func step(_ elapsed: TimeInterval) -> CGFloat {
        guard isGliding, elapsed > 0, elapsed.isFinite else {
            velocity = 0
            return 0
        }
        // Exponential decay integrated over the step, so the distance covered
        // does not depend on how often the caller happens to call.
        let remaining = pow(Self.decay, elapsed)
        let distance = velocity * (remaining - 1) / log(Self.decay)
        velocity *= remaining
        if !isGliding { velocity = 0 }
        return CGFloat(distance)
    }

    /// The glide is over because something else ended it — the card closed,
    /// the rule was touched again, the range ran out.
    public mutating func stop() { velocity = 0 }

    /// Speed from the last samples of a drag, in points per second.
    ///
    /// Measured over a short window rather than the whole gesture: what the
    /// hand was doing at the end is what should carry, not the average of a
    /// drag that paused in the middle and then flicked.
    public static func velocity(
        from samples: [(translation: CGFloat, time: TimeInterval)],
        window: TimeInterval = 0.08
    ) -> Double {
        guard let last = samples.last else { return 0 }
        // The earliest sample still *inside* the window. Reaching for the last
        // one outside it measures the whole drag instead of its end, which is
        // the average of a wander and a flick rather than the flick.
        guard let first = samples.first(where: { last.time - $0.time <= window })
            ?? samples.first, first.time < last.time
        else { return 0 }
        let seconds = last.time - first.time
        guard seconds > 0, seconds.isFinite else { return 0 }
        return Double(last.translation - first.translation) / seconds
    }
}
