import Foundation
import Observation

/// The single source of truth for what the Island shows.
///
/// Every feature submits `ActivityUpdate`s here. The Island UI only *observes* `primary` and
/// `secondaries`; no feature talks to the window or views.
@MainActor
@Observable
public final class ActivityManager {
    public struct LogEntry: Identifiable, Sendable {
        public let id: UInt64
        public let date: Date
        public let message: String
    }

    public private(set) var activities: [String: Activity] = [:]
    public private(set) var ordered: [Activity] = []
    public private(set) var primary: Activity?
    public private(set) var secondaries: [Activity] = []
    public private(set) var previousPrimaryID: String?
    public private(set) var pinnedID: String?
    public private(set) var log: [LogEntry] = []

    public var maxSecondaries = 2 { didSet { recompute() } }
    public var maxActivities = 32
    /// Kinds the user disabled are dropped on arrival and purged when toggled off.
    public var enabledKinds: Set<ActivityKind> = Set(ActivityKind.allCases) {
        didSet {
            for (id, a) in activities where !enabledKinds.contains(a.kind) { removeInternal(id) }
            recompute()
        }
    }
    /// Disable for deterministic tests; then call `purgeExpired(now:)` manually.
    public var schedulesExpiry = true

    /// Called synchronously after every change to the ordered activities (primary, secondaries, content).
    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored public let bus: EventBus
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var sequence: UInt64 = 0
    @ObservationIgnored private var logSequence: UInt64 = 0
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    public init(bus: EventBus? = nil, clock: @escaping () -> Date = Date.init) {
        self.bus = bus ?? EventBus()
        self.clock = clock
    }

    // MARK: Input

    public func submit(_ update: ActivityUpdate) {
        let now = clock()
        switch update {
        case .upsert(let activity):
            upsert(activity, now: now)
        case .remove(let id):
            removeInternal(id)
        case .complete(let id, let final, let linger):
            if var final, linger > 0 {
                final.expiresAt = now.addingTimeInterval(linger)
                if final.id != id { removeInternal(id) }
                upsert(final, now: now)
            } else if linger > 0, var existing = activities[id] {
                existing.expiresAt = now.addingTimeInterval(linger)
                activities[id] = existing
            } else {
                removeInternal(id)
            }
        }
        recompute()
    }

    /// User selection. The pinned activity outranks normal/low activities until it ends.
    public func select(id: String?) {
        guard id == nil || activities[id!] != nil else { return }
        pinnedID = id
        record("pin \(id ?? "none")")
        recompute()
    }

    /// Cycle the primary through the visible activities (used by keyboard / debug "Switch Activity").
    public func selectNext() {
        guard ordered.count > 1 else { return }
        // Cycle in arrival order, which (unlike rank order) doesn't change when the selection does.
        let visible = Array(ordered.prefix(maxSecondaries + 1)).sorted { $0.sequence < $1.sequence }
        guard let current = primary, let idx = visible.firstIndex(where: { $0.id == current.id }) else { return }
        select(id: visible[(idx + 1) % visible.count].id)
    }

    public func dismiss(id: String) {
        removeInternal(id)
        recompute()
    }

    public func removeAll() {
        for id in Array(activities.keys) { removeInternal(id) }
        pinnedID = nil
        recompute()
    }

    public func purgeExpired(now: Date? = nil) {
        let now = now ?? clock()
        var changed = false
        for (id, a) in activities {
            if let exp = a.expiresAt, exp <= now {
                removeInternal(id)
                changed = true
            }
        }
        if changed { recompute() } else { scheduleExpiry() }
    }

    public func activity(id: String) -> Activity? { activities[id] }

    // MARK: Internals

    private func upsert(_ incoming: Activity, now: Date) {
        guard enabledKinds.contains(incoming.kind) else { return }
        switch ActivityValidator.sanitize(incoming, now: now) {
        case .failure(let reason):
            record("rejected \(incoming.id): \(reason)")
            bus.publish(.activityRejected(reason: reason.description))
        case .success(var a):
            if let existing = activities[a.id] {
                a.sequence = existing.sequence
                a.createdAt = existing.createdAt
                a.updatedAt = now
                activities[a.id] = a
            } else {
                sequence += 1
                a.sequence = sequence
                a.createdAt = now
                a.updatedAt = now
                activities[a.id] = a
                record("start \(a.id) [\(a.priority)]")
                bus.publish(.activityStarted(id: a.id, kind: a.kind))
                enforceCapacity()
            }
        }
    }

    private func enforceCapacity() {
        guard activities.count > maxActivities else { return }
        let victims = ActivityOrdering.sort(Array(activities.values), pinnedID: pinnedID).suffix(activities.count - maxActivities)
        for v in victims { removeInternal(v.id) }
    }

    private func removeInternal(_ id: String) {
        guard let removed = activities.removeValue(forKey: id) else { return }
        if pinnedID == id { pinnedID = nil }
        record("end \(id)")
        bus.publish(.activityEnded(id: id, kind: removed.kind))
    }

    private func recompute() {
        let sorted = ActivityOrdering.sort(Array(activities.values), pinnedID: pinnedID)
        let newPrimary = sorted.first
        if newPrimary?.id != primary?.id {
            if let old = primary?.id { previousPrimaryID = old }
            record("primary \(primary?.id ?? "none") → \(newPrimary?.id ?? "none")")
            bus.publish(.primaryChanged(from: primary?.id, to: newPrimary?.id))
        }
        if ordered != sorted { ordered = sorted }
        if primary != newPrimary { primary = newPrimary }
        let newSecondaries = Array(sorted.dropFirst().prefix(maxSecondaries))
        if secondaries != newSecondaries { secondaries = newSecondaries }
        scheduleExpiry()
        onChange?()
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        guard schedulesExpiry, let next = activities.values.compactMap(\.expiresAt).min() else { return }
        let delay = max(0, next.timeIntervalSince(clock()))
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((delay + 0.01) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.purgeExpired()
        }
    }

    private func record(_ message: String) {
        logSequence += 1
        log.append(LogEntry(id: logSequence, date: clock(), message: message))
        if log.count > 100 { log.removeFirst(log.count - 100) }
    }
}
