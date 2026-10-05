//
//  CalendarLiveActivityView.swift
//  LiquidDynamo
//
//  Step 3 Complex View Migration: Calendar Events & Meeting Alerts.
//  Provides both compact top band wing presentation and organic below-notch blooming droplet presentation.
//

import AppKit
import Combine
import Defaults
import EventKit
import Foundation
import SwiftUI

public struct CalendarLiveActivityView: View {
    @ObservedObject var calendarManager = CalendarManager.shared
    @ObservedObject var island = IslandController.shared

    public var isCompactWing: Bool = false
    public var isLeadingWing: Bool = true
    public var customTitle: String? = nil
    public var customSubtitle: String? = nil
    public var onDismiss: () -> Void = {}

    public init(
        isCompactWing: Bool = false,
        isLeadingWing: Bool = true,
        customTitle: String? = nil,
        customSubtitle: String? = nil,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.isCompactWing = isCompactWing
        self.isLeadingWing = isLeadingWing
        self.customTitle = customTitle
        self.customSubtitle = customSubtitle
        self.onDismiss = onDismiss
    }

    private var nextEvent: EventModel? {
        calendarManager.events.first { event in
            event.start > Date().addingTimeInterval(-60)
        }
    }

    private var eventTitle: String {
        customTitle ?? nextEvent?.title ?? "Upcoming Event"
    }

    private var eventTimeText: String {
        if let custom = customSubtitle { return custom }
        guard let start = nextEvent?.start else { return "Soon" }
        let diff = start.timeIntervalSince(Date())
        if diff <= 0 {
            return "Now"
        } else if diff < 3600 {
            let mins = max(1, Int(diff / 60))
            return "in \(mins)m"
        } else {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: start)
        }
    }

    private var tintColor: Color {
        Color.blue
    }

    public var body: some View {
        if isCompactWing {
            compactWingLayout
        } else {
            bloomingDropletLayout
        }
    }

    // MARK: - 1. Compact Wing Presentation (Top Band)

    private var compactWingLayout: some View {
        HStack(spacing: 5) {
            if isLeadingWing {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tintColor)
                Text(eventTitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else {
                Text(eventTimeText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(tintColor)
                Image(systemName: "clock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tintColor)
            }
        }
        .padding(.horizontal, 6)
        .avoidsNotch(id: isLeadingWing ? "CalendarWingL" : "CalendarWingR")
    }

    // MARK: - 2. Blooming Droplet Presentation (Below Notch)

    private var bloomingDropletLayout: some View {
        HStack(spacing: 12) {
            // Calendar Date Badge
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tintColor.opacity(0.2))
                    .frame(width: 32, height: 32)

                VStack(spacing: 0) {
                    Text(currentMonthShort)
                        .font(.system(size: 7.5, weight: .black))
                        .foregroundStyle(tintColor)
                    Text("\(currentDayNumber)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }

            // Event Title & Start Time
            VStack(alignment: .leading, spacing: 2) {
                Text(eventTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(eventTimeText)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(tintColor)

                    if let location = nextEvent?.location, !location.isEmpty {
                        Text("• \(location)")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            // Join / Open Button
            Button(action: {
                if let url = nextEvent?.url {
                    NSWorkspace.shared.open(url)
                } else {
                    island.setExpanded(view: .calendar)
                }
                onDismiss()
            }) {
                Text("Join")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tintColor))
            }
            .buttonStyle(.plain)

            // Dismiss Button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .avoidsNotch(id: "CalendarBloomingDroplet")
    }

    private var currentMonthShort: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: Date()).uppercased()
    }

    private var currentDayNumber: Int {
        Calendar.current.component(.day, from: Date())
    }
}
