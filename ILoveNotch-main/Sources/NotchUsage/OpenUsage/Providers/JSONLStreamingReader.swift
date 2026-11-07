// SPDX-License-Identifier: MIT
// Adapted from OpenUsage (https://github.com/robinebers/openusage) at 4ce7887.
// Copyright (c) Robin Ebers and contributors. MIT License; see THIRD_PARTY_NOTICES.md.
// swift-format-ignore-file

import Foundation

/// Reads local provider logs in bounded batches without ever materializing an entire rollout.
/// Complete records stay together, so existing provider parsers can keep accepting JSONL `Data`.
enum JSONLStreamingReader {
    static let readChunkBytes = 64 * 1024
    static let maximumRecordBytes = 1024 * 1024

    struct Result<Item: Sendable>: Sendable {
        var items: [Item]?
        var oversizedRecordCount: Int
    }

    static func read<Item: Sendable, State: Sendable>(
        path: String,
        initialState: State,
        parse: @Sendable (Data, inout State) -> [Item]?
    ) throws -> Result<Item> {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }

        var state = initialState
        var items: [Item] = []
        var pendingRecord = Data()
        var batch = Data()
        var oversizedRecordCount = 0
        var discardingOversizedRecord = false
        var readAnyBytes = false

        func flushBatch() throws -> Bool {
            guard !batch.isEmpty else { return true }
            try Task.checkCancellation()
            guard let parsed = autoreleasepool(invoking: { parse(batch, &state) }) else { return false }
            items.append(contentsOf: parsed)
            batch.removeAll(keepingCapacity: batch.count <= readChunkBytes)
            return true
        }

        func finishRecord(terminated: Bool) throws -> Bool {
            guard !discardingOversizedRecord else {
                discardingOversizedRecord = false
                return true
            }

            let recordBytes = pendingRecord.count + (terminated ? 1 : 0)
            if !batch.isEmpty, batch.count + recordBytes > readChunkBytes {
                guard try flushBatch() else { return false }
            }

            batch.append(pendingRecord)
            if terminated { batch.append(UInt8(ascii: "\n")) }
            pendingRecord.removeAll(keepingCapacity: pendingRecord.count <= readChunkBytes)

            if batch.count >= readChunkBytes {
                return try flushBatch()
            }
            return true
        }

        while true {
            try Task.checkCancellation()
            // A whole-file read is one job, so nothing drains autoreleased chunks (or the parser's
            // JSONSerialization objects, above) until it ends: an 80 MB log held ~120 MB. Drain per chunk.
            guard let chunk = try autoreleasepool(invoking: { try handle.read(upToCount: readChunkBytes) }),
                  !chunk.isEmpty
            else { break }
            readAnyBytes = true

            var offset = chunk.startIndex
            while offset < chunk.endIndex {
                let newline = chunk[offset..<chunk.endIndex].firstIndex(of: UInt8(ascii: "\n"))
                let end = newline ?? chunk.endIndex
                let fragment = chunk[offset..<end]

                if !discardingOversizedRecord {
                    if fragment.count > maximumRecordBytes - pendingRecord.count {
                        oversizedRecordCount += 1
                        discardingOversizedRecord = true
                        pendingRecord.removeAll(keepingCapacity: false)
                    } else {
                        pendingRecord.append(contentsOf: fragment)
                    }
                }

                if let newline {
                    guard try finishRecord(terminated: true) else {
                        return Result(items: nil, oversizedRecordCount: oversizedRecordCount)
                    }
                    offset = chunk.index(after: newline)
                } else {
                    offset = chunk.endIndex
                }
            }
        }

        if !discardingOversizedRecord, !pendingRecord.isEmpty {
            guard try finishRecord(terminated: false) else {
                return Result(items: nil, oversizedRecordCount: oversizedRecordCount)
            }
        }
        guard try flushBatch() else {
            return Result(items: nil, oversizedRecordCount: oversizedRecordCount)
        }

        if !readAnyBytes {
            guard let parsed = parse(Data(), &state) else {
                return Result(items: nil, oversizedRecordCount: oversizedRecordCount)
            }
            items.append(contentsOf: parsed)
        }

        return Result(items: items, oversizedRecordCount: oversizedRecordCount)
    }
}

struct JSONLStatelessParserState: Sendable {}
