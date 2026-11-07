#if DEBUG
import AppKit
import IslandCore

/// DEBUG: randomized stress test over the real controller / view-model / manager paths.
/// `scripts/island-debug.sh stress` → results in $TMPDIR/island-stress.txt.
@MainActor
struct StressTest {
    let env: AppEnvironment

    func run(steps: Int = 400, seed: UInt64 = 42) {
        var rng = SeededRNG(seed: seed)
        var violations: [String] = []
        var slowest: (String, Double) = ("", 0)
        let island = env.island, manager = env.manager
        let savedMedia = env.commands.media
        env.commands.media = { _, _ in } // never touch real players
        env.window.pointerTrackingSuspended = true
        defer { env.window.pointerTrackingSuspended = false }
        manager.removeAll()
        let start = Date()

        for step in 0..<steps {
            let op = Int.random(in: 0..<16, using: &rng)
            let name: String
            let t0 = CACurrentMediaTime()
            switch op {
            case 0: name = "hoverIn"; island.mouseInsideChanged(true)
            case 1: name = "hoverOut"; island.mouseInsideChanged(false)
            case 2: name = "click"; island.click()
            case 3: name = "clickOutside"; island.clickOutside()
            case 4: name = "escape"; island.escape()
            case 5: name = "toggleSearch"; env.commands.perform(.ui(.toggleSearch))
            case 6: name = "music"; manager.submit(.upsert(DebugActivities.music(playing: Bool.random(using: &rng), source: "dev.island.test", name: "Test")))
            case 7: name = "timer"; env.timers.handle(.start(duration: Double.random(in: 1...30, using: &rng), label: "S"))
            case 8: name = "download"; manager.submit(.upsert(DebugActivities.download(fraction: Double.random(in: 0...1, using: &rng))))
            case 9:
                name = "event"
                let p = ActivityPriority.allCases.randomElement(using: &rng)!
                manager.submit(.upsert(Activity(id: "stress.\(Int.random(in: 0..<5, using: &rng))", kind: .notification, priority: p,
                                                content: .event(SystemEventActivity(symbol: "bell", title: "E")),
                                                expiresAt: Date().addingTimeInterval(Double.random(in: 0.05...2, using: &rng)))))
            case 10: name = "selectNext"; manager.selectNext()
            case 11: name = "selectRandom"; manager.select(id: manager.ordered.randomElement(using: &rng)?.id)
            case 12: name = "dismiss"; if let a = manager.ordered.randomElement(using: &rng) { manager.dismiss(id: a.id) }
            case 13: name = "query"; if island.mode == .search { env.search.query = ["timer 5 min", "saf", "", "open notes", "x"].randomElement(using: &rng)! }
            case 14: name = "expand"; island.expand()
            default: name = "collapse"; island.collapse()
            }
            let ms = (CACurrentMediaTime() - t0) * 1000
            if ms > slowest.1 { slowest = (name, ms) }
            RunLoop.main.run(until: Date().addingTimeInterval(Double.random(in: 0.001...0.03, using: &rng)))
            violations += check(step: step, op: name)
        }

        // Settle: everything must end in a consistent resting state.
        island.mouseInsideChanged(false)
        island.collapse()
        manager.removeAll()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        violations += check(step: steps, op: "settle")
        if island.mode != .idle { violations.append("settle: mode \(island.mode) expected idle") }
        env.commands.media = savedMedia

        let report = """
        steps=\(steps) seconds=\(String(format: "%.1f", Date().timeIntervalSince(start)))
        slowest=\(slowest.0) \(String(format: "%.2f", slowest.1))ms
        violations=\(violations.count)
        \(violations.prefix(40).joined(separator: "\n"))
        """
        try? report.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("island-stress.txt"), atomically: true, encoding: .utf8)
        env.window.refreshMouseState()
    }

    private func check(step: Int, op: String) -> [String] {
        var v: [String] = []
        let island = env.island, m = env.manager, w = env.window
        func fail(_ s: String) { v.append("#\(step) after \(op): \(s)") }
        if m.primary?.id != m.ordered.first?.id { fail("primary != ordered.first") }
        if Set(m.ordered.map(\.id)).count != m.ordered.count { fail("duplicate ids") }
        if m.secondaries.count > m.maxSecondaries { fail("too many secondaries") }
        if m.secondaries.contains(where: { $0.id == m.primary?.id }) { fail("primary also secondary") }
        if !island.presentation.isExpanded {
            let expected: IslandMode = m.primary == nil ? .idle : .compact
            if island.mode != expected { fail("resting mode \(island.mode) expected \(expected)") }
        }
        let expanded = island.mode == .expanded || island.mode == .search
        if w.escapeArmed != expanded { fail("escape armed=\(w.escapeArmed) mode=\(island.mode)") }
        if w.panel.isKeyWindow && island.mode != .search { fail("panel key outside search") }
        if !w.panel.isVisible { fail("panel hidden") }
        let s = island.islandSize
        if !(s.width.isFinite && s.height.isFinite) || s.width <= 0 { fail("bad size \(s)") }
        if island.mode != .search, s.height > island.metrics.windowSize.height { fail("size exceeds window") }
        return v
    }
}

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
#endif
