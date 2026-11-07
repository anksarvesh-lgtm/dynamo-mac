// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import NotchCore
import os

/// Sends files to a phone: connects, agrees on keys, describes the files, waits for the phone's
/// answer, then streams each file in 512 KB chunks, reading the next chunk only once the last has
/// gone out, so memory stays flat whatever the size. Like Android, it counts the files as sent
/// once the phone hangs up, which it does after saving them.
final class OutboundSession {
    enum Update: Sendable {
        case connected(pin: String)
        case accepted
        case progress(Double)
        case sent
        case failed(QuickShareError)
    }

    static let chunkSize = 512 * 1024

    private enum Stage {
        case connecting, serverInit, connectionResponse, pairing, waiting, sending, finishing, done
    }

    private let link: FrameLink
    private let files: [OutgoingFile]
    private let endpointID: String
    private let me: EndpointInfo
    private let qrCode: QRCodeKey?
    private let timing: Timing
    private let report: @Sendable (Update) -> Void

    private var stage = Stage.connecting
    private let handshake = Handshake()
    private var clientInit = Data()
    private var clientFinished = Data()
    private var secure: SecureLink?
    private var index = 0
    private let total: Int64
    private var sentBytes: Int64 = 0
    private var reportedPercent = -1
    private var deadline = 0
    private var lastHeard = Date.now

    /// `qrCode` is the code the phone scanned to find this Mac, if it did.
    init(
        link: FrameLink, files: [OutgoingFile], endpointID: String, me: EndpointInfo, qrCode: QRCodeKey?,
        timing: Timing = Timing(), report: @escaping @Sendable (Update) -> Void
    ) {
        self.link = link
        self.files = files
        self.endpointID = endpointID
        self.me = me
        self.qrCode = qrCode
        self.timing = timing
        self.report = report
        total = files.reduce(0) { $0 + $1.offer.size }
    }

    func run() async {
        link.start()
        advance(to: .connecting, within: timing.handshake)
        for await event in link.events {
            do {
                try handle(event)
            } catch {
                end(error as? QuickShareError ?? .malformed)
            }
            if stage == .done { break }
        }
        link.close()
    }

