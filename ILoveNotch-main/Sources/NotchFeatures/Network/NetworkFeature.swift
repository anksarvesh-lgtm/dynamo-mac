// SPDX-License-Identifier: MIT
import Foundation
import NotchCore
import Observation
import SwiftUI

/// Bytes a second, down and up.
public struct Rate: Hashable, Sendable {
    public var down: Double = 0
    public var up: Double = 0
}

/// A rate and when it was read, for the live graph.
public struct RateSample: Hashable, Sendable {
    public var at: Date
    public var rate: Rate
}

/// Network speed as it happens, and a history of what this Mac downloads and uploads: NetSpeed's
/// menu bar app, absorbed into the notch, with its history brought along.
///
/// macOS has no event for bytes moving, so this is the app's second deliberate poll, and each
/// reading is one list of counters (20 µs). It reads every second while a speed is on screen (the
/// tab, or the closed notch during a transfer), every 3 seconds while the closed notch waits for a
/// transfer, and otherwise once an hour, on the hour, to keep each hour's bytes in their hour. It
/// stops with the notch (sleep, display sleep, lock) and when the tab is off. The counters keep
/// counting while it's stopped, so it shares what moved meanwhile among those hours when it starts.
@MainActor
@Observable
public final class NetworkFeature: NotchFeature {
    /// When the closed notch shows the speed beside it, over the menu bar, in the order macOS offers
    /// its own menu bar items.
    public enum ClosedNotch: String, CaseIterable, Identifiable, Sendable {
        case always, transfers, off

        public var id: Self { self }

        public var title: String {
            switch self {
            case .always: "Always"
            case .transfers: "While Downloading"
            case .off: "Never"
            }
        }
    }

    public let id = FeatureID.network
    public var phase: FeaturePhase = .stopped {
        didSet { if phase != oldValue { update() } }
    }
    /// Whether the tab is on. Off, it forgets where the counters stood, so nothing that moves while
    /// it's off is counted when it comes back.
    public var isEnabled = true {
        didSet { if !isEnabled { last = nil } }
    }
    /// Per-feature setting: when the closed notch shows the speed.
    public var closedNotch: ClosedNotch {
        didSet {
            defaults.set(closedNotch.rawValue, forKey: Self.closedNotchKey)
            update()
        }
    }
    /// The history chart's range.
    public var range: HistoryRange {
        didSet {
            defaults.set(range.rawValue, forKey: Self.rangeKey)
            if phase == .foreground { reload() }
        }
    }
    /// The speed at the latest reading.
    public private(set) var rate = Rate()
    /// The last minute of speeds, oldest first.
    public private(set) var recent: [RateSample] = []
    /// Everything recorded, from disk, as of the tab's last look.
    public private(set) var lifetime = Traffic()
    /// Raised when a transfer the closed notch showed finishes: what it moved.
    @ObservationIgnored public var onActivity: ((Activity) -> Void)?
    /// Shows the speed on the closed notch; nil once it shouldn't.
    @ObservationIgnored public var onOngoing: ((Activity?) -> Void)?

    /// The range's bars from disk, without the traffic still in memory.
    private var stored: [TrafficBucket] = []
    /// Traffic not written yet, by the hour it moved in.
    private var pending: [Date: Traffic] = [:]

    // ponytail: a rate needs a sampling interval; over a longer gap (sleep, an hour's wait) the
    // bytes only go to the history. Half a second is the shortest a rate isn't noise.
    nonisolated static let shortest: TimeInterval = 0.5
    nonisolated static let longest: TimeInterval = 5
    /// How much of the recent past the live graph shows.
    nonisolated static let window: TimeInterval = 60
    /// A transfer this big gets a word when it finishes.
    nonisolated static let announced: Int64 = 50_000_000
    private static let closedNotchKey = "network.closedNotch"
    private static let rangeKey = "network.range"
    private static let importedKey = "network.importedNetSpeed"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storeURL: URL
    /// NetSpeed's history, brought in the first time; nil to skip.
    @ObservationIgnored private let netSpeedURL: URL?
    @ObservationIgnored private let readCounters: () -> [String: Traffic]
    @ObservationIgnored private var store: NetworkHistory?
    @ObservationIgnored private var poll: DispatchSourceTimer?
    /// The previous reading.
    @ObservationIgnored private var last: (counters: [String: Traffic], at: Date)?
    @ObservationIgnored private var watch = TransferWatch()
    /// What the transfer being watched has moved so far.
    @ObservationIgnored private var transferred = Traffic()
    @ObservationIgnored private var ongoing: Activity?
    /// The hour the chart was loaded in, so it moves on when the hour does.
    @ObservationIgnored private var loadedHour: Date?

