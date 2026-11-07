// SPDX-License-Identifier: MIT
import AppKit
import Network
import NotchCore
import Observation
import SystemConfiguration

/// Sharing with Android phones over Quick Share, for the shelf, on the local network only.
///
/// Receiving: while the user allows it, the Mac announces itself to phones on the same Wi-Fi. A
/// phone that connects shows up in the notch with its code, and nothing is saved until the user
/// accepts. Sending: shelf files go from a small window, like AirDrop's, that looks for phones
/// only while it's open and shows a QR code for phones that won't appear otherwise.
@MainActor
@Observable
public final class TransferFeature {
    public enum ReceiveMode: String, CaseIterable, Identifiable, Sendable {
        case off, whileOpen, always

        public var id: Self { self }

        var title: String {
            switch self {
            case .off: "Off"
            case .whileOpen: "While the notch is open"
            case .always: "Always"
            }
        }
    }

    /// Staying visible this long after the notch closes lets the user close it and pick the Mac
    /// on the phone.
    nonisolated static let linger: TimeInterval = 60
    /// "Receive for 10 minutes".
    nonisolated static let window: TimeInterval = 600

    public var receiveMode: ReceiveMode {
        didSet {
            defaults.set(receiveMode.rawValue, forKey: Key.mode)
            updateVisibility()
        }
    }

    /// The name phones show; empty means the Mac's own name.
    public var deviceName: String {
        didSet {
            defaults.set(deviceName, forKey: Key.name)
            if advertiser.isRunning { advertiser.start(endpointID: endpointID, info: me) }
        }
    }

    public var addsToShelf: Bool {
        didSet { defaults.set(addsToShelf, forKey: Key.addsToShelf) }
    }

    /// Where received files go; nil means Downloads.
    public private(set) var folder: URL?

    /// When "Receive for 10 minutes" ends.
    private(set) var visibleUntil: Date?
    /// Announcing the Mac right now.
    private(set) var isVisible = false
    private(set) var localNetworkDenied = false
    /// The share a phone is offering or sending, shown in the Shelf tab.
    private(set) var incoming: Incoming?
    /// The send window's transfer, while it's open.
    private(set) var outgoing: Outgoing?
    /// Devices nearby, while the send window looks for them.
    private(set) var devices: [NearbyDevice] = []
    /// The send window's QR code, for phones that only appear after scanning it.
    private(set) var qrCode: QRCodeKey?

    /// A one-shot live activity: received, sent, or why not.
    @ObservationIgnored public var onActivity: ((Activity) -> Void)?
    /// What the resting notch shows meanwhile: a phone waiting for an answer, or progress.
    @ObservationIgnored public var onOngoing: ((Activity?) -> Void)?
    /// Received files, for the shelf, when the user has that on.
    @ObservationIgnored public var onReceived: (([URL]) -> Void)?
    /// A phone is asking: the notch should open on the shelf, where the request is.
    @ObservationIgnored public var onRequest: (() -> Void)?

