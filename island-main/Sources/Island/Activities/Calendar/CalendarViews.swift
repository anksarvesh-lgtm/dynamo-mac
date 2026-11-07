import IslandCore
import SwiftUI

struct CalendarCompactTrailing: View {
    let event: CalendarActivity
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            Text(CalendarText.relative(event, now: ctx.date))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(IslandPalette.secondaryText)
        }
    }
}

struct CalendarExpanded: View {
    let event: CalendarActivity
    let id: String
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            EventLikeExpanded(symbol: "calendar", tint: IslandPalette.hex(event.calendarColorHex) ?? .red, title: event.title,
                              subtitle: "\(Formatters.time.string(from: event.start)) – \(Formatters.time.string(from: event.end)) · \(CalendarText.relative(event, now: ctx.date))" + (event.location.map { " · \($0)" } ?? ""),
                              id: id)
        }
    }
}

enum CalendarText {
    static func relative(_ e: CalendarActivity, now: Date) -> String {
        if now >= e.start && now < e.end { return "Now" }
        let mins = Int(ceil(e.start.timeIntervalSince(now) / 60))
        return mins <= 0 ? "Ended" : mins < 60 ? "in \(mins)m" : "in \(mins / 60)h"
    }
}
