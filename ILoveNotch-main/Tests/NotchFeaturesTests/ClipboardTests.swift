// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import Testing

@testable import NotchFeatures

/// On a private pasteboard, which macOS always lets an app read, never the user's own clipboard.
@MainActor
struct ClipboardTests {
    private let pasteboard = NSPasteboard(name: .init("ILoveNotchTests.\(UUID().uuidString)"))
    private let folder = FileManager.default.temporaryDirectory.appending(path: "Clipboard-\(UUID().uuidString)")
    private let defaults = UserDefaults(suiteName: "Clipboard.\(UUID().uuidString)")!

    private func clipboard(in app: (id: String?, name: String?) = ("com.apple.TextEdit", "TextEdit")) throws
        -> ClipboardFeature
    {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return ClipboardFeature(
            pasteboard: pasteboard, defaults: defaults, storeURL: folder.appending(path: "clipboard.json"),
            imagesURL: folder.appending(path: "Clipboard"), frontmostApp: { app })
    }

    private func copy(_ text: String, marked type: String? = nil) {
        var types: [NSPasteboard.PasteboardType] = [.string]
        if let type { types.append(NSPasteboard.PasteboardType(type)) }
        pasteboard.clearContents()
        pasteboard.declareTypes(types, owner: nil)
        pasteboard.setString(text, forType: .string)
    }

    @Test func nothingIsReadUntilTheUserTurnsItOn() throws {
        let clipboard = try clipboard()
        clipboard.phase = .background
        #expect(!clipboard.isRecording && !clipboard.isPolling, "off by default: no poll at all")
        clipboard.startRecording()
        #expect(clipboard.isRecording && clipboard.isPolling && clipboard.access == .allowed)
        clipboard.stopRecording()
        #expect(!clipboard.isPolling)
    }

    @Test func copiesAreKeptNewestFirstAndACopyAgainMovesToTheTop() throws {
        let clipboard = try clipboard()
        clipboard.phase = .background
        clipboard.startRecording()
        copy("first")
        clipboard.check()
        copy("https://example.com/page")
        clipboard.check()
        copy("first")
        clipboard.check()
        clipboard.check()  // nothing changed since
        #expect(clipboard.items.map(\.text) == ["first", "https://example.com/page"])
        #expect(clipboard.items.map(\.kind) == [.text, .link] && clipboard.items.first?.source == "TextEdit")
    }

    @Test func privateCopiesAndPasswordManagersAreSkipped() throws {
        let clipboard = try clipboard()
        clipboard.phase = .background
        clipboard.startRecording()
        copy("hunter2", marked: "org.nspasteboard.ConcealedType")
        clipboard.check()
        #expect(clipboard.items.isEmpty, "marked secret by the app that copied it")

        let manager = try self.clipboard(in: ("com.1password.1password", "1Password"))
        manager.phase = .background
        manager.startRecording()
        copy("correct horse battery staple")
        manager.check()
        #expect(manager.items.isEmpty, "copied in a password manager")
    }

    @Test func filesAndImagesAreKeptAsWhatTheyAre() throws {
        let clipboard = try clipboard()
        clipboard.phase = .background
        clipboard.startRecording()
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(filePath: "/tmp/Invoice.pdf") as NSURL])
        clipboard.check()
        #expect(clipboard.items.first?.kind == .files && clipboard.items.first?.paths == ["/tmp/Invoice.pdf"])

        let image = NSImage(size: CGSize(width: 40, height: 30), flipped: false) { rect in
            NSColor.systemOrange.setFill()
            rect.fill()
            return true
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        clipboard.check()
        let copied = try #require(clipboard.items.first)
        #expect(copied.kind == .image && clipboard.image(for: copied) != nil && clipboard.thumbnail(for: copied) != nil)
    }

    @Test func pickingPutsAnItemBackWithoutRecordingItTwice() throws {
        let clipboard = try clipboard()
        var picked = false
        clipboard.onPicked = { picked = true }
        clipboard.phase = .background
        clipboard.startRecording()
        for text in ["one", "two"] {
            copy(text)
            clipboard.check()
        }
        let one = try #require(clipboard.items.last)
        clipboard.pick(one)
        clipboard.check()
        #expect(pasteboard.string(forType: .string) == "one" && picked)
        #expect(clipboard.items.map(\.text) == ["one", "two"], "back at the top, and only once")
    }

    @Test func favoritesOutlastTheCapAndClearing() throws {
        let clipboard = try clipboard()
        clipboard.phase = .background
        clipboard.startRecording()
        copy("keep me")
        clipboard.check()
        clipboard.toggleFavorite(try #require(clipboard.items.first))
        for index in 0...ClipboardFeature.capacity {
            copy("copy \(index)")
            clipboard.check()
        }
        #expect(clipboard.items.count == ClipboardFeature.capacity && clipboard.items.contains { $0.text == "keep me" })
        #expect(clipboard.search("").first?.text == "keep me", "favorites come first")
        #expect(clipboard.search("copy 20").map(\.text) == ["copy 200", "copy 20"])
        clipboard.clear()
        #expect(clipboard.items.map(\.text) == ["keep me"])
    }

    @Test func selectedItemsAreDeletedTogetherFavoritesToo() throws {
        let clipboard = try clipboard()
        clipboard.phase = .background
        clipboard.startRecording()
        for text in ["one", "two", "three"] {
            copy(text)
            clipboard.check()
        }
        let two = try #require(clipboard.items.first { $0.text == "two" })
        clipboard.toggleFavorite(two)
        let three = try #require(clipboard.items.first { $0.text == "three" })
        clipboard.remove([two.id, three.id])
        #expect(clipboard.items.map(\.text) == ["one"])
        clipboard.phase = .stopped
        clipboard.phase = .background
        #expect(clipboard.items.map(\.text) == ["one"], "saved that way")
    }

    @Test func theHistoryIsSavedAndLetGoWhenStopped() throws {
        let clipboard = try clipboard()
        clipboard.phase = .background
        clipboard.startRecording()
        copy("saved")
        clipboard.check()
        clipboard.phase = .stopped
        #expect(clipboard.items.isEmpty && !clipboard.isPolling, "stopped: nothing in memory, no poll")
        clipboard.phase = .background
        #expect(clipboard.items.map(\.text) == ["saved"])
        #expect(try self.clipboard().isRecording, "recording stays on across launches")
    }
}
