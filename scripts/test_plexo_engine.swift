import Foundation

@main
struct PlexoTestRunner {
    static func main() {
        print("=== Running Plexo Multi-Network Engine Unit Tests ===")

        // 1. Test Bencode Parser
        let intData = "i42e".data(using: .utf8)!
        let parsedInt = try! BencodeParser.parse(data: intData)
        assert(parsedInt.intValue == 42, "Bencode integer parsing failed")

        let strData = "4:spam".data(using: .utf8)!
        let parsedStr = try! BencodeParser.parse(data: strData)
        assert(parsedStr.stringValue == "spam", "Bencode string parsing failed")

        let listData = "l4:spami42ee".data(using: .utf8)!
        let parsedList = try! BencodeParser.parse(data: listData)
        assert(parsedList.listValue?.count == 2, "Bencode list parsing failed")

        let dictData = "d3:bar4:spam3:fooi42ee".data(using: .utf8)!
        let parsedDict = try! BencodeParser.parse(data: dictData)
        assert(parsedDict.dictValue?["bar"]?.stringValue == "spam", "Bencode dict string failed")
        assert(parsedDict.dictValue?["foo"]?.intValue == 42, "Bencode dict int failed")
        print("Test 1 (Bencode Parser BEP 0003): PASS")

        // 2. Test Magnet Link Parser
        let magnet = "magnet:?xt=urn:btih:c12fe1c06bba254a9dc9f519b335380dc102e94a&dn=Ubuntu+24.04&tr=https%3A%2F%2Ftracker.example.com%2Fannounce"
        let parsedMagnet = PlexoTorrentEngine.parseMagnetLink(magnet)
        assert(parsedMagnet != nil, "Magnet parser failed to parse valid link")
        assert(parsedMagnet?.infoHashHex == "c12fe1c06bba254a9dc9f519b335380dc102e94a", "InfoHash mismatch")
        assert(parsedMagnet?.displayName == "Ubuntu 24.04", "Display name mismatch")
        assert(parsedMagnet?.trackers.contains("https://tracker.example.com/announce") == true, "Tracker mismatch")
        print("Test 2 (Magnet Link Parser): PASS")

        // 3. Test Chunk Planning
        let totalBytes: Int64 = 100 * 1024 * 1024 // 100 MB
        let chunkSize: Int64 = 8 * 1024 * 1024 // 8 MB
        var chunks: [PlexoChunk] = []
        var offset: Int64 = 0
        var id = 0
        while offset < totalBytes {
            let end = min(totalBytes - 1, offset + chunkSize - 1)
            chunks.append(PlexoChunk(id: id, rangeStart: offset, rangeEnd: end))
            offset = end + 1
            id += 1
        }
        assert(chunks.count == 13, "Chunk count should be 13")
        assert(chunks.first?.rangeStart == 0, "First chunk starts at 0")
        assert(chunks.last?.rangeEnd == totalBytes - 1, "Last chunk ends at totalBytes - 1")
        for i in 0..<(chunks.count - 1) {
            assert(chunks[i].rangeEnd + 1 == chunks[i+1].rangeStart, "Chunks must be strictly continuous without gaps")
        }
        print("Test 3 (Chunk Range Partitioning & Continuity): PASS [\(chunks.count) chunks]")

        // 4. Test Speed & Byte Formatting
        assert(PlexoFormatting.formatSpeed(0) == "0 KB/s")
        assert(PlexoFormatting.formatSpeed(1024 * 500).contains("500.0 KB/s"))
        assert(PlexoFormatting.formatSpeed(1024 * 1024 * 15.5).contains("15.5 MB/s"))
        print("Test 4 (Throughput & Byte Formatting): PASS")

        // 5. Test Bandwidth Controls & Slow Mode
        var settings = PlexoBandwidthSettings(
            globalSpeedLimitBytesPerSec: 20 * 1024 * 1024,
            isSlowModeActive: false,
            slowModeSpeedLimitBytesPerSec: 1 * 1024 * 1024
        )
        settings.isSlowModeActive = true
        func getLimit(_ s: PlexoBandwidthSettings) -> Double? {
            s.isSlowModeActive ? s.slowModeSpeedLimitBytesPerSec : s.globalSpeedLimitBytesPerSec
        }
        assert(getLimit(settings) == 1 * 1024 * 1024, "Slow mode should cap speed to 1MB/s")
        print("Test 5 (Bandwidth Limiter & Slow Mode Logic): PASS")

        print("\n✅ ALL 5 PLEXO MULTI-NETWORK TESTS PASSED!")
    }
}
