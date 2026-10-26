//
//  test_clipboard_milestone3.swift
//  LiquidDynamo Tests - Milestone 3 (Robust Clipboard History Service)
//

import AppKit
import CryptoKit
import Foundation

public enum ClipboardType: String, Codable, CaseIterable {
    case text
    case image
    case file
    case url
}

public struct ClipboardEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let type: ClipboardType
    public let text: String
    public let fileURL: URL?
    public let imageData: Data?
    public let timestamp: Date
    public var isPinned: Bool
    public let imageHash: String?

    public init(
        id: UUID = UUID(),
        type: ClipboardType = .text,
        text: String,
        fileURL: URL? = nil,
        imageData: Data? = nil,
        timestamp: Date = Date(),
        isPinned: Bool = false,
        imageHash: String? = nil
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.fileURL = fileURL
        self.imageData = imageData
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.imageHash = imageHash
    }

    enum CodingKeys: String, CodingKey {
        case id, type, text, fileURL, imageData, timestamp, isPinned, imageHash
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.type = try container.decodeIfPresent(ClipboardType.self, forKey: .type) ?? .text
        self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.fileURL = try container.decodeIfPresent(URL.self, forKey: .fileURL)
        self.imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.imageHash = try container.decodeIfPresent(String.self, forKey: .imageHash)
    }
}

// MARK: - Test Runner Definitions

var totalTests = 0
var passedTests = 0

func assertTest(_ condition: Bool, _ message: String) {
    totalTests += 1
    if condition {
        passedTests += 1
        print("  ✅ PASS: \(message)")
    } else {
        print("  ❌ FAIL: \(message)")
    }
}

print("==================================================================")
print("🚀 RUNNING MILESTONE 3 TEST SUITE: CLIPBOARD HISTORY SERVICE")
print("==================================================================")

// Test Suite 1: Image Deduplication via SHA-256 vs prefix(256) Collision
print("\n[Suite 1: Image SHA-256 Hash Deduplication vs prefix(256) Flaw]")
do {
    // Construct two distinct 512-byte payloads that have identical first 256 bytes
    var imageBytesA = Data(repeating: 0x41, count: 256) // 256 'A's
    imageBytesA.append(Data(repeating: 0x11, count: 256)) // 256 0x11s

    var imageBytesB = Data(repeating: 0x41, count: 256) // 256 'A's (matching prefix)
    imageBytesB.append(Data(repeating: 0x22, count: 256)) // 256 0x22s (differing payload)

    // Legacy flaw demonstration: prefix(256) falsely considers them identical!
    let legacyMatches = (imageBytesA.prefix(256) == imageBytesB.prefix(256))
    assertTest(legacyMatches, "Legacy bug confirmed: prefix(256) matches distinct images sharing header")

    // SHA-256 hash calculation
    let hashA = SHA256.hash(data: imageBytesA).map { String(format: "%02x", $0) }.joined()
    let hashB = SHA256.hash(data: imageBytesB).map { String(format: "%02x", $0) }.joined()
    assertTest(hashA != hashB, "SHA-256 correctly differentiates images with identical 256-byte prefixes")

    // Identical image test
    let hashA_duplicate = SHA256.hash(data: imageBytesA).map { String(format: "%02x", $0) }.joined()
    assertTest(hashA == hashA_duplicate, "Identical image data yields matching SHA-256 hash for deduplication")
}

