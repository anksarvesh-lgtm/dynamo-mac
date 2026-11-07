// SPDX-License-Identifier: MIT
import Foundation
import NotchCore
import SQLite3
import Testing

@testable import NotchFeatures

@MainActor
struct NetworkTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "Network-\(UUID().uuidString)")
    private let defaults = UserDefaults(suiteName: "Network.\(UUID().uuidString)")!

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    @Test func theCountersComeFromThisMacsOwnInterfaces() {
        let counters = InterfaceCounters.read()
        #expect(counters.keys.contains { $0.hasPrefix("en") }, "Wi-Fi or Ethernet")
        #expect(!counters.keys.contains { $0 == "lo0" || $0.hasPrefix("utun") || $0.hasPrefix("awdl") })
    }

    @Test func whatMovedCountsRestartedInterfacesAndSkipsNewOnes() {
        let before = ["en0": Traffic(down: 1_000, up: 100), "en5": Traffic(down: 9_000, up: 900)]
        let after = [
            "en0": Traffic(down: 1_500, up: 160),  // grew
            "en5": Traffic(down: 300, up: 30),  // came back up: counts from zero
            "pdp_ip0": Traffic(down: 7_000, up: 700),  // just appeared: next time
        ]
        #expect(InterfaceCounters.moved(from: before, to: after) == Traffic(down: 800, up: 90))
    }

    /// India is 5:30 ahead of UTC, so its hours start at half past the UTC hour.
    @Test func aGapIsSharedAmongTheLocalHoursItSpans() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Kolkata"))
        let ten = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 10)))
        let parts = NetworkFeature.spread(
            Traffic(down: 900, up: 91), from: ten + 45 * 60, to: ten + 135 * 60, calendar: calendar)
        #expect(parts[ten] == Traffic(down: 150, up: 15))
        #expect(parts[ten + 3600] == Traffic(down: 600, up: 60))
        #expect(parts[ten + 7200] == Traffic(down: 150, up: 16), "the last hour takes the rounding")
        let withinAnHour = NetworkFeature.spread(Traffic(down: 5), from: ten + 60, to: ten + 120, calendar: calendar)
        #expect(withinAnHour == [ten: Traffic(down: 5)])
    }

    @Test func onlyASustainedTransferShowsAndAQuietSpellHidesIt() {
        var watch = TransferWatch()
        for _ in 0..<3 { watch.observe(30_000_000, over: 1) }  // a page load's burst
        watch.observe(0, over: 1)
        #expect(!watch.showing && !watch.isBusy)
        for _ in 0..<4 { watch.observe(2_000_000, over: 1) }
        #expect(watch.showing)
        for _ in 0..<4 { watch.observe(100_000, over: 1) }
        watch.observe(2_000_000, over: 1)  // it picks up again before 5 quiet seconds
        for _ in 0..<4 { watch.observe(0, over: 1) }
        #expect(watch.showing)
        watch.observe(0, over: 1)
        #expect(!watch.showing)
    }

    @Test func readingsAreRareUnlessASpeedIsOnScreen() throws {
        let now = try #require(Calendar.current.date(bySettingHour: 10, minute: 59, second: 30, of: .now))
        #expect(NetworkFeature.interval(phase: .background, closedNotch: .off, busy: false, now: now) == 31)
        #expect(NetworkFeature.interval(phase: .background, closedNotch: .transfers, busy: false, now: now) == 3)
        #expect(NetworkFeature.interval(phase: .background, closedNotch: .transfers, busy: true, now: now) == 1)
        #expect(NetworkFeature.interval(phase: .background, closedNotch: .always, busy: false, now: now) == 1)
        #expect(NetworkFeature.interval(phase: .foreground, closedNotch: .off, busy: false, now: now) == 1)
    }

    @Test func speedsReadLikeNetSpeedsAndBytesLikeFinders() {
        #expect(NetworkFeature.speed(9_800) == ("9.8", "KB/s"))
        #expect(NetworkFeature.speed(999_600) == ("1.0", "MB/s"))
        #expect(NetworkFeature.speed(12_400_000) == ("12", "MB/s"))
        #expect(NetworkFeature.speed(-5) == ("0.0", "KB/s"))
        #expect(NetworkFeature.bytes(0) == "0 KB")
        #expect(NetworkFeature.bytes(500_900_000) == "501 MB")
        #expect(NetworkFeature.bytes(2_100_000_000) == "2.1 GB")
        #expect(NetworkFeature.bytes(262_018_343_936) == "262 GB")
    }

    /// A download: shown on the closed notch once it's sustained, a word on what it moved when it's
    /// done, and its bytes in the history.
    @Test func aDownloadShowsOnTheClosedNotchAndEndsUpInTheHistory() {
        var counters = ["en0": Traffic(down: 1_000, up: 1_000)]
        let network = NetworkFeature(
            defaults: defaults, storeURL: folder.appending(path: "network.sqlite"), netSpeedURL: nil,
            readCounters: { counters })
        var shown: [Activity?] = []
        var announced: [Activity] = []
        network.onOngoing = { shown.append($0) }
        network.onActivity = { announced.append($0) }
        let start = Date.now - 60
        network.receive(counters, at: start)
        for second in 1...8 {
            counters["en0"]?.down += 20_000_000
            network.receive(counters, at: start + TimeInterval(second))
        }
        #expect(network.rate == Rate(down: 20_000_000, up: 0))
        #expect(shown.count == 1 && shown.last??.title == "20 MB/s" && shown.last??.symbol == "arrow.down.circle.fill")
        for second in 9...14 { network.receive(counters, at: start + TimeInterval(second)) }
        #expect(shown.map { $0?.title } == ["20 MB/s", "0.0 KB/s", nil], "the stall shows, then it hides")
        #expect(announced.map(\.title) == ["Downloaded 160 MB"])

        network.phase = .foreground  // loads the chart
        #expect(network.buckets.count == 24)
        #expect(network.buckets.reduce(0) { $0 + $1.traffic.down } == 160_000_000)
        network.phase = .stopped
        #expect(!network.isPolling && network.recent.isEmpty)
        network.refreshTotals()
        #expect(network.lifetime.down == 160_000_000, "stopping wrote the hour to disk")
    }

    /// NetSpeed kept a row a minute; they come in by the hour, once, and only into an empty history.
    @Test func netSpeedsHistoryComesAlongOnce() throws {
        let netSpeed = folder.appending(path: "history.sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(netSpeed.path, &db) == SQLITE_OK)
        let hour = NetworkFeature.hour(of: .now - 3 * 3600)
        let minutes = [(hour, 100), (hour + 60, 200), (hour + 3600, 400)].map { date, bytes in
            "(\(Int(date.timeIntervalSince1970)), \(bytes), 1)"
        }
        sqlite3_exec(db, "CREATE TABLE samples (ts INTEGER PRIMARY KEY, down INTEGER, up INTEGER)", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO samples VALUES \(minutes.joined(separator: ","))", nil, nil, nil)
        sqlite3_close(db)

        func feature() -> NetworkFeature {
            NetworkFeature(
                defaults: defaults, storeURL: folder.appending(path: "network.sqlite"), netSpeedURL: netSpeed,
                readCounters: { [:] })
        }
        let network = feature()
        network.phase = .foreground
        let bars = network.buckets.filter { $0.traffic.total > 0 }
        #expect(bars.map(\.start) == [hour, hour + 3600])
        #expect(bars.map(\.traffic.down) == [300, 400])
        network.phase = .stopped

        let again = feature()
        again.phase = .background
        again.refreshTotals()
        #expect(again.lifetime == Traffic(down: 700, up: 3), "imported once")
        again.phase = .stopped
    }
}
