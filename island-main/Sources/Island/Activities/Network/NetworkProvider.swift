import Foundation
import IslandCore
import Network

/// Connectivity changes via NWPathMonitor. Only transitions are shown (never the initial state).
@MainActor
final class NetworkProvider {
    private let sink: (ActivityUpdate) -> Void
    private let bus: EventBus
    private var monitor: NWPathMonitor?
    private var lastConnected: Bool?
    private var lastInterface: NetworkActivity.Interface = .none

    init(bus: EventBus, sink: @escaping (ActivityUpdate) -> Void) {
        self.bus = bus
        self.sink = sink
    }

    func start() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let iface: NetworkActivity.Interface =
                path.usesInterfaceType(.wifi) ? .wifi :
                path.usesInterfaceType(.wiredEthernet) ? .ethernet :
                path.usesInterfaceType(.cellular) ? .cellular : (connected ? .other : .none)
            DispatchQueue.main.async { self?.update(connected: connected, interface: iface) }
        }
        m.start(queue: DispatchQueue(label: "island.network"))
        monitor = m
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    private func update(connected: Bool, interface: NetworkActivity.Interface) {
        defer { lastConnected = connected; lastInterface = interface }
        guard let was = lastConnected, was != connected else { return }
        bus.publish(.networkChanged(connected: connected))
        sink(.upsert(Activity(id: "network", kind: .network, priority: connected ? .normal : .high,
                              content: .network(NetworkActivity(connected: connected, interface: interface)),
                              expiresAt: Date().addingTimeInterval(connected ? 3 : 5))))
    }
}
