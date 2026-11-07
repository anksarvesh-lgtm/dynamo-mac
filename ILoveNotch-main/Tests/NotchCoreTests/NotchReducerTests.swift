// SPDX-License-Identifier: MIT
import Foundation
import Testing

@testable import NotchCore

private let song = Activity(feature: .media, symbol: "music.note", title: "Song", duration: .seconds(2))
private let drop = Activity(feature: .shelf, symbol: "tray.full", title: "2 files", duration: .seconds(1))
/// A system activity: it belongs to no tab.
private let volume = Activity(
    feature: nil, symbol: "speaker.wave.2.fill", title: "50%", level: 0.5, duration: .seconds(1))
/// An ongoing activity: it stays in the resting notch until its feature clears it.
private let meeting = Activity(
    feature: .calendar, symbol: "video.fill", title: "Standup", duration: .zero,
    countdown: Date(timeIntervalSince1970: 1_790_000_000))

/// The state a fresh reducer reaches after `events`.
private func after(_ events: NotchEvent...) -> NotchState { after(events) }

private func after(_ events: [NotchEvent]) -> NotchState {
    var state = NotchState()
    for event in events { _ = state.handle(event) }
    return state
}

struct NotchReducerTests {
    @Test func startsHiddenAndShowRevealsTheCompactNotch() {
        var state = NotchState()
        #expect(state.presentation == .hidden)
        #expect(state.handle(.show).isEmpty)
        #expect(state.presentation == .compact)
    }

    @Test(arguments: [NotchEvent.pointerEntered, .clicked, .selectTab(.notes), .activity(song), .dragEntered])
    func hiddenIgnoresEverythingButShow(event: NotchEvent) {
        var state = NotchState()
        #expect(state.handle(event).isEmpty)
        #expect(state.presentation == .hidden)
    }

    @Test func hoverExpandsOnlyAfterTheDwell() {
        var state = after(.show)
        #expect(state.handle(.pointerEntered) == [.schedule(.hoverDwell, after: NotchTiming.hoverDwell)])
        #expect(state.presentation == .hoverArmed)
        #expect(state.handle(.deadline(.hoverDwell)).isEmpty)
        #expect(state.presentation == .expanded(tab: .media))
    }

    @Test func aQuickPassDoesNotExpand() {
        var state = after(.show, .pointerEntered)
        #expect(state.handle(.pointerExited) == [.cancel(.hoverDwell)])
        #expect(state.presentation == .compact)
    }

    @Test func clickingExpandsWithoutWaiting() {
        #expect(after(.show, .clicked).presentation == .expanded(tab: .media))
        var state = after(.show, .pointerEntered)
        #expect(state.handle(.clicked) == [.cancel(.hoverDwell)])
        #expect(state.presentation == .expanded(tab: .media))
    }

    @Test func leavingStartsTheCollapseGraceAndReturningCancelsIt() {
        var state = after(.show, .clicked)
        #expect(state.handle(.pointerExited) == [.schedule(.collapseGrace, after: NotchTiming.collapseGrace)])
        #expect(state.handle(.pointerEntered) == [.cancel(.collapseGrace)])
        // A deadline that fires late, after the pointer came back, must not collapse the notch.
        #expect(state.handle(.deadline(.collapseGrace)).isEmpty)
        #expect(state.presentation == .expanded(tab: .media))
    }

    @Test func theGraceRunningOutCollapses() {
        var state = after(.show, .clicked, .pointerExited)
        #expect(state.handle(.deadline(.collapseGrace)).isEmpty)
        #expect(state.presentation == .compact)
    }

    @Test(arguments: [NotchEvent.clickedOutside, .dismiss])
    func clickAwayAndEscapeCloseTheExpandedNotch(event: NotchEvent) {
        #expect(after(.show, .clicked, event).presentation == .compact)
    }

    @Test func pinnedStaysOpenUntilDismissed() {
        var state = after(.show, .clicked, .togglePin)
        #expect(state.presentation == .pinned(tab: .media))
        #expect(state.presentation.isPinned)
        #expect(state.handle(.pointerExited).isEmpty)
        #expect(state.handle(.clickedOutside).isEmpty)
        #expect(state.presentation == .pinned(tab: .media))
        #expect(state.handle(.dismiss).isEmpty)
        #expect(state.presentation == .compact)
    }

