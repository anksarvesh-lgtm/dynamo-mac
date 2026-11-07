// SPDX-License-Identifier: MIT
import Foundation
import NotchCore
import Observation
import SwiftUI

/// How the notes list is ordered. Pinned notes always come first.
public enum NoteSort: String, CaseIterable, Identifiable, Sendable {
    case modified
    case created
    case title

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .modified: "Last Edited"
        case .created: "Date Created"
        case .title: "Title"
        }
    }
}

/// Quick notes kept as Markdown files, one per note, named after their first line. They live in
/// Application Support unless the user picks a folder, such as one in iCloud Drive, so they reach
/// the iPhone's Files app or a Markdown app there. They load when the tab comes on screen, save half
/// a second after typing stops, are written out whenever the tab goes away, and leave memory when
/// the feature stops. Empty notes are never saved.
@MainActor
@Observable
public final class NotesFeature: NotchFeature {
    public let id = FeatureID.notes
    public var phase: FeaturePhase = .stopped {
        didSet {
            guard phase != oldValue else { return }
            if phase == .foreground {
                load()
            } else {
                flush()
            }
            if phase == .stopped { notes = [] }
        }
    }
    public private(set) var notes: [Note] = []
    public var selection: Note.ID?
    /// Filters the list to notes containing this text.
    public var search = ""
    public var sort: NoteSort {
        didSet { defaults.set(sort.rawValue, forKey: Self.sortKey) }
    }
    /// Per-feature setting: Control-Option-N opens a new note from anywhere.
    public var quickNoteShortcut: Bool {
        didSet { defaults.set(quickNoteShortcut, forKey: Self.shortcutKey) }
    }
    /// Where the notes are stored.
    public private(set) var directory: URL
    /// Whether `directory` is a folder the user chose rather than the app's own.
    public private(set) var usesCustomFolder: Bool
    /// A short confirmation or problem, such as "Sent 3 items to Tasks". Clears itself.
    public private(set) var notice: String?
    /// Set when a quick note starts, until the editor takes the keyboard.
    public private(set) var wantsEditorFocus = false
    /// Adds a task from a checklist item; returns whether it was added.
    @ObservationIgnored public var onSendToTasks: ((String) -> Bool)?

    private static let sortKey = "notes.sort"
    private static let shortcutKey = "notes.quickNoteShortcut"
    private static let folderKey = "notes.folderBookmark"
    @ObservationIgnored private let defaultDirectory: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var unsaved: Set<Note.ID> = []
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var clearNotice: Task<Void, Never>?
    /// The chosen folder while its security scope is open, in a sandboxed build.
    @ObservationIgnored private var folderAccess: URL?

    /// `directory` replaces both the default folder and any folder the user chose, for tests.
    public init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultDirectory = directory ?? AppSupport.file("Notes")
        sort = defaults.string(forKey: Self.sortKey).flatMap(NoteSort.init(rawValue:)) ?? .modified
        quickNoteShortcut = defaults.object(forKey: Self.shortcutKey) as? Bool ?? true
        let chosen = directory == nil ? defaults.data(forKey: Self.folderKey).flatMap(Self.resolve) : nil
        self.directory = chosen ?? defaultDirectory
        usesCustomFolder = chosen != nil
        if let chosen, ShelfFeature.sandboxed, chosen.startAccessingSecurityScopedResource() { folderAccess = chosen }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public var view: some View { NotesView(notes: self) }

    public var selected: Note? { notes.first { $0.id == selection } }

    /// The notes the list shows: matching the search, pinned first, then in the chosen order.
    public var visibleNotes: [Note] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = query.isEmpty ? notes : notes.filter { $0.text.localizedCaseInsensitiveContains(query) }
        let order = self.sort
        return matching.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            switch order {
            case .modified: return lhs.modified > rhs.modified
            case .created: return lhs.created > rhs.created
            case .title: return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }

