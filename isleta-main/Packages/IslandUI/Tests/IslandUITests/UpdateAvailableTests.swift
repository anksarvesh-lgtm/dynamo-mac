import CoreGraphics
import Foundation
import IslandKit
import Testing

@testable import IslandUI

@Suite("Update notes")
struct UpdateNotesParserTests {

    private let notes = """
    # Isleta 2.6.0

    Swiping through an open island now always reaches your pages, album covers keep loading
    however long Isleta has been running.

    ## Improved

    - **Swiping over a call opens your pages.** You go to Today, then Music if something is
      playing, then Weather.
    - **Album covers that are slow to load still arrive.**

    ## Fixed

    - **A city you type is used for the weather.**
    """

    @Test("the house shape becomes a paragraph, headings and bullets, without the title")
    func houseShape() {
        let blocks = UpdateNotesParser.blocks(from: notes)
        let kinds = blocks.map { block -> String in
            switch block {
            case .heading(let title): "h:\(title)"
            case .bullet: "b"
            case .paragraph: "p"
            }
        }
        #expect(kinds == ["p", "h:Improved", "b", "b", "h:Fixed", "b"])
    }

    @Test("a wrapped bullet is one bullet, and its bold lead is bold rather than asterisks")
    func wrappedBulletJoinsAndKeepsBold() throws {
        let blocks = UpdateNotesParser.blocks(from: notes)
        guard case .bullet(let first) = blocks[2] else {
            Issue.record("expected a bullet, got \(blocks[2])")
            return
        }
        let text = String(first.characters)
        #expect(!text.contains("**"))
        #expect(text.hasPrefix("Swiping over a call opens your pages."))
        #expect(text.hasSuffix("then Weather."))
        let bold = first.runs.contains { run in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        }
        #expect(bold)
    }

    @Test("no notes is no blocks, not a crash")
    func emptyIsEmpty() {
        #expect(UpdateNotesParser.blocks(from: "").isEmpty)
        #expect(UpdateNotesParser.blocks(from: "# Isleta 1.0.0\n").isEmpty)
    }
}

@Suite("The update surface")
@MainActor
struct UpdateAvailableModelTests {

    private func scrolled(by delta: CGFloat) -> IslandScrollSample {
        IslandScrollSample(phase: .changed, deltaX: 0, deltaY: delta)
    }

    @Test("the notes scroll within their extent and no further")
    func scrollIsBounded() {
        let model = UpdateAvailableModel()
        model.offer(version: "9.9.9", notesMarkdown: "- one\n- two")
        model.notesHeight = UpdateAvailableLayout.viewportHeight + 40
        model.scroll(scrolled(by: -500))
        #expect(model.scrollOffset == 40)
        model.scroll(scrolled(by: 500))
        #expect(model.scrollOffset == 0)
    }

    @Test("notes that fit do not scroll and draw no indicator")
    func shortNotesStayPut() {
        let model = UpdateAvailableModel()
        model.offer(version: "9.9.9", notesMarkdown: "- one")
        model.notesHeight = 20
        model.scroll(scrolled(by: -100))
        #expect(model.scrollOffset == 0)
        #expect(UpdateAvailableLayout.indicator(offset: 0, contentHeight: 20) == nil)
    }

    @Test("withdrawing forgets the update entirely")
    func withdrawClears() {
        let model = UpdateAvailableModel()
        model.offer(version: "9.9.9", notesMarkdown: "- one")
        #expect(model.isOffering)
        model.withdraw()
        #expect(!model.isOffering)
        #expect(model.notes.isEmpty)
        #expect(model.version == nil)
    }
}
