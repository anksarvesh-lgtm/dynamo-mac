import AppKit
import IslandCore

/// Headless smoke test run by `Island --self-test` (CI + scripts/test.sh). Exercises the real window,
/// view model and manager: launch → compact → hover/expand → interaction → collapse → switching.
@MainActor
struct SelfTest {
    let env: AppEnvironment

    func run() {
        var failures: [String] = []
        func check(_ cond: @autoclosure () -> Bool, _ name: String) {
            if cond() { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures.append(name) }
        }
        print("Island self-test")
        env.start(providers: false)
        // Never touch real media apps / media keys from a test.
        env.commands.media = { _, _ in }
        let island = env.island, manager = env.manager
        manager.schedulesExpiry = false

        check(env.window.panel.isVisible || NSScreen.screens.isEmpty, "launch: window visible")
        check(island.geometry != nil || NSScreen.screens.isEmpty, "display: geometry resolved")
        check(island.mode == .idle, "idle with no activities")
        check(env.window.panel.ignoresMouseEvents, "idle window passes mouse through")

        manager.submit(.upsert(DebugActivities.music()))
        drain()
        check(island.mode == .compact, "compact when media starts")
        let compactSize = island.islandSize

        island.apply(.hoverBegan)
        check(island.mode == .expanded, "hover expands")
        check(island.islandSize.width > compactSize.width && island.islandSize.height > compactSize.height, "expanded is larger")

        env.commands.perform(.media(.togglePlayPause, sourceBundleID: "com.apple.Music"))
        check(env.commands.lastCommand == .media(.togglePlayPause, sourceBundleID: "com.apple.Music"), "interaction routes command")

        island.apply(.hoverEnded)
        check(island.mode == .compact, "hover exit collapses")
        check(island.islandSize == compactSize, "collapse restores compact size")

        env.timers.handle(.start(duration: 600, label: "Test"))
        manager.submit(.upsert(DebugActivities.download()))
        drain()
        check(manager.primary?.kind == .media, "incumbent media stays primary")
        check(manager.secondaries.count == 2, "two minimal activities")

        manager.submit(.upsert(DebugActivities.criticalEvent()))
        check(manager.primary?.kind == .call, "critical event takes over")
        manager.dismiss(id: "event.critical")
        check(manager.primary?.kind == .media, "previous activity returns")

        env.commands.perform(.ui(.selectNext))
        check(manager.primary?.kind != .media, "switch activity")

        island.toggleSearch()
        check(island.mode == .search, "search mode")
        island.escape()
        check(island.mode == .compact, "escape leaves search")

        manager.submit(.upsert(Activity(id: "", kind: .custom, priority: .normal, content: .event(SystemEventActivity(symbol: "", title: "x")))))
        check(manager.activity(id: "") == nil, "malformed activity rejected")

        manager.removeAll()
        drain()
        check(island.mode == .idle, "returns to idle")

        print(failures.isEmpty ? "SELF-TEST PASSED" : "SELF-TEST FAILED: \(failures.count)")
        fflush(stdout)
        exit(failures.isEmpty ? 0 : 1)
    }

    /// Let main-queue observation callbacks run.
    private func drain() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}
