// SPDX-License-Identifier: MIT
import Charts
import NotchCore
import NotchFeatures
import SwiftUI

/// The Usage tab: a small dashboard card per provider that's on, with a tray of every other provider
/// under them to add from; a provider's full detail, with a way back; or, before any provider is on,
/// the tray alone.
struct UsageView: View {
    let usage: UsageFeature

    @State private var selected: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let providers = usage.enabledProviders
        // Relative times ("Resets in 2h 13m") move on once a minute, only while the tab is on screen.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Group {
                if providers.isEmpty {
                    UsageOnboarding(usage: usage)
                } else if let provider = providers.first(where: { $0.id == selected }) {
                    ProviderDetail(usage: usage, provider: provider, now: context.date) { selected = nil }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    dashboard(now: context.date)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: selected)
        }
    }

    /// The cards, then the tray. The cards take the room between the two, sized to fit it.
    private func dashboard(now: Date) -> some View {
        VStack(spacing: 6) {
            UsageHeader(usage: usage, now: now)
            GeometryReader { space in
                let providers = usage.enabledProviders
                let plan = CardGrid.plan(count: providers.count, in: space.size)
                let cards = CardGrid(plan: plan) {
                    ForEach(providers) { provider in
                        Button {
                            selected = provider.id
                        } label: {
                            ProviderTile(
                                provider: provider, snapshot: usage.snapshots[provider.id],
                                error: usage.errors[provider.id], refreshing: usage.refreshing.contains(provider.id),
                                size: plan.card, now: now)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Turn Off \(provider.name)") { usage.setEnabled(provider.id, false) }
                        }
                    }
                }
                if plan.scrolls {
                    ScrollView { cards }.fadingEdges(length: 6)
                } else {
                    cards
                }
            }
            if usage.providers.contains(where: { !usage.isEnabled($0.id) }) { ProviderTray(usage: usage) }
        }
        // The same local check onboarding runs, so the tray knows which tools are signed in.
        .task { if !usage.hasDetected { await usage.detect() } }
    }
}

/// The providers' cards, fitted to the room the notch has. Cards share a row's width, so one card
/// spans the row and two share it, and a last row that isn't full sits centered. The grid takes
/// the number of columns that keeps cards closest to full size, and each card shows as much as its
/// size holds; only when even the shortest cards don't fit does it scroll.
struct CardGrid: Layout {
    static let spacing: CGFloat = 8
    /// A card with room for everything: its ring, three limits, and when the headline resets.
    static let full = CGSize(width: 158, height: 128)
    /// The smallest card: a name, a headline number, and a thin bar.
    static let minimum = CGSize(width: 80, height: 40)

    struct Plan: Equatable {
        var frames: [CGRect]
        var card: CGSize
        /// The cards need more height than there is, at their smallest.
        var scrolls: Bool
    }

    let plan: Plan

    /// Where each of `count` cards goes in `space`.
    static func plan(count: Int, in space: CGSize) -> Plan {
        guard count > 0 else { return Plan(frames: [], card: .zero, scrolls: false) }
        func rows(_ columns: Int) -> Int { (count + columns - 1) / columns }
        func card(columns: Int) -> CGSize {
            let rowCount = CGFloat(rows(columns))
            return CGSize(
                width: (space.width - spacing * CGFloat(columns - 1)) / CGFloat(columns),
                height: min(full.height, (space.height - spacing * (rowCount - 1)) / rowCount))
        }
        /// How near a card comes to a full one, by its tighter side.
        func fit(_ columns: Int) -> CGFloat {
            let size = card(columns: columns)
            return min(size.width / full.width, size.height / full.height)
        }
        // The best fit; between equals, fewer rows, then wider cards.
        let usable = (1...count).filter { $0 == 1 || card(columns: $0).width >= minimum.width }
        let columns = usable.max { (fit($0), -rows($0), -$0) < (fit($1), -rows($1), -$1) } ?? 1
        var size = card(columns: columns)
        let scrolls = size.height < minimum.height
        if scrolls { size.height = minimum.height }
        let frames = (0..<count).map { index in
            let row = index / columns
            let inRow = min(columns, count - row * columns)
            let rowWidth = size.width * CGFloat(inRow) + spacing * CGFloat(inRow - 1)
            let x = (space.width - rowWidth) / 2 + CGFloat(index % columns) * (size.width + spacing)
            return CGRect(x: x, y: CGFloat(row) * (size.height + spacing), width: size.width, height: size.height)
        }
        return Plan(frames: frames, card: size, scrolls: scrolls)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? plan.frames.map(\.maxX).max() ?? 0, height: plan.frames.last?.maxY ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, plan.frames) {
            let origin = CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY)
            subview.place(at: origin, proposal: ProposedViewSize(frame.size))
        }
    }
}

