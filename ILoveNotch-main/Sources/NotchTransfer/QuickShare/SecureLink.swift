// SPDX-License-Identifier: MIT
import Foundation
import NotchCore
import os

/// A connection once the handshake is done. Frames go through the secure channel, keep-alives
/// are answered, offers to move to a faster link (the phone's own hotspot or Wi-Fi Direct) are
/// declined so the transfer stays on the local network, and byte payloads are put back together.
final class SecureLink {
    enum Received {
        case none
        case share(ShareFrame)
        /// A finished byte payload the session asked to have whole: shared text.
        case bytes(Data)
        /// A piece of a payload the session writes as it arrives: a file.
        case chunk(PayloadFrame)
        /// The other side hung up.
        case disconnected
    }

    let keys: SessionKeys
    /// Payloads delivered piece by piece.
    var streamed: Set<Int64> = []
    /// Byte payloads delivered whole instead of read as Quick Share's messages.
    var whole: Set<Int64> = []
    private let link: FrameLink
    private let channel: SecureChannel
    private var buffers: [Int64: Data] = [:]

    init(link: FrameLink, keys: SessionKeys) {
        self.link = link
        self.keys = keys
        channel = SecureChannel(keys)
    }

    func send(_ frame: OfflineFrame, then event: LinkEvent? = nil) throws {
        link.send(try channel.seal(frame.encoded), then: event)
    }

    /// Quick Share's messages go as byte payloads: all of it in one chunk, then an empty last one,
    /// as Android sends them.
    func send(_ frame: ShareFrame) throws {
        let body = frame.encoded
        let id = Int64.random(in: .min ... .max)
        let size = Int64(body.count)
        try send(.payload(PayloadFrame(id: id, isFile: false, totalSize: size, offset: 0, body: body, isLast: false)))
        try send(
            .payload(PayloadFrame(id: id, isFile: false, totalSize: size, offset: size, body: Data(), isLast: true)))
    }

    func receive(_ data: Data) throws -> Received {
        switch try OfflineFrame(channel.open(data)) {
        case .keepAlive(ack: false, let sequence):
            try send(.keepAlive(ack: true, sequence: sequence))
        case .upgradePathAvailable(let info):
            Log.transfer.info("Declined an offer to move to another link; staying on the local network")
            try send(.upgradeFailure(pathInfo: info))
        case .disconnection:
            return .disconnected
        case .payload(let payload):
            return try assemble(payload)
        case .keepAlive, .connectionRequest, .connectionResponse, .upgradeFailure, .other:
            Log.transfer.debug("Ignored a frame this Mac doesn't use")
        }
        return .none
    }

    private func assemble(_ payload: PayloadFrame) throws -> Received {
        if streamed.contains(payload.id) { return .chunk(payload) }
        // A file nobody agreed to.
        guard !payload.isFile || whole.contains(payload.id) else { throw QuickShareError.malformed }
        if payload.isCancelled {
            buffers[payload.id] = nil
            return .none
        }
        var buffer = buffers.removeValue(forKey: payload.id) ?? Data()
        let held = buffers.values.reduce(0) { $0 + $1.count }
        guard payload.offset == buffer.count, held + buffer.count + payload.body.count <= FrameLink.maxFrame else {
            throw QuickShareError.malformed
        }
        buffer.append(payload.body)
        guard payload.isLast else {
            buffers[payload.id] = buffer
            return .none
        }
        return whole.contains(payload.id) ? .bytes(buffer) : .share(try ShareFrame(buffer))
    }
}

/// How long each stage may take: Quick Share's own limits, 15 seconds for each handshake frame
/// and 60 for the other side's answer and for hanging up after the last file, and 30 seconds of
/// silence while files move.
struct Timing: Sendable {
    var handshake: TimeInterval = 15
    var answer: TimeInterval = 60
    var stall: TimeInterval = 30
    var finish: TimeInterval = 60
}
