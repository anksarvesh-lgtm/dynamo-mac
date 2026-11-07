import IslandCore
import SwiftUI

private struct TimerClock<Content: View>: View {
    let timer: TimerActivity
    @ViewBuilder var content: (Date) -> Content
    @Environment(\.islandContentActive) private var active
    var body: some View {
        if case .running = timer.state {
            TimelineView(.periodic(from: .now, by: clockInterval(active: active))) { ctx in content(ctx.date) }
        } else {
            content(Date())
        }
    }
}

struct TimerCompactLeading: View {
    let timer: TimerActivity
    let id: String
    @Environment(\.islandNamespace) private var ns
    var body: some View {
        TimerClock(timer: timer) { now in
            ZStack {
                ProgressRing(fraction: 1 - timer.fraction(at: now), tint: IslandPalette.timer, lineWidth: 2.2)
                    .frame(width: 18, height: 18)
                if case .finished = timer.state {
                    Image(systemName: "bell.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(IslandPalette.timer)
                }
            }
            .islandMatched("icon-\(id)", in: ns)
        }
    }
}

struct TimerCompactTrailing: View {
    let timer: TimerActivity
    var body: some View {
        TimerClock(timer: timer) { now in
            Text(timerText(now))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(IslandPalette.timer)
                
        }
    }

    private func timerText(_ now: Date) -> String {
        if case .finished = timer.state { return "Done" }
        return DurationFormatter.clock(timer.remaining(at: now).rounded(.up))
    }
}

struct TimerMinimal: View {
    let timer: TimerActivity
    var body: some View {
        TimerClock(timer: timer) { now in
            ZStack {
                ProgressRing(fraction: 1 - timer.fraction(at: now), tint: IslandPalette.timer, lineWidth: 2)
                Image(systemName: "timer").font(.system(size: 8, weight: .bold)).foregroundStyle(IslandPalette.timer)
            }
            .padding(5)
        }
    }
}

struct TimerExpanded: View {
    let timer: TimerActivity
    let id: String
    @Environment(\.islandNamespace) private var ns
    @Environment(\.islandCommands) private var send

    var body: some View {
        TimerClock(timer: timer) { now in
            HStack(spacing: 16) {
                ZStack {
                    ProgressRing(fraction: 1 - timer.fraction(at: now), tint: IslandPalette.timer, lineWidth: 4)
                    Image(systemName: isFinished ? "bell.fill" : "timer")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(IslandPalette.timer)
                }
                .frame(width: 46, height: 46)
                .islandMatched("icon-\(id)", in: ns)

                VStack(alignment: .leading, spacing: 2) {
                    Text(timer.label.isEmpty ? "Timer" : timer.label)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(IslandPalette.secondaryText)
                    Text(isFinished ? "Done" : DurationFormatter.clock(timer.remaining(at: now).rounded(.up)))
                        .font(.system(size: 34, weight: .light).monospacedDigit())
                        .foregroundStyle(IslandPalette.timer)
                        
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                controls
            }
        }
    }

    private var isFinished: Bool { if case .finished = timer.state { true } else { false } }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 10) {
            switch timer.state {
            case .running:
                IslandIconButton(symbol: "pause.fill", size: 15, label: "Pause timer", prominent: true) { send(.timer(.pause(timer.timerID))) }
            case .paused:
                IslandIconButton(symbol: "play.fill", size: 15, label: "Resume timer", prominent: true) { send(.timer(.resume(timer.timerID))) }
            case .finished:
                IslandPillButton(title: "+1 min", symbol: "plus", tint: IslandPalette.timer) {
                    send(.timer(.stop(timer.timerID)))
                    send(.timer(.start(duration: 60, label: timer.label)))
                }
            }
            if !isFinished {
                IslandIconButton(symbol: "arrow.counterclockwise", size: 13, label: "Reset timer") { send(.timer(.reset(timer.timerID))) }
            }
            IslandIconButton(symbol: "xmark", size: 13, label: isFinished ? "Dismiss timer" : "Stop timer") { send(.timer(.stop(timer.timerID))) }
        }
    }
}
