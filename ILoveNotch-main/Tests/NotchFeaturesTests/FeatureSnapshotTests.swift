// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import Testing

@testable import NotchFeatures

/// Renders each feature tab with sample data inside a notch-sized black panel. Always checks that
/// it draws; with SNAPSHOT_DIR set, also writes PNGs there for eyeballing.
@MainActor
struct FeatureSnapshotTests {
    /// The content area of an expanded notch.
    private let size = CGSize(width: 428, height: 200)
    /// The content area of the smallest open notch.
    private static let smallest = CGSize(width: 350, height: 102)

    @Test func mediaWithATrack() throws {
        let media = MediaFeature(bundle: Bundle(for: SnapshotMarker.self))
        media.receive(
            NowPlaying(
                title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming", isPlaying: true,
                duration: 243, elapsed: 61, timestamp: Date(), artwork: Self.sampleArtwork(),
                appBundleID: "com.apple.Music", shuffle: true, repeatMode: .all))
        #expect(media.artwork != nil, "artwork is decoded into a thumbnail")
        try render(media.view, name: "media-playing")
    }

    @Test func mediaWithNothingPlaying() throws {
        try render(MediaFeature(bundle: Bundle(for: SnapshotMarker.self)).view, name: "media-idle")
    }

    @Test func shelfWithFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ShelfSnapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = try ["Invoice.pdf", "Screenshot.png", "Notes.txt", "Archive.zip"].map { name in
            let url = folder.appending(path: name)
            try Data(name.utf8).write(to: url)
            return url
        }
        let shelf = ShelfFeature(storeURL: folder.appending(path: "shelf.json"))
        shelf.add(files)
        try FileManager.default.removeItem(at: files[3])
        shelf.phase = .foreground  // Archive.zip now shows as missing
        try render(shelf.view, name: "shelf")
    }

    @Test func clipboardOffThenWithAHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ClipboardSnapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pasteboard = NSPasteboard(name: .init("ClipboardSnapshot.\(UUID().uuidString)"))
        let clipboard = ClipboardFeature(
            pasteboard: pasteboard, defaults: UserDefaults(suiteName: "CS-\(UUID())")!,
            storeURL: folder.appending(path: "clipboard.json"), imagesURL: folder.appending(path: "Clipboard"),
            frontmostApp: { ("com.apple.Safari", "Safari") })
        clipboard.phase = .foreground
        try render(clipboard.view, name: "clipboard-off")
        clipboard.startRecording()
        for text in ["Meeting at 4 in the big room", "https://github.com/niyamvora/ILoveNotch", "make install"] {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            clipboard.check()
        }
        clipboard.toggleFavorite(try #require(clipboard.items.last))
        try render(clipboard.view, name: "clipboard")
    }

    /// The tab as the notch shows it: white on black, dark mode, in the content area.
    private func inNotch(_ view: some View, size: CGSize) -> some View {
        view
            .frame(width: size.width, height: size.height)
            .padding(16)
            .background(.black)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
    }

    @Test func timerPresetsAndARunningCountdown() throws {
        let timer = TimerFeature()
        try render(timer.view, name: "timer-presets")
        timer.start(25 * 60)
        try render(timer.view, name: "timer-running")
        timer.mode = .stopwatch
        timer.toggleStopwatch(now: Date(timeIntervalSinceNow: -83.4))
        timer.lap(now: Date(timeIntervalSinceNow: -41))
        try render(timer.view, name: "stopwatch")
    }

    @Test func keepAwakeOffTimedAndUntilTurnedOff() throws {
        let timer = TimerFeature()
        timer.mode = .keepAwake
        try render(timer.view, name: "keep-awake")
        timer.keepAwake(for: 2 * 3600)
        try render(timer.view, name: "keep-awake-timed")
        timer.keepAwake(for: nil)
        try render(timer.view, name: "keep-awake-on")
        timer.allowSleep()
    }

    /// A month of made-up traffic, busiest in the evenings, then a download ramping up over the last
    /// minute; each range of the chart, and the tab with nothing recorded yet.
    @Test func networkLiveAndItsHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NetworkSnapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var counters = ["en0": Traffic()]
        let network = NetworkFeature(
            defaults: UserDefaults(suiteName: "NS-\(UUID())")!, storeURL: folder.appending(path: "network.sqlite"),
            netSpeedURL: nil, readCounters: { counters })
        network.phase = .foreground
        try render(network.view, name: "network-empty")
        network.phase = .stopped
        let now = Date.now
        for hour in stride(from: 30 * 24, through: 1, by: -1) {
            let evening = max(0, sin(Double(hour % 24) / 24 * .pi * 2 - 1.2))
            let noise = abs(sin(Double(hour) * 12.9898)) * 0.7
            counters["en0"]?.down += Int64(400_000_000 * (evening + noise) + 20_000_000)
            counters["en0"]?.up += Int64(60_000_000 * (evening + noise * 0.5) + 5_000_000)
            network.receive(counters, at: now - TimeInterval(hour * 3600) - 61)
        }
        for second in stride(from: 60, through: 0, by: -1) {
            let ramp = min(1, Double(60 - second) / 25)
            counters["en0"]?.down += Int64(24_000_000 * ramp * (0.85 + 0.15 * sin(Double(second))))
            counters["en0"]?.up += Int64(900_000 + 500_000 * abs(sin(Double(second) / 3)))
            network.receive(counters, at: now - TimeInterval(second))
        }
        network.phase = .foreground
        for range in HistoryRange.allCases {
            network.range = range
            try render(network.view, name: range == .day ? "network" : "network-\(range.rawValue)", settles: true)
        }
        network.phase = .stopped
    }

    @Test func notesWithAFewNotes() throws {
        let notes = NotesFeature(
            directory: FileManager.default.temporaryDirectory.appending(path: "N-\(UUID())"),
            defaults: UserDefaults(suiteName: "N-\(UUID())")!)
        notes.phase = .foreground
        try render(notes.view, name: "notes-empty")
        for text in ["Groceries\n- oat milk\n- coffee", "Ideas for the notch", "Meeting notes\nShip Phase 4"] {
            notes.update(notes.add(), text: text)
        }
        try render(notes.view, name: "notes")
        notes.search = "milk"  // search stays open while it has text
        try render(notes.view, name: "notes-searching")
        notes.search = ""
        let id = notes.add()
        notes.update(id, text: "Trip\n- [ ] passport\n- [x] tickets\n- socks")
        notes.setColor(id, .mint)
        try render(notes.view, name: "notes-checklist")
    }

    @Test func tasksWithACompletedSection() throws {
        let tasks = TasksFeature(eventStore: EventStore(), defaults: UserDefaults(suiteName: "T-\(UUID())")!)
        let now = Date.now
        tasks.show(
            tasks: [
                TaskItem(id: "1", title: "Send the invoice", due: now - 3600),
                TaskItem(id: "2", title: "Book flights", due: now + 86_400),
                TaskItem(id: "3", title: "Water the plants"),
            ],
            completed: [
                TaskItem(id: "4", title: "Ship Phase 4", completed: now - 600),
                TaskItem(id: "5", title: "Renew passport", completed: now - 90_000),
            ])
        tasks.showsCompleted = true
        try render(tasks.view, name: "tasks")
        tasks.show(
            tasks: [TaskItem(id: "6", title: "Stand-up", due: now, hasTime: true, priority: .high)], completed: [],
            alerting: TaskItem(id: "6", title: "Stand-up", due: now, hasTime: true))
        try render(tasks.view, name: "tasks-alert")
    }

    @Test func calendarWithEventsAndTasks() throws {
        let calendar = CalendarFeature(eventStore: EventStore(), defaults: UserDefaults(suiteName: "C-\(UUID())")!)
        let now = Date.now
        calendar.show(
            events: [
                DayEvent(
                    id: "1", title: "Design review", start: now - 1800, end: now + 1800,
                    color: RGB(red: 0.3, green: 0.6, blue: 1)),
                DayEvent(id: "2", title: "Gym", start: now + 7200, end: now + 10_800),
            ],
            dueTasks: [TaskItem(id: "3", title: "Pay rent", due: Calendar.current.startOfDay(for: now))])
        try render(calendar.view, name: "calendar")
        try render(CalendarView(calendar: calendar, editing: "2"), name: "calendar-editing")
        calendar.show(events: [DayEvent(id: "2", title: "Gym", start: now + 7200, end: now + 10_800)])
        let small = CalendarView(calendar: calendar, editing: "2")
        try render(small, name: "calendar-editing-smallest", size: Self.smallest)
    }

    @Test func calendarWithAMeetingToJoin() throws {
        let calendar = CalendarFeature(eventStore: EventStore(), defaults: UserDefaults(suiteName: "C-\(UUID())")!)
        let now = Date.now
        let meet = MeetingLink(URL(string: "https://meet.google.com/abc-defg-hij")!)
        calendar.show(events: [
            DayEvent(id: "1", title: "Standup", start: now - 7200, end: now - 6300, meeting: meet),
            DayEvent(id: "2", title: "Design review", start: now + 240, end: now + 3840, meeting: meet),
            DayEvent(id: "3", title: "Lunch with Sam", start: now + 7200, end: now + 10_800),
        ])
        try render(calendar.view, name: "calendar-meeting")
    }

    @Test func eventKitTabsBeforeAccess() throws {
        let store = EventStore()
        try render(CalendarFeature(eventStore: store).view, name: "calendar-no-access")
        try render(TasksFeature(eventStore: store).view, name: "tasks-no-access")
        try render(ShortcutsFeature().view, name: "shortcuts-loading")
    }

    /// Without a size, at the default size and again at the smallest, where every tab is tightest.
    /// `settles` draws it once what rises into place on appearing has (without animation, so at once).
    private func render(_ view: some View, name: String, size: CGSize? = nil, settles: Bool = false) throws {
        guard let size else {
            try render(view, name: name, size: self.size, settles: settles)
            return try render(view, name: name + "-smallest", size: Self.smallest, settles: settles)
        }
        let host = NSHostingView(rootView: inNotch(view, size: size).transaction { if settles { $0.animation = nil } })
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: size.width + 32, height: size.height + 32),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        if settles {
            RunLoop.main.run(until: .now + 0.1)
            host.layoutSubtreeIfNeeded()
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
        if let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(
                to: URL(filePath: directory).appending(path: "\(name).png"))
        }
    }

    /// A made-up album cover: a diagonal gradient, PNG-encoded like real artwork data.
    private static func sampleArtwork() -> Data? {
        let image = NSImage(size: CGSize(width: 600, height: 600), flipped: false) { rect in
            NSGradient(colors: [.systemPurple, .systemOrange])?.draw(in: rect, angle: 45)
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private final class SnapshotMarker {}
