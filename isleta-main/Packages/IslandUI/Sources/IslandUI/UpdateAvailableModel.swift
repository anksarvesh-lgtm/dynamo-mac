import CoreGraphics
import Foundation
import IslandKit
import Observation

/// One block of an update's release notes, as the island draws them.
///
/// The notes arrive as the Markdown in `release-notes/v<VERSION>.md`, embedded in the appcast — the
/// same text Sparkle's own window renders. Only the house shape is understood here (headings,
/// bullets, paragraphs, and `**bold**` inside them), because that is the only shape the release-notes
/// rules allow; anything else falls through as a paragraph rather than being dropped.
public enum UpdateNotesBlock: Equatable, Sendable {
    case heading(String)
    case bullet(AttributedString)
    case paragraph(AttributedString)
}

/// Turns a release-notes Markdown file into blocks. Pure, so the shape is pinned by tests.
public enum UpdateNotesParser {

    public static func blocks(from markdown: String) -> [UpdateNotesBlock] {
        var blocks: [UpdateNotesBlock] = []
        // The lines of the block being gathered: a bullet's continuation lines, or a paragraph's.
        var pending: [String] = []
        var pendingIsBullet = false

        func flush() {
            guard !pending.isEmpty else { return }
            let text = pending.joined(separator: " ")
            blocks.append(pendingIsBullet ? .bullet(inline(text)) : .paragraph(inline(text)))
            pending = []
        }

        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("# ") {
                // The `# Isleta X.Y.Z` title. The island's own header already says which version,
                // and repeating it as the first line of the list spends a row saying it twice.
                flush()
            } else if line.hasPrefix("#") {
                flush()
                let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { blocks.append(.heading(title)) }
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush()
                pending = [String(line.dropFirst(2))]
                pendingIsBullet = true
            } else {
                // A wrapped bullet's next line, or a paragraph's: both join the block in progress.
                if pending.isEmpty { pendingIsBullet = false }
                pending.append(line)
            }
        }
        flush()
        return blocks
    }

    /// `**bold**` and friends inside one block, never block structure — that was decided above.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// The update the island is offering, and how far its notes have been scrolled.
///
/// **One instance for the whole app**, pushed into every `IslandScreenModel` by the shell, for the
/// reason `DropHistoryModel` is: there is one update and one person reading about it. The activity
/// on the stack carries only the two flanks; the version, the notes and the button live here,
/// because `ActivityContent` is four short slots and release notes are not.
@MainActor
@Observable
public final class UpdateAvailableModel {

    /// The version on offer, as Sparkle displays it. Nil when there is no update.
    public private(set) var version: String?

    /// The notes, parsed. Empty for an appcast entry with no embedded notes, which the layer says
    /// in words rather than drawing an empty box.
    public private(set) var notes: [UpdateNotesBlock] = []

    /// Where the list is scrolled to, pushed to the view. See `IslandListScrollTarget`.
    public private(set) var scrollTarget = IslandListScrollTarget()

    /// How tall the notes are as laid out, written back by the view. The scroll needs it as its
    /// extent and only the view can measure wrapped text at the width it is drawn.
    public var notesHeight: CGFloat = 0

    /// The button: hand over to Sparkle's window.
    public var onInstall: (() -> Void)?

    @ObservationIgnored private var scroll = IslandListScroll()

    public init() {}

    public var isOffering: Bool { version != nil }

    /// An update was found: what it is and what it says.
    public func offer(version: String, notesMarkdown: String?) {
        self.version = version
        notes = notesMarkdown.map(UpdateNotesParser.blocks(from:)) ?? []
        resetScroll()
    }

    /// The update has been looked at in Sparkle's window, or the session ended.
    public func withdraw() {
        version = nil
        notes = []
        notesHeight = 0
        resetScroll()
    }

    /// How far the notes can scroll.
    public var scrollExtent: CGFloat {
        max(0, notesHeight - UpdateAvailableLayout.viewportHeight)
    }

    public var scrollOffset: CGFloat { scrollTarget.offset }

    /// One trackpad or wheel sample over the notes.
    public func scroll(_ sample: IslandScrollSample) {
        scroll.consume(sample, extent: scrollExtent)
        scrollTarget = scrollTarget.dragged(to: scroll.offset)
    }

    /// Back to the top — opening, and offering a new version, both start from the first line.
    public func resetScroll() {
        scroll.reset()
        scrollTarget = scrollTarget.dragged(to: 0)
    }
}

/// The geometry of the update surface: a header, the notes in a fixed window, and the button.
///
/// A **constant** height, like Up Next's and the drop history's: `islandPath` tracks a settled
/// shape, and an island that grew with a longer release note would move its own bottom edge as a
/// consequence of what was published.
public enum UpdateAvailableLayout {

    public static let horizontalPadding: CGFloat = ActivityExpandedHeight.horizontalPadding

    public static let topPadding: CGFloat = 12

    public static let headerHeight: CGFloat = 22

    public static let headerSpacing: CGFloat = 6

    /// About seven lines of notes — the headline sentence and the first section, which is what a
    /// reader deciding whether to install actually reads.
    public static let viewportHeight: CGFloat = 132

    public static let buttonSpacing: CGFloat = 10

    public static let buttonHeight: CGFloat = 28

    /// Small, because the page dots already hold a strip under the body.
    public static let bottomPadding: CGFloat = 2

    public static var contentHeight: CGFloat {
        topPadding + headerHeight + headerSpacing + viewportHeight + buttonSpacing + buttonHeight
            + bottomPadding
    }

    public static let blockSpacing: CGFloat = 6

    public static let indicatorWidth: CGFloat = 2

    public static let indicatorMinimumLength: CGFloat = 24

    /// The scroll indicator's length and position, or nil when everything fits.
    public static func indicator(offset: CGFloat, contentHeight content: CGFloat) -> (length: CGFloat, top: CGFloat)? {
        let extent = content - viewportHeight
        guard extent > 0 else { return nil }
        let length = max(indicatorMinimumLength, viewportHeight * (viewportHeight / content))
        let progress = min(max(0, offset / extent), 1)
        return (length, (viewportHeight - length) * progress)
    }
}
