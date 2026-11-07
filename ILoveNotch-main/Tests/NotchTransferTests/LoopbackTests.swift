// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Network
import Testing

@testable import NotchTransfer

/// This Mac sending to itself over TCP on the loopback interface: the real sessions end to end,
/// with no Bonjour, no firewall prompt, and no local network permission involved.
private final class Loopback: Sendable {
    let folder: URL
    let destination: URL
    private let listener: NWListener
    private let inbound: AsyncStream<InboundSession.Update>
    private let inboundInput: AsyncStream<InboundSession.Update>.Continuation

    /// `answer` is what the receiver's user does when asked, and `cancelAt` how far along they
    /// cancel, if they do.
    init(answer: LinkEvent = .accept, cancelAt: Double? = nil, timing: Timing = Timing()) async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "Loopback-\(UUID().uuidString)")
        destination = folder.appending(path: "Received")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        (inbound, inboundInput) = AsyncStream.makeStream()
        listener.newConnectionHandler = { [destination, inboundInput] connection in
            let link = FrameLink(connection)
            Task.detached {
                await InboundSession(link: link, folder: destination, timing: timing) { update in
                    if case .asking = update { link.post(answer) }
                    if case .progress(let done) = update, let cancelAt, done >= cancelAt { link.post(.cancel) }
                    inboundInput.yield(update)
                }
                .run()
                inboundInput.finish()
            }
        }
        let (ready, readyInput) = AsyncStream<Void>.makeStream()
        listener.stateUpdateHandler = { if case .ready = $0 { readyInput.yield() } }
        listener.start(queue: DispatchQueue(label: "loopback"))
        for await _ in ready { break }
    }

    deinit {
        listener.cancel()
        try? FileManager.default.removeItem(at: folder)
    }

    func file(_ name: String, _ contents: Data) throws -> URL {
        let url = folder.appending(path: name)
        try contents.write(to: url)
        return url
    }

    func connection() -> NWConnection {
        NWConnection(to: .hostPort(host: .ipv4(.loopback), port: listener.port ?? .any), using: .tcp)
    }

    /// Sends `urls`, with the sender cancelling `cancelAt` of the way through if asked. Also returns
    /// the most bytes the sender had handed to the network and not yet sent.
    func send(_ urls: [URL], cancelAt: Double? = nil) async throws -> (
        sent: [OutboundSession.Update], received: [InboundSession.Update], peakUnsent: Int
    ) {
        let link = FrameLink(connection())
        let (outbound, outboundInput) = AsyncStream<OutboundSession.Update>.makeStream()
        let files = try urls.map(OutgoingFile.init)
        Task.detached {
            await OutboundSession(
                link: link, files: files, endpointID: "TEST", me: EndpointInfo(name: "Test Mac", kind: .laptop),
                qrCode: nil
            ) { update in
                if case .progress(let done) = update, let cancelAt, done >= cancelAt { link.post(.cancel) }
                outboundInput.yield(update)
            }
            .run()
            outboundInput.finish()
        }
        var sent: [OutboundSession.Update] = []
        for await update in outbound { sent.append(update) }
        var received: [InboundSession.Update] = []
        for await update in inbound { received.append(update) }
        return (sent, received, link.peakUnsent)
    }

    /// What's left in the folder the receiver saves to.
    func saved() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
    }
}

private func sha256(_ url: URL) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
    return Data(hash.finalize())
}

struct LoopbackTests {
    @Test func oneFileArrivesIntactAndBothSidesShowTheSameCode() async throws {
        let loopback = try await Loopback()
        let photo = try loopback.file("photo.jpg", randomData(300_000))
        let (sent, received, _) = try await loopback.send([photo])

        guard case .connected(let senderPin)? = sent.first, case .asking(let offer)? = received.first else {
            Issue.record("sent \(sent), received \(received)")
            return
        }
        #expect(senderPin == offer.pin)
        #expect(offer.device == "Test Mac")
        #expect(offer.kind == .laptop)
        #expect(offer.files.map(\.name) == ["photo.jpg"])
        guard case .sent? = sent.last, case .files(let urls)? = received.last else {
            Issue.record("sent \(sent), received \(received)")
            return
        }
        #expect(urls.map(\.lastPathComponent) == ["photo.jpg"])
        #expect(try Data(contentsOf: urls[0]) == Data(contentsOf: photo))
    }

    @Test func aHundredFilesArriveUnderTheirOwnNames() async throws {
        let loopback = try await Loopback()
        let files = try (0..<100).map { try loopback.file("file \($0).txt", Data("contents \($0)".utf8)) }
        let empty = try loopback.file("empty", Data())
        let (sent, received, _) = try await loopback.send(files + [empty])

        guard case .sent? = sent.last, case .files(let urls)? = received.last else {
            Issue.record("sent \(sent), received \(received)")
            return
        }
        #expect(urls.count == 101)
        #expect(try loopback.saved() == ((0..<100).map { "file \($0).txt" } + ["empty"]).sorted())
        for (index, url) in urls.dropLast().enumerated() {
            #expect(try String(contentsOf: url, encoding: .utf8) == "contents \(index)")
        }
    }

