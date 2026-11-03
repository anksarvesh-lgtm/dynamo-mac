//
//  IslandEventManager.swift
//  LiquidDynamo
//
//  Created for Production Dynamic Island Architecture.
//  Central event bus, priority queue, deduplication pipeline, and real device snapshot registry.
//

import AppKit
import Combine
import Foundation
import SwiftUI
import IOKit.ps

public enum EventPriority: Int, Comparable, Sendable {
    case informational = 0
    case normal = 1
    case high = 2
    case critical = 3

    public static func < (lhs: EventPriority, rhs: EventPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum EventCategory: String, Sendable {
    case power
    case bluetooth
    case media
    case systemLifecycle
    case utilityApp
    case localNotification
}

public struct IslandEvent: Identifiable {
    public let id: UUID
    public let sourceID: String
    public let category: EventCategory
    public let priority: EventPriority
    public let timestamp: Date
    public let title: String
    public let subtitle: String?
    public let iconName: String?
    public let tintColor: Color?
    public let duration: TimeInterval
    public let action: (() -> Void)?

    public init(
        id: UUID = UUID(),
        sourceID: String,
        category: EventCategory,
        priority: EventPriority = .normal,
        timestamp: Date = Date(),
        title: String,
        subtitle: String? = nil,
        iconName: String? = nil,
        tintColor: Color? = nil,
        duration: TimeInterval = 3.5,
        action: (() -> Void)? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.category = category
        self.priority = priority
        self.timestamp = timestamp
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.tintColor = tintColor
        self.duration = duration
        self.action = action
    }
}

public struct ConnectedDeviceSnapshot: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let isConnected: Bool
    public let category: String
    public let batteryPercent: Int?
    public let reportedPowerWatts: Double?
    public let lastUpdated: Date
    public let source: String

    public init(
        id: String,
        name: String,
        isConnected: Bool,
        category: String,
        batteryPercent: Int? = nil,
        reportedPowerWatts: Double? = nil,
        lastUpdated: Date = Date(),
        source: String
    ) {
        self.id = id
        self.name = name
        self.isConnected = isConnected
        self.category = category
        self.batteryPercent = batteryPercent
        self.reportedPowerWatts = reportedPowerWatts
        self.lastUpdated = lastUpdated
        self.source = source
    }
}

@MainActor
public final class IslandEventManager: ObservableObject {
    public static let shared = IslandEventManager()

    @Published public private(set) var activeEvent: IslandEvent?
    @Published public private(set) var eventQueue: [IslandEvent] = []
    @Published public private(set) var connectedDevices: [ConnectedDeviceSnapshot] = []

    private var cancellables = Set<AnyCancellable>()
    private var dismissTask: Task<Void, Never>?

    private init() {
        setupSystemLifecycleObservers()
        refreshPowerSnapshot()
    }

    // MARK: - Central Event Pipeline

    public func postEvent(_ event: IslandEvent) {
        // 1. Deduplication: Drop duplicate source events within 2.0 seconds
        if let current = activeEvent, current.sourceID == event.sourceID,
           event.timestamp.timeIntervalSince(current.timestamp) < 2.0 {
            return
        }

        // 2. Priority check: Critical alerts preempt current event immediately
        if let current = activeEvent {
            if event.priority >= current.priority {
                presentEvent(event)
            } else {
                // Enqueue behind higher-priority alerts, keeping max 6 items
                if !eventQueue.contains(where: { $0.sourceID == event.sourceID }) {
                    eventQueue.append(event)
                    eventQueue.sort(by: { $0.priority > $1.priority })
                    if eventQueue.count > 6 {
                        eventQueue.removeLast()
                    }
                }
            }
        } else {
            presentEvent(event)
        }
    }

    private func presentEvent(_ event: IslandEvent) {
        dismissTask?.cancel()
        self.activeEvent = event

        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(event.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismissCurrentEvent()
        }
    }

    public func dismissCurrentEvent() {
        dismissTask?.cancel()
        self.activeEvent = nil

        // Promote next queued event if available
        if !eventQueue.isEmpty {
            let next = eventQueue.removeFirst()
            presentEvent(next)
        }
    }

    // MARK: - Hardware Power & Battery Telemetry (IOKit.ps)

    public func refreshPowerSnapshot() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else { continue }

            let isCharging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false
            let currentCap = (desc[kIOPSCurrentCapacityKey as String] as? Int) ?? 0
            let maxCap = (desc[kIOPSMaxCapacityKey as String] as? Int) ?? 100
            let pct = maxCap > 0 ? Int((Double(currentCap) / Double(maxCap)) * 100.0) : currentCap

            var adapterWatts: Double? = nil
            if let adapterDetails = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
               let watts = adapterDetails[kIOPSPowerAdapterWattsKey as String] as? Int {
                adapterWatts = Double(watts)
            }

            let name = adapterWatts != nil ? "MagSafe 3 Charger" : "MacBook Battery"
            let dev = ConnectedDeviceSnapshot(
                id: "power.internal",
                name: name,
                isConnected: isCharging || adapterWatts != nil,
                category: "Power",
                batteryPercent: pct,
                reportedPowerWatts: adapterWatts,
                source: "IOKit.ps"
            )

            // Update connected devices atomically
            updateDevice(dev)
        }
    }

    public func updateDevice(_ device: ConnectedDeviceSnapshot) {
        if let idx = connectedDevices.firstIndex(where: { $0.id == device.id }) {
            connectedDevices[idx] = device
        } else {
            connectedDevices.append(device)
        }
    }

    public func removeDevice(id: String) {
        connectedDevices.removeAll(where: { $0.id == id })
    }

    // MARK: - System Lifecycle Observers (NSWorkspace)

    private func setupSystemLifecycleObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter

        wsCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPowerSnapshot()
                self?.postEvent(IslandEvent(
                    sourceID: "system.wake",
                    category: .systemLifecycle,
                    priority: .informational,
                    title: "System Resumed",
                    subtitle: "All services active",
                    iconName: "macbook.and.iphone"
                ))
            }
            .store(in: &cancellables)

        wsCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPowerSnapshot()
            }
            .store(in: &cancellables)
    }
}

