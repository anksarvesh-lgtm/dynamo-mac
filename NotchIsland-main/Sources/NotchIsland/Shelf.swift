import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Files parked on the notch: drag them in, drag them out later, or AirDrop them.
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [URL] = []

    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        withAnimation(Motion.quick) {
            for url in urls where !items.contains(url) { items.insert(url, at: 0) }
            if items.count > 12 { items.removeLast(items.count - 12) }
        }
        Feedback.tap()
    }

    func remove(_ url: URL) { withAnimation(Motion.quick) { items.removeAll { $0 == url } } }
    func clear() { withAnimation(Motion.quick) { items.removeAll() } }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    /// Resolves dropped item providers to file URLs.
    static func urls(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}

struct ShelfStrip: View {
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(symbol: "tray.full.fill", "Shelf", count: shelf.items.count) {
                PillButton(title: "AirDrop", symbol: "square.and.arrow.up", small: true, help: "AirDrop everything on the shelf") {
                    shelf.airDrop(shelf.items)
                }
                IconButton(symbol: "xmark", size: 22, help: "Clear the shelf") { shelf.clear() }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(shelf.items, id: \.self) { url in
                        VStack(spacing: 5) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable().frame(width: 40, height: 40)
                            Text(url.lastPathComponent)
                                .font(UI.caption(9.5)).lineLimit(1).frame(width: 64)
                        }
                        .padding(.vertical, 8)
                        .frame(width: 76)
                        .background(UI.controlFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
                        .help(url.lastPathComponent)
                        .contextMenu {
                            Button("Open") { NSWorkspace.shared.open(url) }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            Button("AirDrop…") { shelf.airDrop([url]) }
                            Divider()
                            Button("Remove from Shelf") { shelf.remove(url) }
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.never)
        }
        .foregroundStyle(.white)
        .islandCard()
    }
}
