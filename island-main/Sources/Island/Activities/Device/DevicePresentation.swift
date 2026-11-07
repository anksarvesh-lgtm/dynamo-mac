import IslandCore

enum DevicePresentation {
    static func symbol(_ d: DeviceActivity) -> String {
        let lower = d.name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        switch d.type {
        case .headphones: return "headphones"
        case .speaker: return "hifispeaker.fill"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .display: return "display"
        case .other: return "cable.connector"
        }
    }
}