    @Test func pinningCancelsAPendingCollapse() {
        var state = after(.show, .clicked, .pointerExited)
        #expect(state.handle(.togglePin) == [.cancel(.collapseGrace)])
        #expect(state.presentation == .pinned(tab: .media))
        #expect(state.handle(.togglePin).isEmpty)
        #expect(state.presentation == .expanded(tab: .media))
    }

    @Test(arguments: [false, true])
    func textInputReturnsToWhereItStarted(pinned: Bool) {
        var state = after(pinned ? [.show, .clicked, .togglePin] : [.show, .clicked])
        _ = state.handle(.beginTextInput)
        #expect(state.presentation == .focused(tab: .media, pinned: pinned))
        // Moving the pointer away mid-sentence must not close the notch.
        #expect(state.handle(.pointerExited).isEmpty)
        _ = state.handle(.endTextInput)
        #expect(state.presentation == (pinned ? .pinned(tab: .media) : .expanded(tab: .media)))
    }

    @Test func clickingAwayEndsTextInputButKeepsAPin() {
        #expect(after(.show, .clicked, .beginTextInput, .clickedOutside).presentation == .compact)
        let pinned = after(.show, .clicked, .togglePin, .beginTextInput, .clickedOutside)
        #expect(pinned.presentation == .pinned(tab: .media))
    }

    @Test func switchingTabsWhileTypingKeepsFocusAndThePin() {
        // The panel still has the keyboard, so leaving focus here would need a visible hand-back.
        let unpinned = after(.show, .clicked, .beginTextInput, .selectTab(.notes))
        #expect(unpinned.presentation == .focused(tab: .notes, pinned: false))
        let pinned = after(.show, .clicked, .togglePin, .beginTextInput, .selectTab(.notes), .endTextInput)
        #expect(pinned.presentation == .pinned(tab: .notes))
        let dragged = after(.show, .clicked, .beginTextInput, .dragEntered)
        #expect(dragged.presentation == .focused(tab: .shelf, pinned: false))
    }

    @Test func theLastTabIsRemembered() {
        #expect(after(.show, .clicked, .selectTab(.notes), .dismiss, .clicked).presentation == .expanded(tab: .notes))
    }

    @Test func anActivityShowsUntilItsDeadline() {
        var state = after(.show)
        #expect(state.handle(.activity(song)) == [.schedule(.activityEnd, after: song.duration)])
        #expect(state.presentation == .transient(song))
        #expect(state.handle(.deadline(.activityEnd)).isEmpty)
        #expect(state.presentation == .compact)
    }

    @Test func aNewActivityReplacesTheCurrentOne() {
        var state = after(.show, .activity(song))
        #expect(state.handle(.activity(drop)) == [.schedule(.activityEnd, after: drop.duration)])
        #expect(state.presentation == .transient(drop))
    }

    @Test func hoveringAnActivityOpensItsFeature() {
        var state = after(.show, .activity(drop))
        let effects = state.handle(.pointerEntered)
        #expect(effects == [.cancel(.activityEnd), .schedule(.hoverDwell, after: NotchTiming.hoverDwell)])
        _ = state.handle(.deadline(.hoverDwell))
        #expect(state.presentation == .expanded(tab: .shelf))
        #expect(after(.show, .activity(drop), .clicked).presentation == .expanded(tab: .shelf))
    }

    @Test func aSystemActivityShowsWhateverTabsAreEnabledAndOpensTheLastTab() {
        #expect(after(.show, .setTabs([.notes]), .activity(volume)).presentation == .transient(volume))
        #expect(after(.show, .setTabs([]), .activity(volume)).presentation == .transient(volume))
        let retabbed = after(.show, .activity(volume), .setTabs([.notes]))
        #expect(retabbed.presentation == .transient(volume), "it has no tab to lose")
        let opened = after(.show, .clicked, .selectTab(.tasks), .dismiss, .activity(volume), .clicked)
        #expect(opened.presentation == .expanded(tab: .tasks), "a system activity opens the last tab")
        var hovered = after(.show, .activity(volume))
        _ = hovered.handle(.pointerEntered)
        _ = hovered.handle(.deadline(.hoverDwell))
        #expect(hovered.presentation == .expanded(tab: .media))
        #expect(after(.show, .setTabs([]), .activity(volume), .pointerEntered).presentation == .transient(volume))
    }