    /// Memory stays flat because the sender hands the network one chunk at a time and the receiver
    /// reads a frame at a time and writes it out. The process's own footprint is too noisy to check
    /// with other tests running alongside, so this checks the chunks in flight instead.
    @Test func aLargeFileStreamsThroughAChunkAtATime() async throws {
        let loopback = try await Loopback()
        let big = loopback.folder.appending(path: "video.mov")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let writer = try FileHandle(forWritingTo: big)
        for _ in 0..<200 { try writer.write(contentsOf: randomData(1 << 20)) }  // 200 MB, a megabyte at a time
        try writer.close()

        let (sent, received, peakUnsent) = try await loopback.send([big])
        guard case .sent? = sent.last, case .files(let urls)? = received.last else {
            Issue.record("sent \(sent.suffix(3)), received \(received.suffix(3))")
            return
        }
        #expect(try sha256(urls[0]) == sha256(big))
        #expect(peakUnsent < 2 * OutboundSession.chunkSize, "at most \(peakUnsent) bytes waiting to go out")
        let progress = received.compactMap { if case .progress(let done) = $0 { done } else { nil } }
        #expect(progress.count > 50, "progress along the way, one report per percent")
    }

    @Test func declining() async throws {
        let loopback = try await Loopback(answer: .decline)
        let (sent, received, _) = try await loopback.send([try loopback.file("a.txt", Data("a".utf8))])
        guard case .failed(let error)? = sent.last else {
            Issue.record("sent \(sent)")
            return
        }
        #expect(error == .declined)
        #expect(received.count == 1, "asked, and nothing after")
        #expect(try loopback.saved().isEmpty)
    }

    @Test func theSenderCancellingPartwayLeavesNoPartialFile() async throws {
        let loopback = try await Loopback()
        let big = try loopback.file("big.bin", randomData(8 << 20))
        let (_, received, _) = try await loopback.send([big], cancelAt: 0.3)
        guard case .failed(let error)? = received.last else {
            Issue.record("received \(received.suffix(3))")
            return
        }
        #expect(error == .cancelled)
        #expect(try loopback.saved().isEmpty)
    }

    @Test func theReceiverCancellingPartwayStopsTheSender() async throws {
        let loopback = try await Loopback(cancelAt: 0.3)
        let files = try (0..<3).map { try loopback.file("\($0).bin", randomData(4 << 20)) }
        let (sent, _, _) = try await loopback.send(files)
        guard case .failed(let error)? = sent.last else {
            Issue.record("sent \(sent.suffix(3))")
            return
        }
        #expect(error == .cancelled)
        #expect(try loopback.saved().isEmpty)
    }

    @Test func aHandshakeThatStallsIsDropped() async throws {
        let timing = Timing(handshake: 0.3, answer: 1, stall: 1, finish: 1)
        let loopback = try await Loopback(timing: timing)
        // A connection that says nothing at all.
        let silent = loopback.connection()
        silent.start(queue: .global())
        defer { silent.cancel() }
        let started = ContinuousClock.now
        let dropped = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            silent.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, isComplete, error in
                done.resume(returning: isComplete || error != nil)
            }
        }
        #expect(dropped)
        #expect(ContinuousClock.now - started < .seconds(5))
    }
}

struct FramingTests {
    /// A listener and one connection to it, both on the loopback interface.
    private func pair() async throws -> (server: FrameLink, client: NWConnection, listener: NWListener) {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        let (accepted, acceptedInput) = AsyncStream<NWConnection>.makeStream()
        listener.newConnectionHandler = { acceptedInput.yield($0) }
        let (ready, readyInput) = AsyncStream<Void>.makeStream()
        listener.stateUpdateHandler = { if case .ready = $0 { readyInput.yield() } }
        listener.start(queue: DispatchQueue(label: "framing"))
        for await _ in ready { break }
        let client = NWConnection(to: .hostPort(host: .ipv4(.loopback), port: listener.port ?? .any), using: .tcp)
        client.start(queue: DispatchQueue(label: "client"))
        var server: FrameLink?
        for await connection in accepted {
            server = FrameLink(connection)
            break
        }
        let link = try #require(server)
        link.start()
        return (link, client, listener)
    }

    @Test func aFrameSplitAcrossManyWritesArrivesWhole() async throws {
        let (server, client, listener) = try await pair()
        defer {
            listener.cancel()
            client.cancel()
        }
        let message = Data("a frame that trickles in a byte at a time".utf8)
        var wire = Data()
        withUnsafeBytes(of: UInt32(message.count).bigEndian) { wire.append(contentsOf: $0) }
        wire.append(message)
        for byte in wire {
            client.send(content: Data([byte]), completion: .contentProcessed { _ in })
            try await Task.sleep(for: .milliseconds(2))
        }
        server.receive()
        for await event in server.events {
            if case .frame(let data) = event {
                #expect(data == message)
                break
            }
        }
    }

    @Test func anOversizedFrameIsRefused() async throws {
        let (server, client, listener) = try await pair()
        defer {
            listener.cancel()
            client.cancel()
        }
        var wire = Data()
        withUnsafeBytes(of: UInt32(FrameLink.maxFrame + 1).bigEndian) { wire.append(contentsOf: $0) }
        client.send(content: wire, completion: .contentProcessed { _ in })
        server.receive()
        for await event in server.events {
            if case .failed(let error) = event {
                #expect(error == .malformed)
                break
            }
        }
    }
}
