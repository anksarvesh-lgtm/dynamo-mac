// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// The notes tab: a searchable list of notes beside an editor. Hovering a note lights it up and shows
/// its pin and delete buttons; the selection slides between notes. A note's unticked checklist items
/// can go to Tasks. Clicking into a field gives the notch keyboard focus; Escape or clicking
/// elsewhere hands it back.
struct NotesView: View {
    @Bindable var notes: NotesFeature
    @Namespace private var selectionSpace
    @Namespace private var searchSpace
    @FocusState private var editorFocused: Bool
    @FocusState private var searchFocused: Bool
    /// Search was opened from its icon; it also stays open while it has text.
    @State private var searching = false
    @State private var searchHovering = false
    @State private var showsPalette = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if notes.notes.isEmpty {
            FeatureUnavailableView(
                symbol: "note.text",
                title: "No notes yet",
                message: notes.usesCustomFolder
                    ? "Jot something down. Notes are saved as Markdown in \(notes.directory.lastPathComponent)."
                    : "Jot something down. Notes stay on this Mac as plain text.",
                action: (label: "New Note", perform: { notes.add() }))
        } else {
            HStack(spacing: 10) {
                list.frame(width: 136)
                editor
            }
            .onAppear(perform: takeFocusIfWanted)
            .onChange(of: notes.wantsEditorFocus) { _, _ in takeFocusIfWanted() }
        }
    }

    /// Puts the cursor in the editor after the quick note shortcut, once the editor is on screen.
    private func takeFocusIfWanted() {
        guard notes.wantsEditorFocus else { return }
        Task { @MainActor in
            editorFocused = true
            notes.editorTookFocus()
        }
    }

    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82) }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(notes.visibleNotes) { note in
                        NoteRow(
                            notes: notes, note: note, isSelected: notes.selection == note.id,
                            selectionSpace: selectionSpace,
                            select: { withAnimation(spring) { notes.selection = note.id } })
                    }
                    if notes.visibleNotes.isEmpty {
                        Text("No matches").font(.caption).foregroundStyle(.white.opacity(0.5)).padding(6)
                    }
                }
                .padding(.vertical, 6)
            }
            .fadingEdges()
        }
    }

    /// Search, sort, and new note as three icons of one size. Search opens out of its icon into a
    /// field across the header, and folds back when closed or left empty.
    private var header: some View {
        let open = searching || !notes.search.isEmpty
        return HStack(spacing: 6) {
            if open {
                HStack(spacing: 4) {
                    searchGlass
                    TextField("Search", text: $notes.search)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .focused($searchFocused)
                        .takesKeyboard(searching)
                    Button(action: closeSearch) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 10)).opacity(0.5)
                    }
                    .buttonStyle(.plain)
                    .help("Close search")
                    .accessibilityLabel("Close Search")
                }
                .padding(.leading, 6)
                .padding(.trailing, 5)
                .frame(height: HeaderIcon.side)
                .background { searchField }
                .transition(.opacity)
            } else {
                Button(action: openSearch) {
                    searchGlass
                        .frame(width: HeaderIcon.side, height: HeaderIcon.side)
                        .background { searchField }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { searchHovering = inside } }
                .help("Search notes")
                .accessibilityLabel("Search")
                Spacer(minLength: 0)
                Menu {
                    Picker("Sort By", selection: $notes.sort) {
                        ForEach(NoteSort.allCases) { sort in Text(sort.name).tag(sort) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HeaderIcon(symbol: "arrow.up.arrow.down")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sort notes")
                .accessibilityLabel("Sort")
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
                Button {
                    withAnimation(spring) { _ = notes.add() }
                } label: {
                    HeaderIcon(symbol: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .help("New note")
                .accessibilityLabel("New Note")
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .frame(height: HeaderIcon.side)
        .onChange(of: searchFocused) { _, focused in
            // Clicking away from an empty search folds it back into its icon.
            if !focused, notes.search.isEmpty { withAnimation(spring) { searching = false } }
        }
    }

    /// The icon and the field's backdrop are shared, so the icon's circle stretches into the field.
    private var searchGlass: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: HeaderIcon.symbolSize, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            .matchedGeometryEffect(id: "glass", in: searchSpace)
    }

    private var searchField: some View {
        Capsule()
            .fill(.white.opacity(searchHovering && !searching ? 0.18 : 0.1))
            .matchedGeometryEffect(id: "field", in: searchSpace)
    }

    private func openSearch() {
        searchHovering = false
        withAnimation(spring) { searching = true }
        Task { @MainActor in searchFocused = true }
    }

    private func closeSearch() {
        withAnimation(spring) {
            notes.search = ""
            searching = false
        }
        searchFocused = false
    }

    // MARK: Editor

    @ViewBuilder private var editor: some View {
        if let note = notes.selected {
            VStack(alignment: .leading, spacing: 4) {
                toolbar(note)
                TextEditor(text: Binding(get: { note.text }, set: { notes.update(note.id, text: $0) }))
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .accessibilityLabel("Note text")
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(tint(note.color), in: RoundedRectangle(cornerRadius: 8))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: note.color)
                footer(note)
            }
        }
    }

    private func tint(_ color: NoteColor?) -> Color {
        guard let color else { return .white.opacity(0.06) }
        return color.swatch.opacity(0.18)
    }

    private func toolbar(_ note: Note) -> some View {
        HStack(spacing: ColorPalette.gap) {
            Button {
                showsPalette.toggle()
            } label: {
                Circle()
                    .fill(note.color?.swatch ?? .white.opacity(0.35))
                    .frame(width: ColorPalette.dot, height: ColorPalette.dot)
                    .overlay(Circle().strokeBorder(.white.opacity(showsPalette ? 0.9 : 0.5), lineWidth: 1))
                    .scaleEffect(showsPalette && !reduceMotion ? 1.2 : 1)
                    .animation(spring, value: showsPalette)
                    .contentShape(Circle().inset(by: -4))
            }
            .help(showsPalette ? "Close colors" : "Color")
            .accessibilityLabel("Color")
            // The palette opens over the other buttons, which step aside while it's out.
            ZStack(alignment: .leading) {
                HStack(spacing: 10) {
                    ToolbarButton(
                        symbol: note.isPinned ? "pin.fill" : "pin", help: note.isPinned ? "Unpin" : "Pin to top",
                        isOn: note.isPinned
                    ) { withAnimation(spring) { notes.togglePin(note.id) } }
                    Spacer(minLength: 0)
                    // What the note is (color, pin) on the left; what to do with its text on the right.
                    if note.hasOpenChecklist {
                        ToolbarButton(symbol: "checklist", help: "Send unticked items to Tasks", isOn: false) {
                            _ = notes.sendToTasks(note.id)
                        }
                        .transition(.opacity)
                    }
                    ShareLink(item: note.text, subject: Text(note.title)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Share to Notes, Mail, Messages, and more")
                    .accessibilityLabel("Share")
                }
                .opacity(showsPalette ? 0 : 1)
                .allowsHitTesting(!showsPalette)
                .accessibilityHidden(showsPalette)
                // Out of the way at once; back once the swatches have folded up.
                .animation(
                    showsPalette ? .easeOut(duration: 0.1) : .easeIn(duration: 0.18).delay(0.12), value: showsPalette)
                ColorPalette(selected: note.color, open: showsPalette) { color in
                    notes.setColor(note.id, color)
                    showsPalette = false
                }
            }
        }
        .onChange(of: notes.selection) { _, _ in showsPalette = false }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.75))
        .frame(height: HeaderIcon.side)  // in line with the list's header
    }

    private func footer(_ note: Note) -> some View {
        HStack(spacing: 6) {
            Text(note.wordCount == 1 ? "1 word" : "\(note.wordCount) words")
            Spacer(minLength: 0)
            if let notice = notes.notice {
                Text(notice).foregroundStyle(.white.opacity(0.85)).transition(.opacity)
            } else {
                Text("Edited \(note.modified, format: .relative(presentation: .named))")
            }
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.45))
        .lineLimit(1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: notes.notice)
    }
}

