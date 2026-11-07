// SPDX-License-Identifier: MIT
import SwiftUI

/// Download in Vercel's Geist blue and upload in its amber: the dark-mode pair NetSpeed's palette
/// validator picked to tell apart with any color vision, each with a lighter step for gradients.
enum NetworkTint {
    static let down = Color(red: 0.196, green: 0.569, blue: 1)  // #3291FF
    static let downLight = Color(red: 0.51, green: 0.76, blue: 1)  // #82C2FF
    static let up = Color(red: 0.851, green: 0.467, blue: 0.024)  // #D97706
    static let upLight = Color(red: 0.98, green: 0.73, blue: 0.33)  // #FABA54

    /// Lit from the top, like the Sound tab's faders.
    static var downFill: LinearGradient { lit(down, from: downLight) }
    static var upFill: LinearGradient { lit(up, from: upLight) }

    private static func lit(_ color: Color, from light: Color) -> LinearGradient {
        LinearGradient(colors: [light, color], startPoint: .top, endPoint: .bottom)
    }
}

/// The Network tab: the speed now over a graph of the last minute, beside the history as bars by
/// the hour, day, or month. A short notch keeps the numbers and the bars and drops the captions.
struct NetworkView: View {
    let network: NetworkFeature

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 140
            HStack(spacing: 8) {
                LiveCard(network: network, compact: compact)
                    .frame(width: min(max(proxy.size.width * 0.38, 132), 230))
                HistoryCard(network: network, compact: compact)
            }
        }
    }
}

/// Cards like the AI Usage tiles: a faint tint from the top corner and a hairline edge.
private struct Card: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [tint.opacity(0.16), .white.opacity(0.03)], startPoint: .topLeading,
                        endPoint: .bottomTrailing))
            )
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.08)))
    }
}

/// The download's speed, big, with the upload's under it, over the last minute's graph.
private struct LiveCard: View {
    let network: NetworkFeature
    let compact: Bool

    var body: some View {
        let rate = network.rate
        let down = NetworkFeature.speed(rate.down)
        let up = NetworkFeature.speed(rate.up)
        let padding: CGFloat = compact ? 8 : 10
        VStack(alignment: .leading, spacing: compact ? 1 : 3) {
            if !compact {
                // The minute's peak joins the caption where there's room for both.
                ViewThatFits(in: .horizontal) {
                    HStack {
                        label("Download", color: NetworkTint.down)
                        Spacer(minLength: 6)
                        if let peak = network.recent.map(\.rate.down).max(), peak > 0 {
                            let speed = NetworkFeature.speed(peak)
                            Text("peak \(speed.value) \(speed.unit)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                                .fixedSize()
                        }
                    }
                    label("Download", color: NetworkTint.down)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if compact {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(NetworkTint.downLight)
                }
                // ponytail: no rolling digits. A numericText transition on a number that changes every
                // second kept the open tab at 12-51% of a core (0.5% without); roll them only if that changes.
                Text(down.value)
                    .font(.system(size: compact ? 22 : 32, weight: .bold, design: .rounded))
                Text(down.unit)
                    .font(.system(size: compact ? 10 : 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            HStack(spacing: 3) {
                Image(systemName: "arrow.up").font(.system(size: compact ? 8 : 9, weight: .heavy))
                Text("\(up.value) \(up.unit)")
            }
            .font(.system(size: compact ? 10.5 : 13, weight: .semibold, design: .rounded))
            .foregroundStyle(NetworkTint.upLight)
            Sparkline(samples: network.recent)
                .padding(.horizontal, -padding)
                .padding(.bottom, -padding)
                .padding(.top, compact ? 2 : 6)
        }
        .monospacedDigit()
        .lineLimit(1)
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(Card(tint: NetworkTint.down))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Network speed")
        .accessibilityValue("\(Self.spoken(down)) down, \(Self.spoken(up)) up")
    }

    private func label(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color, radius: 2)
            Text(title).textCase(.uppercase).tracking(0.6)
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.white.opacity(0.5))
        .fixedSize()
    }

    static func spoken(_ speed: (value: String, unit: String)) -> String {
        "\(speed.value) \(speed.unit.replacingOccurrences(of: "/s", with: " per second"))"
    }
}

/// The last minute of speed: the download as a glowing blue area with a dot on its latest reading,
/// and the upload as an amber line. Scaled to the minute's peak, never below 100 KB/s, so idle
/// chatter stays a ripple. Drawn once per reading, never animated in between.
private struct Sparkline: View {
    let samples: [RateSample]

    var body: some View {
        Canvas { context, size in
            let baseline = Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1))
            context.fill(baseline, with: .color(.white.opacity(0.06)))
            guard samples.count > 1, let latest = samples.last?.at else { return }
            let peak = max(samples.map { max($0.rate.down, $0.rate.up) }.max() ?? 0, 100_000)
            let top: CGFloat = 8
            let width = size.width - 5  // room for the dot on the latest reading
            func points(_ value: (Rate) -> Double) -> [CGPoint] {
                samples.map { sample in
                    CGPoint(
                        x: width * (1 - latest.timeIntervalSince(sample.at) / NetworkFeature.window),
                        y: size.height - 1 - (size.height - top - 1) * min(value(sample.rate) / peak, 1))
                }
            }
            let down = points(\.down)
            let line = Self.smooth(down)
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: down[down.count - 1].y))  // on past the dot to the edge
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: down[0].x, y: size.height))
            area.closeSubpath()
            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [NetworkTint.down.opacity(0.5), NetworkTint.down.opacity(0.02)]),
                    startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(
                Self.smooth(points(\.up)), with: .color(NetworkTint.up),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            context.drawLayer { glow in
                glow.addFilter(.shadow(color: NetworkTint.down, radius: 3))
                glow.stroke(
                    line, with: .color(NetworkTint.downLight),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                let head = down[down.count - 1]
                let dot = CGRect(x: head.x - 3, y: head.y - 3, width: 6, height: 6)
                glow.fill(Path(ellipseIn: dot), with: .color(.white))
            }
        }
        .accessibilityHidden(true)
    }

    /// Through the midpoints between readings, curving at each reading: smooth without overshooting.
    private static func smooth(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for (previous, point) in zip(points, points.dropFirst()) {
            path.addQuadCurve(
                to: CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2), control: previous)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}