    private func handle(_ event: LinkEvent) throws {
        switch event {
        case .ready where stage == .connecting:
            // Say who this is, then open the handshake by committing to the key this Mac will send.
            link.send(
                OfflineFrame.connectionRequest(endpointID: endpointID, name: me.name ?? "", info: me.encoded).encoded)
            clientFinished = Ukey2.message(.clientFinish, Ukey2.clientFinished(publicKey: handshake.publicKey))
            let commitment = Data(SHA512.hash(data: clientFinished))
            clientInit = Ukey2.message(
                .clientInit, Ukey2.ClientInit(random: randomData(32), commitment: commitment).encoded)
            link.send(clientInit)
            link.receive()
            advance(to: .serverInit, within: timing.handshake)
        case .frame(let data):
            lastHeard = .now
            try handle(frame: data)
            if stage != .done { link.receive() }
        case .sent where stage == .sending:
            lastHeard = .now
            try sendNextChunk()
        case .cancel:
            try? secure?.send(.cancel)
            try? secure?.send(.disconnection)
            stage = .done
        case .closed:
            guard stage == .finishing else { throw stage == .connecting ? QuickShareError.unreachable : .cancelled }
            succeed()
        case .failed(let error):
            throw stage == .connecting && error == .lost ? QuickShareError.unreachable : error
        case .deadline(let number) where number == deadline:
            let quiet = Date.now.timeIntervalSince(lastHeard)
            switch stage {
            case .finishing:
                succeed()  // everything went out, and the phone has had its minute to hang up
            case .sending where quiet < timing.stall:
                arm(timing.stall - quiet)
            case .connecting:
                throw QuickShareError.unreachable
            case .waiting:
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
        case .serverInit:
            let serverInit = try Ukey2.ServerInit(Ukey2.open(data, expecting: .serverInit))
            guard serverInit.version == Ukey2.version, serverInit.random.count == 32,
                serverInit.cipher == Ukey2.p256SHA512
            else { throw QuickShareError.insecure }
            let peer = try Handshake.peerKey(serverInit.publicKey)
            let keys = try handshake.keys(peer: peer, clientInit: clientInit, serverInit: data, isServer: false)
            link.send(clientFinished)
            link.send(OfflineFrame.connectionResponse(accepted: true).encoded)
            secure = SecureLink(link: link, keys: keys)
            advance(to: .connectionResponse, within: timing.handshake)
            report(.connected(pin: keys.pin))
        case .connectionResponse:
            guard case .connectionResponse(accepted: true) = try OfflineFrame(data), let secure else {
                throw QuickShareError.declined
            }
            // Proves to a phone that scanned this Mac's code that it's talking to the Mac it scanned.
            try secure.send(.pairedKeyEncryption(qrSignature: qrCode?.sign(secure.keys.authString)))
            advance(to: .pairing, within: timing.handshake)
        case .pairing, .waiting, .sending, .finishing:
            guard let secure else { throw QuickShareError.malformed }
            switch try secure.receive(data) {
            case .share(let frame): try handle(frame)
            case .disconnected where stage == .finishing: succeed()
            case .disconnected: throw QuickShareError.cancelled
            default: break
            }
        case .connecting, .done:
            break
        }
    }

    private func handle(_ frame: ShareFrame) throws {
        switch (stage, frame) {
        case (_, .cancel):
            throw QuickShareError.cancelled
        case (.pairing, .pairedKeyEncryption):
            try secure?.send(.pairedKeyResult)
        case (.pairing, .pairedKeyResult):
            try secure?.send(.introduction(Introduction(files: files.map(\.offer))))
            advance(to: .waiting, within: timing.answer)
        case (.waiting, .response(let status)):
            switch status {
            case .accept:
                advance(to: .sending, within: timing.stall)
                report(.accepted)
                try sendNextChunk()
            case .notEnoughSpace: throw QuickShareError.noSpace
            case .unsupportedAttachmentType: throw QuickShareError.unsupported
            case .timedOut: throw QuickShareError.noAnswer
            case .reject, .unknown: throw QuickShareError.declined
            }
        default:
            break
        }
    }

    /// One chunk, then the next when this one has gone out; each file ends with an empty chunk
    /// flagged last.
    private func sendNextChunk() throws {
        guard let secure else { return }
        guard index < files.count else {
            advance(to: .finishing, within: timing.finish)
            return
        }
        let file = files[index]
        let offset = file.sent
        let body = try file.read(upTo: Self.chunkSize)
        let chunk = PayloadFrame(
            id: file.offer.payloadID, isFile: true, totalSize: file.offer.size, offset: offset, body: body,
            isLast: body.isEmpty)
        try secure.send(.payload(chunk), then: .sent)
        if body.isEmpty { index += 1 }
        sentBytes += Int64(body.count)
        let percent = total > 0 ? Int(sentBytes * 100 / total) : 100
        if percent != reportedPercent {
            reportedPercent = percent
            report(.progress(total > 0 ? Double(sentBytes) / Double(total) : 1))
        }
    }

    private func succeed() {
        stage = .done
        report(.sent)
    }

    private func advance(to stage: Stage, within seconds: TimeInterval) {
        self.stage = stage
        arm(seconds)
        Log.transfer.debug("Sending: \(String(describing: stage), privacy: .public)")
    }

    private func arm(_ seconds: TimeInterval) {
        deadline += 1
        link.post(.deadline(deadline), after: seconds)
    }

    private func end(_ error: QuickShareError) {
        let at = String(describing: stage)
        Log.transfer.error("Sending stopped at \(at, privacy: .public): \(error.logName, privacy: .public)")
        if [.waiting, .sending].contains(stage), error != .cancelled, error != .lost { try? secure?.send(.cancel) }
        try? secure?.send(.disconnection)
        stage = .done
        report(.failed(error))
    }
}
