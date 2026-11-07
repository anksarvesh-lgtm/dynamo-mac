// SPDX-License-Identifier: MIT
import Foundation

// Quick Share's messages, with the field numbers of Google's own protocol definitions
// (github.com/google/nearby, Apache-2.0; see THIRD_PARTY_NOTICES.md): Nearby Connections'
// offline_wire_formats.proto, Quick Share's wire_format.proto, and UKEY2's ukey.proto. Only the
// fields Quick Share uses are here.

/// Nearby Connections' frames: the transport Quick Share runs on.
enum OfflineFrame: Equatable {
    case connectionRequest(endpointID: String, name: String, info: Data)
    case connectionResponse(accepted: Bool)
    case payload(PayloadFrame)
    /// The other side offers to move the connection to a faster link, such as its own hotspot.
    case upgradePathAvailable(pathInfo: Data)
    /// The answer to that offer: this Mac stays on the local network.
    case upgradeFailure(pathInfo: Data)
    case keepAlive(ack: Bool, sequence: Int64)
    case disconnection
    /// Anything else, which is ignored.
    case other

    /// V1Frame.FrameType. V1Frame keeps each type's own frame in the field one past its type.
    private enum FrameType {
        static let connectionRequest: Int64 = 1, connectionResponse: Int64 = 2, payloadTransfer: Int64 = 3
        static let upgrade: Int64 = 4, keepAlive: Int64 = 5, disconnection: Int64 = 6
    }

    var encoded: Data {
        Proto.message { frame in
            frame.add(1, 1)  // version: V1
            frame.message(2) { v1 in
                switch self {
                case .connectionRequest(let endpointID, let name, let info):
                    v1.add(1, FrameType.connectionRequest)
                    v1.message(2) {
                        $0.add(1, endpointID)
                        $0.add(2, name)
                        $0.add(5, 5)  // mediums: WIFI_LAN only, so there's nothing else to upgrade to
                        $0.add(6, info)
                    }
                case .connectionResponse(let accepted):
                    v1.add(1, FrameType.connectionResponse)
                    v1.message(3) {
                        $0.add(1, accepted ? 0 : 1)  // status, which older devices read
                        $0.add(3, accepted ? 1 : 2)  // response: ACCEPT or REJECT
                        $0.message(4) { $0.add(1, 4) }  // os_info: APPLE
                    }
                case .payload(let payload):
                    v1.add(1, FrameType.payloadTransfer)
                    v1.add(4, payload.encoded)
                case .upgradePathAvailable(let info):
                    v1.add(1, FrameType.upgrade)
                    v1.message(5) {
                        $0.add(1, 1)  // UPGRADE_PATH_AVAILABLE
                        $0.add(2, info)
                    }
                case .upgradeFailure(let info):
                    v1.add(1, FrameType.upgrade)
                    v1.message(5) {
                        $0.add(1, 5)  // UPGRADE_FAILURE
                        $0.add(2, info)
                    }
                case .keepAlive(let ack, let sequence):
                    v1.add(1, FrameType.keepAlive)
                    v1.message(6) {
                        $0.add(1, ack)
                        $0.add(2, sequence)
                    }
                case .disconnection:
                    v1.add(1, FrameType.disconnection)
                    v1.message(7) { _ in }
                case .other:
                    break
                }
            }
        }
    }

