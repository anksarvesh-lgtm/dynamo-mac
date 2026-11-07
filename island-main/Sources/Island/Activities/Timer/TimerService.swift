import AppKit
import IslandCore

/// Owns countdown timers. Event-driven: one scheduled wake-up for the next completion, no per-second ticking
/// (the UI ticks itself via TimelineView only while visible).
@MainActor
final class TimerService {
    private let sink: (ActivityUpdate) -> Void
    private let bus: EventBus
    private var timers: [UUID: TimerActivity] = [:]
    private var wakeTask: Task<Void, Never>?
    static let finishedLinger: TimeInterval = 60

    init(bus: EventBus, sink: @escaping (ActivityUpdate) -> Void) {
        self.bus = bus
        self.sink = sink
        // If a timer's activity is dismissed anywhere (Island, debug, expiry), forget the timer too,
        // so it can't resurrect itself when it would have finished.
        bus.subscribe { [weak self] event in
            guard case .activityEnded(let id, .timer) = event, let self else { return }
            if let uuid = UUID(uuidString: String(id.dropFirst("timer.".count))), self.timers[uuid] != nil {
                self.timers[uuid] = nil
                self.scheduleWake()
            }
        }
    }

    var activeCount: Int { timers.count }

    func handle(_ command: TimerCommand) {
        let now = Date()
        switch command {
        case .start(let duration, let label):
            guard duration.isFinite, duration > 0, duration <= 24 * 3600 else { return }
            let t = TimerActivity(label: label.isEmpty ? "Timer" : label, duration: duration, state: .running(endDate: now.addingTimeInterval(duration)))
            timers[t.timerID] = t
            publish(t)
        case .pause(let id):
            guard var t = timers[id], case .running = t.state else { return }
            t.state = .paused(remaining: t.remaining(at: now))
            timers[id] = t
            publish(t)
        case .resume(let id):
            guard var t = timers[id], case .paused(let r) = t.state else { return }
            t.state = .running(endDate: now.addingTimeInterval(r))
            timers[id] = t
            publish(t)
        case .reset(let id):
            guard var t = timers[id] else { return }
            t.state = .paused(remaining: t.duration)
            timers[id] = t
            publish(t)
        case .stop(let id):
            timers[id] = nil
            sink(.remove(id: Self.activityID(id)))
        }
        scheduleWake()
    }

    static func activityID(_ id: UUID) -> String { "timer.\(id.uuidString)" }

    private func publish(_ t: TimerActivity) {
        let priority: ActivityPriority
        var expires: Date?
        switch t.state {
        case .finished(let at):
            priority = .high
            expires = at.addingTimeInterval(Self.finishedLinger)
        case .running: priority = .normal
        case .paused: priority = .low
        }
        sink(.upsert(Activity(id: Self.activityID(t.timerID), kind: .timer, priority: priority, content: .timer(t), expiresAt: expires)))
    }

    private func scheduleWake() {
        wakeTask?.cancel()
        let ends = timers.values.compactMap { t -> Date? in
            if case .running(let end) = t.state { return end }
            return nil
        }
        guard let next = ends.min() else { return }
        let delay = max(0, next.timeIntervalSinceNow)
        wakeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((delay + 0.02) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.fireDueTimers()
        }
    }

    private func fireDueTimers() {
        let now = Date()
        for (id, var t) in timers {
            guard case .running(let end) = t.state, end <= now else { continue }
            t.state = .finished(at: now)
            timers[id] = t
            publish(t)
            NSSound(named: "Glass")?.play()
            bus.publish(.timerFinished(label: t.label))
            // Forget it after the linger window (the manager expires the activity itself).
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.finishedLinger * 1_000_000_000))
                if case .finished = self?.timers[id]?.state { self?.timers[id] = nil }
            }
        }
        scheduleWake()
    }
}
