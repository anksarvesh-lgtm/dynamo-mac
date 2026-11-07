import AppKit
import IslandCore
import SwiftUI

/// Developer panel: live state of the activity engine, display, window and performance, plus buttons
/// that inject test activities through the real ActivityManager pipeline.
struct DebugPanelView: View {
    let env: AppEnvironment
    let perf: PerformanceMonitor

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("Island") {
                        row("Mode", env.island.mode.rawValue)
                        row("Expansion reason", env.island.presentation.reason.rawValue)
                        row("Animating", env.island.isAnimating ? "yes" : "no")
                        row("Transitions", "\(env.island.transitionCount)")
                        row("Island size", fmt(env.island.islandSize))
                        row("Window frame", "\(env.window.panel.frame)")
                        row("Mouse pass-through", env.window.panel.ignoresMouseEvents ? "yes" : "no")
                    }
                    section("Activities") {
                        row("Primary", env.manager.primary.map { "\($0.id) [\($0.priority)]" } ?? "—")
                        row("Previous", env.manager.previousPrimaryID ?? "—")
                        row("Pinned", env.manager.pinnedID ?? "—")
                        ForEach(env.manager.ordered) { a in
                            row("• \(a.kind.rawValue)", "\(a.id) [\(a.priority)]\(a.expiresAt.map { " expires \(Int($0.timeIntervalSinceNow))s" } ?? "")")
                        }
                    }
                    section("Display") {
                        if let g = env.display.geometry {
                            row("Screen", g.screen.name)
                            row("Notch", g.hasNotch ? "\(g.notchRect)" : "none (virtual \(fmt(g.notchSize)))")
                            row("Scale", "\(g.screen.backingScale)×")
                        }
                        row("Screens", "\(env.display.screens.count)")
                    }
                    section("Performance") {
                        row("CPU", String(format: "%.1f%%", perf.cpuPercent))
                        row("Memory", String(format: "%.1f MB", perf.memoryMB))
                        row("Main-thread FPS", String(format: "%.0f", perf.fps))
                        row("Providers", env.runningProviders.joined(separator: ", "))
                        row("Media sources", env.media.states.keys.sorted().joined(separator: ", "))
                        if let e = env.media.lastError { row("Media error", e) }
                    }
                    section("Event log") {
                        ForEach(env.manager.log.suffix(20).reversed()) { e in
                            Text("\(Formatters.time.string(from: e.date))  \(e.message)").font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 420)

            VStack(alignment: .leading, spacing: 8) {
                Text("Test").font(.headline)
                Button("Test Music") { env.manager.submit(.upsert(DebugActivities.music())) }
                Button("Test Spotify switch") { env.manager.submit(.upsert(DebugActivities.music(source: "com.spotify.client", name: "Spotify"))) }
                Button("Test Timer (1 min)") { env.timers.handle(.start(duration: 60, label: "Test")) }
                Button("Test Timer (5 s)") { env.timers.handle(.start(duration: 5, label: "Quick")) }
                Button("Test Download") { env.manager.submit(.upsert(DebugActivities.download())) }
                Button("Test Recording") { env.manager.submit(.upsert(DebugActivities.recording())) }
                Button("Test Battery") { env.manager.submit(.upsert(DebugActivities.battery())) }
                Button("Test Critical Event") { env.manager.submit(.upsert(DebugActivities.criticalEvent())) }
                Button("Test Malformed Event") {
                    env.manager.submit(.upsert(Activity(id: "", kind: .timer, priority: .critical, content: .event(SystemEventActivity(symbol: "", title: "")))))
                }
                Divider()
                Text("Island").font(.headline)
                Button("Expand") { env.island.expand() }
                Button("Collapse") { env.island.collapse() }
                Button("Search") { env.commands.perform(.ui(.toggleSearch)) }
                Button("Switch Activity") { env.manager.selectNext() }
                Button("Clear All", role: .destructive) { env.manager.removeAll() }
                Spacer()
            }
            .buttonStyle(.bordered)
            .padding(16)
            .frame(width: 200)
        }
        .frame(minWidth: 680, minHeight: 520)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            content()
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(v).textSelection(.enabled)
        }
        .font(.system(size: 11.5, design: .monospaced))
    }

    private func fmt(_ s: CGSize) -> String { "\(Int(s.width))×\(Int(s.height))" }
}

/// Small always-on-top HUD (Settings › Advanced › Performance overlay).
struct PerformanceOverlayView: View {
    let env: AppEnvironment
    let perf: PerformanceMonitor
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "CPU %.1f%%   MEM %.0f MB   FPS %.0f", perf.cpuPercent, perf.memoryMB, perf.fps))
            Text("mode \(env.island.mode.rawValue) · primary \(env.manager.primary?.kind.rawValue ?? "—")")
            Text("queue \(env.manager.ordered.count) · events \(env.manager.log.count)")
        }
        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.75)))
        .fixedSize()
    }
}

@MainActor
final class DebugWindows {
    let perf = PerformanceMonitor()
    private var panel: NSWindow?
    private var overlay: NSPanel?

    func showPanel(env: AppEnvironment) {
        if panel == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Island Debug"
            w.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: DebugPanelView(env: env, perf: perf))
            w.contentView = host
            w.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.perf.release() }
            }
            panel = w
        }
        if panel?.isVisible == false { perf.acquire(view: panel?.contentView) }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func setOverlay(_ on: Bool, env: AppEnvironment) {
        if on, overlay == nil {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .statusBar
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            let host = NSHostingView(rootView: PerformanceOverlayView(env: env, perf: perf))
            p.contentView = host
            let size = host.fittingSize
            if let screen = NSScreen.main {
                p.setFrame(NSRect(x: screen.visibleFrame.maxX - 300, y: screen.visibleFrame.maxY - size.height - 10, width: 290, height: max(size.height, 52)), display: true)
            }
            p.orderFrontRegardless()
            perf.acquire(view: host)
            overlay = p
        } else if !on, let p = overlay {
            p.orderOut(nil)
            overlay = nil
            perf.release()
        }
    }
}