    init(_ data: Data) throws {
        let frame = try ProtoMessage(data)
        guard frame.int(1) == 1, let v1 = try frame.message(2) else { throw QuickShareError.malformed }
        switch v1.int(1) {
        case FrameType.connectionRequest:
            guard let request = try v1.message(2) else { throw QuickShareError.malformed }
            self = .connectionRequest(
                endpointID: request.string(1) ?? "", name: request.string(2) ?? "", info: request.bytes(6) ?? Data())
        case FrameType.connectionResponse:
            // `response` where the sender sets it, else the older `status`, where 0 is success.
            let response = try v1.message(3)
            let accepted = response?.int(3).map { $0 == 1 } ?? ((response?.int(1) ?? 0) == 0)
            self = .connectionResponse(accepted: accepted)
        case FrameType.payloadTransfer:
            guard let payload = try v1.message(4) else { throw QuickShareError.malformed }
            self = try PayloadFrame(payload).map { .payload($0) } ?? .other
        case FrameType.upgrade:
            let negotiation = try v1.message(5)
            let info = negotiation?.bytes(2) ?? Data()
            self = negotiation?.int(1) == 1 ? .upgradePathAvailable(pathInfo: info) : .other
        case FrameType.keepAlive:
            let keepAlive = try v1.message(6)
            self = .keepAlive(ack: keepAlive?.bool(1) ?? false, sequence: keepAlive?.int(2) ?? 0)
        case FrameType.disconnection:
            self = .disconnection
        default:
            self = .other
        }
    }
}

/// A piece of a payload: bytes (Quick Share's own messages, or shared text) or a file, sent in
/// chunks with a last, empty one flagged. Or a control message cancelling the payload.
struct PayloadFrame: Equatable {
    var id: Int64
    var isFile: Bool
    var totalSize: Int64
    var offset: Int64
    var body: Data
    var isLast: Bool
    /// The sender cancelled this payload, or couldn't read it.
    var isCancelled = false

    var encoded: Data {
        Proto.message {
            $0.add(1, 1)  // packet_type: DATA
            $0.message(2) {
                $0.add(1, id)
                $0.add(2, isFile ? 2 : 1)  // FILE or BYTES
                $0.add(3, totalSize)
                $0.add(4, false)  // is_sensitive
            }
            $0.message(3) {
                $0.add(1, isLast ? 1 : 0)  // flags: LAST_CHUNK
                $0.add(2, offset)
                if !body.isEmpty { $0.add(3, body) }
            }
        }
    }

    init(id: Int64, isFile: Bool, totalSize: Int64, offset: Int64, body: Data, isLast: Bool) {
        self.id = id
        self.isFile = isFile
        self.totalSize = totalSize
        self.offset = offset
        self.body = body
        self.isLast = isLast
    }

    /// Nil for packet types this Mac doesn't use, such as acknowledgments.
    init?(_ frame: ProtoMessage) throws {
        guard let header = try frame.message(2), let id = header.int(1) else { throw QuickShareError.malformed }
        self.id = id
        isFile = header.int(2) == 2
        totalSize = header.int(3) ?? 0
        switch frame.int(1) {
        case 1:  // DATA
            let chunk = try frame.message(3)
            offset = chunk?.int(2) ?? 0
            body = chunk?.bytes(3) ?? Data()
            isLast = (chunk?.int(1) ?? 0) & 1 == 1
        case 2:  // CONTROL: PAYLOAD_ERROR or PAYLOAD_CANCELED
            let event = try frame.message(4)?.int(1)
            guard event == 1 || event == 2 else { return nil }
            offset = 0
            body = Data()
            isLast = false
            isCancelled = true
        default:
            return nil
        }
    }
}

/// Quick Share's own messages, which travel as byte payloads.
enum ShareFrame: Equatable {
    case introduction(Introduction)
    case response(ShareStatus)
    /// Where contacts-only sharing would prove who's who; this Mac has no Google account, so the
    /// contents are random, except a signature when the phone found the Mac by its QR code.
    case pairedKeyEncryption(qrSignature: Data?)
    case pairedKeyResult
    case cancel
    case other

    /// V1Frame.FrameType
    private enum FrameType {
        static let introduction: Int64 = 1, response: Int64 = 2, pairedKeyEncryption: Int64 = 3
        static let pairedKeyResult: Int64 = 4, cancel: Int64 = 6
    }