    /// This Mac's identity on the network for as long as the app runs.
    @ObservationIgnored let endpointID = ServiceName.randomEndpointID()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let advertiser = Advertiser()
    @ObservationIgnored private let browser = Browser()
    @ObservationIgnored private var sendWindow: SendWindow?
    @ObservationIgnored private var check: Task<Void, Never>?
    @ObservationIgnored private var awake = false
    @ObservationIgnored private var notchOpen = false
    @ObservationIgnored private var notchClosedAt: Date?
    @ObservationIgnored private var shownOngoing: Activity?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        receiveMode = defaults.string(forKey: Key.mode).flatMap(ReceiveMode.init) ?? .off
        deviceName = defaults.string(forKey: Key.name) ?? ""
        addsToShelf = defaults.object(forKey: Key.addsToShelf) as? Bool ?? true
        folder = defaults.string(forKey: Key.folder).map { URL(filePath: $0, directoryHint: .isDirectory) }
        advertiser.onConnection = { [weak self] in self?.receive($0) }
        advertiser.onDenied = { [weak self] in self?.localNetworkDenied = $0 }
        browser.onChange = { [weak self] in self?.found($0) }
        browser.onDenied = { [weak self] in self?.localNetworkDenied = $0 }
    }

    /// The name phones show.
    var name: String {
        let chosen = deviceName.trimmingCharacters(in: .whitespaces)
        return chosen.isEmpty ? Self.computerName : chosen
    }

    static var computerName: String {
        SCDynamicStoreCopyComputerName(nil, nil) as String? ?? Host.current().localizedName ?? "Mac"
    }

    /// The chosen folder while it's there, else Downloads.
    var saveFolder: URL {
        if let folder, FileManager.default.fileExists(atPath: folder.path) { return folder }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    func chooseFolder(_ url: URL?) {
        folder = url
        defaults.set(url?.path, forKey: Key.folder)
    }

    private var me: EndpointInfo { EndpointInfo(name: name, kind: .laptop) }

    // MARK: Being visible

    /// The notch changed: whether any is open, and whether it's on screen at all (not asleep,
    /// locked, or turned off with the Shelf).
    public func notchChanged(_ presentations: [NotchPresentationState], shelfEnabled: Bool) {
        let open = presentations.contains { $0.openTab != nil }
        if notchOpen, !open { notchClosedAt = .now }
        notchOpen = open
        awake = shelfEnabled && presentations.contains { $0 != .hidden && $0 != .suspended }
        updateVisibility()
    }

    /// Visible for ten minutes whatever the mode, as Android's own "Everyone for 10 minutes".
    func receiveForTenMinutes() {
        visibleUntil = .now.addingTimeInterval(Self.window)
        updateVisibility()
    }

    func stopReceiving() {
        visibleUntil = nil
        notchClosedAt = nil
        if receiveMode == .always { receiveMode = .off }
        updateVisibility()
    }

    /// Whether to announce the Mac: never while the notch is off screen (asleep, locked) or the
    /// Shelf is off; during a 10-minute window; otherwise as the mode says, with the notch's
    /// "open" lasting a minute past its closing.
    nonisolated static func shouldBeVisible(
        mode: ReceiveMode, awake: Bool, notchOpen: Bool, closedAt: Date?, visibleUntil: Date?, now: Date
    ) -> Bool {
        guard awake else { return false }
        if let visibleUntil, now < visibleUntil { return true }
        switch mode {
        case .off: return false
        case .always: return true
        case .whileOpen: return notchOpen || closedAt.map { now < $0.addingTimeInterval(linger) } ?? false
        }
    }

    private func updateVisibility() {
        let now = Date.now
        if let visibleUntil, visibleUntil <= now { self.visibleUntil = nil }
        let visible = Self.shouldBeVisible(
            mode: receiveMode, awake: awake, notchOpen: notchOpen, closedAt: notchClosedAt,
            visibleUntil: visibleUntil, now: now)
        if visible, !advertiser.isRunning { advertiser.start(endpointID: endpointID, info: me) }
        if !visible { advertiser.stop() }
        if isVisible != visible { isVisible = visible }
        // One timer, for the next moment that could change the answer.
        check?.cancel()
        let lingerEnd = notchOpen || receiveMode != .whileOpen ? nil : notchClosedAt?.addingTimeInterval(Self.linger)
        guard let next = [visibleUntil, lingerEnd].compactMap({ $0 }).filter({ $0 > now }).min() else { return }
        check = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSince(now)), tolerance: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.updateVisibility()
        }
    }

    // MARK: Receiving

    /// A phone connected. One share at a time: another phone is turned away until it's done, and
    /// takes the place of text that already arrived.
    private func receive(_ connection: NWConnection) {
        guard incoming == nil || incoming?.text != nil else {
            connection.cancel()
            return
        }
        let link = FrameLink(connection)
        let id = UUID()
        incoming = Incoming(id: id, link: link)
        let (updates, input) = AsyncStream<InboundSession.Update>.makeStream()
        let folder = saveFolder
        Task.detached {
            await InboundSession(link: link, folder: folder) { input.yield($0) }.run()
            input.finish()
        }
        Task { [weak self] in
            for await update in updates { self?.apply(update, to: id) }
            self?.ended(id)
        }
    }

    private func apply(_ update: InboundSession.Update, to id: UUID) {
        guard var incoming, incoming.id == id else { return }  // declined or cancelled here meanwhile
        switch update {
        case .asking(let offer):
            incoming.offer = offer
            self.incoming = incoming
            onRequest?()
        case .progress(let done):
            incoming.progress = done
            self.incoming = incoming
        case .files(let urls):
            self.incoming = nil
            if addsToShelf { onReceived?(urls) }
            let what = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
            announce("checkmark.circle.fill", "\(what) from \(incoming.device)")
        case .text(let text, let kind):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            incoming.text = ReceivedText(text: text, kind: kind)
            self.incoming = incoming
            announce("doc.on.clipboard.fill", "Copied from \(incoming.device)")
        case .failed(let error):
            self.incoming = nil
            announce("exclamationmark.circle.fill", Self.describe(error, device: incoming.device, sending: false))
        }
        updateOngoing()
    }

    /// The session ended; if it never got as far as asking, the notch never showed it.
    private func ended(_ id: UUID) {
        guard incoming?.id == id, incoming?.text == nil else { return }
        incoming = nil
        updateOngoing()
    }

    func acceptIncoming() {
        guard var incoming, incoming.offer != nil, incoming.progress == nil else { return }
        incoming.link.post(.accept)
        incoming.progress = 0
        self.incoming = incoming
        updateOngoing()
    }

    func declineIncoming() {
        incoming?.link.post(.decline)
        incoming = nil
        updateOngoing()
    }

    func cancelIncoming() {
        incoming?.link.post(.cancel)
        incoming = nil
        updateOngoing()
    }

    /// Opens a shared web link. Other kinds of link are only copied, never opened.
    func openLink() {
        if let text = incoming?.text?.text, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            ["http", "https"].contains(url.scheme?.lowercased())
        {
            NSWorkspace.shared.open(url)
        }
        dismissText()
    }

    func dismissText() {
        incoming = nil
        updateOngoing()
    }

    // MARK: Sending

    /// Opens the send window for these files, and looks for devices while it's open.
    public func send(_ urls: [URL]) {
        if outgoing?.isBusy == true { return showSendWindow() }  // one at a time
        let files = urls.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        guard !files.isEmpty else {
            return announce("folder.fill", urls.count == 1 ? "Folders can't be sent" : "Only files can be sent")
        }
        outgoing = Outgoing(files: files)
        startLooking()
        showSendWindow()
    }

    /// Back to the device list after a failed attempt.
    func tryAgain() {
        guard let files = outgoing?.files else { return }
        outgoing = Outgoing(files: files)
        startLooking()
    }

    private func startLooking() {
        devices = []
        qrCode = QRCodeKey()
        browser.start(excluding: endpointID)
    }

    private func found(_ found: [NearbyDevice]) {
        guard outgoing?.state == .picking else { return }
        // A phone that scanned the code gets the files straight away.
        if let qrCode {
            for var device in found {
                guard let answer = device.qrData,
                    let name = qrCode.name(answering: answer, shown: device.name.isEmpty ? nil : device.name)
                else { continue }
                device.name = name
                return send(to: device, answering: qrCode)
            }
        }
        // Hidden devices can't be told apart until they scan the code.
        devices = found.filter { !$0.name.isEmpty }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func send(to device: NearbyDevice, answering qrCode: QRCodeKey? = nil) {
        guard var outgoing, outgoing.state == .picking else { return }
        browser.stop()
        let link = FrameLink(NWConnection(to: device.endpoint, using: .tcp))
        outgoing.link = link
        outgoing.device = device
        outgoing.state = .connecting
        self.outgoing = outgoing
        let (id, urls, endpointID, me) = (outgoing.id, outgoing.files, endpointID, me)
        let (updates, input) = AsyncStream<OutboundSession.Update>.makeStream()
        Task.detached {
            do {
                let files = try urls.map(OutgoingFile.init)
                await OutboundSession(link: link, files: files, endpointID: endpointID, me: me, qrCode: qrCode) {
                    input.yield($0)
                }
                .run()
            } catch {
                input.yield(.failed(error as? QuickShareError ?? .files(error.localizedDescription)))
            }
            input.finish()
        }
        Task { [weak self] in
            for await update in updates { self?.apply(update, to: id) }
        }
    }

    private func apply(_ update: OutboundSession.Update, to id: UUID) {
        guard var outgoing, outgoing.id == id else { return }  // cancelled meanwhile
        let device = outgoing.device?.name ?? "the phone"
        switch update {
        case .connected(let pin):
            outgoing.pin = pin
            outgoing.state = .waiting
        case .accepted:
            outgoing.state = .sending(0)
        case .progress(let done):
            outgoing.state = .sending(done)
        case .sent:
            outgoing.state = .sent
            announce("checkmark.circle.fill", "Sent to \(device)")
        case .failed(let error):
            outgoing.state = .failed(Self.describe(error, device: device, sending: true))
            announce("exclamationmark.circle.fill", Self.describe(error, device: device, sending: true))
        }
        self.outgoing = outgoing
        updateOngoing()
    }

    /// The send window closed: stops looking, and stops a transfer that hasn't finished.
    func closeSending() {
        if outgoing?.isBusy == true { outgoing?.link?.post(.cancel) }
        outgoing = nil
        devices = []
        qrCode = nil
        browser.stop()
        updateOngoing()
    }

    private func showSendWindow() {
        let window = sendWindow ?? SendWindow(transfer: self)
        sendWindow = window
        window.show()
    }

    /// Everything off, when the app quits.
    public func stop() {
        cancelIncoming()
        closeSending()
        advertiser.stop()
        check?.cancel()
    }

    // MARK: The notch

    /// The resting notch shows a phone waiting for an answer first, then progress either way.
    private func updateOngoing() {
        var activity: Activity?
        if let incoming, let offer = incoming.offer, incoming.text == nil {
            activity =
                if let progress = incoming.progress {
                    Activity(
                        feature: .shelf, symbol: "arrow.down.circle.fill", title: percent(progress), duration: .zero)
                } else {
                    Activity(feature: .shelf, symbol: offer.kind.symbol, title: offer.device, duration: .zero)
                }
        } else if case .sending(let done)? = outgoing?.state {
            activity = Activity(feature: .shelf, symbol: "arrow.up.circle.fill", title: percent(done), duration: .zero)
        }
        guard activity != shownOngoing else { return }
        shownOngoing = activity
        onOngoing?(activity)
    }

    /// Puts states on screen directly, for snapshot tests.
    func show(incoming: Incoming?, outgoing: Outgoing? = nil, devices: [NearbyDevice] = [], visibleUntil: Date? = nil) {
        self.incoming = incoming
        self.outgoing = outgoing
        self.devices = devices
        self.visibleUntil = visibleUntil
        qrCode = outgoing == nil ? nil : QRCodeKey()
    }

    private func announce(_ symbol: String, _ title: String) {
        onActivity?(Activity(feature: .shelf, symbol: symbol, title: title, duration: .seconds(3)))
    }

    /// Why a transfer didn't finish, short enough for the notch.
    static func describe(_ error: QuickShareError, device: String, sending: Bool) -> String {
        switch error {
        case .declined: "\(device) declined"
        case .cancelled: "Cancelled on \(device)"
        case .noAnswer: sending ? "\(device) didn't answer" : "Missed a share from \(device)"
        case .noSpace: sending ? "\(device) is out of space" : "Not enough space on this Mac"
        case .unsupported: sending ? "\(device) can't take these files" : "\(device) sent something a Mac can't take"
        case .unreachable: "Couldn't reach \(device)"
        case .localNetworkDenied: "Local network access is off"
        case .lost: "Lost the connection to \(device)"
        case .insecure: "Couldn't connect securely to \(device)"
        case .malformed: "\(device) sent something unexpected"
        case .files(let reason): reason
        }
    }

    private enum Key {
        static let mode = "transfer.receiveMode"
        static let name = "transfer.deviceName"
        static let folder = "transfer.folder"
        static let addsToShelf = "transfer.addsToShelf"
    }
}

