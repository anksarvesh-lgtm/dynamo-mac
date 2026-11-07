// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import Testing

@testable import NotchUsage

/// Renders the Usage tab with sample data inside a notch-sized black panel. Always checks that it
/// draws; with SNAPSHOT_DIR set, also writes PNGs there for eyeballing.
@MainActor
struct UsageSnapshotTests {
    private let defaults = UserDefaults(suiteName: "UsageSnapshots.\(UUID().uuidString)")!
    private let cache = FileManager.default.temporaryDirectory.appending(path: "usage-snap-\(UUID().uuidString).json")
    /// The content area of the default open notch, the smallest, and the largest.
    private static let size = CGSize(width: 396, height: 192)
    private static let smallest = CGSize(width: 350, height: 102)
    private static let largest = CGSize(width: 656, height: 382)

    private static let now = Date()

    /// A provider with every kind of line: limits at a given level, spend, a trend, and a note.
    private static func sample(_ id: String, _ name: String, session: Double, weekly: Double) -> ProviderSnapshot {
        let trend = (0..<14).map { day in
            MetricChartPoint(value: Double((day * 37) % 11 + 2) * 1_000_000, label: "Sep \(10 + day)", valueLabel: nil)
        }
        return ProviderSnapshot(
            providerID: id, displayName: name, plan: id == "claude" ? "Max" : "Pro",
            lines: [
                .progress(
                    label: "Session", used: session, limit: 100, format: .percent,
                    resetsAt: now.addingTimeInterval(2 * 3600 + 780), periodDurationMs: 5 * 3_600_000),
                .progress(
                    label: "Weekly", used: weekly, limit: 100, format: .percent,
                    resetsAt: now.addingTimeInterval(3 * 86_400), periodDurationMs: 7 * 86_400_000),
                .progress(label: "Extra Usage", used: 12.5, limit: 100, format: .dollars),
                .values(
                    label: "Today",
                    values: [
                        MetricValue(number: 3.12, kind: .dollars),
                        MetricValue(number: 1_200_000, kind: .count, label: "tokens"),
                    ]),
                .values(label: "Yesterday", values: [MetricValue(number: 8.4, kind: .dollars)]),
                .values(label: "Last 30 Days", values: [MetricValue(number: 58.2, kind: .dollars)]),
                .chart(label: "Usage Trend", points: trend),
            ],
            refreshedAt: now.addingTimeInterval(-120))
    }

