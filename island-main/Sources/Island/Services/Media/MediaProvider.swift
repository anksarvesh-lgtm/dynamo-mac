import AppKit
import IslandCore

/// An adapter that reads now-playing state from one app through public interfaces
/// (distributed notifications + the app's own AppleScript dictionary) and can send it commands.
/// Providers emit `MediaActivity` values only — they never touch the Island.
@MainActor
protocol MediaProvider: AnyObject {
    var bundleID: String { get }
    var displayName: String { get }
    /// Called with the latest state, or nil when the source stopped/quit.
    var onUpdate: ((MediaActivity?) -> Void)? { get set }
    func start()
    func stop()
    func perform(_ command: MediaCommand) async throws
}

extension MediaProvider {
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
}

/// Observes app launch/termination for a bundle id (event-driven; used to gate any work).
@MainActor
final class AppLifecycleObserver {
    private var tokens: [NSObjectProtocol] = []

    init(bundleID: String, onLaunch: @escaping () -> Void, onTerminate: @escaping () -> Void) {
        let nc = NSWorkspace.shared.notificationCenter
        let matches: @Sendable (Notification) -> Bool = { n in
            (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == bundleID
        }
        tokens.append(nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { n in
            if matches(n) { MainActor.assumeIsolated { onLaunch() } }
        })
        tokens.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { n in
            if matches(n) { MainActor.assumeIsolated { onTerminate() } }
        })
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        tokens.forEach(nc.removeObserver)
    }
}
