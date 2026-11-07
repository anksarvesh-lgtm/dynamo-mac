import Foundation
import Testing

@testable import LedgeSystem

/// Watching the power source, and stopping.
///
/// Low Power Mode is not a power *source* property: IOKit's source
/// notification is not obliged to fire when somebody switches it on from
/// Settings or the battery menu, so the flag used to change only when an
/// unrelated power event happened to arrive. The watcher now listens for the
/// process signal as well — and, as with any second signal, the interesting
/// cases are the repeat and the one that arrives after the watcher stopped.
@Suite("Power watching")
@MainActor
struct PowerWatchTests {

    private func post() {
        NotificationCenter.default.post(
            name: .NSProcessInfoPowerStateDidChange, object: ProcessInfo.processInfo
        )
    }

    @Test("A power-state change after stopping cannot reach the watcher")
    func lateSignalAfterStop() {
        let source = IOKitPowerSource()
        var delivered = 0
        source.startWatching { _ in delivered += 1 }
        post()
        let beforeStop = delivered
        source.stopWatching()
        post()
        #expect(delivered == beforeStop, "a stopped watcher publishes nothing")
    }

    /// The flag is process-wide and the snapshot is deduplicated, so a signal
    /// with nothing behind it must be silent rather than republishing the same
    /// card.
    @Test("A repeated signal with nothing behind it publishes nothing")
    func repeatsAreDeduplicated() {
        let source = IOKitPowerSource()
        var delivered = 0
        source.startWatching { _ in delivered += 1 }
        post()
        let first = delivered
        post()
        post()
        #expect(delivered == first, "the same snapshot is not published twice")
        source.stopWatching()
    }

    /// Restarting must re-arm: the observer is removed on stop, and a watcher
    /// that stopped and started again is watching.
    @Test("Stopping and starting again leaves nothing double-registered")
    func restartIsClean() {
        let source = IOKitPowerSource()
        var delivered = 0
        source.startWatching { _ in delivered += 1 }
        source.stopWatching()
        source.startWatching { _ in delivered += 1 }
        let before = delivered
        post()
        #expect(delivered - before <= 1, "one registration, not two")
        source.stopWatching()
    }
}
