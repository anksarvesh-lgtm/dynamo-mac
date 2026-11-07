import AppKit
import IslandCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var env: AppEnvironment!
    private var statusItem: StatusItemController?
    #if DEBUG
    private var remote: DebugRemote?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.contains("--self-test") {
            let settings = IslandSettings(defaults: UserDefaults(suiteName: "island.selftest.\(UUID().uuidString)")!)
            env = AppEnvironment(settings: settings)
            SelfTest(env: env).run()
            return
        }
        env = AppEnvironment(settings: IslandSettings())
        statusItem = StatusItemController(env: env)
        env.start()
        #if DEBUG
        remote = DebugRemote(env: env)
        #endif
        if args.contains("--demo") { injectDemo() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        env.commands.perform(.openSettings)
        return false
    }

    private func injectDemo() {
        env.manager.submit(.upsert(DebugActivities.music()))
        env.timers.handle(.start(duration: 25 * 60, label: "Focus"))
        env.manager.submit(.upsert(DebugActivities.download()))
    }
}
