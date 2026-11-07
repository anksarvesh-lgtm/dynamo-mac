// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import NotchCore
import os

/// Receives one share from a phone, start to finish. The phone connects and both sides agree on
/// keys; the phone says what it's sending; the user accepts or declines in the notch; accepted
/// files stream to disk as their chunks arrive, never whole in memory. A file takes its name in
/// the folder only once all of it has arrived, and anything unfinished is deleted.
final class InboundSession {
    struct Offer: Equatable, Sendable {
        var device: String
        var kind: EndpointInfo.Kind
        var pin: String
        var files: [FileOffer]
        var text: TextOffer?
        var size: Int64
    }

    enum Update: Sendable {
        case asking(Offer)
        case progress(Double)
        case files([URL])
        case text(String, TextKind)
        case failed(QuickShareError)
    }

    private enum Stage {
        case request, clientInit, clientFinish, connectionResponse, pairing, asking, receiving, done
    }

    private let link: FrameLink
    private let folder: URL
    private let timing: Timing
    private let report: @Sendable (Update) -> Void

    private var stage = Stage.request
    private let handshake = Handshake()
    private var clientInit = Data()
    private var serverInit = Data()
    private var commitment = Data()
    private var secure: SecureLink?
    private var device = "Android device"
    private var kind = EndpointInfo.Kind.phone
    private var offer: Offer?

    private var temporary: URL?
    private var writing: [Int64: IncomingFile] = [:]
    private var finished: Set<Int64> = []
    private var saved: [URL] = []
    private var received: Int64 = 0
    private var reportedPercent = -1
    private var deadline = 0
    private var lastHeard = Date.now

    init(link: FrameLink, folder: URL, timing: Timing = Timing(), report: @escaping @Sendable (Update) -> Void) {
        self.link = link
        self.folder = folder
        self.timing = timing
        self.report = report
    }

    func run() async {
        link.start()
        link.receive()
        advance(to: .request, within: timing.handshake)
        for await event in link.events {
            do {
                try handle(event)
            } catch {
                end(error as? QuickShareError ?? .malformed)
            }
            if stage == .done { break }
        }
        writing = [:]
        if let temporary { try? FileManager.default.removeItem(at: temporary) }  // and anything half-written in it
        link.close()
    }

    private func handle(_ event: LinkEvent) throws {
        switch event {
        case .frame(let data):
            lastHeard = .now
            try handle(frame: data)
            if stage != .done { link.receive() }
        case .accept where stage == .asking:
            try accept()
        case .decline where stage == .asking:
            try secure?.send(.response(.reject))
            try secure?.send(.disconnection)
            stage = .done
        case .cancel:
            try? secure?.send(.cancel)
            try? secure?.send(.disconnection)
            stage = .done
        case .closed:
            throw QuickShareError.cancelled  // the phone hung up before the end
        case .failed(let error):
            throw error
        case .deadline(let number) where number == deadline:
            let quiet = Date.now.timeIntervalSince(lastHeard)
            switch stage {
            case .receiving where quiet < timing.stall:
                arm(timing.stall - quiet)
            case .asking:
                try? secure?.send(.response(.timedOut))
                throw QuickShareError.noAnswer
            default:
                throw QuickShareError.lost
            }
        default:
            break
        }
    }

    private func handle(frame data: Data) throws {
        switch stage {
        case .request:
            guard case .connectionRequest(_, _, let info) = try OfflineFrame(data) else {
                throw QuickShareError.malformed
            }
            let endpoint = EndpointInfo(info)
            kind = endpoint?.kind ?? .phone
            device = endpoint?.name ?? (kind == .tablet ? "Android tablet" : "Android phone")
            advance(to: .clientInit, within: timing.handshake)
        case .clientInit:
            try answer(clientInit: data)
        case .clientFinish:
            try finishHandshake(data)
        case .connectionResponse:
            guard case .connectionResponse(accepted: true) = try OfflineFrame(data), let secure else {
                throw QuickShareError.cancelled
            }
            link.send(OfflineFrame.connectionResponse(accepted: true).encoded)
            try secure.send(.pairedKeyEncryption(qrSignature: nil))  // encrypted from here on
            advance(to: .pairing, within: timing.handshake)
        case .pairing, .asking, .receiving:
            guard let secure else { throw QuickShareError.malformed }
            switch try secure.receive(data) {
            case .share(let frame): try handle(frame)
            case .chunk(let chunk): try write(chunk)
            case .bytes(let text): finish(text: text)
            case .disconnected: throw QuickShareError.cancelled
            case .none: break
            }
        case .done:
            break
        }
    }

    // MARK: Handshake

    private func answer(clientInit data: Data) throws {
        guard let clientInit = try? Ukey2.ClientInit(Ukey2.open(data, expecting: .clientInit)) else { throw alert(4) }
        // Ukey2Alert's BAD_VERSION, BAD_RANDOM, BAD_HANDSHAKE_CIPHER, and BAD_NEXT_PROTOCOL.
        guard clientInit.version == Ukey2.version else { throw alert(100) }
        guard clientInit.random.count == 32 else { throw alert(101) }
        guard let commitment = clientInit.commitments[Ukey2.p256SHA512] else { throw alert(102) }
        guard clientInit.nextProtocol == Ukey2.nextProtocol else { throw alert(103) }
        self.clientInit = data
        self.commitment = commitment
        serverInit = Ukey2.message(
            .serverInit, Ukey2.ServerInit(random: randomData(32), publicKey: handshake.publicKey).encoded)
        link.send(serverInit)
        advance(to: .clientFinish, within: timing.handshake)
    }