    @Test func anOngoingActivityRestsInTheClosedNotchUntilItsFeatureClearsIt() {
        var state = after(.show)
        #expect(state.handle(.setOngoing(meeting)).isEmpty, "no deadline: it stays until it's cleared")
        #expect(state.presentation == .compact && state.restingActivity == meeting)
        _ = state.handle(.setOngoing(nil))
        #expect(state.restingActivity == nil)
        #expect(after(.setOngoing(meeting), .show).restingActivity == meeting, "it waits while the notch is hidden")
    }

    @Test func hoveringOrClickingAnOngoingActivityOpensItsFeature() {
        var hovered = after(.show, .setOngoing(meeting))
        _ = hovered.handle(.pointerEntered)
        #expect(hovered.restingActivity == meeting, "hovered, it stays in view, so the pointer stays on it")
        _ = hovered.handle(.deadline(.hoverDwell))
        #expect(hovered.presentation == .expanded(tab: .calendar))
        #expect(after(.show, .setOngoing(meeting), .clicked).presentation == .expanded(tab: .calendar))
        let closed = after(.show, .setOngoing(meeting), .clicked, .dismiss)
        #expect(closed.restingActivity == meeting, "and it's back when the notch closes")
    }

    @Test func oneShotActivitiesShowOverAnOngoingOne() {
        var state = after(.show, .setOngoing(meeting), .activity(song))
        #expect(state.presentation == .transient(song) && state.restingActivity == nil)
        _ = state.handle(.deadline(.activityEnd))
        #expect(state.restingActivity == meeting)
    }

    @Test func anOngoingActivityRestsOnlyWhileItsFeatureIsEnabled() {
        #expect(after(.show, .setOngoing(meeting), .setTabs([.notes])).restingActivity == nil)
        #expect(after(.show, .setTabs([.notes]), .setOngoing(meeting), .clicked).presentation == .expanded(tab: .notes))
        let system = Activity(feature: nil, symbol: "bell.fill", title: "Hi", duration: .zero)
        #expect(after(.show, .setTabs([]), .setOngoing(system)).restingActivity == system, "a system one always rests")
    }

    @Test func activitiesDoNotInterruptAnOpenNotch() {
        var state = after(.show, .clicked)
        #expect(state.handle(.activity(song)).isEmpty)
        #expect(state.presentation == .expanded(tab: .media))
    }

    @Test func draggingFilesOverTheNotchOpensTheShelf() {
        var state = after(.show)
        #expect(state.handle(.dragEntered).isEmpty)
        #expect(state.presentation == .expanded(tab: .shelf))
        #expect(state.handle(.dragExited) == [.schedule(.collapseGrace, after: NotchTiming.collapseGrace)])
        // Dragging back in cancels the collapse; dropping keeps the shelf open under the pointer.
        #expect(state.handle(.dragEntered) == [.cancel(.collapseGrace)])
        #expect(state.handle(.dropped) == [.cancel(.collapseGrace)])
        #expect(state.presentation == .expanded(tab: .shelf))
        #expect(state.pointerInside)
    }

    @Test func draggingKeepsAPinAndIgnoresADisabledShelf() {
        #expect(after(.show, .clicked, .togglePin, .dragEntered).presentation == .pinned(tab: .shelf))
        #expect(after(.show, .setTabs([.media, .notes]), .dragEntered).presentation == .compact)
    }

    @Test func overlappingSuspensionsAllHaveToClear() {
        var state = after(.show, .clicked, .pointerExited)
        #expect(state.handle(.suspend(.screenLocked)) == [.cancel(.collapseGrace)])
        _ = state.handle(.suspend(.systemSleep))
        #expect(state.handle(.clicked).isEmpty)
        #expect(state.handle(.activity(song)).isEmpty)
        _ = state.handle(.resume(.systemSleep))
        #expect(state.presentation == .suspended, "still locked")
        _ = state.handle(.resume(.screenLocked))
        #expect(state.presentation == .compact)
    }

    @Test func aNotchShownWhileSuspendedStartsSuspended() {
        #expect(after(.suspend(.displaySleep), .show).presentation == .suspended)
        #expect(after(.suspend(.displaySleep), .show, .resume(.displaySleep)).presentation == .compact)
    }