/// Today's spend across providers, when they report it, the last update, and refresh.
private struct UsageHeader: View {
    let usage: UsageFeature
    let now: Date

    var body: some View {
        let snapshots = usage.enabledProviders.compactMap { usage.snapshots[$0.id] }
        let today = snapshots.compactMap { $0.dollars(for: "Today") }
        HStack(spacing: 8) {
            if !today.isEmpty {
                HStack(spacing: 4) {
                    Text("Today").foregroundStyle(.white.opacity(0.5))
                    Text(MetricFormatter.number(today.reduce(0, +), kind: .dollars, style: .row))
                        .fontWeight(.semibold)
                        .contentTransition(.numericText())
                }
                .font(.system(size: 11))
            }
            Spacer(minLength: 0)
            if let latest = snapshots.map(\.refreshedAt).max() {
                Text(Self.updated(latest, now: now))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }
            RefreshButton(spinning: !usage.refreshing.isEmpty) { Task { await usage.refreshAll(force: true) } }
        }
        .frame(height: 18)
    }

    static func updated(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 60, let ago = Formatters.compactDuration(seconds) else { return "Updated just now" }
        return "Updated \(ago) ago"
    }
}

/// One provider at a glance, showing as much as its card holds: its headline limit as a ring beside
/// up to three limits as bars, then when the headline resets. Smaller, the ring goes, then limits one
/// by one, then the reset line, down to the name, the headline number, and a thin bar.
private struct ProviderTile: View {
    let provider: UsageProvider
    let snapshot: ProviderSnapshot?
    let error: String?
    let refreshing: Bool
    /// The card's size in the grid.
    let size: CGSize
    let now: Date