    public convenience init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(
            defaults: .standard, storeURL: AppSupport.file("network.sqlite"),
            netSpeedURL: support.appending(path: "NetSpeed/history.sqlite"), readCounters: InterfaceCounters.read)
    }

    init(
        defaults: UserDefaults, storeURL: URL, netSpeedURL: URL?,
        readCounters: @escaping () -> [String: Traffic]
    ) {
        self.defaults = defaults
        self.storeURL = storeURL
        self.netSpeedURL = netSpeedURL
        self.readCounters = readCounters
        closedNotch = defaults.string(forKey: Self.closedNotchKey).flatMap(ClosedNotch.init) ?? .transfers
        range = defaults.string(forKey: Self.rangeKey).flatMap(HistoryRange.init) ?? .day
    }

    public var view: some View { NetworkView(network: self) }

    /// The chart's bars: the range from disk, with the traffic still in memory added to its bar.
    public var buckets: [TrafficBucket] {
        var buckets = stored
        for (hour, traffic) in pending {
            guard let index = buckets.lastIndex(where: { $0.start <= hour }) else { continue }
            buckets[index].traffic += traffic
        }
        return buckets
    }

    /// Whether the counters are being read on a schedule.
    var isPolling: Bool { poll != nil }

    /// Deletes the history. What moves from now on is still recorded.
    public func clearHistory() {
        pending = [:]
        history().clear()
        reload()
    }

    /// Reads the lifetime totals again, for Settings.
    public func refreshTotals() {
        lifetime = history().total() + pending.values.reduce(Traffic(), +)
    }

    // MARK: Readings

    /// Starts, reschedules, or stops the readings for the phase and the setting.
    private func update() {
        guard phase != .stopped else { return stop() }
        importNetSpeed()
        if phase == .foreground { reload() }
        sample()
        schedule()
    }

    private func stop() {
        poll?.cancel()
        poll = nil
        flush()
        store = nil  // closes the database
        stored = []
        recent = []
        rate = Rate()
        watch = TransferWatch()
        transferred = Traffic()
        show(nil)
    }

    /// A second while a speed shows or a transfer may be starting, 3 seconds while the closed notch
    /// waits for one, and otherwise just past the next hour.
    nonisolated static func interval(
        phase: FeaturePhase, closedNotch: ClosedNotch, busy: Bool, now: Date, calendar: Calendar = .current
    ) -> TimeInterval {
        if phase == .foreground || closedNotch == .always || (closedNotch == .transfers && busy) { return 1 }
        if closedNotch == .transfers { return 3 }
        let next = calendar.dateInterval(of: .hour, for: now)?.end ?? now.addingTimeInterval(3600)
        return next.timeIntervalSince(now) + 1
    }

    private func schedule() {
        let delay = Self.interval(phase: phase, closedNotch: closedNotch, busy: watch.isBusy, now: .now)
        // Leeway lets macOS fold the reading into other wakeups (Apple's energy guidance): a quarter
        // of the wait, up to a minute.
        let leeway = DispatchTimeInterval.milliseconds(Int(min(delay / 4, 60) * 1000))
        let deadline = DispatchTime.now() + .milliseconds(Int(delay * 1000))
        if let poll { return poll.schedule(deadline: deadline, leeway: leeway) }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: deadline, leeway: leeway)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.sample()
                self?.schedule()
            }
        }
        timer.resume()
        poll = timer
    }

    private func sample() { receive(readCounters(), at: .now) }

    /// One reading. What moved since the last one goes to the hours it moved in, and over a sampling
    /// interval it's the speed too; after a gap it's only history.
    func receive(_ counters: [String: Traffic], at now: Date) {
        guard let last else {
            self.last = (counters, now)
            return
        }
        let seconds = now.timeIntervalSince(last.at)
        guard seconds >= Self.shortest || seconds < 0 else { return }  // the next reading covers it
        self.last = (counters, now)
        let moved = InterfaceCounters.moved(from: last.counters, to: counters)
        record(moved, from: last.at, to: now)
        guard seconds <= Self.longest, seconds > 0 else { return }
        rate = Rate(down: Double(moved.down) / seconds, up: Double(moved.up) / seconds)
        recent.removeAll { now.timeIntervalSince($0.at) > Self.window }
        recent.append(RateSample(at: now, rate: rate))
        if phase == .foreground, loadedHour != Self.hour(of: now) { reload() }
        guard closedNotch != .off else { return }
        let wasShowing = watch.showing
        watch.observe(max(rate.down, rate.up), over: seconds)
        transferred = watch.isBusy || wasShowing ? transferred + moved : Traffic()
        if wasShowing, !watch.showing { finished() }
        show(closedNotch == .always || watch.showing ? Self.activity(for: rate) : nil)
    }

    /// The speed for the closed notch: the upload's while it's the transfer, else the download's.
    nonisolated static func activity(for rate: Rate) -> Activity {
        let up = rate.up > rate.down && rate.up >= TransferWatch.start
        let speed = speed(up ? rate.up : rate.down)
        return Activity(
            feature: .network, symbol: up ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
            title: "\(speed.value) \(speed.unit)", duration: .zero)
    }

    private func show(_ activity: Activity?) {
        guard activity != ongoing else { return }
        ongoing = activity
        onOngoing?(activity)
    }

    /// A transfer the closed notch showed is over: a word on what it moved, when that was a lot.
    private func finished() {
        defer { transferred = Traffic() }
        let down = transferred.down >= transferred.up
        let bytes = down ? transferred.down : transferred.up
        guard bytes >= Self.announced else { return }
        onActivity?(
            Activity(
                feature: .network, symbol: "checkmark.circle.fill",
                title: "\(down ? "Downloaded" : "Uploaded") \(Self.bytes(bytes))", duration: .seconds(3)))
    }

    // MARK: History

    private func record(_ moved: Traffic, from start: Date, to end: Date) {
        guard moved.total > 0 else { return }
        for (hour, part) in Self.spread(moved, from: start, to: end) { pending[hour, default: Traffic()] += part }
        // Hours that are over go to disk; this one stays in memory until it's over too.
        let hour = Self.hour(of: end)
        if pending.keys.contains(where: { $0 < hour }) { flush() }
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        history().add(pending)
        pending = [:]
        if phase == .foreground { reload() }
    }

    private func reload() {
        let now = Date.now
        loadedHour = Self.hour(of: now)
        stored = history().buckets(for: range, now: now)
        lifetime = history().total() + pending.values.reduce(Traffic(), +)
    }

    /// NetSpeed's history comes in the first time the tab runs, before its first reading, so
    /// NetSpeed's rows end where these begin and no hour counts twice, even while NetSpeed runs on.
    private func importNetSpeed() {
        guard let netSpeedURL, !defaults.bool(forKey: Self.importedKey) else { return }
        defaults.set(true, forKey: Self.importedKey)
        guard history().isEmpty else { return }
        let hours = history().importNetSpeed(from: netSpeedURL)
        if hours > 0 { Log.features.info("Imported \(hours, privacy: .public) hours of NetSpeed history") }
    }

    /// The database, opened on first use and closed when the feature stops.
    private func history() -> NetworkHistory {
        if let store { return store }
        let store = NetworkHistory(url: storeURL)
        self.store = store
        return store
    }

    nonisolated static func hour(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }

    /// Splits traffic that moved evenly from `start` to `end` among the hours of the local clock it
    /// spans, by the time spent in each. The last hour takes the rounding, so the parts add up.
    nonisolated static func spread(_ traffic: Traffic, from start: Date, to end: Date, calendar: Calendar = .current)
        -> [Date: Traffic]
    {
        let last = hour(of: end, calendar: calendar)
        guard start < last else { return [last: traffic] }  // one hour, or a clock that went back
        let span = end.timeIntervalSince(start)
        var hours: [Date: Traffic] = [:]
        var left = traffic
        var hour = hour(of: start, calendar: calendar)
        // ponytail: at most 400 days of hours; a longer gap is a clock that jumped, and the rest
        // lands in the last hour.
        for _ in 0..<(24 * 400) {
            guard let next = calendar.date(byAdding: .hour, value: 1, to: hour), next <= last else { break }
            let share = min(next, end).timeIntervalSince(max(hour, start)) / span
            let part = Traffic(down: Int64(Double(traffic.down) * share), up: Int64(Double(traffic.up) * share))
            hours[hour] = part
            left.down -= part.down
            left.up -= part.up
            hour = next
        }
        hours[last, default: Traffic()] += left
        return hours
    }

    // MARK: Formatting

    /// A speed like NetSpeed's: "9.8" "KB/s" or "12" "MB/s", a decimal only under 10, so the width
    /// barely moves.
    public nonisolated static func speed(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        scaled(bytesPerSecond, units: ["KB/s", "MB/s", "GB/s"], decimalsUnder: 10)
    }

    /// "160 MB" or "2.1 GB"; nothing is "0 KB", a number rather than words that would read as a
    /// broken label on a chart.
    public nonisolated static func bytes(_ count: Int64) -> String {
        let scaled = scaled(Double(count), units: ["KB", "MB", "GB", "TB"], decimalsUnder: 100)
        return "\(scaled.value) \(scaled.unit)"
    }

    /// In the decimal units Finder uses (1 KB is 1,000 bytes), from KB up, with one decimal under
    /// `limit` and whole numbers from there.
    private nonisolated static func scaled(_ count: Double, units: [String], decimalsUnder limit: Double)
        -> (value: String, unit: String)
    {
        var value = max(count, 0) / 1000
        var unit = 0
        while value >= 999.5, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        if value == 0, limit > 10 { return ("0", units[unit]) }
        return (String(format: value < limit - 0.05 ? "%.1f" : "%.0f", value), units[unit])
    }
}

