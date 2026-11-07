// SPDX-License-Identifier: MIT
import Foundation
import NotchCore
import Testing

@testable import NotchFeatures

@MainActor
struct ShelfFeatureTests {
    /// A scratch folder per test, with a few real files to drop.
    private let folder: URL
    private let store: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ShelfTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store = folder.appending(path: "shelf.json")
    }

    private func file(_ name: String) throws -> URL {
        let url = folder.appending(path: name)
        try Data(name.utf8).write(to: url)
        return url
    }

    @Test func droppedFilesAreKeptAndAnnounced() throws {
        let shelf = ShelfFeature(storeURL: store)
        var activities: [Activity] = []
        shelf.onActivity = { activities.append($0) }

        #expect(shelf.add([try file("a.txt"), try file("b.txt")]))
        #expect(shelf.items.map(\.name) == ["a.txt", "b.txt"])
        #expect(activities.map(\.title) == ["2 files"])
    }

    @Test func dropsAlreadyOnTheShelfAreSkipped() throws {
        let shelf = ShelfFeature(storeURL: store)
        let a = try file("a.txt")
        shelf.add([a])
        #expect(!shelf.add([a]))
        #expect(shelf.add([a, try file("b.txt")]))
        #expect(shelf.items.count == 2)
    }

    @Test func theShelfSurvivesARelaunch() throws {
        ShelfFeature(storeURL: store).add([try file("a.txt")])
        let relaunched = ShelfFeature(storeURL: store)
        #expect(relaunched.items.map(\.name) == ["a.txt"])
        #expect(relaunched.url(for: relaunched.items[0]) != nil)
    }

    @Test func renamedFilesAreFollowed() throws {
        let shelf = ShelfFeature(storeURL: store)
        let original = try file("draft.txt")
        shelf.add([original])
        let renamed = folder.appending(path: "final.txt")
        try FileManager.default.moveItem(at: original, to: renamed)

        shelf.phase = .foreground  // coming on screen re-resolves bookmarks
        #expect(shelf.url(for: shelf.items[0])?.lastPathComponent == "final.txt")
        #expect(shelf.items[0].name == "final.txt")
    }

    @Test func deletedFilesStayVisibleAsMissing() throws {
        let shelf = ShelfFeature(storeURL: store)
        let doomed = try file("doomed.txt")
        shelf.add([doomed, try file("kept.txt")])
        try FileManager.default.removeItem(at: doomed)

        shelf.phase = .foreground
        #expect(shelf.items.count == 2, "missing files are shown, not dropped")
        #expect(shelf.url(for: shelf.items[0]) == nil)
        #expect(shelf.url(for: shelf.items[1]) != nil)
        shelf.remove(shelf.items[0])
        #expect(ShelfFeature(storeURL: store).items.map(\.name) == ["kept.txt"])
    }

    @Test func theShelfIsBounded() throws {
        let shelf = ShelfFeature(storeURL: store)
        let files = try (0..<(ShelfFeature.capacity + 5)).map { try file("\($0).txt") }
        shelf.add(files)
        #expect(shelf.items.count == ShelfFeature.capacity)
        #expect(shelf.items.last?.name == "\(ShelfFeature.capacity + 4).txt", "the newest files are kept")
    }
}