    @discardableResult
    public func add(_ text: String = "") -> Note.ID {
        let note = Note(id: UUID(), text: text, modified: .now)
        notes.insert(note, at: 0)
        selection = note.id
        search = ""
        if !text.isEmpty {
            unsaved.insert(note.id)
            scheduleSave()
        }
        return note.id
    }

    /// Starts a note from the keyboard shortcut: reuses an empty selected note, and asks the editor
    /// for the keyboard.
    public func quickCapture() {
        search = ""
        if selected?.isEmpty != true { add() }
        wantsEditorFocus = true
    }

    /// Called by the editor once it has the keyboard.
    public func editorTookFocus() { wantsEditorFocus = false }

    public func update(_ id: Note.ID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        notes[index].text = text
        notes[index].modified = .now
        unsaved.insert(id)
        scheduleSave()
    }

    public func setColor(_ id: Note.ID, _ color: NoteColor?) {
        change(id) { $0.color = color }
    }

    public func togglePin(_ id: Note.ID) {
        change(id) { $0.isPinned.toggle() }
    }

    /// Sends a note's unticked checklist items to Tasks. Returns how many were added.
    @discardableResult
    public func sendToTasks(_ id: Note.ID) -> Int {
        guard let note = notes.first(where: { $0.id == id }), let send = onSendToTasks else { return 0 }
        let items = note.openChecklistItems
        guard !items.isEmpty else {
            show(notice: "No unticked checklist items")
            return 0
        }
        let sent = items.filter(send).count
        switch sent {
        case 0: show(notice: "Allow Reminders access in the Tasks tab first")
        case 1: show(notice: "Sent 1 item to Tasks")
        default: show(notice: "Sent \(sent) items to Tasks")
        }
        return sent
    }