    var body: some View {
        let style = ProviderStyle.of(provider.id)
        Group {
            if let headline = snapshot?.meters.first {
                ViewThatFits(in: .vertical) {
                    if size.width >= CardGrid.full.width { withRing(headline, style: style) }
                    bars(3, headline: headline, style: style)
                    bars(2, headline: headline, style: style)
                    bars(1, headline: headline, style: style)
                    bars(1, headline: headline, style: style, footer: false)
                    VStack(alignment: .leading, spacing: 5) {
                        header(style, value: headline.headline)
                        MeterBar(meter: headline, style: style, height: 3)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    header(style)
                    placeholder(style: style)
                }
            }
        }
        .padding(size.height < CardGrid.full.height ? 8 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)  // the grid's size
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [style.start.opacity(0.16), .white.opacity(0.04)], startPoint: .topLeading,
                        endPoint: .bottomTrailing))
        }
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08)) }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows every limit")
    }

    /// The ring beside three limits, then the reset line: a card with room for everything.
    private func withRing(_ headline: Meter, style: ProviderStyle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                header(style)
                HStack(spacing: 10) {
                    UsageRing(meter: headline, style: style, size: 56)
                    limits(3, style: style)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            footer(headline).padding(.top, 4)
        }
    }

    /// `count` limits as bars under the name, and the reset line at the bottom.
    private func bars(_ count: Int, headline: Meter, style: ProviderStyle, footer: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                header(style)
                limits(count, style: style)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            if footer { self.footer(headline).padding(.top, 4) }
        }
    }

    private func limits(_ count: Int, style: ProviderStyle) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach((snapshot?.meters ?? []).prefix(count)) { meter in miniMeter(meter, style: style) }
        }
    }

    /// The logo and name, and the plan when there's room for it. `value`, when given, is the
    /// headline number, for a card too small for anything else.
    private func header(_ style: ProviderStyle, value: String? = nil) -> some View {
        HStack(spacing: 6) {
            ProviderLogo(providerID: provider.id, name: provider.name, size: 13)
                .foregroundStyle(style.end)
            let name = Text(provider.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            if let plan = snapshot?.plan, !plan.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        name
                        PlanPill(plan: plan, style: style)
                    }
                    name
                }
            } else {
                name
            }
            Spacer(minLength: 0)
            if let value {
                Text(value).font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
            }
            status
        }
    }

    @ViewBuilder private var status: some View {
        if refreshing {
            ProgressView().controlSize(.mini)
        } else if error != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: 0xF59E_0B))
                .help(error ?? "")
        }
    }

    /// When the headline limit resets, and whether it will last until then, on one line. Narrow, the
    /// pace is a dot, with its words in the tooltip.
    private func footer(_ headline: Meter) -> some View {
        ViewThatFits(in: .horizontal) {
            footerLine(headline, paceWords: true)
            footerLine(headline, paceWords: false)
        }
    }

    private func footerLine(_ headline: Meter, paceWords: Bool) -> some View {
        let left = headline.resetsAt.flatMap { Formatters.compactDuration($0.timeIntervalSince(now)) }
        return HStack(spacing: 6) {
            if let left {
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(left).monospacedDigit()
                }
                .help("Resets in \(left)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Resets in \(left)")
            }
            Spacer(minLength: 0)
            PaceBadge(meter: headline, now: now, showsWords: paceWords)
        }
        .font(.system(size: 10))
        .foregroundStyle(.white.opacity(0.55))
        .lineLimit(1)
    }

    private func miniMeter(_ meter: Meter, style: ProviderStyle) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(meter.label).foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 4)
                Text(meter.headline).monospacedDigit()
            }
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            MeterBar(meter: meter, style: style, height: 4)
        }
    }

    /// No limits to show: still loading, a failure, or a provider that only reports spend.
    @ViewBuilder private func placeholder(style: ProviderStyle) -> some View {
        if let spend = snapshot?.dollars(for: "Today") ?? snapshot?.dollars(for: "Last 30 Days") {
            Text(MetricFormatter.number(spend, kind: .dollars, style: .row))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(style.end)
        } else {
            Text(error ?? (refreshing || snapshot == nil ? "Checking…" : "No limits to show"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
        }
    }
}

/// Everything a provider reports: each limit with its reset and pace, spend, and the daily trend.
/// `back` returns to the tiles.
struct ProviderDetail: View {
    let usage: UsageFeature
    let provider: UsageProvider
    let now: Date
    let back: () -> Void

    var body: some View {
        let style = ProviderStyle.of(provider.id)
        let snapshot = usage.snapshots[provider.id]
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("All providers")
                .accessibilityLabel("Back")
                ProviderLogo(providerID: provider.id, name: provider.name, size: 15).foregroundStyle(style.end)
                Text(provider.name).font(.system(size: 13, weight: .semibold))
                if let plan = snapshot?.plan, !plan.isEmpty { PlanPill(plan: plan, style: style) }
                Spacer(minLength: 0)
                if let dashboard = provider.dashboard {
                    Link(destination: dashboard) {
                        HStack(spacing: 2) {
                            Text("Dashboard")
                            Image(systemName: "arrow.up.right").font(.system(size: 7, weight: .bold))
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .help("Open \(provider.name)'s usage page")
                }
                RefreshButton(spinning: usage.refreshing.contains(provider.id)) {
                    Task { await usage.refresh(provider.id, force: true) }
                }
            }
            if let error = usage.errors[provider.id] { banner(error) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(snapshot?.meters ?? []) { meter in MeterRow(meter: meter, style: style, now: now) }
                    if let snapshot {
                        SpendRow(snapshot: snapshot, style: style)
                        if let trend = snapshot.trend, trend.count > 1 { TrendChart(points: trend, style: style) }
                        notes(snapshot)
                    }
                }
                .padding(.vertical, 4)
            }
            .fadingEdges(length: 8)
        }
    }

    private func banner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(Color(hex: 0xFDE6_8A))
            .lineLimit(2)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0xF59E_0B).opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Badges and notes the provider adds, like an organization's status or a sign-in hint.
    @ViewBuilder private func notes(_ snapshot: ProviderSnapshot) -> some View {
        if let warning = snapshot.warning {
            Text(warning).font(.system(size: 10)).foregroundStyle(Color(hex: 0xFDE6_8A))
        }
        ForEach(Array(snapshot.lines.enumerated()), id: \.offset) { _, line in
            switch line {
            case .badge(let label, let text, _, _) where !line.isError:
                HStack {
                    Text(label).foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Text(text).fontWeight(.medium)
                }
                .font(.system(size: 11))
            case .text(let label, let value, _, _):
                HStack {
                    Text(label).foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Text(value)
                }
                .font(.system(size: 11))
            case .values(let label, let values, _, _, _, _) where !SpendRow.periods.contains(label):
                HStack {
                    Text(label).foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Text(values.map { MetricFormatter.string(for: $0, style: .row) }.joined(separator: " · "))
                        .monospacedDigit()
                }
                .font(.system(size: 11))
            default:
                EmptyView()
            }
        }
    }
}

