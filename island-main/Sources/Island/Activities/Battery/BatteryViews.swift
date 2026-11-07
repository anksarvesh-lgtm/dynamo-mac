import IslandCore
import SwiftUI

enum BatteryPresentation {
    static func symbol(_ b: BatteryActivity) -> String {
        if b.isCharging { return "bolt.fill" }
        switch b.level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
    static func tint(_ b: BatteryActivity) -> Color {
        b.isCharging || b.level > 20 ? IslandPalette.batteryGood : IslandPalette.batteryLow
    }
    static func title(_ b: BatteryActivity) -> String {
        switch b.reason {
        case .pluggedIn: "Charging"
        case .unplugged: "On battery"
        case .low: "Low battery"
        case .full: "Fully charged"
        }
    }
}

struct BatteryCompactLeading: View {
    let battery: BatteryActivity
    let id: String
    @Environment(\.islandNamespace) private var ns
    var body: some View {
        Image(systemName: BatteryPresentation.symbol(battery))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(BatteryPresentation.tint(battery))
            .islandMatched("icon-\(id)", in: ns)
    }
}

struct BatteryCompactTrailing: View {
    let battery: BatteryActivity
    var body: some View {
        Text("\(battery.level)%")
            .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(BatteryPresentation.tint(battery))
    }
}

struct BatteryExpanded: View {
    let battery: BatteryActivity
    let id: String
    @Environment(\.islandNamespace) private var ns
    @Environment(\.islandCommands) private var send
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: BatteryPresentation.symbol(battery))
                .font(.system(size: 24, weight: .semibold)).foregroundStyle(BatteryPresentation.tint(battery))
                .frame(width: 44, height: 44)
                .islandMatched("icon-\(id)", in: ns)
            VStack(alignment: .leading, spacing: 6) {
                Text(BatteryPresentation.title(battery)).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                LinearProgress(fraction: Double(battery.level) / 100, tint: BatteryPresentation.tint(battery), height: 6)
                    .frame(width: 160)
            }
            Spacer()
            Text("\(battery.level)%").font(.system(size: 26, weight: .light).monospacedDigit()).foregroundStyle(BatteryPresentation.tint(battery))
            IslandIconButton(symbol: "xmark", size: 11, label: "Dismiss") { send(.ui(.dismiss(activityID: id))) }
        }
        .accessibilityElement(children: .combine)
    }
}
