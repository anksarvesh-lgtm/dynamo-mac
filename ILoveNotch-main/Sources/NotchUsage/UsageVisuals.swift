// SPDX-License-Identifier: MIT
import SwiftUI

/// A limit's colors: the provider's own until it gets close, then amber at 80% and red at 95%.
struct Tone {
    let start: Color
    let end: Color

    static func of(_ fraction: Double, _ style: ProviderStyle) -> Tone {
        if fraction >= 0.95 { return Tone(start: Color(hex: 0xEF44_44), end: Color(hex: 0xFCA5_A5)) }
        if fraction >= 0.8 { return Tone(start: Color(hex: 0xF59E_0B), end: Color(hex: 0xFDE6_8A)) }
        return Tone(start: style.start, end: style.end)
    }
}

/// A limit as a ring: an angular gradient that glows faintly, with the value in the middle. It fills
/// from empty when it first appears and springs to each new value.
struct UsageRing: View {
    let meter: Meter
    let style: ProviderStyle
    var size: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0

    var body: some View {
        let fraction = min(max(meter.fraction, 0), 1)
        let tone = Tone.of(meter.fraction, style)
        let width = size * 0.12
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: width)
            Circle()
                .trim(from: 0, to: max(shown, 0.001))
                .stroke(
                    AngularGradient(
                        colors: [tone.start, tone.end], center: .center, startAngle: .zero,
                        endAngle: .degrees(max(360 * shown, 1))),
                    style: StrokeStyle(lineWidth: width, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tone.end.opacity(0.5), radius: size * 0.08)
            Text(meter.headline)
                .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(width)
                .contentTransition(.numericText(value: fraction))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.82)) { shown = fraction }
        }
        .onChange(of: fraction) { _, value in
            withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8)) { shown = value }
        }
        .accessibilityElement()
        .accessibilityLabel("\(meter.label), \(meter.headline)")
    }
}

/// A limit as a bar with the same colors as its ring.
struct MeterBar: View {
    let meter: Meter
    let style: ProviderStyle
    var height: CGFloat = 5

    var body: some View {
        let tone = Tone.of(meter.fraction, style)
        let fill = LinearGradient(colors: [tone.start, tone.end], startPoint: .leading, endPoint: .trailing)
        Capsule()
            .fill(.white.opacity(0.1))
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { track in
                    Capsule()
                        .fill(fill)
                        .frame(width: max(height, track.size.width * min(max(meter.fraction, 0), 1)))
                        .shadow(color: tone.end.opacity(0.4), radius: 2)
                }
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: meter.fraction)
            .accessibilityHidden(true)
    }
}

/// A plan name like "Max" or "Pro".
struct PlanPill: View {
    let plan: String
    let style: ProviderStyle

    var body: some View {
        Text(plan)
            .font(.system(size: 9, weight: .bold))
            .textCase(.uppercase)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(style.start.opacity(0.28), in: Capsule())
            .foregroundStyle(style.end)
    }
}

/// Whether a limit will last until it resets, from OpenUsage's burn-rate projection. Without
/// `showsWords`, just its dot, with the words in the tooltip.
struct PaceBadge: View {
    let meter: Meter
    let now: Date
    var showsWords = true

    var body: some View {
        if let resetsAt = meter.resetsAt, let period = meter.period, let pace = meter.pace(now: now) {
            let (color, text) = Self.describe(pace.status, meter: meter, resetsAt: resetsAt, period: period, now: now)
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6).shadow(color: color, radius: 2)
                if showsWords { Text(text).lineLimit(1) }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .help(text)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
        }
    }

    private static func describe(_ status: Pace.Status, meter: Meter, resetsAt: Date, period: TimeInterval, now: Date)
        -> (Color, String)
    {
        switch status {
        case .ahead:
            return (Color(hex: 0x60A5_FA), "Plenty left")
        case .onTrack:
            return (Color(hex: 0xF59E_0B), "Cutting it close")
        case .behind:
            let runOut = Pace.secondsToRunOut(
                used: meter.used, limit: meter.limit, resetsAt: resetsAt, periodDuration: period, now: now)
            let label = runOut.flatMap(Formatters.compactDuration).map { "Runs out in \($0)" }
            return (Color(hex: 0xEF44_44), label ?? "Over pace")
        }
    }
}

/// Refresh, spinning while anything refreshes.
struct RefreshButton: View {
    let spinning: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let spins = spinning && !reduceMotion
        let spin: Animation = spins ? .linear(duration: 1).repeatForever(autoreverses: false) : .default
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .rotationEffect(.degrees(spins ? 360 : 0))
                .animation(spin, value: spinning)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.75))
        .help("Refresh now")
        .accessibilityLabel("Refresh")
    }
}

extension Meter {
    /// The value to headline: a percentage, or the amount used for dollar and count limits.
    var headline: String {
        switch format {
        case .percent: MetricFormatter.number(used, kind: .percent, style: .tray)
        case .dollars: MetricFormatter.number(used, kind: .dollars, style: .tray)
        case .count: MetricFormatter.number(used, kind: .count, style: .tray)
        }
    }

    /// Used of limit, like "$42 of $100", or the percentage.
    var detail: String {
        switch format {
        case .percent:
            return MetricFormatter.number(used, kind: .percent, style: .row)
        case .dollars:
            return "\(MetricFormatter.number(used, kind: .dollars, style: .row)) of "
                + MetricFormatter.number(limit, kind: .dollars, style: .row)
        case .count(let suffix):
            let unit = suffix.isEmpty ? "" : " \(suffix)"
            return "\(MetricFormatter.number(used, kind: .count, style: .row)) of "
                + "\(MetricFormatter.number(limit, kind: .count, style: .row))\(unit)"
        }
    }

    func resetLabel(now: Date) -> String? {
        resetsAt.flatMap { Formatters.resetRelativeLabel(until: $0, now: now) }
    }

    /// Whether it will last until it resets, when the provider says how long its window is.
    func pace(now: Date) -> Pace.Result? {
        guard let resetsAt, let period else { return nil }
        return Pace.evaluate(used: used, limit: limit, resetsAt: resetsAt, periodDuration: period, now: now)
    }
}
