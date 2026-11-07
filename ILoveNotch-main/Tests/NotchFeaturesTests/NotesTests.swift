// SPDX-License-Identifier: MIT
import Foundation
import Testing

@testable import NotchFeatures

@MainActor
struct NotesFeatureTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "NotesTests-\(UUID().uuidString)")

    private func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    @Test func notesAreSavedAsFilesNamedByTitleAndSurviveARelaunch() {
        let notes = NotesFeature(directory: folder)
        notes.phase = .foreground
        let id = notes.add()
        notes.update(id, text: "Groceries\n- milk")
        notes.phase = .background  // leaving the tab writes pending edits
        #expect(files() == ["Groceries.md"])

        let relaunched = NotesFeature(directory: folder)
        relaunched.phase = .foreground
        #expect(relaunched.notes.map(\.text) == ["Groceries\n- milk"])
        #expect(relaunched.selected?.title == "Groceries")
    }

    @Test func typingSavesAfterAShortPause() async throws {
        let notes = NotesFeature(directory: folder)
        notes.phase = .foreground
        notes.update(notes.add(), text: "draft")
        #expect(files().isEmpty, "not on every keystroke")
        #expect(await eventually { files().count == 1 })
    }

    @Test func emptyNotesAreNeverKept() {
        let notes = NotesFeature(directory: folder)
        notes.phase = .foreground
        let id = notes.add()
        notes.update(id, text: "temporary")
        notes.phase = .background
        notes.phase = .foreground
        notes.update(id, text: "   \n")
        notes.phase = .background
        #expect(files().isEmpty)
    }

    @Test func deletingANoteRemovesItsFileAndMovesTheSelection() {
        let notes = NotesFeature(directory: folder)
        notes.phase = .foreground
        let first = notes.add()
        notes.update(first, text: "one")
        let second = notes.add()
        notes.update(second, text: "two")
        notes.phase = .background
        notes.delete(second)
        #expect(files() == ["one.md"])
        #expect(notes.selection == first)
    }

    @Test func stoppingWritesEverythingAndReleasesMemory() {
        let notes = NotesFeature(directory: folder)
        notes.phase = .foreground
        notes.update(notes.add(), text: "keep me")
        notes.phase = .stopped
        #expect(notes.notes.isEmpty)
        #expect(files().count == 1)
    }

    @Test func titlesComeFromTheFirstNonEmptyLine() {
        #expect(Note(id: UUID(), text: "\n  \n  Plan  \nmore", modified: .now).title == "Plan")
        #expect(Note(id: UUID(), text: "## Trip", modified: .now).title == "Trip")
        #expect(Note(id: UUID(), text: "", modified: .now).title == "New Note")
    }

    @Test func renamingTheFirstLineRenamesTheFile() {
        let notes = NotesFeature(directory: folder)
        notes.phase = .foreground
        let id = notes.add()
        notes.update(id, text: "Draft")
        notes.flush()
        notes.update(id, text: "Final: plan\nbody")
        notes.flush()
        #expect(files() == ["Final- plan.md"], "a colon isn't allowed in a file name")
    }

    @Test func aFileTheUserNamedKeepsItsNameThroughEdits() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, text) in [
            ("Meeting 2026-09-01.md", "# Standup\n- notes"), ("Vault note.md", "---\ntags:\n  - work\n---\nBody"),
            ("Groceries 2.md", "Groceries\n- milk"),
        ] {
            try text.write(to: folder.appending(path: name), atomically: true, encoding: .utf8)
        }
        let notes = NotesFeature(directory: folder)
        notes.phase = .foreground
        for note in notes.notes {
            let edited = note.text.replacingOccurrences(of: "Standup", with: "Retro")
            notes.update(note.id, text: edited.replacingOccurrences(of: "Groceries", with: "Shopping") + "\nmore")
        }
        notes.phase = .background
        #expect(files() == ["Meeting 2026-09-01.md", "Shopping.md", "Vault note.md"], "only ILoveNotch's names follow")
    }

    @Test func notesWithTheSameTitleGetTheirOwnFiles() {
        let notes = NotesFeature(directory: folder)
        notes.phase = .foreground
        notes.update(notes.add(), text: "Todo")
        notes.update(notes.add(), text: "Todo")
        notes.flush()
        #expect(files() == ["Todo 2.md", "Todo.md"])
    }

    @Test func filesFromBeforeTitleNamesStillLoad() throws {
        let id = UUID()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "Old note".write(to: folder.appending(path: "\(id.uuidString).md"), atomically: true, encoding: .utf8)
        let notes = NotesFeature(directory: folder)
        notes.phase = .foreground
        #expect(notes.notes.map(\.id) == [id])
        notes.update(id, text: "Old note, edited")
        notes.flush()
        #expect(files() == ["Old note, edited.md"])
    }

    @Test func colorAndPinAreKeptInFrontMatter() throws {
        let notes = NotesFeature(directory: folder)
        notes.phase = .foreground
        let id = notes.add()
        notes.update(id, text: "Ideas")
        notes.setColor(id, .mint)
        notes.togglePin(id)
        notes.flush()
        let contents = try String(contentsOf: folder.appending(path: "Ideas.md"), encoding: .utf8)
        #expect(contents == "---\ncolor: mint\npinned: true\n---\nIdeas")

        let relaunched = NotesFeature(directory: folder)
        relaunched.phase = .foreground
        let note = try #require(relaunched.notes.first)
        #expect(note.text == "Ideas" && note.color == .mint && note.isPinned)
    }

    @Test func frontMatterFromOtherAppsIsKeptAndRulesAreNotFrontMatter() {
        let note = Note(
            id: UUID(), fileName: "a.md", contents: "---\ntags: work\ncolor: blue\n---\nBody", modified: .now,
            created: nil)
        #expect(note.text == "Body" && note.color == .blue)
        #expect(note.fileContents == "---\ncolor: blue\ntags: work\n---\nBody")
        let rule = Note(id: UUID(), fileName: "b.md", contents: "---\nJust text\n---\n", modified: .now, created: nil)
        #expect(rule.text == "---\nJust text\n---\n" && rule.color == nil)
    }

    @Test func pinnedNotesComeFirstAndSearchFilters() throws {
        let now = Date.now
        let defaults = try #require(UserDefaults(suiteName: "NotesTests.\(UUID().uuidString)"))
        let notes = NotesFeature(directory: folder, defaults: defaults)
        notes.show(notes: [
            Note(id: UUID(), text: "Newest", modified: now),
            Note(id: UUID(), text: "Pinned and old", modified: now - 3600, isPinned: true),
            Note(id: UUID(), text: "Middle\nmilk", modified: now - 60),
        ])
        #expect(notes.visibleNotes.map(\.title) == ["Pinned and old", "Newest", "Middle"])
        notes.sort = .title
        #expect(notes.visibleNotes.map(\.title) == ["Pinned and old", "Middle", "Newest"])
        notes.search = "MILK"
        #expect(notes.visibleNotes.map(\.title) == ["Middle"])
    }

    @Test func uncheckedChecklistItemsGoToTasks() {
        let text = "# Trip\n- [ ] passport\n- [x] tickets\n- socks\n  * [ ]  adapter \n- [ ]\n- [ ]x\n1. pack"
        let note = Note(id: UUID(), text: text, modified: .now)
        #expect(note.openChecklistItems == ["passport", "adapter"], "ticked, plain, empty, and malformed are left")
        #expect(!Note(id: UUID(), text: "- [x] done\n- socks", modified: .now).hasOpenChecklist)

        let notes = NotesFeature(directory: folder)
        notes.phase = .foreground
        var sent: [String] = []
        notes.onSendToTasks = {
            sent.append($0)
            return true
        }
        let id = notes.add()
        notes.update(id, text: text)
        #expect(notes.sendToTasks(id) == 2)
        #expect(sent == ["passport", "adapter"])
    }

    @Test func choosingAFolderMovesTheNotesThere() throws {
        let defaults = try #require(UserDefaults(suiteName: "NotesTests.\(UUID().uuidString)"))
        let notes = NotesFeature(directory: folder, defaults: defaults)
        notes.phase = .foreground
        notes.update(notes.add(), text: "Moving day")
        notes.flush()
        let chosen = FileManager.default.temporaryDirectory.appending(path: "NotesFolder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        notes.chooseFolder(chosen)
        #expect(notes.usesCustomFolder)
        #expect(files().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: chosen.path) == ["Moving day.md"])
        #expect(notes.notes.map(\.title) == ["Moving day"])
    }
}
