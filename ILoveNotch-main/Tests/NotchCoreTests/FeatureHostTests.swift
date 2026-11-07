// SPDX-License-Identifier: MIT
import Testing

@testable import NotchCore

/// Records every phase the host moves it through.
@MainActor
private final class RecordingFeature: NotchFeature {
    let id: FeatureID
    private(set) var history: [FeaturePhase] = []
    var phase: FeaturePhase = .stopped { didSet { history.append(phase) } }

    init(_ id: FeatureID) { self.id = id }
}

@MainActor
struct FeatureHostTests {
    private let all = Set(FeatureID.allCases)

    @Test func featuresFollowTheActivationPolicy() {
        let media = RecordingFeature(.media)
        let notes = RecordingFeature(.notes)
        let host = FeatureHost([media, notes])

        host.update(presentations: [.compact], enabled: all)
        #expect(media.phase == .background && notes.phase == .background)
        host.update(presentations: [.expanded(tab: .media)], enabled: all)
        #expect(media.phase == .foreground && notes.phase == .background)
        host.update(presentations: [.pinned(tab: .notes)], enabled: all)
        #expect(media.phase == .background && notes.phase == .foreground)
        host.update(presentations: [.suspended], enabled: all)
        #expect(media.phase == .stopped && notes.phase == .stopped)
        #expect(media.history == [.background, .foreground, .background, .stopped])
    }

    @Test func aFeatureRunsAtTheHighestPhaseAnyDisplayAsks() {
        let media = RecordingFeature(.media)
        let host = FeatureHost([media])
        host.update(presentations: [.compact, .expanded(tab: .media)], enabled: all)
        #expect(media.phase == .foreground)
        host.update(presentations: [.suspended, .compact], enabled: all)
        #expect(media.phase == .background)
        host.update(presentations: [], enabled: all)
        #expect(media.phase == .stopped)
    }

    @Test func aLiveActivityBringsItsFeatureForward() {
        let shelf = RecordingFeature(.shelf)
        let host = FeatureHost([shelf])
        let activity = Activity(feature: .shelf, symbol: "tray.full", title: "1 file", duration: .seconds(1))
        host.update(presentations: [.transient(activity)], enabled: all)
        #expect(shelf.phase == .foreground)
    }

    @Test func disabledFeaturesStayStopped() {
        let media = RecordingFeature(.media)
        let host = FeatureHost([media])
        host.update(presentations: [.expanded(tab: .media)], enabled: [.notes])
        #expect(media.phase == .stopped)
        #expect(media.history.isEmpty, "a phase that doesn't change must not be reassigned")
    }
}
