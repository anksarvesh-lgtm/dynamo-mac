//
//  ConnectionStatusService.swift
//  boringNotch
//
//  Created for Boring Notch
//

import Combine
import Foundation
import Network
import SwiftUI

// MARK: - Models

/// Active network interface category.
public enum NetworkInterfaceType: Equatable, Sendable {
    case wifi
    case ethernet
    case cellularHotspot
    case other(String)
    case none

    public var displayName: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .ethernet:
            return "Ethernet"
        case .cellularHotspot:
            return "Personal Hotspot"
        case .other(let name):
            return name
        case .none:
            return "Disconnected"
        }
    }

    public var iconName: String {
        switch self {
        case .wifi:
            return "wifi"
        case .ethernet:
            return "cable.connector"
        case .cellularHotspot:
            return "personalhotspot"
        case .other:
            return "network"
        case .none:
            return "wifi.slash"
        }
    }
}

/// Detailed online/offline connection state.
public enum ConnectionStatus: Equatable, Sendable {
    case online(interfaceType: NetworkInterfaceType, interfaceName: String, isExpensive: Bool, isConstrained: Bool)
    case offline

    public var isConnected: Bool {
        if case .online = self { return true }
        return false
    }
}

// MARK: - Connection Status Service

/// Event-driven service monitoring system network path, connectivity, and interface type via `NWPathMonitor`.
///
/// Features:
/// - Zero polling: 100% event-driven via `NWPathMonitor.pathUpdateHandler`.
/// - Filters out loopback (`lo`), VPN tunnels (`utun`, `ipsec`, `ppp`), and Apple direct-link interfaces (`awdl`, `p2p`).
/// - Detects online/offline, interface type (Wi-Fi, Ethernet, Cellular Hotspot), and Low Data Mode (`isConstrained`).
/// - Clean lifecycle management with `start()` and `stop()` cancelling monitoring completely when inactive.
@MainActor
public final class ConnectionStatusService: ObservableObject {
    public static let shared = ConnectionStatusService()

    // MARK: - Published Properties

    @Published public private(set) var isOnline: Bool = false
    @Published public private(set) var primaryInterfaceName: String? = nil
    @Published public private(set) var interfaceType: NetworkInterfaceType = .none
    @Published public private(set) var isExpensive: Bool = false
    @Published public private(set) var isConstrained: Bool = false
    @Published public private(set) var status: ConnectionStatus = .offline
    @Published public private(set) var isMonitoring: Bool = false

    // MARK: - Private State

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.agrigence.liquiddynamo.connectionstatus", qos: .utility)

    // Set of interface prefixes to ignore so VPN/virtual traffic is never counted as physical
    private static let ignoredInterfacePrefixes = [
        "lo", "utun", "ipsec", "ppp", "tap", "tun", "bridge", "p2p", "awdl", "llw", "anpi", "gif", "stf"
    ]

    private init() {}

    // MARK: - Lifecycle

    /// Starts event-driven path monitoring on a background queue.
    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        let monitor = NWPathMonitor()
        self.monitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self, self.isMonitoring else { return }
                self.processPathUpdate(path)
            }
        }

        monitor.start(queue: queue)
    }

    /// Stops path monitoring and cancels the underlying NWPathMonitor.
    public func stop() {
        guard isMonitoring else { return }
        isMonitoring = false

        monitor?.cancel()
        monitor = nil
    }

    // MARK: - Path Processing

    private func processPathUpdate(_ path: NWPath) {
        let online = (path.status == .satisfied)
        self.isOnline = online
        self.isExpensive = path.isExpensive
        self.isConstrained = path.isConstrained

        guard online else {
            self.primaryInterfaceName = nil
            self.interfaceType = .none
            self.status = .offline
            return
        }

        // Determine primary physical interface name, ignoring virtual/VPN interfaces
        let primaryName = determinePrimaryPhysicalInterface(for: path)
        self.primaryInterfaceName = primaryName

        // Determine interface type
        let type = determineInterfaceType(for: path, interfaceName: primaryName)
        self.interfaceType = type

        self.status = .online(
            interfaceType: type,
            interfaceName: primaryName ?? "en0",
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }

    /// Identifies the active physical interface by filtering out virtual, tunnel, and loopback adapters.
    private func determinePrimaryPhysicalInterface(for path: NWPath) -> String? {
        // First look at available interfaces used by this path
        for interface in path.availableInterfaces {
            let name = interface.name
            if !Self.isVirtualInterface(name) && path.usesInterfaceType(interface.type) {
                return name
            }
        }

        // Secondary pass: any available interface that is not virtual
        for interface in path.availableInterfaces {
            let name = interface.name
            if !Self.isVirtualInterface(name) {
                return name
            }
        }

        // Default fallback for macOS standard primary Wi-Fi
        return "en0"
    }

    /// Maps NWInterface types and hotspot indicators to `NetworkInterfaceType`.
    private func determineInterfaceType(for path: NWPath, interfaceName: String?) -> NetworkInterfaceType {
        // 1. Check if cellular/hotspot
        if path.usesInterfaceType(.cellular) {
            return .cellularHotspot
        }

        // 2. Check if Wi-Fi
        if path.usesInterfaceType(.wifi) {
            // If the connection is marked expensive, or Wi-Fi service detected a mobile hotspot subnet, classify as hotspot
            if path.isExpensive || WiFiInfoService.shared.currentInfo?.isHotspot == true {
                return .cellularHotspot
            }
            return .wifi
        }

        // 3. Check if Ethernet
        if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        }

        // 4. Other physical interface
        if let name = interfaceName {
            return .other(name)
        }

        return .other("Network")
    }

    /// Returns true if the interface is a loopback, VPN tunnel, tap, bridge, or Apple direct link.
    public static func isVirtualInterface(_ name: String) -> Bool {
        let lower = name.lowercased()
        return ignoredInterfacePrefixes.contains { lower.hasPrefix($0) }
    }
}
