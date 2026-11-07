// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// The shelf tab: dropped files in a scrolling row. Drag them back out, double-click to preview,
/// or use the context menu to reveal, AirDrop, send to Android, or remove them.
struct ShelfView: View {
    let shelf: ShelfFeature

    var body: some View {
        if shelf.items.isEmpty {
            VStack(spacing: 8) {
                FeatureUnavailableView(
                    symbol: "tray.and.arrow.down",
                    title: "Drop files here",
                    message: "Drag files onto the notch to keep them handy, then drag them back out when you need them."
                )
                if let control = shelf.androidControl {
                    control.font(.caption).padding(.bottom, 4)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 8) {
                        ForEach(shelf.items.reversed()) { item in
                            ShelfItemView(shelf: shelf, item: item)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .fadingEdges(.horizontal)
                HStack(spacing: 12) {
                    Text(shelf.items.count == 1 ? "1 item" : "\(shelf.items.count) items")
                        .foregroundStyle(.white.opacity(0.5))
                    shelf.androidControl
                    Spacer()
                    if let send = shelf.sendToAndroid {
                        Button("Send to Android") { send(shelf.items.compactMap(shelf.url(for:))) }
                    }
                    Button("AirDrop All") { shelf.airDrop(shelf.items) }
                    Button("Clear") { shelf.removeAll() }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .lineLimit(1)
            }
        }
    }
}

private struct ShelfItemView: View {
    let shelf: ShelfFeature
    let item: ShelfItem

    var body: some View {
        let url = shelf.url(for: item)
        VStack(spacing: 4) {
            icon(for: url)
                .resizable()
                .frame(width: 44, height: 44)
                .opacity(url == nil ? 0.35 : 1)
            // One line, middle-truncated, so the extension stays readable (never "Screenshot.p-ng").
            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
            if url == nil {
                Text("Missing").font(.caption2.bold()).foregroundStyle(.orange)
            }
        }
        .frame(width: 76)
        .contentShape(Rectangle())
        .onDrag { url.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider() }
        .onTapGesture(count: 2) { shelf.quickLook(item) }
        .contextMenu {
            Button("Quick Look") { shelf.quickLook(item) }.disabled(url == nil)
            Button("Show in Finder") { shelf.reveal(item) }.disabled(url == nil)
            Button("AirDrop") { shelf.airDrop([item]) }.disabled(url == nil)
            if let send = shelf.sendToAndroid {
                Button("Send to Android\u{2026}") { url.map { send([$0]) } }.disabled(url == nil)
            }
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(url == nil ? "\(item.name), missing" : item.name)
        .accessibilityAction(named: "Quick Look") { shelf.quickLook(item) }
        .accessibilityAction(named: "Remove from Shelf") { shelf.remove(item) }
    }

    private func icon(for url: URL?) -> Image {
        guard let url else { return Image(systemName: "questionmark.folder") }
        return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
    }
}
