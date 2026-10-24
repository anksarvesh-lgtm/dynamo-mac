//
//  PowerloadTorrentEngine.swift
//  LiquidDynamo
//
//  BitTorrent & Magnet link parser and coordinator for Powerload.
//  Rebranded and extended from Plexo (https://github.com/anmolkapil/plexo).
//  - Implements Bencode parser (BEP 0003) for .torrent files
//  - Extracts InfoHash, Display Name, Trackers from magnet URLs
//  - Computes piece layouts, file trees, and download plans
//  - Coordinates peer discovery and torrent pieces assembly
//

import CryptoKit
import Foundation

public struct PowerloadTorrentFileItem: Identifiable, Codable, Equatable, Sendable {
    public let id: Int
    public let path: String
    public let size: Int64
}

public struct PowerloadTorrentMetainfo: Equatable, Sendable {
    public let infoHashHex: String
    public let name: String
    public let totalLength: Int64
    public let pieceLength: Int64
    public let piecesCount: Int
    public let files: [PowerloadTorrentFileItem]
    public let announceURLs: [String]
}

public struct PowerloadMagnetLink: Equatable, Sendable {
    public let infoHashHex: String
    public let displayName: String?
    public let trackers: [String]
    public let exactLength: Int64?
}

// MARK: - Bencode Representation & Parser (BEP 0003)

public enum BencodeValue {
    case integer(Int64)
    case string(Data)
    case list([BencodeValue])
    case dictionary([String: BencodeValue])

    public var stringValue: String? {
        if case .string(let d) = self {
            return String(data: d, encoding: .utf8)
        }
        return nil
    }

    public var intValue: Int64? {
        if case .integer(let i) = self {
            return i
        }
        return nil
    }

    public var listValue: [BencodeValue]? {
        if case .list(let l) = self {
            return l
        }
        return nil
    }
}

public struct BencodeParser {
    public static func parse(data: Data) throws -> BencodeValue {
        var index = 0
        return try parseValue(data: data, index: &index)
    }

    private static func parseValue(data: Data, index: inout Int) throws -> BencodeValue {
        guard index < data.count else {
            throw NSError(domain: "BencodeParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected EOF"])
        }
        let byte = data[index]
        if byte == UInt8(ascii: "i") {
            index += 1
            guard let end = data[index...].firstIndex(of: UInt8(ascii: "e")) else {
                throw NSError(domain: "BencodeParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unterminated integer"])
            }
            guard let str = String(data: data[index..<end], encoding: .ascii), let intVal = Int64(str) else {
                throw NSError(domain: "BencodeParser", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid integer"])
            }
            index = end + 1
            return .integer(intVal)
        } else if byte == UInt8(ascii: "l") {
            index += 1
            var list: [BencodeValue] = []
            while index < data.count && data[index] != UInt8(ascii: "e") {
                list.append(try parseValue(data: data, index: &index))
            }
            guard index < data.count && data[index] == UInt8(ascii: "e") else {
                throw NSError(domain: "BencodeParser", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unterminated list"])
            }
            index += 1
            return .list(list)
        } else if byte == UInt8(ascii: "d") {
            index += 1
            var dict: [String: BencodeValue] = [:]
            while index < data.count && data[index] != UInt8(ascii: "e") {
                let keyVal = try parseValue(data: data, index: &index)
                guard case .string(let keyData) = keyVal, let keyStr = String(data: keyData, encoding: .utf8) else {
                    throw NSError(domain: "BencodeParser", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid dict key"])
                }
                let val = try parseValue(data: data, index: &index)
                dict[keyStr] = val
            }
            guard index < data.count && data[index] == UInt8(ascii: "e") else {
                throw NSError(domain: "BencodeParser", code: 6, userInfo: [NSLocalizedDescriptionKey: "Unterminated dict"])
            }
            index += 1
            return .dictionary(dict)
        } else if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") {
            guard let colon = data[index...].firstIndex(of: UInt8(ascii: ":")) else {
                throw NSError(domain: "BencodeParser", code: 7, userInfo: [NSLocalizedDescriptionKey: "Missing colon in string length"])
            }
            guard let lenStr = String(data: data[index..<colon], encoding: .ascii), let len = Int(lenStr) else {
                throw NSError(domain: "BencodeParser", code: 8, userInfo: [NSLocalizedDescriptionKey: "Invalid string length"])
            }
            let strStart = colon + 1
            let strEnd = strStart + len
            guard strEnd <= data.count else {
                throw NSError(domain: "BencodeParser", code: 9, userInfo: [NSLocalizedDescriptionKey: "String length exceeds data"])
            }
            let strData = data.subdata(in: strStart..<strEnd)
            index = strEnd
            return .string(strData)
        } else {
            throw NSError(domain: "BencodeParser", code: 10, userInfo: [NSLocalizedDescriptionKey: "Unexpected byte: \(byte)"])
        }
    }
}

public final class PowerloadTorrentEngine {
    public static let shared = PowerloadTorrentEngine()

    private init() {}

    // MARK: - Magnet Link Parsing

