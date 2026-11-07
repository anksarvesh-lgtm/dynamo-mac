// SPDX-License-Identifier: MIT
import AppKit
import CoreImage.CIFilterBuiltins
import NotchFeatures
import SwiftUI

extension TransferFeature {
    /// The Shelf tab, with a phone's request, its transfer, or the text it sent in place of the
    /// shelf while there is one.
    public func shelfView(_ shelf: AnyView) -> some View { TransferShelf(transfer: self, shelf: shelf) }

    /// Receiving from Android, for the shelf's footer.
    public var receiveControl: some View { ReceiveControl(transfer: self) }

    /// Settings › Shelf: receiving from Android.
    public var settingsView: some View { TransferSettings(transfer: self) }
}

private struct TransferShelf: View {
    let transfer: TransferFeature
    let shelf: AnyView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let incoming = transfer.incoming, incoming.offer != nil {
                IncomingCard(transfer: transfer, incoming: incoming)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                shelf.transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85), value: transfer.incoming?.id)
    }
}

// MARK: - In the notch

/// A phone asking to send, then its progress, or the text it sent. The smallest notch gets a
/// denser card, with its buttons moved up beside the details.
private struct IncomingCard: View {
    let transfer: TransferFeature
    let incoming: Incoming

    var body: some View {
        ViewThatFits(in: .vertical) {
            card(compact: false)
            card(compact: true)
        }
        .frame(maxHeight: .infinity)
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
    }

    private func card(compact: Bool) -> some View {
        VStack(spacing: 12) {
            if let text = incoming.text {
                received(text, compact: compact)
            } else if let offer = incoming.offer {
                if let progress = incoming.progress {
                    receiving(offer, progress: progress)
                } else {
                    request(offer, compact: compact)
                }
            }
        }
        .padding(compact ? 10 : 14)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func request(_ offer: InboundSession.Offer, compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 12) {
            HStack(spacing: 12) {
                DeviceBadge(symbol: offer.kind.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.device).font(.headline).lineLimit(1)
                    Text("wants to send \(offer.what)").font(.callout).foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("CODE").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.45))
                    Text(offer.pin).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                        .kerning(1.5)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Code \(offer.pin.map(String.init).joined(separator: " "))")
                .help("The same code shows on the phone")
            }
            // Middle-truncated, so the last name and the size stay in view.
            let detail = Text(offer.detail ?? "").font(.caption).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                .truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            if !compact, offer.detail != nil { detail }
            HStack(spacing: 8) {
                if compact { detail } else { Spacer() }
                CapsuleButton("Decline", prominent: false, action: transfer.declineIncoming)
                CapsuleButton("Accept", prominent: true, action: transfer.acceptIncoming)
            }
        }
    }

    private func receiving(_ offer: InboundSession.Offer, progress: Double) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                DeviceBadge(symbol: offer.kind.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receiving from \(offer.device)").font(.headline).lineLimit(1)
                    Text("\(offer.what.capitalizedFirst) · \(Int(progress * 100))%").font(.callout).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
                Spacer(minLength: 8)
                CapsuleButton("Cancel", prominent: false, action: transfer.cancelIncoming)
            }
            ProgressView(value: progress).progressViewStyle(.linear).tint(.white)
                .accessibilityLabel("Receiving")
        }
    }

    private func received(_ text: ReceivedText, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(spacing: 12) {
                DeviceBadge(symbol: text.isLink ? "link" : "text.alignleft")
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(incoming.device) sent \(text.isLink ? "a link" : "text")").font(.headline).lineLimit(1)
                    Label("Copied to the clipboard", systemImage: "checkmark").font(.callout)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
            }
            let sent = Text(text.text).font(.callout).lineLimit(compact ? 1 : 3).truncationMode(.middle)
                .textSelection(.enabled).foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            if !compact { sent }
            HStack(spacing: 8) {
                if compact { sent } else { Spacer() }
                CapsuleButton("Done", prominent: !text.isLink, action: transfer.dismissText)
                if text.isLink { CapsuleButton("Open", prominent: true, action: transfer.openLink) }
            }
        }
    }
}

