// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import SwiftUI
import Testing

@testable import NotchSurface

/// Renders the notch offscreen in every state. Always checks that each state draws; with
/// SNAPSHOT_DIR set, also writes PNGs there for eyeballing:
///
///     SNAPSHOT_DIR=/tmp/notch swift test --filter Snapshot
private let notched = NotchMetrics(
    screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
    left: CGRect(x: 0, y: 950, width: 662, height: 32), right: CGRect(x: 850, y: 950, width: 662, height: 32))
private let notchless = NotchMetrics(
    screen: CGRect(x: 0, y: 0, width: 2560, height: 1440), safeAreaTop: 0, left: nil, right: nil)
private let standIn = NotchMetrics(
    screen: CGRect(x: 0, y: 0, width: 2560, height: 1440), safeAreaTop: 0, left: nil, right: nil,
    standIn: CGSize(width: 185, height: 24))
private let song = Activity(feature: .media, symbol: "music.note", title: "Midnight City", duration: .seconds(3))
private let volume = Activity(
    feature: nil, symbol: "speaker.wave.2.fill", title: "56%", level: 0.56, duration: .seconds(1))
private let meeting = Activity(
    feature: .calendar, symbol: "video.fill", title: "Standup", duration: .zero,
    countdown: Date(timeIntervalSinceNow: 272))
private let copied = Activity(
    feature: .clipboard, symbol: "doc.on.clipboard.fill", title: "Copied", duration: .seconds(2))
private let waiting = Activity(feature: .agents, symbol: "hand.raised.fill", title: "2 waiting", duration: .zero)
private let downloading = Activity(
    feature: .network, symbol: "arrow.down.circle.fill", title: "24 MB/s", duration: .zero)
private let downloaded = Activity(
    feature: .network, symbol: "checkmark.circle.fill", title: "Downloaded 1.2 GB", duration: .seconds(3))

private let snapshotCases: [(name: String, metrics: NotchMetrics, events: [NotchEvent])] = [
    ("compact", notched, [.show]),
    ("hover", notched, [.show, .pointerEntered]),
    ("activity", notched, [.show, .activity(song)]),
    ("copied", notched, [.show, .activity(copied)]),
    ("volume", notched, [.show, .activity(volume)]),
    ("ongoing", notched, [.show, .setOngoing(meeting)]),
    ("ongoing-words", notched, [.show, .setOngoing(waiting)]),
    ("ongoing-hover", notched, [.show, .setOngoing(waiting), .pointerEntered]),
    ("ongoing-speed", notched, [.show, .setOngoing(downloading)]),
    ("downloaded", notched, [.show, .activity(downloaded)]),
    ("pill-speed", notchless, [.show, .setOngoing(downloading)]),
    ("pill-activity", notchless, [.show, .activity(copied)]),
    ("pill-ongoing", notchless, [.show, .setOngoing(meeting)]),
    ("expanded-media", notched, [.show, .clicked]),
    ("pinned-notes", notched, [.show, .selectTab(.notes), .togglePin]),
    ("pill-compact", notchless, [.show]),
    ("pill-expanded", notchless, [.show, .selectTab(.shelf)]),
    ("standin-compact", standIn, [.show]),
    ("standin-activity", standIn, [.show, .activity(song)]),
    ("standin-expanded", standIn, [.show, .selectTab(.shelf)]),
]

@MainActor
struct NotchSnapshotTests {
    @Test(arguments: snapshotCases.indices)
    func everyStateRenders(index: Int) throws {
        let (name, metrics, events) = snapshotCases[index]
        try draw(name, metrics: metrics, events: events, preferences: Self.preferences())
    }

    @Test func draggingTheCornerGrowsTheNotchFromItsCenter() {
        let start = CGSize(width: 460, height: 290)
        #expect(NotchView.resized(start, by: CGSize(width: 10, height: 5)) == CGSize(width: 480, height: 295))
        #expect(NotchView.resized(start, by: CGSize(width: -3.3, height: 0.4)) == CGSize(width: 453, height: 290))
        let preferences = Self.preferences()
        preferences.resizeExpanded(to: NotchView.resized(start, by: CGSize(width: 900, height: -900)))
        #expect(preferences.expandedSize == CGSize(width: 720, height: 200), "held between the largest and smallest")
    }

    /// The Glass theme open, closed, and with an activity, on each kind of display. An offscreen
    /// render can't show glass, which the window server draws, so this checks that each state draws.
    @Test(arguments: [("glass-expanded", notched), ("glass-pill", notchless), ("glass-standin", standIn)])
    func theGlassThemeRenders(name: String, metrics: NotchMetrics) throws {
        let preferences = Self.preferences()
        preferences.theme = .glass
        try draw(name, metrics: metrics, events: [.show, .selectTab(.shelf)], preferences: preferences)
        try draw(name + "-closed", metrics: metrics, events: [.show], preferences: preferences)
        try draw(name + "-activity", metrics: metrics, events: [.show, .activity(song)], preferences: preferences)
    }

    /// The densest layout: every tab, Edit Tabs, the pin, and Settings in the header, and the resize
    /// corner, at the smallest open size.
    @Test func everyTabFitsTheSmallestSize() throws {
        let preferences = Self.preferences()
        for feature in FeatureID.allCases { preferences.setEnabled(feature, true) }
        preferences.resizeExpanded(to: NotchPreferences.minimumExpandedSize)
        try draw("expanded-smallest", metrics: notched, events: [.show, .clicked], preferences: preferences)
    }

