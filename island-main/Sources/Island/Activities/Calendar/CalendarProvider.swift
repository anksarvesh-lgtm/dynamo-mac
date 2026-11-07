import EventKit
import Foundation
import IslandCore

/// Upcoming/current calendar event (opt-in; asks for Calendar access only when enabled).
/// Event-driven: EKEventStoreChanged plus one scheduled wake-up for the next boundary.
@MainActor
final class CalendarProvider {
    private let sink: (ActivityUpdate) -> Void
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var wakeTask: Task<Void, Never>?
    private(set) var status: String = "Off"
    static let lookahead: TimeInterval = 15 * 60

    init(sink: @escaping (ActivityUpdate) -> Void) { self.sink = sink }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.status = granted ? "On" : "Calendar access denied (System Settings › Privacy & Security › Calendars)"
                if granted { self?.refresh() }
            }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        wakeTask?.cancel()
        sink(.remove(id: "calendar"))
        status = "Off"
    }

    private func refresh() {
        wakeTask?.cancel()
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-12 * 3600), end: now.addingTimeInterval(24 * 3600), calendars: nil)
        let events = store.events(matching: predicate).filter { !$0.isAllDay && $0.endDate > now }.sorted { $0.startDate < $1.startDate }
        var nextWake: Date?
        if let e = events.first {
            if e.startDate.timeIntervalSince(now) <= Self.lookahead {
                let soon = e.startDate.timeIntervalSince(now) <= 120
                let inProgress = e.startDate <= now
                let c = CalendarActivity(title: e.title ?? "Event", start: e.startDate, end: e.endDate, location: e.location,
                                         calendarColorHex: e.calendar.flatMap { Self.hex($0.cgColor) })
                sink(.upsert(Activity(id: "calendar", kind: .calendar, priority: soon && !inProgress ? .normal : .low, content: .calendar(c))))
                nextWake = inProgress ? e.endDate : (soon ? e.startDate : e.startDate.addingTimeInterval(-120))
            } else {
                sink(.remove(id: "calendar"))
                nextWake = e.startDate.addingTimeInterval(-Self.lookahead)
            }
        } else {
            sink(.remove(id: "calendar"))
        }
        if let nextWake {
            let delay = max(1, nextWake.timeIntervalSinceNow + 1)
            wakeTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if !Task.isCancelled { self?.refresh() }
            }
        }
    }

    static func hex(_ c: CGColor?) -> String? {
        guard let c = c?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let comps = c.components, comps.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X", Int(comps[0] * 255), Int(comps[1] * 255), Int(comps[2] * 255))
    }
}
