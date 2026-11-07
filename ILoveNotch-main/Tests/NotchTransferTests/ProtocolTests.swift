// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Testing

@testable import NotchTransfer

private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined(separator: " ") }

private func bytes(_ hex: String) -> Data {
    Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! })
}

struct ProtobufTests {
    @Test func encodesTheWireFormatAsProtobufDoes() {
        // The protobuf encoding guide's own examples: an int of 150, a string, a nested message.
        #expect(hex(Proto.message { $0.add(1, 150) }) == "08 96 01")
        #expect(hex(Proto.message { $0.add(2, "testing") }) == "12 07 74 65 73 74 69 6e 67")
        #expect(hex(Proto.message { $0.message(3) { $0.add(1, 150) } }) == "1a 03 08 96 01")
        // A negative int64 takes ten bytes: payload IDs are random and often negative.
        #expect(hex(Proto.message { $0.add(1, Int64(-1)) }) == "08 ff ff ff ff ff ff ff ff ff 01")
    }

    @Test func readsBackWhatItWrites() throws {
        let data = Proto.message {
            $0.add(1, Int64.min)
            $0.add(2, true)
            $0.add(3, "héllo")
            $0.message(4) { $0.add(1, 7) }
            $0.message(4) { $0.add(1, 8) }
        }
        let message = try ProtoMessage(data)
        #expect(message.int(1) == .min)
        #expect(message.bool(2) == true)
        #expect(message.string(3) == "héllo")
        #expect(try message.messages(4).map { $0.int(1) } == [7, 8])
        #expect(message.int(9) == nil)
    }

    @Test func skipsFieldsItDoesNotKnow() throws {
        // A fixed64 (field 5), a fixed32 (field 6), then a varint it knows.
        let message = try ProtoMessage(bytes("29 01 02 03 04 05 06 07 08 35 01 02 03 04 08 2a"))
        #expect(message.int(1) == 42)
    }

    @Test func rejectsBrokenMessages() {
        for broken in ["08", "12 05 61 62", "08 ff ff ff ff ff ff ff ff ff 02", "0b 00", "00 00"] {
            #expect(throws: QuickShareError.malformed, "\(broken)") { try ProtoMessage(bytes(broken)) }
        }
    }
}

struct FrameTests {
    @Test func aKeepAliveAnswerIsByteForByteWhatAndroidSends() {
        // OfflineFrame { version: V1, v1 { type: KEEP_ALIVE, keep_alive { ack: true, seq_num: 3 } } }
        #expect(hex(OfflineFrame.keepAlive(ack: true, sequence: 3).encoded) == "08 01 12 08 08 05 32 04 08 01 10 03")
    }

    @Test func offlineFramesRoundTrip() throws {
        let payload = PayloadFrame(
            id: -42, isFile: true, totalSize: 3, offset: 0, body: Data("abc".utf8), isLast: false)
        let frames: [OfflineFrame] = [
            .connectionRequest(endpointID: "ABCD", name: "Mac", info: Data([1, 2, 3])),
            .connectionResponse(accepted: true),
            .connectionResponse(accepted: false),
            .payload(payload),
            .upgradePathAvailable(pathInfo: Data([9, 9])),
            .keepAlive(ack: false, sequence: 12),
            .disconnection,
        ]
        for frame in frames {
            #expect(try OfflineFrame(frame.encoded) == frame)
        }
    }

    @Test func anOlderPhoneAcceptsWithItsStatusAlone() throws {
        // ConnectionResponseFrame { status: 0 }, without the newer `response` field.
        let frame = Proto.message {
            $0.add(1, 1)
            $0.message(2) {
                $0.add(1, 2)
                $0.message(3) { $0.add(1, 0) }
            }
        }
        #expect(try OfflineFrame(frame) == .connectionResponse(accepted: true))
    }

    @Test func aCancelledPayloadIsNoticed() throws {
        let frame = Proto.message {
            $0.add(1, 1)
            $0.message(2) {
                $0.add(1, 3)
                $0.message(4) {
                    $0.add(1, 2)  // CONTROL
                    $0.message(2) { $0.add(1, 77) }
                    $0.message(4) { $0.add(1, 2) }  // PAYLOAD_CANCELED
                }
            }
        }
        guard case .payload(let payload) = try OfflineFrame(frame) else {
            Issue.record("not a payload")
            return
        }
        #expect(payload.id == 77)
        #expect(payload.isCancelled)
    }