/// The share a phone is offering or sending.
struct Incoming {
    let id: UUID
    let link: FrameLink
    /// What it's offering, once the handshake is done.
    var offer: InboundSession.Offer?
    /// Set once accepted, 0...1.
    var progress: Double?
    /// Text or a link, copied to the clipboard.
    var text: ReceivedText?

    var device: String { offer?.device ?? "Android phone" }
}

struct ReceivedText: Equatable {
    var text: String
    var kind: TextKind

    /// A web link the user can open.
    var isLink: Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return ["http", "https"].contains(url.scheme?.lowercased())
    }
}

/// The send window's transfer.
struct Outgoing {
    enum State: Equatable {
        case picking, connecting, waiting
        case sending(Double)
        case sent
        case failed(String)
    }

    let id = UUID()
    var files: [URL]
    var state = State.picking
    var device: NearbyDevice?
    var link: FrameLink?
    var pin: String?

    /// Connected or connecting to a device and not done yet.
    var isBusy: Bool {
        switch state {
        case .connecting, .waiting, .sending: true
        default: false
        }
    }
}

extension EndpointInfo.Kind {
    var symbol: String {
        switch self {
        case .tablet: "ipad.landscape"
        case .laptop: "laptopcomputer"
        case .car: "car.fill"
        case .headset: "visionpro"
        case .unknown, .phone, .foldable: "smartphone"
        }
    }
}

private func percent(_ done: Double) -> String { "\(Int((done * 100).rounded(.down)))%" }