    var encoded: Data {
        Proto.message { frame in
            frame.add(1, 1)  // version: V1
            frame.message(2) { v1 in
                switch self {
                case .introduction(let introduction):
                    v1.add(1, FrameType.introduction)
                    v1.add(2, introduction.encoded)
                case .response(let status):
                    v1.add(1, FrameType.response)
                    v1.message(3) { $0.add(1, status.rawValue) }
                case .pairedKeyEncryption(let signature):
                    v1.add(1, FrameType.pairedKeyEncryption)
                    v1.message(4) {
                        $0.add(1, randomData(72))  // signed_data
                        $0.add(2, randomData(6))  // secret_id_hash
                        if let signature { $0.add(4, signature) }  // qr_code_handshake_data
                    }
                case .pairedKeyResult:
                    v1.add(1, FrameType.pairedKeyResult)
                    v1.message(5) { $0.add(1, 3) }  // status: UNABLE
                case .cancel:
                    v1.add(1, FrameType.cancel)
                case .other:
                    break
                }
            }
        }
    }

    init(_ data: Data) throws {
        let frame = try ProtoMessage(data)
        guard frame.int(1) == 1, let v1 = try frame.message(2) else { throw QuickShareError.malformed }
        switch v1.int(1) {
        case FrameType.introduction:
            guard let introduction = try v1.message(2) else { throw QuickShareError.malformed }
            self = .introduction(try Introduction(introduction))
        case FrameType.response:
            let status = try v1.message(3)?.int(1).flatMap { ShareStatus(rawValue: Int($0)) }
            self = .response(status ?? .unknown)
        case FrameType.pairedKeyEncryption:
            self = .pairedKeyEncryption(qrSignature: try v1.message(4)?.bytes(4))
        case FrameType.pairedKeyResult:
            self = .pairedKeyResult
        case FrameType.cancel:
            self = .cancel
        default:
            self = .other
        }
    }
}

/// What the sender is about to send.
struct Introduction: Equatable {
    var files: [FileOffer] = []
    var texts: [TextOffer] = []
    /// Wi-Fi networks, apps, or streams: things a phone can share that a Mac can't take.
    var hasUnsupported = false

    var encoded: Data {
        Proto.message { introduction in
            for file in files {
                introduction.message(1) {
                    $0.add(1, file.name)
                    $0.add(2, file.kind)
                    $0.add(3, file.payloadID)
                    $0.add(4, file.size)
                    $0.add(5, file.mimeType)
                    $0.add(6, file.payloadID)  // the attachment's ID, unique like the payload's
                }
            }
        }
    }

    init(files: [FileOffer]) { self.files = files }

    init(_ introduction: ProtoMessage) throws {
        files = try introduction.messages(1).map {
            FileOffer(
                name: $0.string(1) ?? "", size: $0.int(4) ?? 0, mimeType: $0.string(5) ?? "application/octet-stream",
                payloadID: $0.int(3) ?? 0)
        }
        texts = try introduction.messages(2).map {
            TextOffer(
                title: $0.string(2) ?? "", kind: $0.int(3).flatMap { TextKind(rawValue: Int($0)) } ?? .text,
                size: $0.int(5) ?? 0, payloadID: $0.int(4) ?? 0)
        }
        hasUnsupported = [4, 5, 7].contains(where: introduction.has)
    }
}

struct FileOffer: Equatable, Sendable {
    var name: String
    var size: Int64
    var mimeType: String
    var payloadID: Int64

    /// FileMetadata.Type, which the phone uses to pick where the file goes.
    var kind: Int {
        switch mimeType.prefix(while: { $0 != "/" }) {
        case "image": 1
        case "video": 2
        case "audio": 4
        case _ where name.lowercased().hasSuffix(".apk"): 3
        default: 0
        }
    }
}

struct TextOffer: Equatable, Sendable {
    /// The phone's description, such as a page's title, which may be empty.
    var title: String
    var kind: TextKind
    var size: Int64
    var payloadID: Int64
}