/// The history: a range switch, the range's download, upload, and total (or the bar under the
/// pointer's), and its bars.
private struct HistoryCard: View {
    let network: NetworkFeature
    let compact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picked: Int?
    @Namespace private var selection

    var body: some View {
        let buckets = network.buckets
        let bar = picked.flatMap { buckets.indices.contains($0) ? buckets[$0] : nil }
        let traffic = bar?.traffic ?? buckets.reduce(Traffic()) { $0 + $1.traffic }
        let caption = bar.map { network.range.label($0.start) } ?? network.range.caption
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            if compact {
                // The bar under the pointer shows its time where the switch was.
                Group {
                    if bar == nil {
                        picker(short: true)
                    } else {
                        Text(caption)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .frame(height: 20)
            } else {
                picker(short: false)
                Text(caption)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Totals(traffic: traffic, compact: compact)
            Bars(buckets: buckets, range: network.range, picked: $picked)
            if !compact, let first = buckets.first, let last = buckets.last {
                HStack {
                    Text(network.range.axisLabel(first.start))
                    Spacer()
                    Text(network.range.axisLabel(buckets[buckets.count / 2].start))
                    Spacer()
                    Text(network.range.axisLabel(last.start))
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .accessibilityHidden(true)
            }
        }
        .padding(compact ? 8 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(Card(tint: .white))
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: network.range)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: picked)
    }

    /// Day, Week, Month, and Year, or 24h, 7d, 30d, and 1y in a short notch, with a light that slides to
    /// the one picked.
    private func picker(short: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(HistoryRange.allCases) { range in
                let chosen = network.range == range
                Button {
                    picked = nil
                    network.range = range
                } label: {
                    Text(short ? range.shortTitle : range.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(chosen ? 1 : 0.5))
                        .padding(.horizontal, short ? 6 : 8)
                        .frame(height: short ? 16 : 18)
                        .background {
                            if chosen {
                                Capsule().fill(.white.opacity(0.16)).matchedGeometryEffect(id: "range", in: selection)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(range.caption)
                .accessibilityLabel(range.caption)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(2)
        .background(.white.opacity(0.07), in: Capsule())
        .fixedSize()
    }

}

/// Download, upload, and the two together, in the bars' colors: three columns under the switch, or
/// one line in a short notch, whose type shrinks a little before a number would go.
private struct Totals: View {
    let traffic: Traffic
    let compact: Bool

    var body: some View {
        Group {
            if compact {
                ViewThatFits(in: .horizontal) {
                    line(size: 10.5)
                    line(size: 9.5)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    column("Download", traffic.down, color: NetworkTint.downLight, dot: NetworkTint.down)
                    column("Upload", traffic.up, color: NetworkTint.upLight, dot: NetworkTint.up)
                    column("Total", traffic.total, color: .white, dot: nil)
                }
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(NetworkFeature.bytes(traffic.down)) down, \(NetworkFeature.bytes(traffic.up)) up, "
                + "\(NetworkFeature.bytes(traffic.total)) in all")
    }

    private func line(size: CGFloat) -> some View {
        HStack(spacing: size * 0.55) {
            Text("↓ \(NetworkFeature.bytes(traffic.down))").foregroundStyle(NetworkTint.downLight)
            Text("↑ \(NetworkFeature.bytes(traffic.up))").foregroundStyle(NetworkTint.upLight)
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                Text("Total").foregroundStyle(.white.opacity(0.5))
                Text(NetworkFeature.bytes(traffic.total))
            }
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
    }

    private func column(_ title: String, _ bytes: Int64, color: Color, dot: Color?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                if let dot { Circle().fill(dot).frame(width: 5, height: 5) }
                Text(title).textCase(.uppercase).tracking(0.4)
            }
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(.white.opacity(0.5))
            Text(NetworkFeature.bytes(bytes))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The range as bars, download under upload, scaled to the tallest. The pointer picks a bar and the
/// others dim.
private struct Bars: View {
    let buckets: [TrafficBucket]
    let range: HistoryRange
    @Binding var picked: Int?

    var body: some View {
        GeometryReader { proxy in
            let peak = CGFloat(max(buckets.map(\.traffic.total).max() ?? 0, 1))
            let count = CGFloat(max(buckets.count, 1))
            let gap: CGFloat = buckets.count > 12 ? 2 : 4
            let width = max(1, (proxy.size.width - gap * (count - 1)) / count)
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                    Bar(
                        traffic: bucket.traffic, width: width, scale: proxy.size.height / peak,
                        lit: picked == nil || picked == index, now: index == buckets.count - 1, order: index)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                // Every pointer move lands here; only crossing into another bar changes anything.
                var bar: Int?
                if case .active(let location) = phase {
                    bar = min(max(Int(location.x / (width + gap)), 0), buckets.count - 1)
                }
                if bar != picked { picked = bar }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(range.caption)
        .accessibilityValue(spokenValue)
        .accessibilityAdjustableAction { direction in
            let next = (picked ?? buckets.count) + (direction == .increment ? 1 : -1)
            picked = buckets.indices.contains(next) ? next : nil
        }
    }

    private var spokenValue: String {
        let traffic: Traffic
        var prefix = ""
        if let picked, buckets.indices.contains(picked) {
            traffic = buckets[picked].traffic
            prefix = range.label(buckets[picked].start) + ", "
        } else {
            traffic = buckets.reduce(Traffic()) { $0 + $1.traffic }
        }
        return "\(prefix)\(NetworkFeature.bytes(traffic.down)) down, \(NetworkFeature.bytes(traffic.up)) up, "
            + "\(NetworkFeature.bytes(traffic.total)) in all"
    }
}

/// Upload stacked on download, rounded on top, or a sliver while empty so the row keeps its shape. It
/// rises into place when it appears, a moment after the bar before it, and glows while it's now's.
private struct Bar: View {
    let traffic: Traffic
    let width: CGFloat
    /// Points per byte.
    let scale: CGFloat
    let lit: Bool
    let now: Bool
    /// Its place in the row, for the rising wave.
    let order: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var risen = false

    var body: some View {
        let scale = risen ? scale : 0
        let radius = min(width / 2, 3)
        ZStack(alignment: .bottom) {
            let empty = traffic.total == 0
            Rectangle().fill(empty ? AnyShapeStyle(.white.opacity(0.08)) : AnyShapeStyle(NetworkTint.upFill))
            Rectangle().fill(NetworkTint.downFill).frame(height: CGFloat(traffic.down) * scale)
        }
        .frame(width: width, height: max(CGFloat(traffic.total) * scale, 2))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous))
        .background {
            // A glow for now's bar only: a shadow on every bar, even a clear one, costs a pass each.
            if now, traffic.total > 0 {
                UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous)
                    .fill(NetworkTint.down)
                    .blur(radius: 4)
                    .opacity(0.7)
            }
        }
        .opacity(lit ? 1 : 0.35)
        .onAppear {
            let rise: Animation? =
                reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.78).delay(Double(order) * 0.012)
            withAnimation(rise) { risen = true }
        }
    }
}

extension HistoryRange {
    /// Under the chart: "3 PM", "Mon", "12 Sep", or "Sep".
    func axisLabel(_ date: Date) -> String {
        switch self {
        case .day: date.formatted(.dateTime.hour())
        case .week: date.formatted(.dateTime.weekday(.abbreviated))
        case .month: date.formatted(.dateTime.day().month(.abbreviated))
        case .year: date.formatted(.dateTime.month(.abbreviated))
        }
    }

    /// A bar in full: "Tue 3 PM", "Tue 12 Sep", or "September 2026".
    func label(_ date: Date) -> String {
        switch self {
        case .day: date.formatted(.dateTime.weekday(.abbreviated).hour())
        case .week, .month: date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .year: date.formatted(.dateTime.month(.wide).year())
        }
    }
}
