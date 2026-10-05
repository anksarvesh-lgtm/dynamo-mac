//
//  CalendarActivitySource.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import Combine
import EventKit
import Foundation
import SwiftUI

/// Emits LiveActivity alerts for upcoming calendar events ("Next calendar event in N minutes").
/// Reuses CalendarManager.shared and EventKit observation.
@MainActor
public final class CalendarActivitySource: LiveActivitySource {
    public let identifier: String = "calendar_events"

    private let subject = PassthroughSubject<LiveActivity, Never>()
    public var activityPublisher: AnyPublisher<LiveActivity, Never> {
        subject.eraseToAnyPublisher()
    }

    private var cancellables = Set<AnyCancellable>()
    private var reminderTimer: Timer?
    private var notifiedEventIDs = Set<String>()
    private var isStarted = false

    public static let shared = CalendarActivitySource()

    private init() {}

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        // 1. Observe CalendarManager events updates
        CalendarManager.shared.$events
            .receive(on: RunLoop.main)
            .sink { [weak self] events in
                self?.evaluateUpcomingEvents(events)
            }
            .store(in: &cancellables)

        // 2. Periodic timer to evaluate time to next event (every 60s)
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateUpcomingEvents(CalendarManager.shared.events)
            }
        }

        evaluateUpcomingEvents(CalendarManager.shared.events)
    }

    public func stop() {
        reminderTimer?.invalidate()
        reminderTimer = nil
        cancellables.removeAll()
        isStarted = false
    }

    // MARK: - Evaluation Logic

    func evaluateUpcomingEvents(_ events: [EventModel]) {
        let now = Date()

        for event in events {
            if case .event = event.type {
                let startDate = event.start
                let timeInterval = startDate.timeIntervalSince(now)

                // If event is in the future between 0 and 15 minutes away
                if timeInterval > 0 && timeInterval <= 15 * 60 {
                    let minutes = max(1, Int(ceil(timeInterval / 60)))
                    let notificationKey = "\(event.id)_\(minutes <= 5 ? "5" : "15")"

                    guard !notifiedEventIDs.contains(notificationKey) else { continue }
                    notifiedEventIDs.insert(notificationKey)

                    emitUpcomingEventAlert(event: event, minutesAway: minutes)
                    break // Only emit for the closest upcoming event
                }
            }
        }
    }

    // MARK: - Activity Emission

    func emitUpcomingEventAlert(event: EventModel, minutesAway: Int) {
        let title = event.title.isEmpty ? String(localized: "Event") : event.title
        let subtitle = minutesAway == 1
            ? String(localized: "Starts in 1 minute")
            : String(localized: "Starts in \(minutesAway) minutes")
        let url = event.url

        let activity = LiveActivity(
            id: "cal_event_\(event.id)",
            source: identifier,
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: Color(nsColor: event.calendar.color),
            duration: 5.0,
            coalescingKey: "calendar_upcoming",
            payload: LiveActivityPayload(
                title: title,
                subtitle: subtitle,
                iconName: "calendar.badge.clock",
                body: event.notes?.isEmpty == false ? event.notes : String(localized: "Upcoming calendar event"),
                actionTitle: url != nil ? String(localized: "Join") : String(localized: "Open"),
                action: {
                    if let u = url {
                        NSWorkspace.shared.open(u)
                    } else if let calURL = event.calendarAppURL() {
                        NSWorkspace.shared.open(calURL)
                    }
                }
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
    }
}
