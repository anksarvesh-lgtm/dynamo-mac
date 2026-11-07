// SPDX-License-Identifier: MIT
import Foundation
import Testing

@testable import NotchFeatures

@MainActor
struct ShortcutsFeatureTests {
    private let defaults = UserDefaults(suiteName: "ShortcutsTests.\(UUID().uuidString)")!

    @Test func theListIsOneNamePerLineSortedLikeFinder() {
        let output = "Shortcut 10\n\nmake GIF\n  Shortcut 2  \nAirDrop Clipboard\n"
        #expect(ShortcutsFeature.parseList(output) == ["AirDrop Clipboard", "make GIF", "Shortcut 2", "Shortcut 10"])
    }

    @Test func hiddenShortcutsStayHiddenAcrossLaunches() {
        let first = ShortcutsFeature(defaults: defaults)
        first.hidden = ["Secret"]
        #expect(ShortcutsFeature(defaults: defaults).hidden == ["Secret"])
    }

    // CI runners have no Shortcuts user session, so this only runs on a real Mac.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func listingUsesTheRealCommandLineTool() async throws {
        let (status, _) = await Subprocess.run(ShortcutsFeature.tool, ["list"])
        #expect(status == 0, "/usr/bin/shortcuts should answer on every supported macOS")
    }

    @Test func aListThatArrivesAfterStoppingIsDropped() async throws {
        let shortcuts = ShortcutsFeature(defaults: defaults)
        shortcuts.phase = .foreground  // starts listing
        shortcuts.phase = .stopped
        try await Task.sleep(for: .seconds(2))
        #expect(shortcuts.shortcuts.isEmpty && shortcuts.status == .loading)
    }
}
