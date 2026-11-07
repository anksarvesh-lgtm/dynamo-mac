// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import Observation
import QuickLookUI
import SwiftUI

/// A file on the shelf, kept as a bookmark so it follows renames and moves.
public struct ShelfItem: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var bookmark: Data
    public var name: String
}

/// Files dropped on the notch, saved across launches. A file that disappears stays on the shelf,
/// marked missing, until the user removes it: nothing is dropped silently.
@MainActor
@Observable
public final class ShelfFeature: NotchFeature {
    public let id = FeatureID.shelf
    public var phase: FeaturePhase = .stopped {
        didSet { if phase == .foreground { refresh() } }
    }
    public private(set) var items: [ShelfItem] = []
    /// Where each file is now. An item without a location is missing.
    public private(set) var locations: [ShelfItem.ID: URL] = [:]
    /// Raised when files land on the shelf.
    @ObservationIgnored public var onActivity: ((Activity) -> Void)?
    /// Sends files to an Android phone, in the build that can (the GitHub build's Quick Share).
    @ObservationIgnored public var sendToAndroid: (([URL]) -> Void)?
    /// Receiving from Android, for the footer, in the build that can.
    @ObservationIgnored public var androidControl: AnyView?

    // ponytail: a fixed cap keeps the shelf and its bookmark checks bounded; make it a setting if asked.
    static let capacity = 100
    /// A sandboxed build (the App Store edition) may only reach a dropped file again through a
    /// security-scoped bookmark, and holds access to each file while it's on the shelf.
    static let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    @ObservationIgnored private let storeURL: URL
    @ObservationIgnored private let quickLook = QuickLookSource()
    /// Files whose security scope is open, in a sandboxed build.
    @ObservationIgnored private var accessing: [ShelfItem.ID: URL] = [:]

    public init(storeURL: URL = AppSupport.file("shelf.json")) {
        self.storeURL = storeURL
        if let data = try? Data(contentsOf: storeURL) {
            items = (try? JSONDecoder().decode([ShelfItem].self, from: data)) ?? []
        }
        refresh()
    }

    public var view: some View { ShelfView(shelf: self) }

    /// Adds dropped files, skipping ones already on the shelf. Returns whether anything was added.
    @discardableResult
    public func add(_ urls: [URL]) -> Bool {
        var known = Set(locations.values.map(\.standardizedFileURL))
        var added: [ShelfItem] = []
        for url in urls where url.isFileURL && !known.contains(url.standardizedFileURL) {
            guard let bookmark = try? url.bookmarkData(options: Self.bookmarkOptions) else { continue }
            let item = ShelfItem(bookmark: bookmark, name: url.lastPathComponent)
            added.append(item)
            locations[item.id] = url
            known.insert(url.standardizedFileURL)
        }
        guard !added.isEmpty else { return false }
        items = Array((items + added).suffix(Self.capacity))
        save()
        let title = added.count == 1 ? "1 file" : "\(added.count) files"
        onActivity?(Activity(feature: .shelf, symbol: "tray.and.arrow.down.fill", title: title, duration: .seconds(2)))
        return true
    }

    public func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        locations[item.id] = nil
        accessing.removeValue(forKey: item.id)?.stopAccessingSecurityScopedResource()
        save()
    }

    public func removeAll() {
        items = []
        locations = [:]
        for url in accessing.values { url.stopAccessingSecurityScopedResource() }
        accessing = [:]
        save()
    }

    /// The file's current location, or nil if it's missing.
    public func url(for item: ShelfItem) -> URL? { locations[item.id] }

    public func quickLook(_ item: ShelfItem) {
        guard let url = url(for: item) else { return }
        quickLook.show(url)
    }

    public func airDrop(_ items: [ShelfItem]) {
        let urls = items.compactMap(url(for:))
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate()
        service.perform(withItems: urls)
    }

    public func reveal(_ item: ShelfItem) {
        guard let url = url(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Finds every file again and renews bookmarks that went stale after a move or rename.
    func refresh() {
        var found: [ShelfItem.ID: URL] = [:]
        var renewed = false
        for index in items.indices {
            var stale = false
            let item = items[index]
            guard
                let url = try? URL(
                    resolvingBookmarkData: item.bookmark, options: Self.resolutionOptions, bookmarkDataIsStale: &stale)
            else { continue }
            if Self.sandboxed, accessing[item.id] == nil, url.startAccessingSecurityScopedResource() {
                accessing[item.id] = url
            }
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            found[item.id] = url
            if stale, let fresh = try? url.bookmarkData(options: Self.bookmarkOptions) {
                items[index].bookmark = fresh
                items[index].name = url.lastPathComponent
                renewed = true
            }
        }
        locations = found
        if renewed { save() }
    }

    private static var bookmarkOptions: URL.BookmarkCreationOptions { sandboxed ? .withSecurityScope : [] }
    private static var resolutionOptions: URL.BookmarkResolutionOptions { sandboxed ? .withSecurityScope : [] }

    private func save() {
        do {
            try JSONEncoder().encode(items).write(to: storeURL, options: .atomic)
        } catch {
            Log.features.error("Couldn't save the shelf: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Feeds one file to the shared Quick Look panel, independent of the notch's views, so the preview
/// stays open when the notch collapses.
@MainActor
private final class QuickLookSource: NSObject, @preconcurrency QLPreviewPanelDataSource {
    private var url: URL?

    func show(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        url as NSURL?
    }
}