    public func delete(_ id: Note.ID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        notes.removeAll { $0.id == id }
        unsaved.remove(id)
        if let name = note.fileName {
            // To the Trash, not gone for good: a note is often the only copy of something.
            let url = directory.appending(path: name)
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) == nil {
                try? FileManager.default.removeItem(at: url)
            }
        }
        if selection == id { selection = visibleNotes.first?.id }
    }

    /// The note's file, written out first, for dragging it out of the notch.
    public func fileURL(for id: Note.ID) -> URL? {
        flush()
        return notes.first { $0.id == id }?.fileName.map { directory.appending(path: $0) }
    }

    /// Stores notes in `folder` from now on. Notes in the app's own folder move there; a folder
    /// chosen earlier keeps its files.
    public func chooseFolder(_ folder: URL) {
        flush()
        guard folder.standardizedFileURL != directory.standardizedFileURL else { return }
        let options: URL.BookmarkCreationOptions = ShelfFeature.sandboxed ? .withSecurityScope : []
        guard let bookmark = try? folder.bookmarkData(options: options) else {
            show(notice: "Couldn't use that folder")
            return
        }
        if !usesCustomFolder { moveNotes(from: directory, to: folder) }
        defaults.set(bookmark, forKey: Self.folderKey)
        switchFolder(to: folder, custom: true)
    }

    /// Goes back to the app's own folder. Notes in the chosen folder stay there.
    public func useDefaultFolder() {
        flush()
        defaults.removeObject(forKey: Self.folderKey)
        switchFolder(to: defaultDirectory, custom: false)
    }

    func load() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey]
        let listing = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        // Ids stay the same across reloads so the selection sticks. Files from before notes were
        // named by title are named by their id.
        let known = Dictionary(
            notes.compactMap { note in note.fileName.map { ($0, note.id) } }, uniquingKeysWith: { first, _ in first })
        let stored = (listing ?? []).filter { $0.pathExtension.lowercased() == "md" }.compactMap { url -> Note? in
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = url.lastPathComponent
            let id = known[name] ?? UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
            return Note(
                id: id, fileName: name, contents: contents, modified: values?.contentModificationDate ?? .distantPast,
                created: values?.creationDate)
        }
        // Edits not yet on disk win over what's stored.
        let pending = notes.filter { unsaved.contains($0.id) }
        let pendingIDs = Set(pending.map(\.id))
        let pendingFiles = Set(pending.compactMap(\.fileName))
        notes = pending + stored.filter { !pendingIDs.contains($0.id) && !pendingFiles.contains($0.fileName ?? "") }
        if selected == nil { selection = visibleNotes.first?.id }
    }

    /// Writes every unsaved note now, renaming a file ILoveNotch named when its title changed; a note
    /// emptied out is deleted rather than kept blank.
    func flush() {
        pendingSave?.cancel()
        let manager = FileManager.default
        for id in unsaved {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { continue }
            let note = notes[index]
            if note.isEmpty {
                if let name = note.fileName { try? manager.removeItem(at: directory.appending(path: name)) }
                notes[index].fileName = nil
                continue
            }
            // A file the user named, in a folder they picked, keeps its name: another app, such as a
            // Markdown editor, may link to it by that name.
            var name =
                note.followsTitle
                ? freeName(for: note.title, in: directory, keeping: note.fileName)
                : note.fileName ?? freeName(for: note.title, in: directory)
            if let old = note.fileName, old != name {
                do {
                    try manager.moveItem(at: directory.appending(path: old), to: directory.appending(path: name))
                } catch {
                    name = old  // keep the old name rather than leave a second copy behind
                }
            }
            let url = directory.appending(path: name)
            do {
                try note.fileContents.write(to: url, atomically: true, encoding: .utf8)
                // An atomic write replaces the file, so the creation date is put back.
                try? manager.setAttributes([.creationDate: note.created], ofItemAtPath: url.path)
                notes[index].fileName = name
            } catch {
                Log.features.error("Couldn't save a note: \(error.localizedDescription, privacy: .public)")
            }
        }
        unsaved = []
    }

    /// Shows the given notes as they'd load from disk. For tests and snapshots only.
    func show(notes: [Note]) {
        self.notes = notes
        selection = visibleNotes.first?.id
    }

    private func change(_ id: Note.ID, _ apply: (inout Note) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        apply(&notes[index])
        unsaved.insert(id)
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            self?.flush()
        }
    }

    private func show(notice text: String) {
        notice = text
        clearNotice?.cancel()
        clearNotice = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.notice = nil
        }
    }

    /// "Groceries.md", or "Groceries 2.md" when another file has that name. The note's own file,
    /// `current`, doesn't count, even if only its capitalization differs.
    private func freeName(for title: String, in folder: URL, keeping current: String? = nil) -> String {
        let base = Note.fileBase(for: title)
        var candidate = "\(base).md"
        var number = 2
        while candidate.lowercased() != current?.lowercased(),
            FileManager.default.fileExists(atPath: folder.appending(path: candidate).path)
        {
            candidate = "\(base) \(number).md"
            number += 1
        }
        return candidate
    }

    private func moveNotes(from source: URL, to folder: URL) {
        let manager = FileManager.default
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = (try? manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension.lowercased() == "md" {
            let contents = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let (_, body) = Note.splitFrontMatter(contents)
            let title = Note(id: UUID(), text: body, modified: .now).title
            let target = folder.appending(path: freeName(for: title, in: folder))
            do {
                try manager.moveItem(at: file, to: target)
            } catch {
                Log.features.error("Couldn't move a note: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func switchFolder(to folder: URL, custom: Bool) {
        folderAccess?.stopAccessingSecurityScopedResource()
        folderAccess = nil
        if custom, ShelfFeature.sandboxed, folder.startAccessingSecurityScopedResource() { folderAccess = folder }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        directory = folder
        usesCustomFolder = custom
        notes = []
        unsaved = []
        selection = nil
        if phase == .foreground { load() }
    }

    /// The folder a bookmark points to. A stale bookmark still resolves; it's renewed next time the
    /// folder is chosen.
    private static func resolve(_ bookmark: Data) -> URL? {
        var stale = false
        let options: URL.BookmarkResolutionOptions = ShelfFeature.sandboxed ? .withSecurityScope : []
        return try? URL(resolvingBookmarkData: bookmark, options: options, bookmarkDataIsStale: &stale)
    }
}
