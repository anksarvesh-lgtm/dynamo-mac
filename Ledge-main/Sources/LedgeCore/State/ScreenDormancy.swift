import Foundation

/// Why the screen is not worth polling: the displays are asleep, the session
/// is locked, or both.
///
/// This was one Boolean with four writers — `screensDidSleep`, `screensDidWake`,
/// `screenIsLocked`, `screenIsUnlocked` — and the two pairs are not the same
/// question. Locking the screen does not sleep the displays straight away, and
/// the displays wake on their own while the session stays locked: that wake
/// cleared the flag and started the 30 Hz pointer tracker and the 2 Hz
/// brightness watcher running behind a lock screen nobody could see past. The
/// mirror case is as bad — unlocking while the displays are still asleep.
///
/// So each reason is remembered on its own and dormancy is their union: dark
/// while *any* reason holds, awake only when none do.
public struct ScreenDormancy: Equatable, Sendable {

    public enum Reason: Equatable, Sendable, CaseIterable {
        /// `NSWorkspace.screensDidSleepNotification` / `screensDidWake`.
        case displaysAsleep
        /// `com.apple.screenIsLocked` / `screenIsUnlocked`.
        case sessionLocked
    }

    private var reasons: Set<Reason>

    public init() { reasons = [] }

    /// Whether anything says the screen is not worth polling.
    public var isDark: Bool { !reasons.isEmpty }

    public func holds(_ reason: Reason) -> Bool { reasons.contains(reason) }

    /// Records one reason arriving or leaving.
    ///
    /// - Returns: true when this changed the answer — the caller starts and
    ///   stops its pollers on that, and a repeated notification for a reason
    ///   already held must not be treated as a fresh transition.
    @discardableResult
    public mutating func set(_ reason: Reason, _ active: Bool) -> Bool {
        let before = isDark
        if active {
            reasons.insert(reason)
        } else {
            reasons.remove(reason)
        }
        return before != isDark
    }

    /// Teardown: everything forgotten, the screen treated as lit again.
    public mutating func clear() { reasons.removeAll() }
}
