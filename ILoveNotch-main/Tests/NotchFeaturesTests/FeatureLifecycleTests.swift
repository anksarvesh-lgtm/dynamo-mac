// SPDX-License-Identifier: MIT
import Foundation
import NotchCore
import Testing

@testable import NotchFeatures

/// The Phase 4 exit: every module starts, suspends, resumes, and releases its resources correctly,
/// driven the way the app drives it, through the FeatureHost.
@MainActor
struct FeatureLifecycleTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "Lifecycle-\(UUID().uuidString)")
    private let defaults = UserDefaults(suiteName: "Lifecycle.\(UUID().uuidString)")!

    @Test func everyFeatureFollowsTheNotchThroughASessionAndReleasesEverything() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let eventStore = EventStore()
        let media = MediaFeature(bundle: Bundle(for: LifecycleMarker.self), defaults: defaults)
        let shelf = ShelfFeature(storeURL: folder.appending(path: "shelf.json"))
        let calendar = CalendarFeature(eventStore: eventStore, defaults: defaults)
        let tasks = TasksFeature(eventStore: eventStore, defaults: defaults)
        let notes = NotesFeature(directory: folder.appending(path: "Notes"))
        let shortcuts = ShortcutsFeature(defaults: defaults)
        let timer = TimerFeature()
        let mirror = MirrorFeature()
        let features: [any NotchFeature] = [media, shelf, calendar, tasks, notes, shortcuts, timer, mirror]
        let host = FeatureHost(features)
        let enabled = Set(FeatureID.allCases)
        let song = Activity(feature: .media, symbol: "music.note", title: "Song", duration: .seconds(1))

        // A session: shown, every tab opened in turn, a live activity, sleep, wake, then quit.
        var session: [NotchPresentationState] = [.compact]
        session += FeatureID.allCases.map { .expanded(tab: $0) }
        session += [.transient(song), .suspended, .compact]
        for presentation in session {
            host.update(presentations: [presentation], enabled: enabled)
            for feature in features {
                #expect(feature.phase == presentation.phase(for: feature.id), "\(feature.id) at \(presentation)")
            }
            if presentation == .expanded(tab: .notes) { notes.update(notes.add(), text: "written during the session") }
        }

        #expect(media.isListening, "media keeps a cheap listener in the background")
        host.update(presentations: [], enabled: enabled)  // quit

        #expect(features.allSatisfy { $0.phase == .stopped })
        #expect(!media.isListening && media.nowPlaying == nil && !media.audio.isRunning)
        #expect(!calendar.isObserving && calendar.events.isEmpty)
        #expect(!tasks.isObserving && tasks.tasks.isEmpty)
        #expect(notes.notes.isEmpty, "notes leave memory")
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "Notes").path).count == 1,
            "and what was typed is on disk")
        #expect(shortcuts.shortcuts.isEmpty)
        #expect(!mirror.isRunning, "the camera is off")
    }

    @Test func disablingAFeatureStopsItWhileTheNotchIsOpen() {
        let media = MediaFeature(bundle: Bundle(for: LifecycleMarker.self), defaults: defaults)
        let host = FeatureHost([media])
        host.update(presentations: [.expanded(tab: .media)], enabled: [.media])
        #expect(media.isListening)
        host.update(presentations: [.expanded(tab: .media)], enabled: [])
        #expect(media.phase == .stopped && !media.isListening)
    }
}

private final class LifecycleMarker {}
