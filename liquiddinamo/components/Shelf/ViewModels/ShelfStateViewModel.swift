//
//  ShelfStateViewModel.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team

import Foundation
import AppKit

@MainActor
final class ShelfStateViewModel: ObservableObject {
    static let shared = ShelfStateViewModel()

    @Published private(set) var items: [ShelfItem] = [] {
        didSet { ShelfPersistenceService.shared.save(items) }
    }

    @Published var isLoading: Bool = false

    var isEmpty: Bool { items.isEmpty }

    // Queue for deferred bookmark updates to avoid publishing during view updates
    private var pendingBookmarkUpdates: [ShelfItem.ID: Data] = [:]
    private var updateTask: Task<Void, Never>?

    private init() {
        items = ShelfPersistenceService.shared.load()
    }


    private struct TrackedShelfEntry: ShelfTrackable {
        let item: ShelfItem
        let identityKey: String
        let isTemporary: Bool
        let createdAt: Date

        @MainActor
        init(item: ShelfItem) {
            self.item = item
            self.identityKey = item.identityKey
            self.isTemporary = item.isTemporary
            self.createdAt = item.createdAt
        }
    }

    func add(_ newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        let existingEntries = items.map(TrackedShelfEntry.init)
        let incomingEntries = newItems.map(TrackedShelfEntry.init)
        let (mergedEntries, evictedEntries) = ShelfPolicy.inserting(
            contentsOf: incomingEntries,
            into: existingEntries,
            maxItems: ShelfPolicy.defaultMaxItems
        )
        for evicted in evictedEntries {
            evicted.item.cleanupStoredData()
        }
        items = mergedEntries.map(\.item)
        DynamicIslandHub.shared.triggerDropperItemAdded(count: newItems.count)
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.prompt = "Add to Dropper"
        panel.message = "Select files or folders to hold on the LiquidDynamo Dropper shelf."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        var selectedItems: [ShelfItem] = []
        for url in panel.urls {
            if let bookmark = url.accessSecurityScopedResource(accessor: { scopedURL in
                try? Bookmark(url: scopedURL)
            }) {
                selectedItems.append(ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: false))
            }
        }
        add(selectedItems)
    }

    func remove(_ item: ShelfItem) {
        item.cleanupStoredData()
        items.removeAll { $0.id == item.id }
    }

    func clearAll() {
        for item in items {
            item.cleanupStoredData()
        }
        items.removeAll()
    }

    func cleanupAllTemporaryItems() {
        for item in items where item.isTemporary {
            item.cleanupStoredData()
        }
        items.removeAll { $0.isTemporary }
    }

    func cleanupExpiredTemporaryItems(olderThan interval: TimeInterval = ShelfPolicy.defaultTemporaryTTL) {
        let now = Date()
        let tracked = items.map(TrackedShelfEntry.init)
        let expiredIDs = Set(ShelfPolicy.expiredItems(in: tracked, now: now, ttl: interval).map { $0.item.id })
        guard !expiredIDs.isEmpty else { return }
        for item in items where expiredIDs.contains(item.id) {
            item.cleanupStoredData()
        }
        items.removeAll { expiredIDs.contains($0.id) }
    }

    func updateBookmark(for item: ShelfItem, bookmark: Data) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if case .file = items[idx].kind {
            items[idx].kind = .file(bookmark: bookmark)
        }
    }

    private func scheduleDeferredBookmarkUpdate(for item: ShelfItem, bookmark: Data) {
        pendingBookmarkUpdates[item.id] = bookmark
        
        // Cancel existing task and schedule a new one
        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self] in
            await Task.yield()
            
            guard let self = self else { return }
            
            for (itemID, bookmarkData) in self.pendingBookmarkUpdates {
                if let idx = self.items.firstIndex(where: { $0.id == itemID }),
                   case .file = self.items[idx].kind {
                    self.items[idx].kind = .file(bookmark: bookmarkData)
                }
            }
            
            self.pendingBookmarkUpdates.removeAll()
        }
    }


    func load(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        isLoading = true
        Task { [weak self] in
            let dropped = await ShelfDropService.items(from: providers)
            await MainActor.run {
                self?.add(dropped)
                self?.isLoading = false
            }
        }
    }

    func cleanupInvalidItems() {
        Task { [weak self] in
            guard let self else { return }
            var keep: [ShelfItem] = []
            for item in self.items {
                switch item.kind {
                case .file(let data):
                    let bookmark = Bookmark(data: data)
                    if await bookmark.validate() {
                        keep.append(item)
                    } else {
                        item.cleanupStoredData()
                    }
                default:
                    keep.append(item)
                }
            }
            await MainActor.run { self.items = keep }
        }
    }


    func resolveFileURL(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            scheduleDeferredBookmarkUpdate(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveAndUpdateBookmark(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            updateBookmark(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveFileURLs(for items: [ShelfItem]) -> [URL] {
        var urls: [URL] = []
        for it in items {
            if let u = resolveFileURL(for: it) { urls.append(u) }
        }
        return urls
    }
}
