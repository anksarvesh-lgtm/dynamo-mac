// SPDX-License-Identifier: MIT
import Foundation

// ponytail: Protocol Buffers' wire format by hand instead of swift-protobuf and generated code:
// Quick Share needs a few fields of about twenty messages. Only varint and length-delimited
// fields are read (32- and 64-bit ones are skipped), which is every field Quick Share uses.

/// Builds one protobuf message: `Proto.message { $0.add(1, 1); $0.message(2) { $0.add(1, true) } }`.
enum Proto {
    static func message(_ build: (inout ProtoWriter) -> Void) -> Data {
        var writer = ProtoWriter()
        build(&writer)
        return writer.data
    }
}

struct ProtoWriter {
    private(set) var data = Data()

    /// An int32, int64, uint32, or enum field. Negative numbers take ten bytes, as protobuf's own do.
    mutating func add(_ field: Int, _ value: Int64) {
        key(field, wire: 0)
        varint(UInt64(bitPattern: value))
    }

    mutating func add(_ field: Int, _ value: Int) { add(field, Int64(value)) }

    mutating func add(_ field: Int, _ value: Bool) { add(field, value ? 1 : 0) }

    mutating func add(_ field: Int, _ value: Data) {
        key(field, wire: 2)
        varint(UInt64(value.count))
        data.append(value)
    }

    mutating func add(_ field: Int, _ value: String) { add(field, Data(value.utf8)) }

    /// A nested message, always written even when it has no fields of its own (an empty
    /// KeepAliveFrame still says "this is a keep-alive").
    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) { add(field, Proto.message(build)) }

    private mutating func key(_ field: Int, wire: UInt64) { varint(UInt64(field) << 3 | wire) }

    private mutating func varint(_ value: UInt64) {
        var value = value
        while value >= 0x80 {
            data.append(UInt8(truncatingIfNeeded: value) | 0x80)
            value >>= 7
        }
        data.append(UInt8(value))
    }
}

/// One decoded message: each field's values in the order they came. Fields this code doesn't know
/// are kept and ignored, so a newer phone that sends more still parses. A scalar that appears
/// twice reads as its last value, as protobuf specifies.
struct ProtoMessage {
    private enum Value {
        case varint(UInt64)
        case bytes(Data)
    }

    private var fields: [Int: [Value]] = [:]

    init(_ data: Data) throws {
        var reader = Reader(data: data)
        while !reader.atEnd {
            let key = try reader.varint()
            let field = Int(key >> 3)
            guard field > 0 else { throw QuickShareError.malformed }
            switch key & 7 {
            case 0: fields[field, default: []].append(.varint(try reader.varint()))
            case 1: try reader.skip(8)
            case 2: fields[field, default: []].append(.bytes(try reader.bytes(try reader.varint())))
            case 5: try reader.skip(4)
            default: throw QuickShareError.malformed  // groups (3 and 4) are long retired
            }
        }
    }

    func has(_ field: Int) -> Bool { fields[field] != nil }

    func int(_ field: Int) -> Int64? {
        guard case .varint(let value)? = fields[field]?.last else { return nil }
        return Int64(bitPattern: value)
    }

    func bool(_ field: Int) -> Bool? { int(field).map { $0 != 0 } }

    func bytes(_ field: Int) -> Data? {
        guard case .bytes(let value)? = fields[field]?.last else { return nil }
        return value
    }

    func string(_ field: Int) -> String? { bytes(field).map { String(decoding: $0, as: UTF8.self) } }

    func message(_ field: Int) throws -> ProtoMessage? { try bytes(field).map(ProtoMessage.init) }

    /// A repeated message field, in order.
    func messages(_ field: Int) throws -> [ProtoMessage] {
        try (fields[field] ?? []).map { value in
            guard case .bytes(let data) = value else { throw QuickShareError.malformed }
            return try ProtoMessage(data)
        }
    }

    private struct Reader {
        let data: Data
        var offset: Data.Index

        init(data: Data) {
            self.data = data
            offset = data.startIndex
        }

        var atEnd: Bool { offset >= data.endIndex }

        mutating func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, to: 64, by: 7) {
                guard offset < data.endIndex else { throw QuickShareError.malformed }
                let byte = data[offset]
                offset += 1
                // The tenth byte holds only the top bit.
                guard shift < 63 || byte <= 1 else { throw QuickShareError.malformed }
                value |= UInt64(byte & 0x7F) << shift
                if byte < 0x80 { return value }
            }
            throw QuickShareError.malformed
        }

        /// A copy, so its indices start at zero like any other `Data`.
        mutating func bytes(_ count: UInt64) throws -> Data {
            guard count <= UInt64(data.endIndex - offset) else { throw QuickShareError.malformed }
            let end = offset + Int(count)
            defer { offset = end }
            return Data(data[offset..<end])
        }

        mutating func skip(_ count: UInt64) throws { _ = try bytes(count) }
    }
}
