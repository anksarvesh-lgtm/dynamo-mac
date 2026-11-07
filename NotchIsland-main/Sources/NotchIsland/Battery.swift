import Foundation
import IOKit.ps

enum Battery {
    struct Info: Equatable {
        let percent: Int
        let charging: Bool   // actively charging
        let onAC: Bool       // power adapter connected (true even when full)
    }

    static func read() -> Info {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
        else { return Info(percent: 100, charging: false, onAC: true) }

        let percent = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
        let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
        let onAC = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        return Info(percent: percent, charging: charging, onAC: onAC)
    }
}
