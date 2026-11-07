// SPDX-License-Identifier: MIT
import CommonCrypto
import CryptoKit
import Foundation

/// UKEY2 (github.com/google/ukey2) as Quick Share runs it. Each side makes a P-256 key pair, the
/// client commits to its key before it sees the server's, and both derive the same secrets from
/// the key agreement and the two opening messages: keys for the secure channel, and a 4-digit
/// code both screens show, so the user can see nobody is in the middle.
struct Handshake {
    let privateKey = P256.KeyAgreement.PrivateKey()

    /// A GenericPublicKey (securemessage.proto): the point's coordinates the way Java writes a
    /// positive big integer, big-endian with a zero byte in front when the top bit is set.
    var publicKey: Data {
        let point = privateKey.publicKey.rawRepresentation  // x then y, 32 bytes each
        return Proto.message {
            $0.add(1, 1)  // type: EC_P256
            $0.message(2) {
                $0.add(1, Self.javaInteger(point.prefix(32)))
                $0.add(2, Self.javaInteger(point.suffix(32)))
            }
        }
    }

    /// The other side's key, which must be a point on the curve. CryptoKit takes any x and y as
    /// they are, so the key is rebuilt from x and y's parity instead: that lands on the same point
    /// only when the point is on the curve.
    static func peerKey(_ genericPublicKey: Data) throws -> P256.KeyAgreement.PublicKey {
        let key = try ProtoMessage(genericPublicKey)
        guard key.int(1) == 1, let point = try key.message(2),
            let x = point.bytes(1).flatMap(coordinate), let y = point.bytes(2).flatMap(coordinate),
            let peer = try? P256.KeyAgreement.PublicKey(compressedRepresentation: [2 | (y[31] & 1)] + x),
            peer.rawRepresentation == x + y
        else { throw QuickShareError.insecure }
        return peer
    }

    /// `clientInit` and `serverInit` are the two Ukey2Messages exactly as they were sent.
    func keys(peer: P256.KeyAgreement.PublicKey, clientInit: Data, serverInit: Data, isServer: Bool) throws
        -> SessionKeys
    {
        let agreed = try privateKey.sharedSecretFromKeyAgreement(with: peer).withUnsafeBytes { Data($0) }
        let secret = SymmetricKey(data: SHA256.hash(data: agreed))
        let transcript = clientInit + serverInit
        let authString = Self.hkdf(secret, salt: Data("UKEY2 v1 auth".utf8), info: transcript)
        let next = Self.hkdf(secret, salt: Data("UKEY2 v1 next".utf8), info: transcript)
        // The device-to-device keys, then SecureMessage's (Chromium's d2d_crypto_ops.cc and crypto_ops.cc).
        let deviceSalt = Data(SHA256.hash(data: Data("D2D".utf8)))
        let client = Self.hkdf(next, salt: deviceSalt, info: Data("client".utf8))
        let server = Self.hkdf(next, salt: deviceSalt, info: Data("server".utf8))
        let messageSalt = Data(SHA256.hash(data: Data("SecureMessage".utf8)))
        func encryption(_ key: SymmetricKey) -> SymmetricKey {
            Self.hkdf(key, salt: messageSalt, info: Data("ENC:2".utf8))
        }
        func signing(_ key: SymmetricKey) -> SymmetricKey {
            Self.hkdf(key, salt: messageSalt, info: Data("SIG:1".utf8))
        }
        let (mine, theirs) = isServer ? (server, client) : (client, server)
        return SessionKeys(
            authString: authString.withUnsafeBytes { Data($0) },
            encrypt: encryption(mine), decrypt: encryption(theirs), sign: signing(mine), verify: signing(theirs))
    }

    private static func hkdf(_ key: SymmetricKey, salt: Data, info: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: key, salt: salt, info: info, outputByteCount: 32)
    }

    static func javaInteger(_ magnitude: Data) -> Data {
        let bytes = Data(magnitude.drop { $0 == 0 })
        return (bytes.first ?? 0x80) >= 0x80 ? Data([0]) + bytes : bytes
    }

    /// A coordinate written as a Java integer, as the 32 bytes CryptoKit takes.
    private static func coordinate(_ bytes: Data) -> Data? {
        let magnitude = bytes.drop { $0 == 0 }
        guard magnitude.count <= 32 else { return nil }
        return Data(count: 32 - magnitude.count) + magnitude
    }
}

