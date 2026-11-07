// SPDX-License-Identifier: MIT
import Foundation

/// A note's colour, stored by name so other Markdown apps see a readable value.
public enum NoteColor: String, CaseIterable, Identifiable, Sendable {
    case red
    case orange
    case yellow
    case green
    case mint
    case blue
    case purple
    case pink

    public var id: String { rawValue }
    public var name: String { rawValue.capitalized }
}

/// One note: a Markdown file. Its colour and pin live in a small front matter block at the top of the
/// file (the `---` header Obsidian and other Markdown apps read), written only when one is set, so an
/// uncoloured note stays plain text.
public struct Note: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The note's text, without the front matter.
    public var text: String
    public var modified: Date
    public var created: Date
    public var color: NoteColor?
    public var isPinned = false
    /// The file's name in the notes folder; nil until the note is first saved.
    var fileName: String?
    /// Whether the file is named after the title the way ILoveNotch names notes, so a new title
    /// renames it. A file the user named, say in a Markdown app's folder, keeps its name.
    var followsTitle = true
    /// Front matter lines other apps wrote, kept as they were.
    var otherFields: [String] = []

    public init(
        id: UUID, text: String, modified: Date, created: Date? = nil, color: NoteColor? = nil, isPinned: Bool = false
    ) {
        self.id = id
        self.text = text
        self.modified = modified
        self.created = created ?? modified
        self.color = color
        self.isPinned = isPinned
    }

    /// Reads a note file's contents.
    init(id: UUID, fileName: String, contents: String, modified: Date, created: Date?) {
        let (fields, body) = Self.splitFrontMatter(contents)
        self.init(id: id, text: body, modified: modified, created: created)
        self.fileName = fileName
        for line in fields {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            switch (parts.first?.lowercased(), parts.count == 2 ? parts[1] : nil) {
            case ("color"?, let value?), ("colour"?, let value?):
                color = NoteColor(rawValue: value.lowercased())
            case ("pinned"?, let value?):
                isPinned = value.lowercased() == "true"
            default:
                otherFields.append(line)
            }
        }
        let base = (fileName as NSString).deletingPathExtension
        followsTitle = UUID(uuidString: base) != nil || Self.isNamed(base, after: title)
    }

    /// Whether `base` is a file name ILoveNotch gives a note titled `title`: "Groceries", or
    /// "Groceries 2" next to another note of that title.
    static func isNamed(_ base: String, after title: String) -> Bool {
        guard let name = base.range(of: fileBase(for: title), options: [.anchored, .caseInsensitive]) else {
            return false
        }
        let rest = base[name.upperBound...]
        return rest.isEmpty || (rest.first == " " && rest.count > 1 && rest.dropFirst().allSatisfy(\.isNumber))
    }

    /// The first non-empty line, without Markdown heading marks, or "New Note".
    public var title: String {
        let line = text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line ?? "New Note"
    }

    /// A few lines after the title, for the hover preview.
    public var preview: String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.dropFirst().prefix(4).joined(separator: "\n")
    }

    public var wordCount: Int { text.split { $0.isWhitespace || $0.isNewline }.count }

    public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The checklist items not yet ticked, like "passport" from "- [ ] passport", in order. Empty
    /// ones are left out.
    public var openChecklistItems: [String] {
        text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let marker = trimmed.first, "-*+".contains(marker), trimmed.dropFirst().hasPrefix(" [ ]") else {
                return nil
            }
            let rest = trimmed.dropFirst(5)
            guard rest.isEmpty || rest.first == " " else { return nil }  // "- [ ]x" isn't a checkbox
            let item = rest.trimmingCharacters(in: .whitespaces)
            return item.isEmpty ? nil : item
        }
    }

    /// Whether the note has checklist items not yet ticked.
    public var hasOpenChecklist: Bool { !openChecklistItems.isEmpty }

    /// What goes on disk: front matter, when there's anything for it, then the text.
    var fileContents: String {
        var fields: [String] = []
        if let color { fields.append("color: \(color.rawValue)") }
        if isPinned { fields.append("pinned: true") }
        fields += otherFields
        guard !fields.isEmpty else { return text }
        return "---\n" + fields.joined(separator: "\n") + "\n---\n" + text
    }

    /// A file name from the title: "Groceries.md". Characters Finder and iCloud reject become dashes.
    static func fileBase(for title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|").union(.newlines).union(.controlCharacters)
        var base = String(String.UnicodeScalarView(title.unicodeScalars.map { forbidden.contains($0) ? "-" : $0 }))
        base = base.trimmingCharacters(in: .whitespaces)
        while base.hasPrefix(".") { base.removeFirst() }
        base = String(base.prefix(80)).trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? "Note" : base
    }

    /// Splits a leading `---` block off a file. Anything else, including a lone `---` rule, is text.
    static func splitFrontMatter(_ contents: String) -> (fields: [String], body: String) {
        let lines = contents.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return ([], contents) }
        let header = lines[1..<end].map(String.init)
        // Front matter is "key: value" lines; anything else means the dashes were a rule.
        let isField = { (line: String) in line.contains(":") || line.trimmingCharacters(in: .whitespaces).isEmpty }
        guard header.allSatisfy(isField) else { return ([], contents) }
        let body = lines[(end + 1)...].joined(separator: "\n")
        return (header.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, body)
    }
}