/// When the closed notch shows a transfer: once something moves at 1 MB/s or more for 4 seconds,
/// longer than a web page or a video's next few seconds take, until it's under 250 KB/s for 5.
struct TransferWatch: Equatable {
    static let start = 1_000_000.0
    static let stop = 250_000.0
    static let showAfter: TimeInterval = 4
    static let hideAfter: TimeInterval = 5

    private(set) var showing = false
    /// How long the speed has been past the line that would change `showing`.
    private(set) var streak: TimeInterval = 0

    /// A transfer is showing or may be starting: worth a reading every second.
    var isBusy: Bool { showing || streak > 0 }

    mutating func observe(_ rate: Double, over seconds: TimeInterval) {
        let crossing = showing ? rate < Self.stop : rate >= Self.start
        streak = crossing ? streak + seconds : 0
        guard streak >= (showing ? Self.hideAfter : Self.showAfter) else { return }
        showing.toggle()
        streak = 0
    }
}

/// Bytes each physical network interface has moved since it came up, by name, from the kernel's
/// 64-bit counters: sysctl NET_RT_IFLIST2 lists an if_msghdr2 per interface, each followed by its
/// link address, which holds the name. Reading the name there takes 20 µs for the whole list;
/// NetSpeed's if_indextoname lists every interface again for each one, 200 µs in all.
enum InterfaceCounters {
    static func read() -> [String: Traffic] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [:] }
        return buffer.withUnsafeBytes { parse(UnsafeRawBufferPointer(rebasing: $0.prefix(length))) }
    }

    /// Wi-Fi and Ethernet (en*) and iPhone tethering (pdp_ip*). Loopback, AirDrop (awdl), and VPN
    /// tunnels (utun) are left out: their bytes never left the Mac, or crossed one of these too.
    static func isPhysical(_ name: String) -> Bool { name.hasPrefix("en") || name.hasPrefix("pdp_ip") }

    static func parse(_ raw: UnsafeRawBufferPointer) -> [String: Traffic] {
        let header = MemoryLayout<if_msghdr2>.size
        var counters: [String: Traffic] = [:]
        var offset = 0
        while offset + 4 <= raw.count {
            let length = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
            guard length > 0, offset + length <= raw.count else { break }
            defer { offset += length }
            guard raw[offset + 3] == UInt8(RTM_IFINFO2), length >= header + 8 else { continue }
            let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
            // The link address: sdl_len, sdl_family, sdl_index (2 bytes), sdl_type, sdl_nlen, sdl_alen,
            // sdl_slen, then sdl_data, which starts with the name.
            let link = offset + header
            guard message.ifm_addrs & RTA_IFP != 0, raw[link + 1] == UInt8(AF_LINK) else { continue }
            let name = link + 8
            let nameEnd = name + Int(raw[link + 5])
            guard nameEnd <= offset + length else { continue }
            let interface = String(decoding: UnsafeRawBufferPointer(rebasing: raw[name..<nameEnd]), as: UTF8.self)
            guard isPhysical(interface) else { continue }
            counters[interface] = Traffic(
                down: Int64(clamping: message.ifm_data.ifi_ibytes), up: Int64(clamping: message.ifm_data.ifi_obytes))
        }
        return counters
    }

    /// What moved between two readings. An interface that just appeared counts from its next
    /// reading, and one whose counters started over (it went down and came back) counts what it
    /// moved since.
    static func moved(from old: [String: Traffic], to new: [String: Traffic]) -> Traffic {
        var moved = Traffic()
        for (name, now) in new {
            guard let then = old[name] else { continue }
            moved.down += now.down >= then.down ? now.down - then.down : now.down
            moved.up += now.up >= then.up ? now.up - then.up : now.up
        }
        return moved
    }
}