/// A limit in full: label and amount, its bar, when it resets, and whether it will last.
private struct MeterRow: View {
    let meter: Meter
    let style: ProviderStyle
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(meter.label).font(.system(size: 11, weight: .medium))
                Spacer()
                Text(meter.detail)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            MeterBar(meter: meter, style: style, height: 6)
            HStack {
                if let reset = meter.resetLabel(now: now) { Text(reset) }
                Spacer()
                PaceBadge(meter: meter, now: now)
            }
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.5))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Today, yesterday, and the last 30 days of spend, as chips.
private struct SpendRow: View {
    static let periods = ["Today", "Yesterday", "Last 30 Days"]

    let snapshot: ProviderSnapshot
    let style: ProviderStyle

    var body: some View {
        let chips = Self.periods.compactMap { period in snapshot.values(for: period).map { (period, $0) } }
        if !chips.isEmpty {
            HStack(spacing: 6) {
                ForEach(chips, id: \.0) { period, values in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(period).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                        Text(values.first.map { MetricFormatter.string(for: $0, style: .row) } ?? "–")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        if values.count > 1 {
                            Text(MetricFormatter.string(for: values[1], style: .row))
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(style.start.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
            .fixedSize(horizontal: false, vertical: true)  // every chip as tall as the tallest
        }
    }
}

/// The daily trend as rounded bars in the provider's colors.
private struct TrendChart: View {
    let points: [MetricChartPoint]
    let style: ProviderStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Daily usage").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                Spacer()
                if let peak = points.max(by: { $0.value < $1.value }) {
                    Text("Peak \(peak.readout)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                }
            }
            let bars = LinearGradient(colors: [style.end, style.start], startPoint: .top, endPoint: .bottom)
            // A bar's ratio width needs a category axis: numeric x gives the bars no width.
            Chart(Array(points.enumerated()), id: \.offset) { index, point in
                BarMark(x: .value("Day", String(index)), y: .value("Usage", point.value), width: .ratio(0.7))
                    .foregroundStyle(bars)
                    .cornerRadius(2)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 54)
            HStack {
                Text(points.first?.label ?? "")
                Spacer()
                Text(points.last?.label ?? "")
            }
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.4))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily usage chart")
    }
}

/// Before any provider is on: the tools signed in on this Mac, one tap to turn each on.
private struct UsageOnboarding: View {
    let usage: UsageFeature

    /// Shorter notches drop the symbol and trade the grid for the one-row tray the cards have, so
    /// nothing clips.
    var body: some View {
        ViewThatFits(in: .vertical) {
            content(compact: false)
            content(compact: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { if !usage.hasDetected { await usage.detect() } }
    }

    private func content(compact: Bool) -> some View {
        let accents = ["claude", "copilot", "cursor"].map { ProviderStyle.of($0).start }
        return VStack(spacing: 8) {
            if !compact {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: accents, startPoint: .leading, endPoint: .trailing))
                    .accessibilityHidden(true)
            }
            VStack(spacing: 3) {
                Text("Your AI plans at a glance").font(.headline)
                Text(
                    "Add the tools you use; the ones in color are signed in on this Mac. Each reads only its own "
                        + "sign-in and sends it only to its own service."
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            }
            ProviderTray(usage: usage, labeled: !compact)
        }
    }
}

/// Every provider that isn't on yet: the ones signed in on this Mac first and in color, then the
/// rest, dimmed. A tap adds one as a card; a provider that needs an API key it doesn't have opens
/// Settings for it instead. Under the cards it's one row that scrolls sideways; `labeled`, for the
/// empty tab when the notch has room, it's a grid with each name under its logo, all of them in view.
private struct ProviderTray: View {
    let usage: UsageFeature
    var labeled = false

    var body: some View {
        let off = usage.providers.filter { !usage.isEnabled($0.id) }
        let ordered = off.filter { usage.detected.contains($0.id) } + off.filter { !usage.detected.contains($0.id) }
        HStack(spacing: 6) {
            if labeled {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 4)], spacing: 8) { items(ordered) }
                    .frame(maxWidth: .infinity)
            } else {
                Text("Add").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                ScrollView(.horizontal) {
                    HStack(spacing: 6) { items(ordered) }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
                .fadingEdges(.horizontal, length: 10)
            }
            Button {
                usage.openSettings?()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
            .help("AI Usage settings: providers, API keys, and background refresh")
            .accessibilityLabel("AI Usage settings")
        }
        .frame(height: labeled ? nil : 26)
    }

    private func items(_ providers: [UsageProvider]) -> some View {
        ForEach(providers) { provider in
            TrayItem(usage: usage, provider: provider, signedIn: usage.detected.contains(provider.id), labeled: labeled)
        }
    }
}

/// One provider in the tray: its logo on a tint of its color, with a + to add it, or a key when it
/// needs an API key first. It grows a little under the pointer.
private struct TrayItem: View {
    let usage: UsageFeature
    let provider: UsageProvider
    let signedIn: Bool
    let labeled: Bool

    @State private var hovering = false

    var body: some View {
        let style = ProviderStyle.of(provider.id)
        let needsKey = usage.takesAPIKey(provider.id) && !signedIn
        let side: CGFloat = labeled ? 30 : 22
        Button {
            if needsKey { usage.openSettings?() } else { usage.setEnabled(provider.id, true) }
        } label: {
            VStack(spacing: 4) {
                ProviderLogo(providerID: provider.id, name: provider.name, size: side * 0.52)
                    .foregroundStyle(signedIn ? style.end : .white.opacity(0.85))
                    .frame(width: side, height: side)
                    .background(
                        (signedIn ? style.start.opacity(0.28) : .white.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: needsKey ? "key.fill" : "plus.circle.fill")
                            .font(.system(size: labeled ? 10 : 8, weight: .bold))
                            .foregroundStyle(signedIn ? style.end : .white.opacity(0.7))
                            .background(Circle().fill(.black).padding(-1))
                            .offset(x: 2, y: 2)
                    }
                if labeled {
                    Text(provider.name).font(.system(size: 9, weight: .medium)).lineLimit(1).fixedSize()
                }
            }
            .opacity(signedIn || hovering ? 1 : 0.55)
            .scaleEffect(hovering ? 1.1 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        .help(hint(needsKey: needsKey))
        .accessibilityLabel(hint(needsKey: needsKey))
    }

    private func hint(needsKey: Bool) -> String {
        if needsKey { return "Add an API key for \(provider.name) in Settings" }
        return signedIn ? "Add \(provider.name)" : "Add \(provider.name). It isn't signed in on this Mac yet."
    }
}

extension ProviderSnapshot {
    /// A spend row's values, like Today's dollars and tokens.
    func values(for label: String) -> [MetricValue]? {
        for line in lines {
            if case .values(label, let values, _, _, _, _) = line, !values.isEmpty { return values }
        }
        return nil
    }

    func dollars(for label: String) -> Double? {
        values(for: label)?.first { $0.kind == .dollars }?.number
    }

    /// The daily usage trend, when the provider keeps local history.
    var trend: [MetricChartPoint]? {
        for line in lines {
            if case .chart(_, let points, _) = line { return points }
        }
        return nil
    }
}
