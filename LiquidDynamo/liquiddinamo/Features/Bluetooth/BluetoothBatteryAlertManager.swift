//
//  BluetoothBatteryAlertManager.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

// MARK: - Alert Item Model

public struct BluetoothBatteryAlertItem: Identifiable, Equatable {
    public let id = UUID()
    public let deviceID: String // Normalized MAC or simulated ID
    public let deviceName: String
    public let iconName: String
    public let partKind: DeviceBatteryPart.PartKind?
    public let partName: String?
    public let percentage: Int
    public let isCritical: Bool
    public let deviceKind: DeviceKind
    public let deviceIdentity: DeviceIdentity?

    public init(
        deviceID: String,
        deviceName: String,
        iconName: String,
        partKind: DeviceBatteryPart.PartKind?,
        partName: String?,
        percentage: Int,
        isCritical: Bool,
        deviceKind: DeviceKind,
        deviceIdentity: DeviceIdentity? = nil
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.iconName = iconName
        self.partKind = partKind
        self.partName = partName
        self.percentage = percentage
        self.isCritical = isCritical
        self.deviceKind = deviceKind
        self.deviceIdentity = deviceIdentity
    }

    /// Header Title:
    /// Critical: "Almost empty"
    /// Multi-part warning: "<Part> battery low" (e.g. "Left earbud battery low")
    /// General warning: "Battery low"
    /// Always kept under ~20 characters, no all-caps, no exclamation marks.
    public var titleText: String {
        if isCritical {
            return String(localized: "Almost empty")
        }
        if let partName = partName, !partName.isEmpty {
            let format = String(localized: "%@ battery low")
            return String(format: format, partName)
        }
        return String(localized: "Battery low")
    }

    /// Second line:
    /// Warning: "<Device name> · <N>% left"
    /// Critical: "<Device name> · <N>% left. It may disconnect soon."
    public var detailLineText: String {
        if isCritical {
            let format = String(localized: "%@ · %lld%% left. It may disconnect soon.")
            return String(format: format, deviceName, Int64(percentage))
        } else {
            let format = String(localized: "%@ · %lld%% left")
            return String(format: format, deviceName, Int64(percentage))
        }
    }

    /// Third line (Call to action):
    /// Audio devices (earbuds, headphones, speakers): "Charge soon to keep listening."
    /// Keyboards, mice, trackpads: "Charge or replace batteries soon."
    /// Anything else: "Charge it soon."
    public var actionLineText: String {
        switch deviceKind {
        case .headphones, .earbuds, .speaker:
            return String(localized: "Charge soon to keep listening.")
        case .keyboard, .mouse:
            return String(localized: "Charge or replace batteries soon.")
        default:
            return String(localized: "Charge it soon.")
        }
    }

    public var batteryColor: Color {
        if isCritical || percentage < 5 {
            return .red
        }
        return .orange // Amber
    }

    public var batteryIconName: String {
        if percentage <= 5 {
            return "battery.0"
        } else if percentage <= 15 {
            return "battery.25"
        } else if percentage <= 50 {
            return "battery.50"
        } else if percentage <= 75 {
            return "battery.75"
        } else {
            return "battery.100"
        }
    }
}

// MARK: - Alert Tracker State

private struct DeviceAlertTracker {
    var lastObservedPercentage: Int?
    var isCharging: Bool = false
    var warningAlertFired: Bool = false
    var criticalAlertFired: Bool = false
    var lastWarningFiredTime: Date? = nil
    var wasDisconnected: Bool = false
}

// MARK: - Manager

@MainActor
public final class BluetoothBatteryAlertManager: ObservableObject {
    public static let shared = BluetoothBatteryAlertManager()

    @Published public private(set) var currentAlert: BluetoothBatteryAlertItem?
    @Published public private(set) var isShowingAlertPopup: Bool = false
    @Published public private(set) var hasActiveLowBatteryDot: Bool = false
    @Published public private(set) var activeDotDeviceID: String? = nil

