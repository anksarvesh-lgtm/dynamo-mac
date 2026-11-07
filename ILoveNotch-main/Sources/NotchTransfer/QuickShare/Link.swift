// SPDX-License-Identifier: MIT
import Foundation
import Network
import os

/// Why a transfer stopped before it finished.
enum QuickShareError: Error, Equatable, Sendable {
    /// The other side said no.
    case declined
    /// The other side cancelled, or hung up partway.
    case cancelled
    /// The other side didn't answer in time.
    case noAnswer
    /// The receiving device is out of space.
    case noSpace
    /// Something Quick Share can share that a Mac can't take, such as a Wi-Fi network or an app.
    case unsupported
    /// The phone couldn't be reached.
    case unreachable
    /// macOS doesn't let ILoveNotch use the local network.
    case localNetworkDenied
    /// The connection dropped or stalled.
    case lost
    /// A handshake or a message's signature didn't check out.
    case insecure
    /// The other side sent something that doesn't fit the protocol.
    case malformed
    /// Reading or writing a file failed.
    case files(String)

    init(_ error: NWError) {
        switch error {
        case .dns(let code) where code == -65570: self = .localNetworkDenied  // kDNSServiceErr_PolicyDenied
        default: self = .lost
        }
    }

    /// The reason alone, for the log, which never gets a file's name.
    var logName: String {
        if case .files = self { return "files" }
        return String(describing: self)
    }
}

/// What moves a session along, one at a time and in the order it happened.
enum LinkEvent: Sendable {
    /// Connected, for a connection this Mac opened.
    case ready
    case frame(Data)
    /// The send that asked for this event has been handed to the network.
    case sent
    /// The other side hung up.
    case closed
    case failed(QuickShareError)
    /// The user's answers.
    case accept, decline, cancel
    /// A stage's time ran out; the number says which one, so a stage that already ended is ignored.
    case deadline(Int)
}

/// One TCP connection carrying Quick Share's frames, each a big-endian 32-bit length and that many
/// bytes. It reads a frame only when the session asks, after handling the one before, so a sender
/// faster than the disk can't pile frames up in memory.
final class FrameLink: Sendable {
    /// No Quick Share frame comes near this; file chunks are 512 KB.
    static let maxFrame = 5 * 1024 * 1024

    let events: AsyncStream<LinkEvent>
    private let input: AsyncStream<LinkEvent>.Continuation
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "cafe.opennotch.quickshare", qos: .userInitiated)
    /// Bytes handed to the network and not yet sent, and the most there have been at once.
    private let unsent = OSAllocatedUnfairLock(initialState: (now: 0, peak: 0))

    /// A sender that waits for each chunk to go out keeps this near one chunk, whatever the size of
    /// the file, which is what keeps memory flat.
    var peakUnsent: Int { unsent.withLock { $0.peak } }

    init(_ connection: NWConnection) {
        self.connection = connection
        (events, input) = AsyncStream.makeStream()
    }

    func start() {
        connection.stateUpdateHandler = { [input] state in
            switch state {
            case .ready: input.yield(.ready)
            // Waiting means it can't connect for now; a transfer doesn't wait for the network to come back.
            case .waiting(let error), .failed(let error): input.yield(.failed(QuickShareError(error)))
            default: break
            }
        }
        connection.start(queue: queue)
    }

    /// Reads the next frame.
    func receive() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [self] header, _, _, error in
            guard let header, header.count == 4 else {
                input.yield(ended(error))
                return
            }
            let length = header.reduce(0) { $0 << 8 | Int($1) }
            if length > Self.maxFrame {
                input.yield(.failed(.malformed))
            } else if length == 0 {
                input.yield(.frame(Data()))
            } else {
                connection.receive(minimumIncompleteLength: length, maximumLength: length) { [self] body, _, _, error in
                    input.yield(body?.count == length ? .frame(body ?? Data()) : ended(error))
                }
            }
        }
    }

    /// Sends one frame; `then` arrives once it's handed to the network, which is how a sender
    /// keeps a single file chunk in flight.
    func send(_ frame: Data, then event: LinkEvent? = nil) {
        var bytes = Data(capacity: 4 + frame.count)
        withUnsafeBytes(of: UInt32(frame.count).bigEndian) { bytes.append(contentsOf: $0) }
        bytes.append(frame)
        let count = bytes.count
        unsent.withLock {
            $0.now += count
            $0.peak = max($0.peak, $0.now)
        }
        connection.send(
            content: bytes,
            completion: .contentProcessed { [input, unsent] error in
                unsent.withLock { $0.now -= count }
                if let error {
                    input.yield(.failed(QuickShareError(error)))
                } else if let event {
                    input.yield(event)
                }
            })
    }

    /// The user's answers, from the notch.
    func post(_ event: LinkEvent) { input.yield(event) }

    func post(_ event: LinkEvent, after seconds: TimeInterval) {
        queue.asyncAfter(deadline: .now() + seconds) { [input] in input.yield(event) }
    }

    /// Hangs up once the other side has too, or after a few seconds if it doesn't. Hanging up with
    /// its bytes still unread resets the connection, and the reset can throw away the frames just
    /// sent: a sender still mid-file then heard a cancel as a lost connection.
    func close() {
        input.finish()
        queue.async { [connection, queue] in
            guard case .ready = connection.state else { return connection.cancel() }
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .idempotent)
            Self.drain(connection)
            queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
        }
    }

    /// Reads and drops whatever the other side still sends, until it hangs up.
    private static func drain(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { _, _, isComplete, error in
            if isComplete || error != nil { connection.cancel() } else { drain(connection) }
        }
    }

    private func ended(_ error: NWError?) -> LinkEvent { error.map { .failed(QuickShareError($0)) } ?? .closed }
}