/// TextMetadata.Type
enum TextKind: Int, Sendable {
    case unknown, text, url, address, phoneNumber
}

/// ConnectionResponseFrame.Status in Quick Share's messages: the receiver's answer.
enum ShareStatus: Int {
    case unknown, accept, reject, notEnoughSpace, unsupportedAttachmentType, timedOut
}

/// UKEY2's handshake messages (ukey.proto), which agree on keys before anything is encrypted.
enum Ukey2 {
    enum Kind: Int {
        case alert = 1
        case clientInit, serverInit, clientFinish
    }

    static let version = 1
    /// Ukey2HandshakeCipher.P256_SHA512
    static let p256SHA512 = 100
    static let nextProtocol = "AES_256_CBC-HMAC_SHA256"

    /// Ukey2Message: its type, then the message itself.
    static func message(_ kind: Kind, _ body: Data) -> Data {
        Proto.message {
            $0.add(1, kind.rawValue)
            $0.add(2, body)
        }
    }

    static func open(_ data: Data, expecting kind: Kind) throws -> Data {
        let message = try ProtoMessage(data)
        guard message.int(1) == Int64(kind.rawValue), let body = message.bytes(2) else {
            throw QuickShareError.insecure
        }
        return body
    }

    /// Ukey2Alert, sent before hanging up on a handshake that can't go on.
    static func alert(_ type: Int) -> Data {
        message(.alert, Proto.message { $0.add(1, type) })
    }

    struct ClientInit: Equatable {
        var version = Ukey2.version
        var random: Data
        /// SHA-512 of the ClientFinish message the client will send, keyed by cipher.
        var commitments: [Int: Data]
        var nextProtocol = Ukey2.nextProtocol

        var encoded: Data {
            Proto.message { message in
                message.add(1, version)
                message.add(2, random)
                for (cipher, commitment) in commitments.sorted(by: { $0.key < $1.key }) {
                    message.message(3) {
                        $0.add(1, cipher)
                        $0.add(2, commitment)
                    }
                }
                message.add(4, nextProtocol)
            }
        }

        init(random: Data, commitment: Data) {
            self.random = random
            commitments = [Ukey2.p256SHA512: commitment]
        }

        init(_ data: Data) throws {
            let message = try ProtoMessage(data)
            version = Int(message.int(1) ?? 0)
            random = message.bytes(2) ?? Data()
            commitments = [:]
            for commitment in try message.messages(3) {
                guard let cipher = commitment.int(1), let hash = commitment.bytes(2) else { continue }
                commitments[Int(cipher)] = hash
            }
            nextProtocol = message.string(4) ?? ""
        }
    }

    struct ServerInit: Equatable {
        var version = Ukey2.version
        var random: Data
        var cipher = Ukey2.p256SHA512
        /// A GenericPublicKey, serialized.
        var publicKey: Data

        var encoded: Data {
            Proto.message {
                $0.add(1, version)
                $0.add(2, random)
                $0.add(3, cipher)
                $0.add(4, publicKey)
            }
        }

        init(random: Data, publicKey: Data) {
            self.random = random
            self.publicKey = publicKey
        }

        init(_ data: Data) throws {
            let message = try ProtoMessage(data)
            version = Int(message.int(1) ?? 0)
            random = message.bytes(2) ?? Data()
            cipher = Int(message.int(3) ?? 0)
            publicKey = message.bytes(4) ?? Data()
        }
    }

    /// Ukey2ClientFinished: the client's public key.
    static func clientFinished(publicKey: Data) -> Data { Proto.message { $0.add(1, publicKey) } }

    static func publicKey(ofClientFinished data: Data) throws -> Data {
        guard let key = try ProtoMessage(data).bytes(1) else { throw QuickShareError.insecure }
        return key
    }
}

/// Cryptographically random bytes, for IVs, handshake nonces, and filler.
func randomData(_ count: Int) -> Data {
    var data = Data(count: count)
    data.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
    return data
}