    @Test func shareFramesRoundTrip() throws {
        let files = [
            FileOffer(name: "photo.jpg", size: 1234, mimeType: "image/jpeg", payloadID: 1),
            FileOffer(name: "app.apk", size: 5, mimeType: "application/vnd.android.package-archive", payloadID: -2),
        ]
        #expect(
            try ShareFrame(ShareFrame.introduction(Introduction(files: files)).encoded)
                == .introduction(Introduction(files: files)))
        for status in [ShareStatus.accept, .reject, .notEnoughSpace, .unsupportedAttachmentType, .timedOut] {
            #expect(try ShareFrame(ShareFrame.response(status).encoded) == .response(status))
        }
        #expect(try ShareFrame(ShareFrame.pairedKeyResult.encoded) == .pairedKeyResult)
        #expect(try ShareFrame(ShareFrame.cancel.encoded) == .cancel)
        #expect(
            try ShareFrame(ShareFrame.pairedKeyEncryption(qrSignature: Data([7])).encoded)
                == .pairedKeyEncryption(qrSignature: Data([7])))
        #expect(files.map(\.kind) == [1, 3], "an image, then an Android app")
    }

    @Test func anIntroductionWithTextOrThingsAMacCantTakeReadsAsSuch() throws {
        let introduction = Proto.message {
            $0.message(2) {  // TextMetadata
                $0.add(2, "Example")
                $0.add(3, 2)  // URL
                $0.add(4, Int64(-5))
                $0.add(5, 19)
            }
            $0.message(4) { $0.add(2, "Home Wi-Fi") }  // WifiCredentialsMetadata
        }
        let parsed = try Introduction(ProtoMessage(introduction))
        #expect(parsed.texts == [TextOffer(title: "Example", kind: .url, size: 19, payloadID: -5)])
        #expect(parsed.hasUnsupported)
    }

    @Test func ukey2MessagesRoundTrip() throws {
        let clientInit = Ukey2.ClientInit(random: randomData(32), commitment: randomData(64))
        #expect(try Ukey2.ClientInit(clientInit.encoded) == clientInit)
        let serverInit = Ukey2.ServerInit(random: randomData(32), publicKey: Handshake().publicKey)
        #expect(try Ukey2.ServerInit(serverInit.encoded) == serverInit)
        let wrapped = Ukey2.message(.clientInit, clientInit.encoded)
        #expect(try Ukey2.open(wrapped, expecting: .clientInit) == clientInit.encoded)
        #expect(throws: QuickShareError.insecure) { try Ukey2.open(wrapped, expecting: .serverInit) }
    }
}

struct DiscoveryTests {
    @Test func readsAPhonesRecord() throws {
        // Version 0, visible, a phone; 16 bytes only Google can read; the name.
        let name = "Galaxy S25 Ultra"
        let record = Data([0b0000_0010]) + Data(count: 16) + Data([UInt8(name.utf8.count)]) + Data(name.utf8)
        let info = try #require(EndpointInfo(record))
        #expect(info == EndpointInfo(name: name, kind: .phone))
    }

    @Test func readsAHiddenPhoneThatScannedACode() throws {
        let record = Data([0b0001_1010]) + Data(count: 16) + Data([2, 1, 0xAA, 1, 2, 0xBB, 0xCC])  // vendor, then QR
        let info = try #require(EndpointInfo(record))
        #expect(info.name == nil)
        #expect(info.kind == .foldable)
        #expect(info.qrData == Data([0xBB, 0xCC]))
    }

    @Test func rejectsBrokenRecords() {
        #expect(EndpointInfo(Data(count: 10)) == nil, "too short")
        #expect(EndpointInfo(Data([0b0100_0000]) + Data(count: 16)) == nil, "an unknown version")
        #expect(EndpointInfo(Data([0]) + Data(count: 16) + Data([9, 65])) == nil, "a name longer than the record")
        #expect(EndpointInfo(Data([0]) + Data(count: 16) + Data([0])) == nil, "an empty name")
    }

    @Test func theMacsOwnRecordReadsBackAndFitsNearbysLimit() throws {
        let long = String(repeating: "é", count: 100)  // 200 bytes of UTF-8
        let encoded = EndpointInfo(name: long, kind: .laptop).encoded
        #expect(encoded.count <= 131)
        let info = try #require(EndpointInfo(encoded))
        #expect(info.kind == .laptop)
        #expect(info.name == String(repeating: "é", count: 56), "whole characters only")
        #expect(EndpointInfo(EndpointInfo(name: "", kind: .laptop).encoded)?.name == "Mac")
    }

