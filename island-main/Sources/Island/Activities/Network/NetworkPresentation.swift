import IslandCore

enum NetworkPresentation {
    static func symbol(_ n: NetworkActivity) -> String {
        guard n.connected else { return "wifi.slash" }
        switch n.interface {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .cellular: return "antenna.radiowaves.left.and.right"
        default: return "network"
        }
    }
    static func title(_ n: NetworkActivity) -> String { n.connected ? "Online" : "Offline" }
    static func subtitle(_ n: NetworkActivity) -> String {
        guard n.connected else { return "No internet connection" }
        switch n.interface {
        case .wifi: return "Connected via Wi-Fi"
        case .ethernet: return "Connected via Ethernet"
        case .cellular: return "Connected via cellular"
        default: return "Connected"
        }
    }
}