extension NoteColor {
    var swatch: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        }
    }
}

/// One note in the list. The selection highlight slides between rows; hovering shows a lighter
/// highlight, a preview tooltip, and pin and delete buttons.
private struct NoteRow: View {
    let notes: NotesFeature
    let note: Note
    let isSelected: Bool
    let selectionSpace: Namespace.ID
    let select: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            if let color = note.color {
                Circle().fill(color.swatch).frame(width: 6, height: 6)
            }
            Text(note.title)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 0)
            if hovering {
                HStack(spacing: 5) {
                    Button {
                        notes.togglePin(note.id)
                    } label: {
                        Image(systemName: note.isPinned ? "pin.slash" : "pin")
                    }
                    .accessibilityLabel(note.isPinned ? "Unpin" : "Pin")
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { notes.delete(note.id) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Move to Trash")
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if note.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.14))
                    .matchedGeometryEffect(id: "selection", in: selectionSpace)
            } else if hovering {
                RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.07))
            }
        }
        .scaleEffect(hovering && !isSelected && !reduceMotion ? 1.02 : 1, anchor: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { hovering = inside }
        }
        .help(tooltip)
        .onDrag {
            notes.fileURL(for: note.id).flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider()
        }
        .contextMenu {
            Button(note.isPinned ? "Unpin" : "Pin to Top") { notes.togglePin(note.id) }
            Picker("Color", selection: Binding(get: { note.color }, set: { notes.setColor(note.id, $0) })) {
                Text("None").tag(NoteColor?.none)
                ForEach(NoteColor.allCases) { color in Text(color.name).tag(NoteColor?.some(color)) }
            }
            .pickerStyle(.menu)
            if note.hasOpenChecklist {
                Button("Send Unticked Items to Tasks") { _ = notes.sendToTasks(note.id) }
            }
            Button("Show in Finder") {
                if let url = notes.fileURL(for: note.id) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Divider()
            Button("Move to Trash", role: .destructive) { notes.delete(note.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: note.isPinned ? "Unpin" : "Pin") { notes.togglePin(note.id) }
        .accessibilityAction(named: "Move to Trash") { notes.delete(note.id) }
    }

    private var tooltip: String {
        let edited = "Edited " + note.modified.formatted(date: .abbreviated, time: .shortened)
        return note.preview.isEmpty ? "\(note.title)\n\(edited)" : "\(note.title)\n\(note.preview)\n\(edited)"
    }
}

/// An icon in the list's header, on a circle that brightens under the pointer.
private struct HeaderIcon: View {
    static let side: CGFloat = 22
    static let symbolSize: CGFloat = 10.5

    let symbol: String
    @State private var hovering = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: Self.symbolSize, weight: .semibold))
            .foregroundStyle(.white.opacity(hovering ? 1 : 0.8))
            .frame(width: Self.side, height: Self.side)
            .background(.white.opacity(hovering ? 0.18 : 0.1), in: Circle())
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// A small icon button in the editor's toolbar that brightens on hover.
private struct ToolbarButton: View {
    let symbol: String
    let help: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .opacity(hovering || isOn ? 1 : 0.7)
                .scaleEffect(hovering ? 1.12 : 1)
                .contentShape(Rectangle())
        }
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The colour choices, as swatches that grow under the pointer. Opening, they spring out of the
/// colour dot one after another; closing, they fold back into it, the last one first.
private struct ColorPalette: View {
    /// The colour dot, and the gap between it and the first swatch.
    static let dot: CGFloat = 10
    static let gap: CGFloat = 10
    private static let side: CGFloat = 11
    private static let spacing: CGFloat = 5
    private static let choices: [NoteColor?] = [nil] + NoteColor.allCases.map(Optional.some)

