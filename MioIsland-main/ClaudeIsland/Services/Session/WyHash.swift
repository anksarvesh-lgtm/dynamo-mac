//
//  WyHash.swift
//  CodeIsland
//
//  Native Swift implementation of wyhash v4 final.
//  Matches Bun.hash() output exactly — no Bun dependency needed.
//

import Foundation

enum WyHash {
    private static let secret: [UInt64] = [
        0xa0761d6478bd642f, 0xe7037ed1a0b428db,
        0x8ebc6af09c88c6e3, 0x589965cc75374cc3
    ]

    private static func wymum(_ a: inout UInt64, _ b: inout UInt64) {
        let (hi, lo) = a.multipliedFullWidth(by: b)
        a = lo
        b = hi
    }

    private static func wymix(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var a = a, b = b
        wymum(&a, &b)
        return a ^ b
    }

    private static func wyr8(_ p: UnsafePointer<UInt8>) -> UInt64 {
        var v: UInt64 = 0
        memcpy(&v, p, 8)
        return v
    }

    private static func wyr4(_ p: UnsafePointer<UInt8>) -> UInt64 {
        var v: UInt32 = 0
        memcpy(&v, p, 4)
        return UInt64(v)
    }

    private static func wyr3(_ p: UnsafePointer<UInt8>, _ k: Int) -> UInt64 {
        return (UInt64(p[0]) << 16) | (UInt64(p[k >> 1]) << 8) | UInt64(p[k - 1])
    }

    /// Compute wyhash of a string, matching Bun.hash() exactly.
    static func hash(_ string: String, seed: UInt64 = 0) -> UInt64 {
        let bytes = Array(string.utf8)
        return hash(bytes: bytes, seed: seed)
    }

    /// Compute wyhash of raw bytes.
    static func hash(bytes: [UInt8], seed: UInt64 = 0) -> UInt64 {
        let len = bytes.count
        return bytes.withUnsafeBufferPointer { buf in
            guard let p = buf.baseAddress else { return 0 }
            var seed = seed ^ wymix(seed ^ secret[0], secret[1])
            var a: UInt64, b: UInt64

            if len <= 16 {
                if len >= 4 {
                    a = (wyr4(p) << 32) | wyr4(p + ((len >> 3) << 2))
                    b = (wyr4(p + len - 4) << 32) | wyr4(p + len - 4 - ((len >> 3) << 2))
                } else if len > 0 {
                    a = wyr3(p, len); b = 0
                } else {
                    a = 0; b = 0
                }
            } else if len <= 48 {
                a = wyr8(p) ^ secret[1]; b = wyr8(p + 8) ^ seed
                seed = wymix(a, b)
                if len > 16 {
                    a = wyr8(p + 16) ^ secret[2]; b = wyr8(p + 24) ^ seed
                    seed = wymix(a, b)
                }
                if len > 32 {
                    a = wyr8(p + 32) ^ secret[3]; b = wyr8(p + 40) ^ seed
                    seed = wymix(a, b)
                }
                a = wyr8(p + len - 16); b = wyr8(p + len - 8)
            } else {
                var i = len
                var pp = p
                if i > 48 {
                    var see1 = seed, see2 = seed
                    repeat {
                        seed = wymix(wyr8(pp) ^ secret[1], wyr8(pp + 8) ^ seed)
                        see1 = wymix(wyr8(pp + 16) ^ secret[2], wyr8(pp + 24) ^ see1)
                        see2 = wymix(wyr8(pp + 32) ^ secret[3], wyr8(pp + 40) ^ see2)
                        pp += 48; i -= 48
                    } while i > 48
                    seed ^= see1 ^ see2
                }
                while i > 16 {
                    seed = wymix(wyr8(pp) ^ secret[1], wyr8(pp + 8) ^ seed)
                    i -= 16; pp += 16
                }
                a = wyr8(pp + i - 16); b = wyr8(pp + i - 8)
            }

            a ^= secret[1]; b ^= seed
            wymum(&a, &b)
            return wymix(a ^ secret[0] ^ UInt64(len), b ^ secret[1])
        }
    }
}
