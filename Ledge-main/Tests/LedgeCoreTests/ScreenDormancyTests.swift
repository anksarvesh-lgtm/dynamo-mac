import Foundation
import LedgeCore
import Testing

/// Why the screen is dark, and when that answer changes.
@Suite("Screen dormancy")
struct ScreenDormancyTests {

    @Test("A fresh session is lit")
    func startsLit() {
        #expect(!ScreenDormancy().isDark)
    }

    @Test("Either reason alone darkens it")
    func eitherDarkens() {
        for reason in ScreenDormancy.Reason.allCases {
            var dormancy = ScreenDormancy()
            let changed = dormancy.set(reason, true)
            #expect(changed, "the answer changed")
            #expect(dormancy.isDark)
        }
    }

    /// The bug this type exists for: the lock screen does not sleep the
    /// displays straight away, and they wake on their own while the session
    /// stays locked. That wake used to clear one shared flag and start the
    /// pointer tracker and brightness watcher running behind the lock screen.
    @Test("Displays waking behind a locked session does not light it")
    func wakeWhileLocked() {
        var dormancy = ScreenDormancy()
        dormancy.set(.sessionLocked, true)
        dormancy.set(.displaysAsleep, true)
        let changed = dormancy.set(.displaysAsleep, false)
        #expect(!changed, "still dark, so nothing changed")
        #expect(dormancy.isDark, "the session is still locked")
    }

    @Test("Unlocking while the displays sleep does not light it either")
    func unlockWhileAsleep() {
        var dormancy = ScreenDormancy()
        dormancy.set(.displaysAsleep, true)
        dormancy.set(.sessionLocked, true)
        let changed = dormancy.set(.sessionLocked, false)
        #expect(!changed)
        #expect(dormancy.isDark, "the displays are still asleep")
    }

    @Test("The last reason leaving lights it, once")
    func lastReasonLights() {
        var dormancy = ScreenDormancy()
        dormancy.set(.displaysAsleep, true)
        dormancy.set(.sessionLocked, true)
        dormancy.set(.sessionLocked, false)
        let lit = dormancy.set(.displaysAsleep, false)
        #expect(lit, "the answer changed")
        #expect(!dormancy.isDark)
    }

    /// macOS repeats these notifications. A second one for a reason already
    /// held must not read as a fresh transition and restart the pollers.
    @Test("A repeated notification is not a transition")
    func repeatsAreQuiet() {
        var dormancy = ScreenDormancy()
        let darkened = dormancy.set(.displaysAsleep, true)
        let again = dormancy.set(.displaysAsleep, true)
        #expect(darkened)
        #expect(!again, "a repeat is not a transition")
        #expect(dormancy.isDark)
        let lit = dormancy.set(.displaysAsleep, false)
        let litAgain = dormancy.set(.displaysAsleep, false)
        #expect(lit)
        #expect(!litAgain)
    }

    @Test("A reason that never arrived can be cleared harmlessly")
    func clearingAnAbsentReason() {
        var dormancy = ScreenDormancy()
        let changed = dormancy.set(.sessionLocked, false)
        #expect(!changed)
        #expect(!dormancy.isDark)
    }

    @Test("Teardown forgets every reason")
    func teardown() {
        var dormancy = ScreenDormancy()
        dormancy.set(.displaysAsleep, true)
        dormancy.set(.sessionLocked, true)
        dormancy.clear()
        #expect(!dormancy.isDark)
        #expect(!dormancy.holds(.sessionLocked))
    }
}
