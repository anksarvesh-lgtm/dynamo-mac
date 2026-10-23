//
//  NetworkActivitySource.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import Combine
import Foundation
import Network
import SwiftUI

/// Emits LiveActivity alerts for Network connectivity (connected, disconnected, and VPN status).
/// Reuses ConnectionStatusService.shared and NWPathMonitor without polling.
@MainActor
public final class NetworkActivitySource: LiveActivitySource {
    public let identifier: String = "network"

    private let subject = PassthroughSubject<LiveActivity, Never>()
    public var activityPublisher: AnyPublisher<LiveActivity, Never> {
        subject.eraseToAnyPublisher()
    }

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.agrigence.liquiddynamo.networksource", qos: .utility)
    private var lastWasOnline: Bool?
    private var lastWasVPNActive: Bool?
    private var isStarted = false

    public static let shared = NetworkActivitySource()

    private init() {}

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        let monitor = NWPathMonitor()
        self.monitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self, self.isStarted else { return }
                self.processPathUpdate(path)
            }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor?.cancel()
        monitor = nil
        isStarted = false
    }

    // MARK: - Path Processing

    private func processPathUpdate(_ path: NWPath) {
        let isOnline = (path.status == .satisfied)
        let isVPNActive = path.availableInterfaces.contains { iface in
            let name = iface.name.lowercased()
            return name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") || name.hasPrefix("tap")
        }

        // 1. Online / Offline transitions
        if let previousOnline = lastWasOnline {
            if previousOnline != isOnline {
                if isOnline {
                    let typeName = determineInterfaceDescription(path)
                    let icon = path.usesInterfaceType(.wifi) ? "wifi" : (path.usesInterfaceType(.wiredEthernet) ? "cable.connector" : "network")
                    emitNetworkAlert(
                        id: "net_online",
                        title: String(localized: "Connected to Network"),
                        subtitle: typeName,
                        icon: icon,
                        tint: LiveActivitySeverity.info.color,
                        body: String(localized: "Internet connection is active via \(typeName)")
                    )
                } else {
                    emitNetworkAlert(
                        id: "net_offline",
                        title: String(localized: "Network Disconnected"),
                        subtitle: String(localized: "No Internet Connection"),
                        icon: "wifi.slash",
                        tint: LiveActivitySeverity.warning.color,
                        body: String(localized: "Your Mac is currently offline")
                    )
                }
            }
        }
        lastWasOnline = isOnline

        // 2. VPN transitions
        if let previousVPN = lastWasVPNActive {
            if previousVPN != isVPNActive {
                if isVPNActive {
                    emitNetworkAlert(
                        id: "vpn_connected",
                        title: String(localized: "VPN Connected"),
                        subtitle: String(localized: "Secure Tunnel Active"),
                        icon: "shield.lefthalf.filled",
                        tint: LiveActivitySeverity.info.color,
                        body: String(localized: "Traffic is now routed through a secure VPN tunnel")
                    )
                } else {
                    emitNetworkAlert(
                        id: "vpn_disconnected",
                        title: String(localized: "VPN Disconnected"),
                        subtitle: String(localized: "Direct Connection"),
                        icon: "shield.slash",
                        tint: LiveActivitySeverity.warning.color,
                        body: String(localized: "VPN tunnel disconnected")
                    )
                }
            }
        }
        lastWasVPNActive = isVPNActive
    }

    private func determineInterfaceDescription(_ path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) {
            return "Wi-Fi"
        } else if path.usesInterfaceType(.wiredEthernet) {
            return "Ethernet"
        } else if path.usesInterfaceType(.cellular) {
            return "Personal Hotspot"
        }
        return "Network"
    }

    private func emitNetworkAlert(id: String, title: String, subtitle: String, icon: String, tint: Color, body: String) {
        let activity = LiveActivity(
            id: id,
            source: identifier,
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: tint,
            duration: 3.0,
            coalescingKey: "network_status",
            payload: LiveActivityPayload(
                title: title,
                subtitle: subtitle,
                iconName: icon,
                body: body
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
    }
}
