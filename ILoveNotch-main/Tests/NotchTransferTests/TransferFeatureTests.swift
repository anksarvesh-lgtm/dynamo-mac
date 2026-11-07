// SPDX-License-Identifier: MIT
import AppKit
import Network
import NotchCore
import SwiftUI
import Testing

@testable import NotchFeatures
@testable import NotchTransfer

struct VisibilityTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func visible(
        _ mode: TransferFeature.ReceiveMode, awake: Bool = true, open: Bool = false, closedAgo: TimeInterval? = nil,
        windowLeft: TimeInterval? = nil
    ) -> Bool {
        TransferFeature.shouldBeVisible(
            mode: mode, awake: awake, notchOpen: open, closedAt: closedAgo.map { now - $0 },
            visibleUntil: windowLeft.map { now + $0 }, now: now)
    }

    @Test func theMacIsVisibleOnlyWhenTheUserAllowsIt() {
        #expect(!visible(.off))
        #expect(!visible(.off, open: true))
        #expect(visible(.always))
        #expect(visible(.whileOpen, open: true))
        #expect(!visible(.whileOpen))
    }

    @Test func whileOpenLastsAMinutePastClosing() {
        #expect(visible(.whileOpen, closedAgo: 30))
        #expect(!visible(.whileOpen, closedAgo: TransferFeature.linger + 1))
    }

    @Test func theTenMinuteWindowOverridesOffAndEnds() {
        #expect(visible(.off, windowLeft: 5 * 60))
        #expect(!visible(.off, windowLeft: -1))
    }

    @Test func nothingIsAnnouncedAsleepLockedOrWithTheShelfOff() {
        for mode in TransferFeature.ReceiveMode.allCases {
            #expect(!visible(mode, awake: false, open: true, windowLeft: 60))
        }
    }

    @MainActor
    @Test func settingsAreKept() throws {
        let defaults = try #require(UserDefaults(suiteName: "Transfer-\(UUID())"))
        let transfer = TransferFeature(defaults: defaults)
        #expect(transfer.receiveMode == .off, "off until the user turns it on")
        #expect(transfer.addsToShelf)
        transfer.receiveMode = .whileOpen
        transfer.deviceName = "Studio"
        transfer.addsToShelf = false
        let relaunched = TransferFeature(defaults: defaults)
        #expect(relaunched.receiveMode == .whileOpen)
        #expect(relaunched.name == "Studio")
        #expect(!relaunched.addsToShelf)
        #expect(
            TransferFeature(defaults: try #require(UserDefaults(suiteName: "T-\(UUID())"))).name
                == TransferFeature.computerName)
    }

    @Test func everyDeviceSymbolExists() {
        for kind in [EndpointInfo.Kind.unknown, .phone, .tablet, .laptop, .car, .foldable, .headset] {
            #expect(NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil) != nil, "\(kind)")
        }
    }
}

/// Renders the notch's Android cards and the send window. Always checks that they draw; with
/// SNAPSHOT_DIR set, also writes PNGs there for eyeballing.
@MainActor
struct TransferSnapshotTests {
    /// The content area of an expanded notch, and of the smallest one.
    private static let notch = CGSize(width: 428, height: 200)
    private static let smallest = CGSize(width: 350, height: 102)

    private let transfer = TransferFeature(defaults: UserDefaults(suiteName: "TransferSnapshot-\(UUID())")!)
    private let link = FrameLink(NWConnection(host: "127.0.0.1", port: 9, using: .tcp))
    private let device = NearbyDevice(
        id: "AB12", name: "Galaxy S25 Ultra", kind: .phone, endpoint: .hostPort(host: "127.0.0.1", port: 9))

    private func offer(files: Int = 3, text: TextOffer? = nil) -> InboundSession.Offer {
        let photos = (0..<files).map {
            FileOffer(name: "IMG_20\(41 + $0).jpg", size: 3_400_000, mimeType: "image/jpeg", payloadID: Int64($0))
        }
        return InboundSession.Offer(
            device: "Galaxy S25 Ultra", kind: .phone, pin: "4821", files: photos, text: text,
            size: photos.reduce(0) { $0 + $1.size })
    }