    @Published public var isHovering: Bool = false {
        didSet {
            handleHoverChanged()
        }
    }

    // Per-device / per-part edge-tracking dictionary
    private var trackers: [String: DeviceAlertTracker] = [:]
    private var dismissTask: Task<Void, Never>?
    private var slowTimer: DispatchSourceTimer?
    private var cancellables = Set<AnyCancellable>()

    #if DEBUG
    // Simulator states for testing without dying hardware
    @Published public var isSimulating: Bool = false
    @Published public var simulatedDeviceName: String = "AirPods Pro (Sim)"
    @Published public var simulatedPercentage: Double = 100
    @Published public var simulatedIsCharging: Bool = false
    @Published public var simulatedSelectedPart: DeviceBatteryPart.PartKind = .leftEarbud
    @Published public var simulatedHasParts: Bool = true
    @Published public var simulatedUnknownBattery: Bool = false
    @Published public var simulatedIsDisconnected: Bool = false
    #endif

    private init() {
        setupObservers()
    }

    private func setupObservers() {
        // Observe Bluetooth connections/disconnections
        NotificationCenter.default.publisher(for: .bluetoothDeviceDidConnect)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                self?.handleDeviceConnected(notif.object)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .bluetoothDeviceDidDisconnect)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                self?.handleDeviceDisconnected(notif.object)
            }
            .store(in: &cancellables)
    }

    // MARK: - Connection & Tab Events

    public func handleBluetoothTabOpened() {
        BluetoothService.shared.refreshDevices()
        evaluateDevices(BluetoothService.shared.connectedDevices)
    }

    public func handleDeviceConnected(_ object: Any?) {
        BluetoothService.shared.refreshDevices()
        evaluateDevices(BluetoothService.shared.connectedDevices)
    }

    public func handleDeviceDisconnected(_ object: Any?) {
        // Identify disconnected address if available
        BluetoothService.shared.refreshDevices()
        evaluateDevices(BluetoothService.shared.connectedDevices)
        updateTimerState()
    }

    // MARK: - Evaluation Engine

    public func evaluateDevices(_ devices: [BluetoothDeviceInfo]) {
        updateTimerState(connectedDevices: devices)

        // Mark any disconnected devices for re-arming when reconnected
        let connectedIDs = Set(devices.map { $0.id })
        for (key, var tracker) in trackers {
            let devID = key.components(separatedBy: "_").first ?? key
            if !connectedIDs.contains(devID) {
                tracker.wasDisconnected = true
                tracker.lastObservedPercentage = nil
                trackers[key] = tracker
            }
        }

        for device in devices {
            // Mute check: per-device mute toggle in Bluetooth tab
            if isDeviceMuted(device.id) {
                continue
            }

            // Multi-part device check (e.g. left bud, right bud, case)
            if !device.batteryParts.isEmpty {
                for part in device.batteryParts {
                    evaluateUnit(
                        deviceID: device.id,
                        deviceName: device.name,
                        iconName: device.iconName,
                        partKind: part.kind,
                        partName: part.kind.displayName,
                        percentage: part.percentage,
                        isCharging: part.isCharging
                    )
                }
            } else if let battery = device.batteryPercentage {
                // Single-unit device
                evaluateUnit(
                    deviceID: device.id,
                    deviceName: device.name,
                    iconName: device.iconName,
                    partKind: nil,
                    partName: nil,
                    percentage: battery,
                    isCharging: device.isCharging
                )
            }
            // Note: If battery is nil (unknown), skip completely. Never show invented values.
        }
    }

    private func evaluateUnit(
        deviceID: String,
        deviceName: String,
        iconName: String,
        partKind: DeviceBatteryPart.PartKind?,
        partName: String?,
        percentage: Int,
        isCharging: Bool
    ) {
        let trackKey = partKind != nil ? "\(deviceID)_\(partKind!.rawValue)" : deviceID
        var tracker = trackers[trackKey] ?? DeviceAlertTracker()

        let warningThreshold = Defaults[.lowBatteryWarningThreshold]

        // 1. Charging suppression and re-arming
        if isCharging {
            tracker.isCharging = true
            tracker.lastObservedPercentage = percentage
            // Re-arm when it starts charging
            tracker.warningAlertFired = false
            tracker.criticalAlertFired = false
            tracker.lastWarningFiredTime = nil
            trackers[trackKey] = tracker

            // If an amber dot is active for this device, dismiss it upon charging
            if hasActiveLowBatteryDot && activeDotDeviceID == deviceID {
                dismissDot()
            }
            return
        }

        tracker.isCharging = false

        // 2. Re-arming when level rises above threshold + 5 or reconnects above threshold
        if tracker.wasDisconnected {
            tracker.wasDisconnected = false
            if percentage >= warningThreshold {
                tracker.warningAlertFired = false
                tracker.lastWarningFiredTime = nil
            }
            if percentage >= 10 { // 5 + 5
                tracker.criticalAlertFired = false
            }
        } else {
            if percentage >= (warningThreshold + 5) {
                tracker.warningAlertFired = false
            }
            if percentage >= 10 {
                tracker.criticalAlertFired = false
            }
        }

        let previous = tracker.lastObservedPercentage
        tracker.lastObservedPercentage = percentage

        // 3. Critical Alert at 5%
        // "Critical stage fires once when crossing below 5%, even if the warning already fired."
        if Defaults[.enableCriticalBatteryAlert] && percentage < 5 {
            let crossedCritical: Bool
            if let prev = previous {
                crossedCritical = prev >= 5
            } else {
                // First observation below 5%
                crossedCritical = true
            }

            if crossedCritical && !tracker.criticalAlertFired {
                tracker.criticalAlertFired = true
                trackers[trackKey] = tracker
                triggerAlert(
                    deviceID: deviceID,
                    deviceName: deviceName,
                    iconName: iconName,
                    partKind: partKind,
                    partName: partName,
                    percentage: percentage,
                    isCritical: true
                )
                return
            }
        }

        // 4. Warning Alert at Threshold (10 / 15 / 20 / 25%)
        // "Edge-triggered. Alert only when a device's level crosses from at or above the threshold to below it."
        // "Don't repeat the warning for the same device within 30 minutes."
        if Defaults[.enableLowBatteryAlerts] && percentage < warningThreshold {
            let crossedWarning: Bool
            if let prev = previous {
                crossedWarning = prev >= warningThreshold
            } else {
                // First observation below threshold
                crossedWarning = true
            }

            if crossedWarning && !tracker.warningAlertFired {
                let now = Date()
                let thirtyMinutes: TimeInterval = 30 * 60
                let canFire: Bool
                if let lastFired = tracker.lastWarningFiredTime {
                    canFire = now.timeIntervalSince(lastFired) >= thirtyMinutes
                } else {
                    canFire = true
                }

                if canFire {
                    tracker.warningAlertFired = true
                    tracker.lastWarningFiredTime = now
                    trackers[trackKey] = tracker
                    triggerAlert(
                        deviceID: deviceID,
                        deviceName: deviceName,
                        iconName: iconName,
                        partKind: partKind,
                        partName: partName,
                        percentage: percentage,
                        isCritical: false
                    )
                    return
                }
            }
        }

        trackers[trackKey] = tracker
    }

    // MARK: - Presentation & Alerts

    private func triggerAlert(
        deviceID: String,
        deviceName: String,
        iconName: String,
        partKind: DeviceBatteryPart.PartKind?,
        partName: String?,
        percentage: Int,
        isCritical: Bool
    ) {
        // Skip if muted
        if isDeviceMuted(deviceID) { return }

        // Classify device kind
        let kind = classifyKind(name: deviceName)

        // Lookup or construct DeviceIdentity for 3D showcase integration
        let normalized = deviceID.lowercased().replacingOccurrences(of: ":", with: "-")
        let stableKey = "bt_\(normalized)"
        let identity = DeviceMonitor.shared.activeDevices[stableKey] ?? DeviceIdentity(
            stableKey: stableKey,
            kind: kind,
            displayName: deviceName,
            vendor: "Bluetooth",
            model: deviceName,
            connectionType: .bluetooth,
            batteryPercentage: percentage,
            iconName: iconName
        )

        let alertItem = BluetoothBatteryAlertItem(
            deviceID: deviceID,
            deviceName: deviceName,
            iconName: iconName,
            partKind: partKind,
            partName: partName,
            percentage: percentage,
            isCritical: isCritical,
            deviceKind: kind,
            deviceIdentity: identity
        )

        self.currentAlert = alertItem

        // Optional sound
        if Defaults[.playLowBatteryAlertSound] {
            playAlertSound()
        }

        // Haptic feedback
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)

        // Set amber dot on notch if enabled
        if Defaults[.keepLowBatteryDot] {
            self.hasActiveLowBatteryDot = true
            self.activeDotDeviceID = deviceID
        }

        // Show collapsed notch popup
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            self.isShowingAlertPopup = true
        }

        // Route through centralized Live Activity Hub with liquid-drop animation
        let hubActivity = LiveActivity(
            id: "bt_battery_\(deviceID)",
            source: "battery",
            kind: .alert,
            priority: isCritical ? LiveActivityPriority.critical : 85,
            tint: isCritical ? LiveActivitySeverity.critical.color : LiveActivitySeverity.warning.color,
            duration: 5.0,
            coalescingKey: "battery_\(deviceID)",
            payload: LiveActivityPayload(
                title: alertItem.titleText,
                subtitle: alertItem.detailLineText,
                iconName: iconName,
                body: alertItem.actionLineText,
                iconColor: isCritical ? .red : .orange,
                value: Double(percentage) / 100.0
            )
        )
        LiveActivityCenter.shared.submit(hubActivity)

        // Schedule auto-dismissal for ~5 seconds
        scheduleDismissal(seconds: 5.0)
    }

    public func dismissAlert() {
        dismissTask?.cancel()
        dismissTask = nil

        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            self.isShowingAlertPopup = false
            self.currentAlert = nil
        }
    }

    public func dismissDot() {
        withAnimation(.easeInOut(duration: 0.2)) {
            self.hasActiveLowBatteryDot = false
            self.activeDotDeviceID = nil
        }
    }

    private func handleHoverChanged() {
        if isHovering {
            // Cancel auto-dismissal while user hovers over popup
            dismissTask?.cancel()
            dismissTask = nil
        } else if isShowingAlertPopup {
            // Re-schedule dismissal when cursor leaves
            scheduleDismissal(seconds: 2.0)
        }
    }

    private func scheduleDismissal(seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.dismissAlert()
        }
    }

    private func playAlertSound() {
        if let sound = NSSound(named: NSSound.Name("Tink")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    // MARK: - Muting Helpers

    public func isDeviceMuted(_ deviceID: String) -> Bool {
        return Defaults[.mutedBatteryAlertDeviceIDs].contains(deviceID)
    }

    public func toggleDeviceMute(_ deviceID: String) {
        var muted = Defaults[.mutedBatteryAlertDeviceIDs]
        if muted.contains(deviceID) {
            muted.removeAll { $0 == deviceID }
        } else {
            muted.append(deviceID)
        }
        Defaults[.mutedBatteryAlertDeviceIDs] = muted
    }

    // MARK: - Watchdog Slow Timer (2 minutes, with leeway)
    // "slow timer (every 2 minutes, with timer leeway) that runs only while at least one connected device reports a battery level. No timer otherwise."

    public func updateTimerState(connectedDevices: [BluetoothDeviceInfo]? = nil) {
        let devList = connectedDevices ?? BluetoothService.shared.connectedDevices
        var hasBatteryReportingDevice = devList.contains { device in
            (device.batteryPercentage != nil) || !device.batteryParts.isEmpty
        }

        #if DEBUG
        if isSimulating && !simulatedUnknownBattery && !simulatedIsDisconnected {
            hasBatteryReportingDevice = true
        }
        #endif

        if hasBatteryReportingDevice {
            startSlowTimerIfNeeded()
        } else {
            stopSlowTimer()
        }
    }

    private func startSlowTimerIfNeeded() {
        guard slowTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        // 2 minutes = 120 seconds, leeway = 15 seconds
        timer.schedule(deadline: .now() + 120, repeating: 120, leeway: .seconds(15))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                BluetoothService.shared.refreshDevices()
                self?.evaluateDevices(BluetoothService.shared.connectedDevices)
            }
        }
        timer.resume()
        self.slowTimer = timer
    }

    private func stopSlowTimer() {
        slowTimer?.cancel()
        slowTimer = nil
    }

    // MARK: - Device Kind Classification

    private func classifyKind(name: String) -> DeviceKind {
        let lower = name.lowercased()
        if lower.contains("airpod") {
            if lower.contains("max") { return .headphones }
            return .earbuds
        } else if lower.contains("buds") || lower.contains("earphone") {
            return .earbuds
        } else if lower.contains("headphone") || lower.contains("wh-1000") || lower.contains("bose") {
            return .headphones
        } else if lower.contains("speaker") || lower.contains("soundlink") || lower.contains("boom") {
            return .speaker
        } else if lower.contains("mouse") {
            return .mouse
        } else if lower.contains("keyboard") {
            return .keyboard
        }
        return .earbuds
    }

    // MARK: - DEBUG-only Simulator
    #if DEBUG
    public func setSimulatedBatteryLevel(_ percentage: Double) {
        self.simulatedPercentage = percentage
        applySimulation()
    }

    public func toggleSimulatedCharging(_ isCharging: Bool) {
        self.simulatedIsCharging = isCharging
        applySimulation()
    }

    public func toggleSimulatedDisconnection(_ isDisconnected: Bool) {
        self.simulatedIsDisconnected = isDisconnected
        let simID = "sim_airpods_pro"
        let trackKey = simulatedHasParts ? "\(simID)_\(simulatedSelectedPart.rawValue)" : simID
        if isDisconnected {
            trackers[trackKey]?.wasDisconnected = true
            trackers[trackKey]?.lastObservedPercentage = nil
        }
        applySimulation()
    }

    public func resetSimulationStates() {
        trackers.removeAll()
        dismissAlert()
        dismissDot()
        simulatedPercentage = 100
        simulatedIsCharging = false
        simulatedUnknownBattery = false
        simulatedIsDisconnected = false
    }

    public func applySimulation() {
        guard isSimulating else { return }

        let simID = "sim_airpods_pro"
        if simulatedIsDisconnected {
            return
        }

        if simulatedUnknownBattery {
            // Unknown battery: skip logic completely
            return
        }

        let intPercent = Int(simulatedPercentage)

        if simulatedHasParts {
            let part = DeviceBatteryPart(
                kind: simulatedSelectedPart,
                percentage: intPercent,
                isCharging: simulatedIsCharging
            )
            evaluateUnit(
                deviceID: simID,
                deviceName: simulatedDeviceName,
                iconName: "airpodspro",
                partKind: part.kind,
                partName: part.kind.displayName,
                percentage: part.percentage,
                isCharging: part.isCharging
            )
        } else {
            evaluateUnit(
                deviceID: simID,
                deviceName: simulatedDeviceName,
                iconName: "airpodspro",
                partKind: nil,
                partName: nil,
                percentage: intPercent,
                isCharging: simulatedIsCharging
            )
        }
    }
    #endif
}