    @Test func serviceNamesCarryTheEndpointID() {
        let name = ServiceName.make(endpointID: "AB12")
        #expect(name == "I0FCMTL8n14AAA", "0x23, AB12, FC 9F 5E, 0, 0 in base64url")
        #expect(ServiceName.endpointID(name) == "AB12")
        #expect(ServiceName.endpointID(Data("not quick share".utf8).base64URL) == nil)
        #expect(ServiceName.randomEndpointID().count == 4)
    }

    @Test func base64URLReadsEitherAlphabetWithOrWithoutPadding() {
        let data = Data([0xFB, 0xFF, 0xBF])
        #expect(data.base64URL == "-_-_")
        #expect(Data(base64URL: "-_-_") == data)
        #expect(Data(base64URL: "+/+/") == data)
        #expect(Data(base64URL: "AQ") == Data([1]))
        #expect(Data(base64URL: "AQ==") == Data([1]))
    }

    @Test func aQRCodeFindsThePhoneThatScannedIt() throws {
        let code = QRCodeKey()
        #expect(code.keyData.count == 35)
        #expect(code.keyData.prefix(2) == Data([0, 0]))
        #expect([2, 3].contains(code.keyData[2]), "a compressed point says which y it is")
        #expect(code.url.absoluteString.hasPrefix("https://quickshare.google/qrcode#key="))

        #expect(code.name(answering: code.advertisingToken, shown: "Pixel 9") == "Pixel 9")
        let hidden = try AES.GCM.seal(Data("Galaxy".utf8), using: code.nameKey, authenticating: code.advertisingToken)
        #expect(code.name(answering: try #require(hidden.combined), shown: nil) == "Galaxy")
        #expect(code.name(answering: randomData(16), shown: "Someone else") == nil)
        #expect(QRCodeKey().name(answering: code.advertisingToken, shown: "Pixel 9") == nil, "another code")
    }

    @Test func theQRSignatureVerifiesWithTheCodesKey() throws {
        let code = QRCodeKey()
        let authString = randomData(32)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: try #require(code.sign(authString)))
        let key = try P256.Signing.PublicKey(compressedRepresentation: code.keyData.dropFirst(2))
        #expect(key.isValidSignature(signature, for: authString))
    }
}

struct CryptoTests {
    /// Runs both halves of a handshake the way the sessions do.
    private func handshake() throws -> (client: SessionKeys, server: SessionKeys) {
        let client = Handshake()
        let server = Handshake()
        let clientInit = Ukey2.message(.clientInit, randomData(40))
        let serverInit = Ukey2.message(.serverInit, randomData(40))
        let clientKeys = try client.keys(
            peer: Handshake.peerKey(server.publicKey), clientInit: clientInit, serverInit: serverInit, isServer: false)
        let serverKeys = try server.keys(
            peer: Handshake.peerKey(client.publicKey), clientInit: clientInit, serverInit: serverInit, isServer: true)
        return (clientKeys, serverKeys)
    }

    @Test func bothSidesAgreeOnTheCodeAndTheKeys() throws {
        let (client, server) = try handshake()
        #expect(client.authString == server.authString)
        #expect(client.pin == server.pin)
        #expect(client.pin.count == 4)
        let message = Data("hello".utf8)
        #expect(try SecureChannel(server).open(SecureChannel(client).seal(message)) == message)
        #expect(try SecureChannel(client).open(SecureChannel(server).seal(message)) == message)
    }

    @Test func theCodeIsQuickSharesHashOfTheAuthString() {
        // Checked against an independent implementation of TokenToFourDigitString.
        func pin(_ bytes: [UInt8]) -> String {
            SessionKeys(
                authString: Data(bytes), encrypt: .init(size: .bits256), decrypt: .init(size: .bits256),
                sign: .init(size: .bits256), verify: .init(size: .bits256)
            ).pin
        }
        #expect(pin(Array(0..<32)) == "5095")
        #expect(pin(Array(224...255)) == "3733")
        #expect(pin([0xFF] + Array(repeating: 0, count: 31)) == "0001", "bytes are signed, and the sign is dropped")
        #expect(pin([0, 1] + Array(repeating: 0, count: 30)) == "0031")
    }

    @Test func aTamperedOrReplayedMessageIsRejected() throws {
        let (client, server) = try handshake()
        let sender = SecureChannel(client)
        let receiver = SecureChannel(server)
        let first = try sender.seal(Data("one".utf8))
        let second = try sender.seal(Data("two".utf8))

        var tampered = first
        tampered[tampered.count / 2] ^= 1
        #expect(throws: QuickShareError.insecure) { try receiver.open(tampered) }
        #expect(throws: QuickShareError.insecure, "out of order") { try SecureChannel(server).open(second) }
        #expect(try receiver.open(first) == Data("one".utf8))
        #expect(throws: QuickShareError.insecure, "replayed") { try receiver.open(first) }
    }

