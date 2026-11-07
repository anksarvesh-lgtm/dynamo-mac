import IslandCore
import SwiftUI

/// What the Island shows when expanded with no live activity: time + quick actions.
struct HomeView: View {
    @Environment(\.islandCommands) private var send

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TimelineView(.everyMinute) { ctx in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.system(size: 28, weight: .light).monospacedDigit())
                        .foregroundStyle(.white)
                    Text(ctx.date, format: .dateTime.weekday(.wide).month().day())
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(IslandPalette.secondaryText)
                }
                .fixedSize()
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                IslandPillButton(title: "5m", symbol: "timer", tint: IslandPalette.timer) { send(.timer(.start(duration: 300, label: "Timer"))) }
                IslandPillButton(title: "25m", symbol: nil, tint: IslandPalette.timer) { send(.timer(.start(duration: 1500, label: "Focus"))) }
                IslandIconButton(symbol: "magnifyingglass", size: 13, label: "Search") { send(.ui(.toggleSearch)) }
                IslandIconButton(symbol: "gearshape.fill", size: 13, label: "Settings") { send(.openSettings) }
            }
            .fixedSize()
        }
    }
}