    private func finishHandshake(_ data: Data) throws {
        // The phone committed to this exact message before it saw this Mac's key.
        guard Data(SHA512.hash(data: data)) == commitment else { throw QuickShareError.insecure }
        let peer = try Handshake.peerKey(Ukey2.publicKey(ofClientFinished: Ukey2.open(data, expecting: .clientFinish)))
        let keys = try handshake.keys(peer: peer, clientInit: clientInit, serverInit: serverInit, isServer: true)
        secure = SecureLink(link: link, keys: keys)
        advance(to: .connectionResponse, within: timing.handshake)
    }

    /// Tells the phone why the handshake stops, for its logs.
    private func alert(_ type: Int) -> QuickShareError {
        link.send(Ukey2.alert(type))
        return .insecure
    }

    // MARK: Sharing

    private func handle(_ frame: ShareFrame) throws {
        switch (stage, frame) {
        case (_, .cancel):
            throw QuickShareError.cancelled
        case (.pairing, .pairedKeyEncryption):
            try secure?.send(.pairedKeyResult)
        case (.pairing, .introduction(let introduction)):
            try ask(introduction)
        default:
            break  // the paired-key result has nothing to check without a Google account
        }
    }

    private func ask(_ introduction: Introduction) throws {
        let files = introduction.files
        let text = introduction.texts.first
        // Files, or a single piece of text. Anything else a phone can share, a Mac has no place for.
        guard !introduction.hasUnsupported, files.isEmpty != (text == nil), introduction.texts.count <= 1 else {
            try secure?.send(.response(.unsupportedAttachmentType))
            throw QuickShareError.unsupported
        }
        // No size beyond a terabyte, which also keeps the total from overflowing.
        let sizes = files.map(\.size) + [text?.size ?? 0]
        guard sizes.allSatisfy({ 0...(1 << 40) ~= $0 }), Set(files.map(\.payloadID)).count == files.count else {
            throw QuickShareError.malformed
        }
        let size = sizes.reduce(0, +)
        if let free = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, free < size
        {
            try secure?.send(.response(.notEnoughSpace))
            throw QuickShareError.noSpace
        }
        guard let secure else { throw QuickShareError.malformed }
        let offer = Offer(
            device: device, kind: kind, pin: secure.keys.pin, files: files, text: text, size: size)
        self.offer = offer
        advance(to: .asking, within: timing.answer)
        report(.asking(offer))
    }

    private func accept() throws {
        guard let secure, let offer else { return }
        secure.streamed = Set(offer.files.map(\.payloadID))
        secure.whole = Set([offer.text?.payloadID].compactMap { $0 })
        try secure.send(.response(.accept))
        advance(to: .receiving, within: timing.stall)
        report(.progress(0))
    }

    private func write(_ chunk: PayloadFrame) throws {
        guard stage == .receiving, !finished.contains(chunk.id),
            let file = offer?.files.first(where: { $0.payloadID == chunk.id })
        else { throw QuickShareError.malformed }
        if chunk.isCancelled { throw QuickShareError.cancelled }
        let writer = try writing[chunk.id] ?? IncomingFile(file, in: temporaryFolder())
        writing[chunk.id] = writer
        try writer.write(chunk)
        received += Int64(chunk.body.count)
        reportProgress()
        guard chunk.isLast else { return }
        writing[chunk.id] = nil
        finished.insert(chunk.id)
        saved.append(try writer.save(in: folder))
        if finished.count == offer?.files.count {
            try? secure?.send(.disconnection)
            stage = .done
            report(.files(saved))
        }
    }

    private func finish(text data: Data) {
        guard stage == .receiving, let text = offer?.text else { return }
        try? secure?.send(.disconnection)
        stage = .done
        report(.text(String(decoding: data, as: UTF8.self), text.kind))
    }

    /// Created on the destination's volume, so a finished file moves into place without a copy.
    private func temporaryFolder() throws -> URL {
        if let temporary { return temporary }
        do {
            let url = try FileManager.default.url(
                for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: folder, create: true)
            temporary = url
            return url
        } catch {
            throw QuickShareError.files(error.localizedDescription)
        }
    }

    private func reportProgress() {
        guard let size = offer?.size, size > 0 else { return }
        let percent = Int(received * 100 / size)
        guard percent != reportedPercent else { return }
        reportedPercent = percent
        report(.progress(Double(received) / Double(size)))
    }

    // MARK: Stages

    private func advance(to stage: Stage, within seconds: TimeInterval) {
        self.stage = stage
        arm(seconds)
        Log.transfer.debug("Receiving: \(String(describing: stage), privacy: .public)")
    }

    private func arm(_ seconds: TimeInterval) {
        deadline += 1
        link.post(.deadline(deadline), after: seconds)
    }

    /// Ends the session early. The notch hears about it once it's shown the request; before that
    /// the user never saw this phone.
    private func end(_ error: QuickShareError) {
        let at = String(describing: stage)
        Log.transfer.error("Receiving stopped at \(at, privacy: .public): \(error.logName, privacy: .public)")
        if stage == .receiving, error != .cancelled, error != .lost { try? secure?.send(.cancel) }
        try? secure?.send(.disconnection)
        if stage == .asking || stage == .receiving { report(.failed(error)) }
        stage = .done
    }
}