    @Test func disablingTheOpenTabMovesToTheNextEnabledOne() {
        let pinned = after(.show, .clicked, .togglePin, .setTabs([.shelf, .notes]))
        #expect(pinned.presentation == .pinned(tab: .shelf))
        #expect(pinned.lastTab == .shelf)
        #expect(after(.show, .clicked, .setTabs([])).presentation == .compact)
    }

    @Test func disabledFeaturesNeverOpenOrRaiseActivities() {
        #expect(after(.show, .setTabs([.notes]), .selectTab(.media)).presentation == .expanded(tab: .notes))
        #expect(after(.show, .setTabs([.notes]), .activity(song)).presentation == .compact)
        #expect(after(.show, .activity(song), .setTabs([.notes])).presentation == .compact)
        #expect(after(.show, .setTabs([]), .clicked).presentation == .compact)
    }

    @Test(arguments: [
        [NotchEvent.show], [.show, .pointerEntered], [.show, .clicked], [.show, .clicked, .togglePin],
        [.show, .clicked, .beginTextInput], [.show, .activity(song)], [.show, .suspend(.systemSleep)],
    ])
    func hideWorksFromEveryStateAndCancelsItsDeadline(path: [NotchEvent]) {
        var state = after(path)
        let owned = state.presentation.deadline
        #expect(state.handle(.hide) == (owned.map { [.cancel($0)] } ?? []))
        #expect(state.presentation == .hidden)
        #expect(!state.pointerInside)
    }

    /// Drives random events through the reducer while simulating a correct timer layer, checking
    /// after every step the invariants that the engine and the surface rely on.
    @Test func randomEventStreamsKeepTheInvariants() throws {
        var rng = SplitMix64(state: 0x0A11_CE5E_ED00_0001)
        let reasons: [SuspendReason] = [.systemSleep, .displaySleep, .screenLocked]
        let inputs: [NotchEvent] =
            [
                .show, .hide, .pointerEntered, .pointerExited, .clicked, .clickedOutside, .dismiss, .togglePin,
                .beginTextInput, .endTextInput, .dragEntered, .dragExited, .dropped, .activity(song),
                .activity(drop), .activity(volume), .setTabs(FeatureID.allCases), .setTabs([.notes, .shelf]),
                .setTabs([]), .setOngoing(meeting), .setOngoing(nil),
            ] + FeatureID.allCases.map(NotchEvent.selectTab) + reasons.map(NotchEvent.suspend)
            + reasons.map(NotchEvent.resume)
        var state = NotchState()
        var pending: Set<Deadline> = []
        var visited: Set<Substring> = []

        for _ in 0..<50_000 {
            let event: NotchEvent
            if let deadline = pending.first, Bool.random(using: &rng) {
                pending.remove(deadline)
                event = .deadline(deadline)
            } else {
                event = inputs.randomElement(using: &rng)!
            }
            for effect in state.handle(event) {
                switch effect {
                case .schedule(let deadline, _): pending.insert(deadline)
                case .cancel(let deadline): pending.remove(deadline)
                }
            }
            visited.insert(String(describing: state.presentation).prefix { $0 != "(" })

            let presentation = state.presentation
            let owned = Set([presentation.deadline].compactMap { $0 })
            try #require(pending.isSubset(of: owned), "\(event) left \(pending) pending in \(presentation)")
            if let tab = presentation.openTab {
                try #require(tab == state.lastTab)
                try #require(state.tabs.contains(tab), "\(event) opened disabled \(tab)")
            }
            if case .transient(let activity) = presentation, let feature = activity.feature {
                try #require(state.tabs.contains(feature), "\(event) showed a disabled feature's activity")
            }
            if let resting = state.restingActivity {
                let closed = presentation == .compact || presentation == .hoverArmed
                try #require(closed, "\(event) showed an ongoing activity in \(presentation)")
                try #require(resting.feature.map(state.tabs.contains) ?? true, "\(event) rested a disabled feature")
            }
            if presentation == .hoverArmed { try #require(state.pointerInside) }
            if presentation != .hidden {
                try #require((presentation == .suspended) == !state.suspensions.isEmpty, "\(event) → \(presentation)")
            }
        }
        #expect(visited.count == 8, "fuzzing only reached \(visited.sorted())")
    }
}

/// Small deterministic generator, so a fuzz failure replays exactly.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
