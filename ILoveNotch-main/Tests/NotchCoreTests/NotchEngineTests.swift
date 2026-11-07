// SPDX-License-Identifier: MIT
import Testing

@testable import NotchCore

@MainActor
struct NotchEngineTests {
    @Test func presentationChangesAreReportedOnce() {
        let engine = NotchEngine()
        var changes: [NotchPresentationState] = []
        engine.onPresentationChange = { _, new in changes.append(new) }
        engine.send(.show)
        engine.send(.pointerExited)  // pointer bookkeeping only
        engine.send(.clicked)
        engine.send(.clicked)  // already open
        #expect(changes == [.compact, .expanded(tab: .media)])
    }

    @Test func timersFireThroughTheReducer() async throws {
        let engine = NotchEngine()
        engine.send(.show)
        engine.send(.pointerEntered)
        #expect(engine.pendingDeadlines == [.hoverDwell])
        #expect(await eventually { engine.state.presentation == .expanded(tab: .media) })
        #expect(engine.pendingDeadlines.isEmpty)
    }

    @Test func leavingAStateCancelsItsTimer() {
        let engine = NotchEngine()
        engine.send(.show)
        engine.send(.pointerEntered)
        engine.send(.pointerExited)
        #expect(engine.pendingDeadlines.isEmpty)
    }

    @Test func aMissedEnterCannotCollapseANotchThePointerIsOn() {
        let engine = NotchEngine()
        engine.pointerCheck = { PointerCheck(isInside: true, isButtonDown: false) }
        engine.send(.show)
        engine.send(.clicked)
        engine.send(.pointerExited)  // spurious: the pointer never left
        engine.fire(.collapseGrace)
        #expect(engine.state.presentation == .expanded(tab: .media))
        #expect(engine.state.pointerInside && engine.pendingDeadlines.isEmpty)
    }

    @Test func nothingCollapsesWhileAMouseButtonIsHeld() {
        let engine = NotchEngine()
        engine.pointerCheck = { PointerCheck(isInside: false, isButtonDown: true) }
        engine.send(.show)
        engine.send(.clicked)
        engine.send(.pointerExited)
        engine.fire(.collapseGrace)
        #expect(engine.state.presentation == .expanded(tab: .media))
        #expect(engine.pendingDeadlines == [.collapseGrace], "it looks again after another grace period")
        engine.pointerCheck = { PointerCheck(isInside: false, isButtonDown: false) }
        engine.fire(.collapseGrace)
        #expect(engine.state.presentation == .compact)
    }

    @Test func aStrayEnterCannotOpenTheNotch() {
        let engine = NotchEngine()
        engine.pointerCheck = { PointerCheck(isInside: false, isButtonDown: false) }
        engine.send(.show)
        engine.send(.pointerEntered)
        engine.fire(.hoverDwell)
        #expect(engine.state.presentation == .compact)
        #expect(engine.pendingDeadlines.isEmpty)
    }

    @Test func anInjectedDeadlineConsumesItsTimer() {
        let engine = NotchEngine()
        engine.send(.show)
        engine.send(.pointerEntered)
        engine.send(.deadline(.hoverDwell))
        #expect(engine.state.presentation == .expanded(tab: .media))
        #expect(engine.pendingDeadlines.isEmpty)
    }
}