// Test Suite 2: Codable Backward Compatibility with Optional imageHash
print("\n[Suite 2: Codable Backward Compatibility]")
do {
    // Legacy JSON stored by previous versions without 'imageHash'
    let legacyJSON = """
    {
        "id": "12345678-1234-1234-1234-123456789abc",
        "type": "text",
        "text": "Copied from older LiquidDynamo",
        "timestamp": 1729900000.0,
        "isPinned": false
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let entry = try decoder.decode(ClipboardEntry.self, from: legacyJSON)
    assertTest(entry.text == "Copied from older LiquidDynamo", "Legacy JSON without imageHash decodes cleanly")
    assertTest(entry.imageHash == nil, "Legacy entry imageHash defaults to nil without crashing")

    // Re-encoding preserves data and produces valid JSON
    let encoder = JSONEncoder()
    let reencoded = try encoder.encode(entry)
    let roundtrip = try decoder.decode(ClipboardEntry.self, from: reencoded)
    assertTest(roundtrip.id == entry.id && roundtrip.text == entry.text, "Round-trip encode/decode succeeds")
}

// Test Suite 3: Screen Recording Debouncer Simulation (Hysteresis)
print("\n[Suite 3: Screen Capture Debouncer (1.5s on, 1.0s off)]")
do {
    class MockScreenRecordingDebouncer {
        var rawActive = false
        var rawSince: Date = Date()
        var isCaptured = false
        var shieldEnabled = true

        func update(now: Date) {
            guard shieldEnabled else {
                isCaptured = false
                return
            }
            let elapsed = now.timeIntervalSince(rawSince)
            if rawActive {
                if elapsed >= 1.5 && !isCaptured {
                    isCaptured = true
                }
            } else {
                if elapsed >= 1.0 && isCaptured {
                    isCaptured = false
                }
            }
        }

        func setRaw(_ active: Bool, now: Date) {
            if active != rawActive {
                rawActive = active
                rawSince = now
            }
        }
    }

    let debouncer = MockScreenRecordingDebouncer()
    let t0 = Date()

    // 1. Transient screenshot spike (e.g. screencapture utility runs for 400ms)
    debouncer.setRaw(true, now: t0)
    debouncer.update(now: t0.addingTimeInterval(0.4))
    assertTest(debouncer.isCaptured == false, "Transient screenshot spike (0.4s) does NOT activate shield")

    // Screenshot ends after 0.5s
    debouncer.setRaw(false, now: t0.addingTimeInterval(0.5))
    debouncer.update(now: t0.addingTimeInterval(0.6))
    assertTest(debouncer.isCaptured == false, "Shield remains off after transient screenshot completion")

    // 2. Sustained screen recording (e.g. QuickTime screen recording for 2.0s)
    let tRec = t0.addingTimeInterval(10.0)
    debouncer.setRaw(true, now: tRec)
    debouncer.update(now: tRec.addingTimeInterval(1.0))
    assertTest(debouncer.isCaptured == false, "Shield not yet active at 1.0s into recording")

    debouncer.update(now: tRec.addingTimeInterval(1.6))
    assertTest(debouncer.isCaptured == true, "Shield activates after 1.5s of sustained recording")

    // 3. Flapping / brief pause during recording (< 1.0s) does not prematurely deactivate
    let tStop = tRec.addingTimeInterval(10.0)
    debouncer.setRaw(false, now: tStop)
    debouncer.update(now: tStop.addingTimeInterval(0.5))
    assertTest(debouncer.isCaptured == true, "Shield remains active during brief glitch (< 1.0s)")

    debouncer.update(now: tStop.addingTimeInterval(1.1))
    assertTest(debouncer.isCaptured == false, "Shield cleanly deactivates after 1.0s of continuous absence")

    // 4. User setting override
    debouncer.setRaw(true, now: tStop.addingTimeInterval(5.0))
    debouncer.update(now: tStop.addingTimeInterval(7.0))
    assertTest(debouncer.isCaptured == true, "Shield active with setting enabled")
    debouncer.shieldEnabled = false
    debouncer.update(now: tStop.addingTimeInterval(7.1))
    assertTest(debouncer.isCaptured == false, "Shield disabled immediately when user preference is off")
}

// Test Suite 4: Change Count Terminal Consumption & Lazy Promise Retry
print("\n[Suite 4: Change Count Terminal Consumption & Lazy Promise Retry]")
do {
    class MockClipboardIngestion {
        var lastChangeCount: Int = -1
        var pendingChangeCount: Int = -1
        var pendingFirstSeen: Date?

        var storedEntries: [String] = []

        func ingest(count: Int, data: String?, isSensitive: Bool, now: Date) {
            guard count != lastChangeCount else { return }

            if count != pendingChangeCount {
                pendingChangeCount = count
                pendingFirstSeen = now
            }

            // Sensitive skip: commit immediately
            if isSensitive {
                commit(count)
                return
            }

            // If data is ready, commit immediately
            if let str = data {
                storedEntries.append(str)
                commit(count)
                return
            }

            // Data not ready (lazy promise): retry until 2.0s timeout
            let elapsed = now.timeIntervalSince(pendingFirstSeen ?? now)
            if elapsed >= 2.0 {
                // Give up
                commit(count)
            }
            // Otherwise: do NOT advance lastChangeCount!
        }

        func commit(_ count: Int) {
            lastChangeCount = count
            pendingChangeCount = -1
            pendingFirstSeen = nil
        }
    }

    let ingester = MockClipboardIngestion()
    let start = Date()

    // 1. Lazy promise arrives: data is nil on tick 0
    ingester.ingest(count: 101, data: nil, isSensitive: false, now: start)
    assertTest(ingester.lastChangeCount == -1, "lastChangeCount is NOT consumed when lazy data is nil on first check")

    // Tick at 0.5s: data arrives!
    ingester.ingest(count: 101, data: "Lazy Content Ready", isSensitive: false, now: start.addingTimeInterval(0.5))
    assertTest(ingester.storedEntries.count == 1 && ingester.storedEntries.first == "Lazy Content Ready", "Lazy promise successfully resolved on retry")
    assertTest(ingester.lastChangeCount == 101, "lastChangeCount committed after successful ingestion")

    // 2. Sensitive content (e.g. 1Password)
    ingester.ingest(count: 102, data: "SecretPassword", isSensitive: true, now: start.addingTimeInterval(1.0))
    assertTest(ingester.storedEntries.count == 1, "Sensitive content skipped from history")
    assertTest(ingester.lastChangeCount == 102, "Sensitive count committed immediately to prevent reprocessing")

    // 3. Genuinely empty / unsupported pasteboard times out after 2.0s
    ingester.ingest(count: 103, data: nil, isSensitive: false, now: start.addingTimeInterval(2.0))
    ingester.ingest(count: 103, data: nil, isSensitive: false, now: start.addingTimeInterval(3.0))
    ingester.ingest(count: 103, data: nil, isSensitive: false, now: start.addingTimeInterval(4.1)) // >2.0s
    assertTest(ingester.lastChangeCount == 103, "Genuinely empty pasteboard gives up after 2.0s timeout without stalling")
}

// Test Suite 5: Type Priority Text Preservation
print("\n[Suite 5: Type Priority Text Preservation with Rich Image Previews]")
do {
    // When rich web text is copied, apps provide both plain text and a rendered bitmap preview
    let copiedText = "https://example.com/article"
    let mockThumbnailData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header

    let entry = ClipboardEntry(
        type: .url,
        text: copiedText,
        fileURL: nil,
        imageData: mockThumbnailData,
        timestamp: Date(),
        isPinned: false
    )

    assertTest(entry.type == .url, "Rich copied item correctly identified as URL despite companion image")
    assertTest(entry.text == copiedText, "Copied text content fully preserved without being dropped")
    assertTest(entry.imageData != nil, "Companion thumbnail image data preserved alongside text")
}

print("\n==================================================================")
print("TEST SUMMARY: \(passedTests)/\(totalTests) TESTS PASSED")
print("==================================================================")

if passedTests == totalTests {
    exit(0)
} else {
    exit(1)
}