    @Test func keysAreWrittenAsJavaWritesBigIntegers() {
        #expect(Handshake.javaInteger(Data([0x00, 0x7F, 0x01])) == Data([0x7F, 0x01]))
        #expect(Handshake.javaInteger(Data([0x80, 0x01])) == Data([0x00, 0x80, 0x01]), "not negative")
        #expect(Handshake.javaInteger(Data(count: 3)) == Data([0]))
    }

    @Test func aKeyOffTheCurveIsRefused() {
        let bogus = Proto.message {
            $0.add(1, 1)
            $0.message(2) {
                $0.add(1, Data(repeating: 1, count: 32))
                $0.add(2, Data(repeating: 2, count: 32))
            }
        }
        #expect(throws: QuickShareError.insecure) { try Handshake.peerKey(bogus) }
    }
}

struct FileNameTests {
    @Test(arguments: [
        ("photo.jpg", "photo.jpg"),
        ("../../etc/passwd", "_.._etc_passwd"),
        ("C:\\Windows\\evil.exe", "C__Windows_evil.exe"),
        (".hidden", "hidden"),
        ("..", "Untitled"),
        ("   ", "Untitled"),
        ("", "Untitled"),
        ("report\u{202E}fdp.app", "reportfdp.app"),
        ("tab\tand\nnewline.txt", "tabandnewline.txt"),
        ("trailing dots...", "trailing dots"),
        ("  spaced.png  ", "spaced.png"),
    ])
    func hostileNamesComeOutSafe(_ name: String, _ expected: String) {
        #expect(FileNames.clean(name) == expected)
    }

    @Test func longNamesKeepTheirExtension() {
        let ascii = FileNames.clean(String(repeating: "a", count: 300) + ".jpg")
        #expect(ascii.utf8.count == FileNames.maxBytes)
        #expect(ascii.hasSuffix(".jpg"))
        let accented = FileNames.clean(String(repeating: "é", count: 150) + ".png")
        #expect(accented.utf8.count <= FileNames.maxBytes)
        #expect(accented.hasSuffix(".png"))
        #expect(accented.dropLast(4).allSatisfy { $0 == "é" }, "no character cut in half")
    }

    @Test func namesForAndroidAvoidItsReservedCharacters() {
        #expect(FileNames.forAndroid("what? a <great> day|.jpg") == "what_ a _great_ day_.jpg")
    }

    @Test func clashesAreNumberedTheWayFinderDoes() {
        #expect(FileNames.numbered("photo.jpg", 1) == "photo.jpg")
        #expect(FileNames.numbered("photo.jpg", 2) == "photo 2.jpg")
        #expect(FileNames.numbered("notes", 3) == "notes 3")
        #expect(FileNames.numbered("archive.tar.gz", 2) == "archive.tar 2.gz")
    }
}

struct IncomingFileTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "IncomingFile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func chunk(_ offset: Int64, _ body: String, last: Bool = false) -> PayloadFrame {
        PayloadFrame(id: 1, isFile: true, totalSize: 6, offset: offset, body: Data(body.utf8), isLast: last)
    }

    private var offer: FileOffer { FileOffer(name: "note.txt", size: 6, mimeType: "text/plain", payloadID: 1) }

    @Test func aFileArrivesInOrderAndTakesAFreeName() throws {
        try Data("taken".utf8).write(to: folder.appending(path: "note.txt"))
        let file = try IncomingFile(offer, in: folder)
        try file.write(chunk(0, "abc"))
        try file.write(chunk(3, "def"))
        try file.write(chunk(6, "", last: true))
        let saved = try file.save(in: folder)
        #expect(saved.lastPathComponent == "note 2.txt")
        #expect(try String(contentsOf: saved, encoding: .utf8) == "abcdef")
        #expect(try saved.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties != nil)
    }

    @Test func dataThatDoesntMatchTheAnnouncementIsRefused() throws {
        let gap = try IncomingFile(offer, in: folder)
        #expect(throws: QuickShareError.malformed, "a gap") { try gap.write(chunk(1, "abc")) }
        let tooMuch = try IncomingFile(offer, in: folder)
        #expect(throws: QuickShareError.malformed, "more than announced") { try tooMuch.write(chunk(0, "abcdefg")) }
        let short = try IncomingFile(offer, in: folder)
        try short.write(chunk(0, "abc"))
        #expect(throws: QuickShareError.malformed, "less than announced") { try short.write(chunk(3, "", last: true)) }
    }
}
