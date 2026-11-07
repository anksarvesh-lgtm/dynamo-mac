// SPDX-License-Identifier: MIT
import SwiftUI

/// The timer tab: countdown presets or a running countdown, a stopwatch with laps, and keep awake.
struct TimerView: View {
    let timer: TimerFeature

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                modeButton("Timer", .countdown)
                modeButton("Stopwatch", .stopwatch)
                modeButton("Keep Awake", .keepAwake, lit: timer.keepsAwake)
            }
            switch timer.mode {
            case .countdown: countdown
            case .stopwatch: stopwatch
            case .keepAwake: keepAwake
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// `lit` marks a mode that's running while another is showing.
    private func modeButton(_ title: String, _ mode: TimerFeature.Mode, lit: Bool = false) -> some View {
        Button {
            timer.mode = mode
        } label: {
            HStack(spacing: 4) {
                if lit { Image(systemName: "cup.and.saucer.fill").font(.system(size: 9)) }
                Text(title)
            }
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(timer.mode == mode ? .white.opacity(0.16) : .clear, in: Capsule())
        .accessibilityLabel(lit ? "\(title), on" : title)
        .accessibilityAddTraits(timer.mode == mode ? .isSelected : [])
    }

    /// How long to stay awake, or how long is left. The smallest notch shrinks the clock and drops
    /// the line of explanation.
    @ViewBuilder private var keepAwake: some View {
        if let until = timer.awakeUntil {
            ViewThatFits(in: .vertical) {
                awake(until: until, compact: false)
                awake(until: until, compact: true)
            }
        } else {
            ViewThatFits(in: .vertical) {
                awakePresets(explained: true)
                awakePresets(explained: false)
            }
        }
    }

    private func awake(until: Date, compact: Bool) -> some View {
        VStack(spacing: 8) {
            if until == .distantFuture {
                Label("Awake until you turn it off", systemImage: "cup.and.saucer.fill")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .padding(.vertical, compact ? 4 : 12)
            } else {
                // Redraws once a second, and only while it's on screen.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    RollingTime(until.timeIntervalSince(context.date), countsDown: true)
                        .font(.system(size: compact ? 30 : 40, weight: .semibold, design: .rounded))
                }
                if !compact {
                    Text("Your Mac and its display stay awake until then.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            HStack(spacing: 18) {
                if until != .distantFuture { control("+30 min") { timer.extendAwake() } }
                control("Turn Off", timer.allowSleep)
            }
        }
    }

    private func awakePresets(explained: Bool) -> some View {
        VStack(spacing: 10) {
            if explained {
                Text("Keep your Mac and its display from sleeping through a download, a build, or a talk.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            HStack(spacing: 8) {
                ForEach(TimerFeature.awakePresets, id: \.self) { seconds in
                    awakePreset(seconds < 3600 ? "\(Int(seconds / 60)) min" : "\(Int(seconds / 3600)) hr") {
                        timer.keepAwake(for: seconds)
                    }
                    .accessibilityLabel("Keep awake for \(formatTime(seconds))")
                }
                awakePreset(nil) { timer.keepAwake(for: nil) }
                    .help("Until you turn it off")
                    .accessibilityLabel("Keep awake until you turn it off")
            }
        }
        .padding(.top, 4)
    }

    /// A duration to stay awake for; nil for "until you turn it off".
    private func awakePreset(_ title: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let title { Text(title) } else { Image(systemName: "infinity") }
            }
            .font(.callout.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    /// The smallest notch shrinks the clock and drops the progress bar, and shortens the presets.
    @ViewBuilder private var countdown: some View {
        if let countdown = timer.countdown {
            // Redraws once a second, and only while running on screen.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = countdown.remaining(at: context.date)
                ViewThatFits(in: .vertical) {
                    running(countdown, left: left, compact: false)
                    running(countdown, left: left, compact: true)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Timer, \(formatTime(left)) left")
            }
        } else {
            ViewThatFits(in: .vertical) {
                presets(height: 34)
                presets(height: 28)
            }
        }
    }

    private func running(_ countdown: Countdown, left: TimeInterval, compact: Bool) -> some View {
        VStack(spacing: 8) {
            RollingTime(left, countsDown: true)
                .font(.system(size: compact ? 30 : 40, weight: .semibold, design: .rounded))
                .opacity(countdown.isRunning ? 1 : 0.5)
            if !compact {
                ProgressView(value: countdown.total - left, total: countdown.total)
                    .tint(.white)
                    .frame(maxWidth: 260)
            }
            HStack(spacing: 18) {
                control(countdown.isRunning ? "Pause" : "Resume") {
                    countdown.isRunning ? timer.pause() : timer.resume()
                }
                control("+1 min", timer.addMinute)
                control("Cancel", timer.cancel)
            }
        }
    }

    private func presets(height: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(TimerFeature.presets, id: \.self) { seconds in
                Button {
                    timer.start(seconds)
                } label: {
                    Text(seconds < 3600 ? "\(Int(seconds / 60)) min" : "1 hr")
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: height)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start a \(formatTime(seconds)) timer")
            }
        }
        .padding(.top, 4)
    }

    /// Laps go under the clock, or beside it when the notch is too short to show a few of them, and
    /// the smallest notch shrinks the clock.
    private var stopwatch: some View {
        let watch = timer.stopwatch
        return ViewThatFits(in: .vertical) {
            VStack(spacing: 8) {
                stopwatchClock(watch)
                if !watch.laps.isEmpty { lapList(watch.laps).frame(idealHeight: 44) }
            }
            HStack(alignment: .top, spacing: 16) {
                stopwatchClock(watch)
                if !watch.laps.isEmpty { lapList(watch.laps) }
            }
            HStack(alignment: .top, spacing: 16) {
                stopwatchClock(watch, compact: true)
                if !watch.laps.isEmpty { lapList(watch.laps) }
            }
        }
    }

    private func stopwatchClock(_ watch: Stopwatch, compact: Bool = false) -> some View {
        // Tenths of a second need ten redraws a second, only while running on screen.
        TimelineView(.periodic(from: .now, by: watch.isRunning ? 0.1 : 3600)) { context in
            VStack(spacing: 8) {
                RollingTime(watch.elapsed(at: context.date), tenths: true)
                    .font(.system(size: compact ? 30 : 40, weight: .semibold, design: .rounded))
                HStack(spacing: 18) {
                    control(watch.isRunning ? "Pause" : "Start") { timer.toggleStopwatch() }
                    if watch.isRunning {
                        control("Lap") { timer.lap() }
                    } else {
                        control("Reset", timer.resetStopwatch).disabled(watch.elapsed(at: context.date) == 0)
                    }
                }
            }
        }
    }

    /// Every lap, newest first, scrolling once they outgrow the notch. It sits outside the timeline,
    /// so it isn't rebuilt ten times a second.
    private func lapList(_ laps: [TimeInterval]) -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(laps.indices.reversed(), id: \.self) { index in
                    let split = laps[index] - (index > 0 ? laps[index - 1] : 0)
                    HStack {
                        Text("Lap \(index + 1)")
                        Spacer()
                        Text(formatTime(split, tenths: true)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
            .padding(.vertical, 6)
        }
        .fadingEdges()
        .frame(maxWidth: 220)
    }

    private func control(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.white.opacity(0.14), in: Capsule())
    }
}