    /// A feature with these providers on, and `offered` ones off, in the tray.
    private func usage(with snapshots: [ProviderSnapshot], offered: [(String, String)] = []) throws -> UsageFeature {
        let cached = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.providerID, $0) })
        try JSONEncoder().encode(cached).write(to: cache)
        defaults.set(snapshots.map(\.providerID), forKey: "usage.enabledProviders")
        let runtimes = (snapshots.map { ($0.providerID, $0.displayName) } + offered).map {
            FakeRuntime(id: $0.0, name: $0.1, used: 0)
        }
        return UsageFeature(defaults: defaults, cacheURL: cache, runtimes: { runtimes })
    }

    @Test func theDashboardShowsEachProvidersHeadlineLimit() async throws {
        let usage = try usage(with: [
            Self.sample("claude", "Claude", session: 42, weekly: 71),
            Self.sample("codex", "Codex", session: 86, weekly: 40),
            Self.sample("cursor", "Cursor", session: 97, weekly: 88),
            Self.sample("copilot", "Copilot", session: 15, weekly: 5),
        ])
        try await render(UsageView(usage: usage), name: "usage-dashboard")
    }

    @Test func cardsShareTheWidthAndShrinkToFitTheNotch() {
        // The room for cards in the default notch, under the header and over the tray.
        let room = CGSize(width: 396, height: 136)
        let one = CardGrid.plan(count: 1, in: room)
        #expect(one.frames == [CGRect(x: 0, y: 0, width: 396, height: 128)], "one card spans the row")
        let two = CardGrid.plan(count: 2, in: room).frames
        #expect(two.map(\.width) == [194, 194] && two[1].minX == 202, "two share it")
        let three = CardGrid.plan(count: 3, in: room)
        #expect(three.frames.allSatisfy { $0.minY == 0 } && three.card.height == 128, "three fit a row, full height")

        let tall = CardGrid.plan(count: 3, in: CGSize(width: 396, height: 300)).frames
        #expect(tall[2] == CGRect(x: 101, y: 136, width: 194, height: 128), "with room, the third sits centered below")
        #expect(CardGrid.plan(count: 4, in: CGSize(width: 656, height: 326)).frames.allSatisfy { $0.minY == 0 })

        // The smallest notch: three cards in a row, as tall as the room, nothing cut off.
        let smallest = CardGrid.plan(count: 3, in: CGSize(width: 350, height: 46))
        #expect(!smallest.scrolls && smallest.frames.allSatisfy { $0.maxY <= 46 } && smallest.card.height == 46)
        let crowded = CardGrid.plan(count: 11, in: CGSize(width: 350, height: 46))
        #expect(crowded.scrolls && crowded.card.height == CardGrid.minimum.height, "too many to fit scroll")
        #expect(crowded.card.width >= CardGrid.minimum.width)
    }

    @Test(arguments: 1...4)
    func cardsFillTheWidthForAnyCount(count: Int) async throws {
        let ids = [("claude", "Claude"), ("codex", "Codex"), ("cursor", "Cursor"), ("copilot", "Copilot")]
        let usage = try usage(
            with: ids.prefix(count).enumerated().map { index, provider in
                Self.sample(provider.0, provider.1, session: [42, 86, 97, 15][index], weekly: [71, 40, 88, 5][index])
            })
        try await render(UsageView(usage: usage), name: "usage-cards-\(count)", size: CGSize(width: 396, height: 330))
    }

    @Test func threeCardsFitTheSmallestAndLargestNotch() async throws {
        let three = [
            Self.sample("claude", "Claude", session: 42, weekly: 71),
            Self.sample("codex", "Codex", session: 86, weekly: 40),
            Self.sample("cursor", "Cursor", session: 97, weekly: 88),
        ]
        // The tightest room there is: the smallest notch, with the tray under the cards.
        let offering = try usage(with: three, offered: [("copilot", "Copilot")])
        try await render(UsageView(usage: offering), name: "usage-cards-3-smallest", size: Self.smallest)
        try await render(UsageView(usage: try usage(with: three)), name: "usage-cards-3-largest", size: Self.largest)
    }

    @Test func aProviderShowsEveryLimitSpendAndItsTrend() async throws {
        let usage = try usage(with: [Self.sample("claude", "Claude", session: 42, weekly: 71)])
        let provider = try #require(usage.enabledProviders.first)
        let detail = ProviderDetail(usage: usage, provider: provider, now: Self.now) {}
        try await render(detail, name: "usage-detail")
        try await render(detail, name: "usage-detail-largest", size: Self.largest)
    }

    @Test func withOneProviderOnTheOthersSignedInCanBeAdded() async throws {
        try JSONEncoder().encode(["claude": Self.sample("claude", "Claude", session: 42, weekly: 71)]).write(to: cache)
        defaults.set(["claude"], forKey: "usage.enabledProviders")
        let runtimes = [("claude", "Claude"), ("codex", "Codex"), ("cursor", "Cursor")].map {
            FakeRuntime(id: $0.0, name: $0.1, used: 0)
        }
        let usage = UsageFeature(defaults: defaults, cacheURL: cache, runtimes: { runtimes })
        try await render(UsageView(usage: usage), name: "usage-one-provider")
        #expect(usage.detected == ["claude", "codex", "cursor"], "the dashboard looks for the others")
    }

    @Test func settingsListEveryProviderAndTakeTheKeysTheyNeed() async throws {
        let runtimes = [("claude", "Claude"), ("codex", "Codex"), ("openrouter", "OpenRouter"), ("zai", "Z.ai")].map {
            FakeRuntime(id: $0.0, name: $0.1, used: 0)
        }
        let usage = UsageFeature(defaults: defaults, cacheURL: cache, runtimes: { runtimes })
        let page = Form { usage.settingsView }.formStyle(.grouped)  // sections, as on its Settings page
        try await render(page, name: "usage-settings", size: CGSize(width: 460, height: 480))
    }

    @Test func beforeAnyProviderIsOnItOffersEveryOneSignedInFirst() async throws {
        let names = [
            "claude": "Claude", "codex": "Codex", "cursor": "Cursor", "antigravity": "Antigravity",
            "copilot": "Copilot", "devin": "Devin", "grok": "Grok", "ollama": "Ollama", "opencode": "OpenCode",
            "openrouter": "OpenRouter", "zai": "Z.ai",
        ]
        let runtimes = names.keys.sorted().map { id in
            let runtime = FakeRuntime(id: id, name: names[id] ?? id, used: 0)
            runtime.signedIn = ["claude", "codex", "copilot"].contains(id)
            return runtime
        }
        let usage = UsageFeature(defaults: defaults, cacheURL: cache, runtimes: { runtimes })
        try await render(UsageView(usage: usage), name: "usage-onboarding")
        #expect(usage.detected == ["claude", "codex", "copilot"])
    }

    /// Without a size, at the default size and again at the smallest.
    private func render(_ view: some View, name: String, size: CGSize? = nil) async throws {
        guard let size else {
            try await render(view, name: name, size: Self.size)
            return try await render(view, name: name + "-smallest", size: Self.smallest)
        }
        let framed = view.frame(width: size.width, height: size.height).padding(16).background(.black)
            .foregroundStyle(.white).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: framed)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: size.width + 32, height: size.height + 32),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Rings fill from empty when they appear: let them get there, without holding up the main actor.
        try await Task.sleep(for: .seconds(1.5))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
        if let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(
                to: URL(filePath: directory).appending(path: "\(name).png"))
        }
    }
}
