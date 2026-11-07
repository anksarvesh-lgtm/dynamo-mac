import Foundation
import Testing

@testable import IslandActivities

@Suite("An update waiting")
struct UpdateAvailableActivityTests {

    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test("alone, it is the icon on the left and the download glyph on the right")
    func aloneItFillsBothFlanks() {
        var stack = ActivityStack()
        stack.insert(BuiltInActivity.updateAvailable(version: "9.9.9", applicationName: "Isleta"), at: t0)
        let stage = try! #require(stack.stage)
        #expect(stage.content(on: .leading).applicationIconName == "Isleta")
        #expect(stage.content(on: .trailing).symbol == "arrow.down.circle.fill")
    }

    @Test("beside the music, Isleta's icon keeps the left and wears the download mark")
    func besideMusicTheIconSurvives() {
        // The flank kept when two share is the primary's own, so the kind's affinity is what decides
        // whether Isleta's icon is still on screen while something plays — and the badge is what
        // still says "update" once the glyph's half has gone to the music.
        var stack = ActivityStack()
        stack.insert(BuiltInActivity.nowPlaying(title: "Song"), at: t0)
        stack.insert(
            BuiltInActivity.updateAvailable(version: "9.9.9", applicationName: "Isleta"),
            at: t0.addingTimeInterval(1)
        )
        let stage = try! #require(stack.stage)
        #expect(stage.primary.kind == .updateAvailable)
        #expect(stage.companion?.kind == .nowPlaying)
        #expect(stage.content(on: .leading).applicationIconName == "Isleta")
        #expect(stage.content(on: .leading).badgeSymbol == "arrow.down.circle.fill")
        #expect(stage.activity(on: .trailing).kind == .nowPlaying)
    }

    @Test("it waits until it has been seen, and never opens the island on its own")
    func itIsAQuietReminder() {
        let update = BuiltInActivity.updateAvailable(version: "9.9.9", applicationName: "Isleta")
        #expect(update.expiry == .never)
        #expect(!ActivityKind.updateAvailable.opensIsland)
        // One reminder however many checks find the same update.
        #expect(update.id == ActivityKind.updateAvailable.singletonID)
        // The body is the update surface's, so the slot layer has nothing to draw there.
        #expect(update.presentations.expanded.isEmpty)
    }
}
