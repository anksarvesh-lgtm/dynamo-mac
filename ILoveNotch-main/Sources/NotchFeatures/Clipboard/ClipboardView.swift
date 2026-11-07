// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// The clipboard tab: search, then click an item (or press Return for the first match) to put it
/// back on the clipboard. Favorites come first and stay. Select mode ticks items to delete together,
/// and Clear deletes all but favorites.
struct ClipboardView: View {
    let clipboard: ClipboardFeature
    @State private var query = ""
    @FocusState private var searching: Bool
    /// Clicking a row ticks it instead of copying it.
    @State private var selecting = false
    @State private var selected: Set<ClipItem.ID> = []
    /// Clear asks once more, until the pointer leaves it.
    @State private var confirmingClear = false

    var body: some View {
        if !clipboard.isRecording {
            FeatureUnavailableView(
                symbol: "doc.on.clipboard", title: "Keep what you copy",
                message: "Text, links, images, and files you copy, kept on this Mac to find and copy again. "
                    + "Passwords and anything marked private are skipped.",
                action: (label: "Turn On", perform: clipboard.startRecording))
        } else if clipboard.access == .asks || clipboard.access == .denied {
            FeatureUnavailableView(
                symbol: "lock", title: "Let ILoveNotch read what you copy",
                message: "In System Settings › Privacy & Security › Paste from Other Apps, set ILoveNotch to "
                    + "Always Allow. Until then macOS would ask each time.",
                action: (
                    label: "Open Privacy Settings",
                    perform: { NSWorkspace.shared.open(.privacySettings("Privacy_Pasteboard")) }
                )
            )
            .onAppear(perform: clipboard.refreshAccess)
        } else {
            history
                .onAppear {
                    clipboard.refreshAccess()
                    takeSearch()
                }
                .onChange(of: clipboard.wantsSearch) { takeSearch() }
        }
    }

    private var history: some View {
        let found = clipboard.search(query)
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.caption).opacity(0.6)
                TextField("Search what you copied", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searching)
                    .onSubmit { if let first = found.first { clipboard.pick(first) } }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            if found.isEmpty {
                FeatureUnavailableView(
                    symbol: "doc.on.clipboard", title: clipboard.items.isEmpty ? "Nothing copied yet" : "No matches",
                    message: clipboard.items.isEmpty ? "Copy something and it shows up here." : "Try other words.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(found) { row($0) }
                    }
                    .padding(.vertical, 4)
                }
                .fadingEdges()
            }
            if !clipboard.items.isEmpty { footer(found) }
        }
    }

    /// How many are ticked or kept, and at the bottom right, Select and Clear, or while selecting,
    /// Select All, Delete, and Done.
    private func footer(_ found: [ClipItem]) -> some View {
        let keptByClear = clipboard.items.count { !$0.favorite }
        let allTicked = !found.isEmpty && found.allSatisfy { selected.contains($0.id) }
        return HStack(spacing: 8) {
            Group {
                if selecting {
                    Text("\(selected.count) selected")
                } else {
                    Text("^[\(clipboard.items.count) item](inflect: true)")
                }
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                if selecting {
                    footerButton(allTicked ? "Select None" : "Select All") {
                        selected = allTicked ? [] : Set(found.map(\.id))
                    }
                    footerButton("Delete", tint: .red) {
                        clipboard.remove(selected)
                        selected = []
                        if clipboard.items.isEmpty { selecting = false }
                    }
                    .disabled(selected.isEmpty)
                    .opacity(selected.isEmpty ? 0.4 : 1)
                    .help("Delete the selected items, favorites too")
                    footerButton("Done") {
                        selecting = false
                        selected = []
                    }
                } else {
                    footerButton("Select") {
                        confirmingClear = false
                        selecting = true
                    }
                    .help("Select items to delete")
                    footerButton(
                        confirmingClear ? "Clear ^[\(keptByClear) item](inflect: true)?" : "Clear",
                        tint: confirmingClear ? .red : .white
                    ) {
                        if confirmingClear {
                            clipboard.clear()
                            confirmingClear = false
                        } else {
                            confirmingClear = true
                        }
                    }
                    .disabled(keptByClear == 0)
                    .opacity(keptByClear == 0 ? 0.4 : 1)
                    .onHover { if !$0 { confirmingClear = false } }
                    .help(keptByClear == 0 ? "Only favorites are left" : "Delete everything but favorites")
                }
            }
            .background(GlassPlatter(shape: Capsule()))
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)  // clear of the resize grip in the notch's corner
    }

    private func footerButton(_ title: LocalizedStringKey, tint: Color = .white, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
    }

    /// The search field takes the keyboard when the tab opened from its shortcut.
    private func takeSearch() {
        guard clipboard.wantsSearch else { return }
        clipboard.wantsSearch = false
        searching = true
    }

    private func row(_ item: ClipItem) -> some View {
        let ticked = selected.contains(item.id)
        return Button {
            if !selecting {
                clipboard.pick(item)
            } else if ticked {
                selected.remove(item.id)
            } else {
                selected.insert(item.id)
            }
        } label: {
            HStack(spacing: 8) {
                if selecting {
                    Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(ticked ? Color.accentColor : .white.opacity(0.4))
                }
                preview(item)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title(item)).font(.callout).lineLimit(1).truncationMode(.middle)
                    Text(detail(item)).font(.caption2).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 0)
                if !selecting {
                    Button {
                        clipboard.toggleFavorite(item)
                    } label: {
                        Image(systemName: item.favorite ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundStyle(item.favorite ? .yellow : .white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help(item.favorite ? "Remove from favorites" : "Keep as a favorite")
                    .accessibilityLabel(item.favorite ? "Favorite" : "Not a favorite")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.white.opacity(ticked ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(selecting ? (ticked ? "Deselect" : "Select") : "Copy again")
        .contextMenu {
            Button("Copy") { clipboard.pick(item) }
            Button(item.favorite ? "Remove from Favorites" : "Add to Favorites") { clipboard.toggleFavorite(item) }
            Divider()
            Button("Delete") { delete(item) }
        }
        .accessibilityAddTraits(ticked ? .isSelected : [])
        .accessibilityAction(named: "Delete") { delete(item) }
    }

    private func delete(_ item: ClipItem) {
        clipboard.remove(item)
        selected.remove(item.id)
    }

    @ViewBuilder private func preview(_ item: ClipItem) -> some View {
        switch item.kind {
        case .image:
            if let image = clipboard.thumbnail(for: item) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                Image(systemName: "photo")
            }
        case .files:
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.paths.first ?? "/")).resizable()
        case .link:
            Image(systemName: "link").font(.system(size: 13)).opacity(0.8)
        case .text:
            Image(systemName: "text.alignleft").font(.system(size: 13)).opacity(0.8)
        }
    }

    private func title(_ item: ClipItem) -> String {
        switch item.kind {
        case .files:
            let names = item.paths.map { URL(filePath: $0).lastPathComponent }
            return names.count == 1 ? names[0] : "\(names[0]) and \(names.count - 1) more"
        default:
            return item.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? item.text
        }
    }

    private func detail(_ item: ClipItem) -> String {
        let when = item.copied.formatted(.relative(presentation: .named))
        return [item.source, when].compactMap { $0 }.joined(separator: " · ")
    }
}