struct SessionKeys: Sendable {
    /// UKEY2's authentication string: the 4-digit code comes from it, and a QR code's key signs it.
    let authString: Data
    let encrypt: SymmetricKey
    let decrypt: SymmetricKey
    let sign: SymmetricKey
    let verify: SymmetricKey

    /// The code both screens show: Quick Share's hash of the authentication string into 0000–9972
    /// (the sharing module's TokenToFourDigitString), reading each byte as a signed Java byte.
    var pin: String {
        var hash = 0
        var multiplier = 1
        for byte in authString {
            hash = (hash + Int(Int8(bitPattern: byte)) * multiplier) % 9973
            multiplier = multiplier * 31 % 9973
        }
        return String(format: "%04d", abs(hash))
    }
}

/// Every frame after the handshake: numbered, encrypted with AES-256-CBC, and signed with
/// HMAC-SHA256, in UKEY2's SecureMessage envelope. A frame whose signature doesn't check out, or
/// that comes out of order or twice, ends the connection.
final class SecureChannel {
    private let keys: SessionKeys
    private var sent: Int64 = 0
    private var received: Int64 = 0

    init(_ keys: SessionKeys) { self.keys = keys }

    func seal(_ frame: Data) throws -> Data {
        sent += 1
        let message = Proto.message {  // DeviceToDeviceMessage
            $0.add(1, frame)
            $0.add(2, sent)
        }
        let iv = randomData(kCCBlockSizeAES128)
        let body = try Self.aes(kCCEncrypt, message, key: keys.encrypt, iv: iv)
        let headerAndBody = Proto.message {
            $0.message(1) {
                $0.add(1, 1)  // signature_scheme: HMAC_SHA256
                $0.add(2, 2)  // encryption_scheme: AES_256_CBC
                $0.add(5, iv)
                $0.message(6) {  // public_metadata: GcmMetadata
                    $0.add(1, 13)  // type: DEVICE_TO_DEVICE_MESSAGE
                    $0.add(2, 1)  // version
                }
            }
            $0.add(2, body)
        }
        return Proto.message {
            $0.add(1, headerAndBody)
            $0.add(2, Data(HMAC<SHA256>.authenticationCode(for: headerAndBody, using: keys.sign)))
        }
    }

    func open(_ secureMessage: Data) throws -> Data {
        let envelope = try ProtoMessage(secureMessage)
        guard let headerAndBody = envelope.bytes(1), let signature = envelope.bytes(2),
            HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: headerAndBody, using: keys.verify)
        else { throw QuickShareError.insecure }
        let parts = try ProtoMessage(headerAndBody)
        guard let header = try parts.message(1), header.int(1) == 1, header.int(2) == 2, let iv = header.bytes(5),
            let body = parts.bytes(2)
        else { throw QuickShareError.insecure }
        let message = try ProtoMessage(try Self.aes(kCCDecrypt, body, key: keys.decrypt, iv: iv))
        received += 1
        guard message.int(2) == received, let frame = message.bytes(1) else { throw QuickShareError.insecure }
        return frame
    }

    /// AES-256-CBC with PKCS #7 padding, which CryptoKit doesn't offer.
    private static func aes(_ operation: Int, _ input: Data, key: SymmetricKey, iv: Data) throws -> Data {
        guard iv.count == kCCBlockSizeAES128 else { throw QuickShareError.insecure }
        var output = Data(count: input.count + kCCBlockSizeAES128)
        var written = 0
        let status = output.withUnsafeMutableBytes { output in
            input.withUnsafeBytes { input in
                iv.withUnsafeBytes { iv in
                    key.withUnsafeBytes { key in
                        CCCrypt(
                            CCOperation(operation), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            key.baseAddress, key.count, iv.baseAddress, input.baseAddress, input.count,
                            output.baseAddress, output.count, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw QuickShareError.insecure }
        output.count = written
        return output
    }
}