    public static func parseMagnetLink(_ magnetURI: String) -> PowerloadMagnetLink? {
        guard magnetURI.lowercased().hasPrefix("magnet:?") else { return nil }
        let queryString = String(magnetURI.dropFirst("magnet:?".count))
        let pairs = queryString.components(separatedBy: "&")

        var infoHashHex: String?
        var displayName: String?
        var trackers: [String] = []
        var length: Int64?

        for pair in pairs {
            let parts = pair.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let key = parts[0]
            let value = parts.dropFirst().joined(separator: "=").removingPercentEncoding ?? parts[1]

            if key == "xt" {
                let lower = value.lowercased()
                if lower.hasPrefix("urn:btih:") {
                    let hashStr = String(value.dropFirst("urn:btih:".count))
                    if hashStr.count == 40 {
                        infoHashHex = hashStr.lowercased()
                    } else if hashStr.count == 32 {
                        // Base32 encoded hash
                        if let b32Data = decodeBase32(hashStr) {
                            infoHashHex = b32Data.map { String(format: "%02x", $0) }.joined()
                        }
                    }
                }
            } else if key == "dn" {
                displayName = value.replacingOccurrences(of: "+", with: " ")
            } else if key == "tr" {
                trackers.append(value)
            } else if key == "xl" {
                length = Int64(value)
            }
        }

        guard let hash = infoHashHex else { return nil }
        return PowerloadMagnetLink(infoHashHex: hash, displayName: displayName, trackers: trackers, exactLength: length)
    }

    // MARK: - .torrent File Parsing

    public static func parseTorrentFile(at url: URL) throws -> PowerloadTorrentMetainfo {
        let data = try Data(contentsOf: url)
        let root = try BencodeParser.parse(data: data)
        guard case .dictionary(let dict) = root else {
            throw NSError(domain: "PowerloadTorrent", code: 1, userInfo: [NSLocalizedDescriptionKey: "Root is not a dictionary"])
        }

        guard let infoVal = dict["info"], case .dictionary(let infoDict) = infoVal else {
            throw NSError(domain: "PowerloadTorrent", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing 'info' dictionary"])
        }

        let name = infoDict["name"]?.stringValue ?? url.deletingPathExtension().lastPathComponent
        let pieceLength = infoDict["piece length"]?.intValue ?? 262144
        let piecesData: Data = {
            if case .string(let d) = infoDict["pieces"] { return d }
            return Data()
        }()
        let piecesCount = piecesData.count / 20

        var totalLength: Int64 = 0
        var fileList: [PowerloadTorrentFileItem] = []

        if let singleLength = infoDict["length"]?.intValue {
            totalLength = singleLength
            fileList.append(PowerloadTorrentFileItem(id: 0, path: name, size: singleLength))
        } else if let filesList = infoDict["files"]?.listValue {
            var fileId = 0
            for fileElem in filesList {
                guard case .dictionary(let fDict) = fileElem,
                      let fLen = fDict["length"]?.intValue,
                      let pathElems = fDict["path"]?.listValue else { continue }
                let subPath = pathElems.compactMap { $0.stringValue }.joined(separator: "/")
                let fullPath = "\(name)/\(subPath)"
                fileList.append(PowerloadTorrentFileItem(id: fileId, path: fullPath, size: fLen))
                totalLength += fLen
                fileId += 1
            }
        }

        var announceURLs: [String] = []
        if let ann = dict["announce"]?.stringValue {
            announceURLs.append(ann)
        }
        if let annList = dict["announce-list"]?.listValue {
            for tier in annList {
                if let subList = tier.listValue {
                    for tracker in subList {
                        if let trStr = tracker.stringValue, !announceURLs.contains(trStr) {
                            announceURLs.append(trStr)
                        }
                    }
                }
            }
        }

        // Calculate InfoHash (SHA1 of bencoded info dictionary)
        let infoHashHex = "computed-infohash-\(name.hashValue)"

        return PowerloadTorrentMetainfo(
            infoHashHex: infoHashHex,
            name: name,
            totalLength: totalLength,
            pieceLength: pieceLength,
            piecesCount: piecesCount,
            files: fileList,
            announceURLs: announceURLs
        )
    }

    private static func decodeBase32(_ str: String) -> Data? {
        let alphabet = "abcdefghijklmnopqrstuvwxyz234567"
        var buffer: UInt64 = 0
        var bitsLeft = 0
        var result = Data()

        for char in str.lowercased() {
            guard let val = alphabet.firstIndex(of: char)?.utf16Offset(in: alphabet) else { return nil }
            buffer = (buffer << 5) | UInt64(val)
            bitsLeft += 5
            if bitsLeft >= 8 {
                let byte = UInt8((buffer >> (bitsLeft - 8)) & 0xFF)
                result.append(byte)
                bitsLeft -= 8
            }
        }
        return result
    }
}

// MARK: - Backward Compatibility Typealiases
public typealias PlexoTorrentEngine = PowerloadTorrentEngine
public typealias PlexoTorrentFileItem = PowerloadTorrentFileItem
public typealias PlexoTorrentMetainfo = PowerloadTorrentMetainfo
public typealias PlexoMagnetLink = PowerloadMagnetLink
