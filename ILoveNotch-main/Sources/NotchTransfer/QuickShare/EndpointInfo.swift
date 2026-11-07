// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// How a device describes itself, in its Bonjour record (TXT key "n", base64url) and when it
/// connects (sharing/advertisement.cc in github.com/google/nearby). One byte packs a version,
/// whether the name is hidden, and the device type; 16 bytes follow that only the device's Google
/// account can read (random here); then the name, after its length; then type-length-value
/// records, where type 1 answers a QR code.
struct EndpointInfo: Equatable {
    /// ShareTargetType, which the phone uses to pick an icon.
    enum Kind: Int, Sendable {
        case unknown, phone, tablet, laptop, car, foldable, headset
    }

    /// Nil when the device hides it.
    var name: String?
    var kind: Kind
    /// A phone that scanned this Mac's QR code puts the code's token here, or its name encrypted
    /// with the code's key when it's hidden.
    var qrData: Data?

    /// Nearby Connections drops endpoint info longer than 131 bytes; 18 go to everything but the name.
    static let maxNameBytes = 131 - 18

    init(name: String?, kind: Kind, qrData: Data? = nil) {
        self.name = name
        self.kind = kind
        self.qrData = qrData
    }

    /// Visible, version 0, no records: what this Mac sends.
    var encoded: Data {
        var data = Data([UInt8(name == nil ? 1 : 0) << 4 | UInt8(kind.rawValue) << 1]) + randomData(16)
        if let name {
            // Android reads an empty name as a broken record.
            let bytes = Data((name.isEmpty ? "Mac" : name).truncated(toUTF8Bytes: Self.maxNameBytes).utf8)
            data.append(UInt8(bytes.count))
            data.append(bytes)
        }
        if let qrData {
            data.append(contentsOf: [1, UInt8(qrData.count)])
            data.append(qrData)
        }
        return data
    }

    init?(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 17, bytes[0] >> 5 <= 1 else { return nil }  // versions 0 and 1
        kind = Kind(rawValue: Int(bytes[0] >> 1 & 7)) ?? .unknown
        var offset = 17
        if bytes[0] >> 4 & 1 == 0 {
            guard offset < bytes.count else { return nil }
            let length = Int(bytes[offset])
            offset += 1
            guard length > 0, offset + length <= bytes.count else { return nil }
            name = String(decoding: bytes[offset..<offset + length], as: UTF8.self)
            offset += length
        }
        while bytes.count - offset >= 2 {
            let type = bytes[offset]
            let length = Int(bytes[offset + 1])
            offset += 2
            guard offset + length <= bytes.count else { return nil }
            if type == 1 { qrData = Data(bytes[offset..<offset + length]) }
            offset += length
        }
    }
}

/// The Bonjour service a Quick Share receiver announces (connections/implementation/
/// wifi_lan_service_info.cc). Its name is base64url of: 0x23 (version 1, point-to-point), the
/// 4-character endpoint ID, the first 3 bytes of SHA-256("NearbySharing"), and two zero bytes
/// (no UWB address, no WebRTC).
enum ServiceName {
    static let type = "_FC9F5ED42C8A._tcp"
    private static let serviceIDHash: [UInt8] = [0xFC, 0x9F, 0x5E]

    static func make(endpointID: String) -> String {
        Data([0x23] + Array(endpointID.utf8) + serviceIDHash + [0, 0]).base64URL
    }

    /// The endpoint ID in a Quick Share service's name, or nil for any other service.
    static func endpointID(_ name: String) -> String? {
        guard let data = Data(base64URL: name) else { return nil }
        let bytes = [UInt8](data)
        guard bytes.count >= 8, bytes[0] >> 5 == 1, Array(bytes[5..<8]) == serviceIDHash else { return nil }
        return String(decoding: bytes[1..<5], as: UTF8.self)
    }

    /// Four characters, as Nearby Connections makes them.
    static func randomEndpointID() -> String {
        String((0..<4).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement() ?? "A" })
    }
}

/// The QR code the send window shows. Phones that only announce themselves on Wi-Fi after a
/// Bluetooth nudge a Mac can't send (Samsung's among them) do once they scan it, and mark their
/// announcement with the code's token, so the Mac knows which phone it is and connects. The Mac
/// then signs the connection's authentication string with the code's key, which proves to the
/// phone that this is the Mac it scanned, so it doesn't ask again.
struct QRCodeKey: Sendable {
    let privateKey = P256.Signing.PrivateKey()

    /// Two version bytes, then the public key, compressed: a byte saying which of the curve's two
    /// y values it is, and x.
    var keyData: Data { Data([0, 0]) + privateKey.publicKey.compressedRepresentation }

    var url: URL { URL(string: "https://quickshare.google/qrcode#key=" + keyData.base64URL)! }

    /// What a phone that scanned the code, and shows its name, puts in its announcement.
    var advertisingToken: Data { derive("advertisingContext").withUnsafeBytes { Data($0) } }

    /// What a phone that scanned the code, but hides its name, seals its name with.
    var nameKey: SymmetricKey { derive("encryptionKey") }

    /// The name of the phone that scanned this code, if `qrData` in its announcement answers it:
    /// the token itself when it shows its name, or its name sealed (AES-GCM, the token as
    /// associated data) when it's hidden. Nil for any other phone.
    func name(answering qrData: Data, shown: String?) -> String? {
        if qrData == advertisingToken { return shown ?? "Android device" }
        guard let box = try? AES.GCM.SealedBox(combined: qrData),
            let name = try? AES.GCM.open(box, using: nameKey, authenticating: advertisingToken)
        else { return nil }
        return String(decoding: name, as: UTF8.self)
    }

    /// An ECDSA signature in IEEE P1363 form (r then s), as the phone checks it.
    func sign(_ authString: Data) -> Data? {
        try? privateKey.signature(for: authString).rawRepresentation
    }

    private func derive(_ info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: keyData), salt: Data(), info: Data(info.utf8), outputByteCount: 16)
    }
}

extension Data {
    /// Base64 with "-" and "_" and no padding, as Nearby Connections writes names and records.
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Reads base64url, and plain base64 too, with or without padding.
    init?(base64URL text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
