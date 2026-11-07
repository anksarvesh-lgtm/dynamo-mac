import Foundation

/// Pure decision logic used by app-side providers, kept here so it can be unit-tested.
public enum MediaSourceSelector {
    public struct Source: Equatable, Sendable {
        public var state: PlaybackState
        public var lastPlayingAt: Date
        public init(state: PlaybackState, lastPlayingAt: Date) {
            self.state = state
            self.lastPlayingAt = lastPlayingAt
        }
    }

    public static let pausedLinger: TimeInterval = 10 * 60

    /// The source that most recently started playing wins; otherwise the most recently paused one
    /// (within `pausedLinger`). Ties break on bundle id so the result is deterministic.
    public static func select(_ sources: [String: Source], now: Date) -> String? {
        func newest(_ s: [String: Source]) -> String? {
            s.max { a, b in a.value.lastPlayingAt != b.value.lastPlayingAt ? a.value.lastPlayingAt < b.value.lastPlayingAt : a.key > b.key }?.key
        }
        if let p = newest(sources.filter { $0.value.state == .playing }) { return p }
        return newest(sources.filter { now.timeIntervalSince($0.value.lastPlayingAt) < pausedLinger })
    }
}

public enum BatteryTransitions {
    public struct Reading: Equatable, Sendable {
        public var level: Int
        public var charging: Bool
        public var onAC: Bool
        public init(level: Int, charging: Bool, onAC: Bool) {
            self.level = level
            self.charging = charging
            self.onAC = onAC
        }
    }

    public static let lowThresholds = [20, 10, 5]

    /// Edge-triggered events between two readings. `shownLow` prevents repeating a threshold.
    public static func events(from old: Reading?, to new: Reading, shownLow: inout Set<Int>) -> [BatteryActivity.Reason] {
        guard let old else { return [] }
        var out: [BatteryActivity.Reason] = []
        if new.onAC && !old.onAC { out.append(.pluggedIn); shownLow.removeAll() }
        if new.onAC, new.level >= 100, old.level < 100 { out.append(.full) }
        if !new.onAC {
            for t in lowThresholds where new.level <= t && old.level > t && !shownLow.contains(t) {
                shownLow.insert(t)
                out.append(.low)
                break
            }
        }
        return out
    }
}