/// The device's symbol on a soft disc, as the notch's other cards show their subject.
private struct DeviceBadge: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 38, height: 38)
            .background(.white.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

/// The notch's buttons: a light capsule, filled with the accent color for the main action.
private struct CapsuleButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void

    init(_ title: String, prominent: Bool, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(prominent ? Color.accentColor : .white.opacity(0.14), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// In the shelf's footer: receive for 10 minutes, how long is left, or that the Mac is visible.
private struct ReceiveControl: View {
    let transfer: TransferFeature

    var body: some View {
        Group {
            if transfer.localNetworkDenied {
                Button {
                    NSWorkspace.shared.open(.privacySettings("Privacy_LocalNetwork"))
                } label: {
                    Label("Allow Local Network", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .help("macOS stops ILoveNotch from finding phones until Local Network is on for it")
            } else if let until = transfer.visibleUntil {
                Button(action: transfer.stopReceiving) {
                    Label {
                        let left = Text(timerInterval: .now...max(until, .now), countsDown: true).monospacedDigit()
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 4) {
                                Text("Visible for")
                                left
                            }
                            left
                        }
                    } icon: {
                        Image(systemName: "dot.radiowaves.left.and.right")
                    }
                }
                .help("Android phones on this Wi-Fi can find this Mac. Click to stop.")
                .accessibilityLabel("Visible to Android. Stop")
            } else if transfer.isVisible {
                Label("Visible", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.white.opacity(0.6))
                    .help("Android phones on this Wi-Fi can send files to this Mac with Quick Share")
            } else {
                Button(action: transfer.receiveForTenMinutes) {
                    Label {
                        ViewThatFits(in: .horizontal) {
                            Text("Receive from Android")
                            Text("Receive")
                        }
                    } icon: {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .help("Let Android phones on this Wi-Fi find this Mac for 10 minutes")
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.plain)
        .lineLimit(1)
    }
}

// MARK: - The send window

/// "Send to Android" opens its own window, as AirDrop does, so it stays up while the notch
/// closes and the user reaches for the phone to scan the code.
@MainActor
final class SendWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private weak var transfer: TransferFeature?

    init(transfer: TransferFeature) {
        self.transfer = transfer
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 480), styleMask: [.titled, .closable],
            backing: .buffered, defer: true)
        super.init()
        window.title = "Send to Android"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: SendView(transfer: transfer) { [weak self] in self?.window.close() })
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        transfer?.closeSending()
    }
}

struct SendView: View {
    let transfer: TransferFeature
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let outgoing = transfer.outgoing {
                FilesSummary(files: outgoing.files)
                if outgoing.state == .picking {
                    picker
                } else {
                    status(outgoing)
                }
            }
        }
        .padding(20)
        .frame(width: 400, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Picking a device

    private var picker: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nearby").font(.headline)
                if transfer.localNetworkDenied {
                    localNetworkNotice
                } else if transfer.devices.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking for phones on this Wi-Fi…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                } else {
                    VStack(spacing: 2) {
                        ForEach(transfer.devices) { device in
                            DeviceRow(device: device) { transfer.send(to: device) }
                        }
                    }
                }
            }
            Divider()
            HStack(alignment: .top, spacing: 16) {
                if let url = transfer.qrCode?.url, let code = QRCodeImage.make(url) {
                    Image(nsImage: code)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 128, height: 128)
                        .padding(8)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityLabel("QR code for Quick Share")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Phone not listed?").font(.headline)
                    Text("Scan this code with its camera. Quick Share opens, and the files go straight to it.")
                        .foregroundStyle(.secondary)
                    Text("Keep both on the same Wi-Fi.").font(.caption).foregroundStyle(.tertiary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
            }
        }
    }

    private var localNetworkNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Local network access is off for ILoveNotch", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Quick Share finds phones on your Wi-Fi, which macOS asks you to allow.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Open Privacy Settings") { NSWorkspace.shared.open(.privacySettings("Privacy_LocalNetwork")) }
        }
    }

    // MARK: Sending

    private func status(_ outgoing: Outgoing) -> some View {
        let name = outgoing.device?.name ?? "Android device"
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: outgoing.device?.kind.symbol ?? "smartphone")
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(.quaternary, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.title3.weight(.semibold)).lineLimit(1)
                    Text(detail(outgoing, name: name)).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 0)
                if let pin = outgoing.pin, outgoing.isBusy {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("CODE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text(pin).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                            .kerning(1.5)
                    }
                    .help("Check it matches the code on the phone")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Code \(pin.map(String.init).joined(separator: " "))")
                }
            }
            switch outgoing.state {
            case .sending(let done):
                ProgressView(value: done).accessibilityLabel("Sending")
            case .connecting, .waiting:
                ProgressView().progressViewStyle(.linear)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .sent:
                Label("Sent", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .picking:
                EmptyView()
            }
            HStack {
                Spacer()
                switch outgoing.state {
                case .failed:
                    Button("Try Again", action: transfer.tryAgain)
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                case .sent:
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                default:
                    Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                }
            }
        }
    }

    private func detail(_ outgoing: Outgoing, name: String) -> String {
        switch outgoing.state {
        case .connecting: "Connecting…"
        case .waiting: "Waiting for it to be accepted…"
        case .sending(let done): "Sending… \(Int(done * 100))%"
        case .sent: "Sent"
        case .failed: "Not sent"
        case .picking: ""
        }
    }
}

