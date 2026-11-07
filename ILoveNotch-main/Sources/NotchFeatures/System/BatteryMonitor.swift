// SPDX-License-Identifier: MIT
import Foundation
import IOKit.ps
import NotchCore

/// The internal battery, as the power source APIs describe it.
public struct BatteryState: Equatable, Sendable {
    /// 0...100.
    public var percent: Int
    /// Plugged into a charger, charging or not.
    public var onAC: Bool
    /// Plugged in and full.
    public var charged: Bool

    public init(percent: Int, onAC: Bool, charged: Bool) {
        self.percent = percent
        self.onAC = onAC
        self.charged = charged
    }

    /// Reads one power source description (`IOPSGetPowerSourceDescription`), or nil if it isn't the
    /// internal battery.
    init?(_ description: [String: Any]) {
        guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
            let current = description[kIOPSCurrentCapacityKey] as? Int,
            let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
        else { return nil }
        percent = min(max(current * 100 / maximum, 0), 100)
        onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        charged = onAC && (description[kIOPSIsChargedKey] as? Bool ?? false)
    }
}

/// Raises a live activity when the charger connects or disconnects, when the battery runs low, and
/// when it's full. The power source notification calls back on changes, so nothing runs between
/// them; Macs without a battery never start it.
@MainActor
public final class BatteryMonitor {
    public var onActivity: ((Activity) -> Void)?
    public var isRunning: Bool { source != nil }

    private var source: CFRunLoopSource?
    private var last: BatteryState?

    public init() {}

    public func start() {
        guard source == nil, let state = Self.read() else { return }
        last = state
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.changed() }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = source
    }

    public func stop() {
        guard let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = nil
    }

    /// The activity a change deserves, if any: the charger connecting or disconnecting, the battery
    /// dropping to 20% or 10% on battery power, or filling up.
    nonisolated static func activity(from old: BatteryState, to new: BatteryState) -> Activity? {
        let level = Double(new.percent) / 100
        func activity(_ symbol: String, _ title: String) -> Activity {
            Activity(feature: nil, symbol: symbol, title: title, level: level, duration: .seconds(3))
        }
        if new.onAC, !old.onAC { return activity("battery.100percent.bolt", "\(new.percent)%") }
        if !new.onAC, old.onAC { return activity(symbol(for: new.percent), "\(new.percent)%") }
        if new.charged, !old.charged { return activity("battery.100percent", "Full") }
        if !new.onAC, let threshold = [20, 10].first(where: { old.percent > $0 && new.percent <= $0 }) {
            return activity(threshold == 10 ? "battery.0percent" : "battery.25percent", "\(new.percent)%")
        }
        return nil
    }

    nonisolated static func symbol(for percent: Int) -> String {
        switch percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }

    private func changed() {
        guard let state = Self.read(), let last, state != last else { return }
        self.last = state
        if let activity = Self.activity(from: last, to: state) { onActivity?(activity) }
    }

    private nonisolated static func read() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        return sources.lazy.compactMap { source in
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            return description.flatMap(BatteryState.init)
        }.first
    }
}