    @Test func aPhoneAskingToSend() throws {
        transfer.show(incoming: Incoming(id: UUID(), link: link, offer: offer()))
        try render(transfer.shelfView(AnyView(Color.clear)), name: "android-request")
        transfer.show(incoming: Incoming(id: UUID(), link: link, offer: offer(files: 1)))
        try render(transfer.shelfView(AnyView(Color.clear)), name: "android-request-one-file")
    }

    @Test func receivingAndReceivedText() throws {
        transfer.show(incoming: Incoming(id: UUID(), link: link, offer: offer(), progress: 0.62))
        try render(transfer.shelfView(AnyView(Color.clear)), name: "android-receiving")
        let link = TextOffer(title: "Swift Concurrency", kind: .url, size: 40, payloadID: 9)
        transfer.show(
            incoming: Incoming(
                id: UUID(), link: self.link, offer: offer(files: 0, text: link),
                text: ReceivedText(text: "https://www.swift.org/documentation/concurrency/", kind: .url)))
        try render(transfer.shelfView(AnyView(Color.clear)), name: "android-link")
    }

    @Test func theShelfWithAndroidInItsFooter() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "AndroidShelf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let shelf = ShelfFeature(storeURL: folder.appending(path: "shelf.json"))
        shelf.sendToAndroid = { _ in }
        shelf.androidControl = AnyView(transfer.receiveControl)
        try render(transfer.shelfView(AnyView(shelf.view)), name: "android-shelf-empty")
        let files = try ["Invoice.pdf", "Screenshot.png", "Notes.txt"].map { name in
            let url = folder.appending(path: name)
            try Data(name.utf8).write(to: url)
            return url
        }
        shelf.add(files)
        try render(transfer.shelfView(AnyView(shelf.view)), name: "android-shelf")
        transfer.show(incoming: nil, visibleUntil: .now + 540)
        try render(transfer.shelfView(AnyView(shelf.view)), name: "android-shelf-visible")
    }

    @Test func theSendWindow() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "SendWindow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = try ["Holiday.mov", "Boarding pass.pdf"].map { name in
            let url = folder.appending(path: name)
            try Data(repeating: 1, count: 2_500_000).write(to: url)
            return url
        }
        var outgoing = Outgoing(files: files)
        transfer.show(incoming: nil, outgoing: outgoing)
        try window(name: "send-looking")
        transfer.show(incoming: nil, outgoing: outgoing, devices: [device])
        try window(name: "send-picking")
        outgoing.device = device
        outgoing.pin = "4821"
        outgoing.state = .waiting
        transfer.show(incoming: nil, outgoing: outgoing)
        try window(name: "send-waiting")
        outgoing.state = .sending(0.4)
        transfer.show(incoming: nil, outgoing: outgoing)
        try window(name: "send-sending")
        outgoing.state = .failed("Galaxy S25 Ultra declined")
        transfer.show(incoming: nil, outgoing: outgoing)
        try window(name: "send-failed")
    }

    @Test func settings() throws {
        let form = Form { transfer.settingsView }.formStyle(.grouped).frame(width: 460, height: 330)
        try write(form, name: "android-settings", size: CGSize(width: 460, height: 330), scheme: .light)
    }

    /// The tab as the notch shows it: white on black, dark mode, in the content area. Without a size,
    /// at the default size and again at the smallest.
    private func render(_ view: some View, name: String, size: CGSize? = nil) throws {
        guard let size else {
            try render(view, name: name, size: Self.notch)
            return try render(view, name: name + "-smallest", size: Self.smallest)
        }
        let framed = view.frame(width: size.width, height: size.height).padding(16).background(.black)
            .foregroundStyle(.white)
        try write(framed, name: name, size: CGSize(width: size.width + 32, height: size.height + 32), scheme: .dark)
    }

    /// The send window's content, in light and dark.
    private func window(name: String) throws {
        let view = SendView(transfer: transfer) {}.background(Color(nsColor: .windowBackgroundColor))
        let size = NSHostingView(rootView: view).fittingSize
        try write(view, name: name, size: size, scheme: .light)
        try write(view, name: name + "-dark", size: size, scheme: .dark)
    }

    private func write(_ view: some View, name: String, size: CGSize, scheme: ColorScheme) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
        if let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(
                to: URL(filePath: directory).appending(path: "\(name).png"))
        }
    }
}