    /// Editing the tabs in the drawer, with a few apps off the row, at the default size and the
    /// smallest, and with every tab in the row.
    @Test func theTabEditorRenders() throws {
        let preferences = Self.preferences()
        preferences.setEnabled(.usage, false)
        preferences.setEnabled(.agents, false)
        preferences.place(.timer, at: 1)
        let events: [NotchEvent] = [.show, .clicked]
        try draw("editing", metrics: notched, events: events, preferences: preferences, editing: true)
        try draw("editing-pill", metrics: notchless, events: events, preferences: preferences, editing: true)
        preferences.resizeExpanded(to: NotchPreferences.minimumExpandedSize)
        try draw("editing-smallest", metrics: notched, events: events, preferences: preferences, editing: true)
        for feature in FeatureID.allCases { preferences.setEnabled(feature, true) }
        try draw("editing-all", metrics: notched, events: events, preferences: preferences, editing: true)
    }

    /// The app drawer: every app, the open one lit, one off dimmed, and the Edit tile; at the default
    /// size, the smallest, and on a display without a notch. Then an app kept in the drawer, open, at
    /// the end of the row.
    @Test func theAppDrawerRenders() throws {
        let preferences = Self.preferences()
        preferences.setEnabled(.agents, false)
        preferences.moveToDrawer(.usage)
        let events: [NotchEvent] = [.show, .clicked]
        try draw("drawer", metrics: notched, events: events, preferences: preferences, drawer: true)
        try draw("drawer-pill", metrics: notchless, events: events, preferences: preferences, drawer: true)
        preferences.resizeExpanded(to: NotchPreferences.minimumExpandedSize)
        try draw("drawer-smallest", metrics: notched, events: events, preferences: preferences, drawer: true)
        try draw("drawer-app-open", metrics: notched, events: events + [.selectTab(.usage)], preferences: preferences)
    }

    private static func preferences() -> NotchPreferences {
        NotchPreferences(defaults: UserDefaults(suiteName: "Snapshots.\(UUID().uuidString)")!)
    }

    private func draw(
        _ name: String, metrics: NotchMetrics, events: [NotchEvent], preferences: NotchPreferences,
        editing: Bool = false, drawer: Bool = false
    ) throws {
        let engine = NotchEngine()
        events.forEach(engine.send)
        let content = NotchContent(
            tab: { feature in
                AnyView(Text("\(feature.title) content").frame(maxWidth: .infinity, maxHeight: .infinity))
            },
            dropFiles: { _ in false },
            openSettings: {})
        let panel = metrics.panelFrame.size
        // Editing happens in the drawer. The room is about what the header leaves the tabs.
        let view = NotchView(
            engine: engine, metrics: metrics, preferences: preferences, content: content,
            editor: editing ? TabEditor(preferences: preferences, room: 262) : nil, drawer: drawer || editing
        )
        .frame(width: panel.width, height: panel.height)
        .background(Color(white: 0.82))  // stands in for the desktop behind the transparent panel
        // The drawer's tiles pop in on appearing; without animation, a moment later they're in place.
        .transaction { if drawer || editing { $0.animation = nil } }
        let image = try #require(Self.render(view, size: panel, name: name, settle: drawer || editing))
        #expect(image.pixelsWide > 0 && image.pixelsHigh > 0)
    }

    @Test func aDraggedTabShowsWhereItWouldLand() {
        let tabs: [FeatureID] = [.media, .shelf, .notes]
        typealias Place = TabEditor.Place
        let moving = TabDrag(feature: .notes, fromRow: true, slot: 0)
        #expect(TabEditor.places(tabs, during: moving) == [Place.tab(.notes), .tab(.media), .tab(.shelf)])
        let joining = TabDrag(feature: .timer, fromRow: false, slot: 1)
        #expect(TabEditor.places(tabs, during: joining) == [Place.tab(.media), .gap, .tab(.shelf), .tab(.notes)])
        let leaving = TabDrag(feature: .shelf, fromRow: true, slot: nil)
        #expect(TabEditor.places(tabs, during: leaving) == [Place.tab(.media), .tab(.notes)], "headed for the tray")
        #expect(TabEditor.places(tabs, during: nil) == tabs.map(Place.tab))
    }

    @Test func thePointerPicksThePlaceUnderIt() {
        // Four places, 30 pt wide with 2 pt between, starting at x = 100.
        #expect(TabEditor.slot(at: 90, from: 100, width: 30, count: 4) == 0, "before the row: first")
        #expect(TabEditor.slot(at: 115, from: 100, width: 30, count: 4) == 0)
        #expect(TabEditor.slot(at: 133, from: 100, width: 30, count: 4) == 1)
        #expect(TabEditor.slot(at: 500, from: 100, width: 30, count: 4) == 3, "past the row: last")
        #expect(TabEditor.slot(at: 115, from: 100, width: 30, count: 0) == 0)
    }

    /// Draws the view through the same AppKit hosting path the app uses (ImageRenderer can't draw
    /// AppKit-backed pieces such as the drop target and paints yellow placeholders over them). With
    /// SNAPSHOT_DIR set, also writes `<name>.png` there.
    /// `settle` lets what the view does on appearing happen before the picture is taken.
    static func render(_ view: some View, size: CGSize, name: String, settle: Bool = false) -> NSBitmapImageRep? {
        let host = NotchHostingView(rootView: view)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        if settle {
            RunLoop.main.run(until: .now + 0.1)
            host.layoutSubtreeIfNeeded()
        }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let png = bitmap.representation(using: .png, properties: [:])
            try? png?.write(to: URL(filePath: directory).appending(path: "\(name).png"))
        }
        return bitmap
    }
}