/// The files going, with the first one's icon.
private struct FilesSummary: View {
    let files: [URL]

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: files[0].path))
                .resizable()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                let first = files[0].lastPathComponent
                Text(files.count == 1 ? first : "\(first) and \(files.count - 1) more")
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).foregroundStyle(.secondary)
            }
        }
    }

    private var size: Int64 {
        files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

private struct DeviceRow: View {
    let device: NearbyDevice
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: device.kind.symbol).font(.system(size: 16)).frame(width: 24)
                Text(device.name).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(hovering ? 1 : 0), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Send to \(device.name)")
    }
}

/// Quick Share's QR code, drawn with Core Image's own generator.
private enum QRCodeImage {
    static func make(_ url: URL) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return nil }
        let representation = NSCIImageRep(ciImage: code)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

// MARK: - Settings

private struct TransferSettings: View {
    @Bindable var transfer: TransferFeature

    var body: some View {
        Group {
            Picker(selection: $transfer.receiveMode) {
                ForEach(TransferFeature.ReceiveMode.allCases) { Text($0.title).tag($0) }
            } label: {
                Text("Receive from Android")
                Text(
                    "Phones on the same Wi-Fi can send you files with Quick Share, set to Everyone. Nothing is saved until "
                        + "you accept in the notch.")
            }
            if transfer.receiveMode != .always {
                LabeledContent {
                    if let until = transfer.visibleUntil {
                        HStack {
                            Text(timerInterval: .now...max(until, .now), countsDown: true).monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button("Stop", action: transfer.stopReceiving)
                        }
                    } else {
                        Button("Be Visible", action: transfer.receiveForTenMinutes)
                    }
                } label: {
                    Text("Visible for 10 minutes")
                    Text("Also from Receive in the shelf.")
                }
            }
            TextField("Name on Android", text: $transfer.deviceName, prompt: Text(TransferFeature.computerName))
            LabeledContent {
                HStack {
                    Button("Choose\u{2026}", action: chooseFolder)
                    if transfer.folder != nil { Button("Use Downloads") { transfer.chooseFolder(nil) } }
                }
            } label: {
                Text("Save received files to")
                Text(transfer.saveFolder.lastPathComponent)
            }
            Toggle("Add received files to the shelf", isOn: $transfer.addsToShelf)
            if transfer.localNetworkDenied {
                LabeledContent("Local network access is off") {
                    Button("Open Privacy Settings") {
                        NSWorkspace.shared.open(.privacySettings("Privacy_LocalNetwork"))
                    }
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose where files from Android go."
        panel.directoryURL = transfer.saveFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        transfer.chooseFolder(url)
    }
}

extension InboundSession.Offer {
    /// "a photo", "3 photos", "2 files", "a link", or "text".
    var what: String {
        if let text { return text.kind == .url ? "a link" : "text" }
        let (one, many) =
            switch Set(files.map { $0.mimeType.prefix { $0 != "/" } }) {
            case ["image"]: ("a photo", "photos")
            case ["video"]: ("a video", "videos")
            default: ("a file", "files")
            }
        return files.count == 1 ? one : "\(files.count) \(many)"
    }

    /// The names and the size ("IMG_2041.jpg and IMG_2042.jpg · 6.8 MB"), or a link's title.
    var detail: String? {
        if let text { return text.title.isEmpty ? nil : text.title }
        let size = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        return "\(files.map(\.name).formatted(.list(type: .and))) · \(size)"
    }
}

extension String {
    /// "3 photos" stays, "a photo" becomes "A photo".
    fileprivate var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