    let selected: NoteColor?
    let open: Bool
    let choose: (NoteColor?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(Array(Self.choices.enumerated()), id: \.offset) { index, color in
                Swatch(color: color, isSelected: selected == color) { choose(color) }
                    .scaleEffect(open || reduceMotion ? 1 : 0.2)
                    .offset(x: open || reduceMotion ? 0 : -folded(index))
                    .opacity(open ? 1 : 0)
                    .animation(animation(index), value: open)
            }
        }
        .allowsHitTesting(open)
        .accessibilityHidden(!open)
    }

    /// How far back swatch `index` sits when folded: centred on the colour dot.
    private func folded(_ index: Int) -> CGFloat {
        CGFloat(index) * (Self.side + Self.spacing) + Self.side / 2 + Self.gap + Self.dot / 2
    }

    private func animation(_ index: Int) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.15) }
        let order = open ? index : Self.choices.count - 1 - index
        return .spring(response: 0.3, dampingFraction: 0.72).delay(Double(order) * 0.02)
    }

    private struct Swatch: View {
        let color: NoteColor?
        let isSelected: Bool
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Circle()
                    .fill(color?.swatch ?? .clear)
                    .overlay(
                        Circle().strokeBorder(.white.opacity(isSelected ? 0.9 : 0.3), lineWidth: isSelected ? 2 : 1)
                    )
                    .overlay {
                        if color == nil { Image(systemName: "slash.circle").font(.system(size: 8)).opacity(0.6) }
                    }
                    .frame(width: 11, height: 11)
                    .scaleEffect(hovering ? 1.3 : 1)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovering)
            .help(color?.name ?? "No Color")
            .accessibilityLabel(color?.name ?? "No Color")
        }
    }
}
