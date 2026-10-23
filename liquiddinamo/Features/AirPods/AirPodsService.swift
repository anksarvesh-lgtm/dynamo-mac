//
//  AirPodsService.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

/// Central AirPods service coordinating pluggable backends (System Data, BLE, Head Motion, AAP),
/// lifecycle management (zero polling when invisible), and battery low-alert evaluation.
@MainActor
public final class AirPodsService: ObservableObject, AirPodsBackendDelegate {
    public static let shared = AirPodsService()

    // MARK: - Published State & Capabilities

    @Published public private(set) var state: AirPodsState = .disconnected
    @Published public private(set) var capabilities: AirPodsCapabilities = .none

    // MARK: - Pluggable Backends

    private let systemBackend = SystemDataBackend()
    private let bleBackend = BLEAdvertisementBackend()
    private let motionBackend = HeadMotionBackend()
    private let aapBackend = AAPBackend()

    // MARK: - Lifecycle & Consumer Tracking

    /// Number of active UI consumers observing the AirPods scene/dashboard
    private var activeConsumerCount: Int = 0

    // MARK: - Low Battery Alert Tracking (Left, Right, Case)

    private struct PartAlertState {
        var warningAlertFired: Bool = false
        var criticalAlertFired: Bool = false
        var lastWarningTime: Date? = nil
        var isCharging: Bool = false
    }

    private var partTrackers: [String: PartAlertState] = [:]

    private init() {
        systemBackend.delegate = self
        bleBackend.delegate = self
        motionBackend.delegate = self

        // Start lightweight system connection monitoring
        systemBackend.start()
    }

    // MARK: - Visibility & Consumer Lifecycle

    /// Call when the AirPods dashboard / 3D scene appears.
    public func acquireConsumer() {
        activeConsumerCount += 1
        updateBackendLifecycle()
    }

    /// Call when the AirPods dashboard / 3D scene disappears.
    public func releaseConsumer() {
        activeConsumerCount = max(0, activeConsumerCount - 1)
        updateBackendLifecycle()
    }

    // MARK: - Head Motion / Follow My Head

    @Published public private(set) var isHeadTrackingActive: Bool = false

    public func setHeadTracking(enabled: Bool, onError: @escaping (String) -> Void = { _ in }) {
        guard enabled else {
            stopHeadMotion()
            return
        }

        guard state.isConnected else {
            isHeadTrackingActive = false
            onError(String(localized: "AirPods are not connected."))
            return
        }

        guard capabilities.supportsHeadMotion else {
            isHeadTrackingActive = false
            onError(String(localized: "Head tracking is not supported on \(state.modelName)."))
            return
        }

        motionBackend.start { [weak self] errorMsg in
            guard let self = self else { return }
            self.isHeadTrackingActive = false
            onError(errorMsg)
        }
        isHeadTrackingActive = motionBackend.isRunning
    }

    public func stopHeadMotion() {
        isHeadTrackingActive = false
        motionBackend.stop()
        state.roll = nil
        state.pitch = nil
        state.yaw = nil
    }

    private func updateBackendLifecycle() {
        let isVisible = activeConsumerCount > 0
        let isConnected = state.isConnected

        // Rule: "No polling when nothing is visible. Backends start only when AirPods connect or the AirPods view is open."
        let shouldRunActiveSensors = isVisible || isConnected

        if shouldRunActiveSensors {
            bleBackend.setTargetDeviceAddress(state.deviceID)
            bleBackend.start()
            if isVisible && capabilities.supportsHeadMotion && isHeadTrackingActive {
                motionBackend.start()
            } else {
                motionBackend.stop()
            }
        } else {
            bleBackend.stop()
            stopHeadMotion()
        }
    }

    // MARK: - Writes & Control Commands

    /// Single point of entry for commands (noise control, adaptive audio, conversation awareness).
    public func writeCommand(_ command: AirPodsCommand) async -> Result<Void, AirPodsControlError> {
        guard state.isConnected else {
            return .failure(.deviceNotConnected)
        }

        switch command {
        case .setNoiseMode(let mode):
            guard capabilities.supportsNoiseControl else {
                return .failure(.unsupportedOnModel(
                    String(localized: "Noise control is not supported on \(state.modelName).")
                ))
            }
            if mode == .adaptive && !capabilities.supportsAdaptiveAudio {
                return .failure(.unsupportedOnModel(
                    String(localized: "Adaptive Audio requires AirPods Pro (2nd gen).")
                ))
            }
            return await aapBackend.executeCommand(command)

        case .setAdaptiveLevel:
            guard capabilities.supportsAdaptiveAudio else {
                return .failure(.unsupportedOnModel(
                    String(localized: "Adaptive Audio level is not supported on \(state.modelName).")
                ))
            }
            return await aapBackend.executeCommand(command)

        case .setConversationAwareness:
            guard capabilities.supportsConversationAwareness else {
                return .failure(.unsupportedOnModel(
                    String(localized: "Conversation Awareness is not supported on \(state.modelName).")
                ))
            }
            return await aapBackend.executeCommand(command)

        case .setOneBudANC:
            guard capabilities.supportsOneBudANC else {
                return .failure(.unsupportedOnModel(
                    String(localized: "One-bud ANC is not supported on \(state.modelName).")
                ))
            }
            return await aapBackend.executeCommand(command)

        case .setVolume(let vol):
            VolumeManager.shared.setAbsolute(Float32(vol))
            return .success(())
        }
    }

    /// Opens macOS native Sound settings as a fallback when AAP is restricted.
    public func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - AirPodsBackendDelegate Callbacks

    public func backendDidUpdateSystemInfo(
        isConnected: Bool,
        deviceID: String?,
        modelName: String,
        capabilities: AirPodsCapabilities,
        baselineBattery: Int?
    ) {
        self.capabilities = capabilities

        if isConnected {
            state.isConnected = true
            state.deviceID = deviceID
            state.modelName = modelName
            state.headMotionAvailable = capabilities.supportsHeadMotion

            // If baseline battery is known from system and parts are currently nil, populate baseline
            if let base = baselineBattery, state.leftBattery.level == nil && state.rightBattery.level == nil {
                state.leftBattery = AirPodsBatteryPart(level: base, isCharging: false, isConnected: true)
                state.rightBattery = AirPodsBatteryPart(level: base, isCharging: false, isConnected: true)
            }
        } else {
            state = .disconnected
            partTrackers.removeAll()
        }

        updateBackendLifecycle()
    }

    public func backendDidUpdateBLEStatus(
        leftBattery: Int?,
        rightBattery: Int?,
        caseBattery: Int?,
        leftCharging: Bool,
        rightCharging: Bool,
        caseCharging: Bool,
        leftInEar: Bool?,
        rightInEar: Bool?,
        lidOpen: Bool?
    ) {
        // Never show invented values: update only if non-nil
        if let left = leftBattery {
            state.leftBattery = AirPodsBatteryPart(level: left, isCharging: leftCharging, isConnected: true)
            evaluatePartBatteryAlert(partName: "Left Earbud", partKey: "left", percentage: left, isCharging: leftCharging)
        }
        if let right = rightBattery {
            state.rightBattery = AirPodsBatteryPart(level: right, isCharging: rightCharging, isConnected: true)
            evaluatePartBatteryAlert(partName: "Right Earbud", partKey: "right", percentage: right, isCharging: rightCharging)
        }
        if let c = caseBattery {
            state.caseBattery = AirPodsBatteryPart(level: c, isCharging: caseCharging, isConnected: true)
            evaluatePartBatteryAlert(partName: "Charging Case", partKey: "case", percentage: c, isCharging: caseCharging)
        }

        if let lIn = leftInEar { state.leftInEar = lIn }
        if let rIn = rightInEar { state.rightInEar = rIn }
        if let lid = lidOpen { state.lidOpen = lid }
    }

    public func backendDidUpdateHeadMotion(roll: Double, pitch: Double, yaw: Double) {
        state.roll = roll
        state.pitch = pitch
        state.yaw = yaw
    }

    // MARK: - Low Battery Alert Rules (15% Warning, 5% Critical)

    private func evaluatePartBatteryAlert(
        partName: String,
        partKey: String,
        percentage: Int,
        isCharging: Bool
    ) {
        guard Defaults[.enableLowBatteryAlerts] else { return }

        var tracker = partTrackers[partKey] ?? PartAlertState()
        let warningThreshold = Defaults[.lowBatteryWarningThreshold]

        // 1. Re-arm if charging or percentage recovers above threshold + 5
        if isCharging {
            tracker.isCharging = true
            tracker.warningAlertFired = false
            tracker.criticalAlertFired = false
            tracker.lastWarningTime = nil
            partTrackers[partKey] = tracker
            return
        }

        if percentage >= (warningThreshold + 5) {
            tracker.warningAlertFired = false
            tracker.criticalAlertFired = false
        }

        // 2. Critical Stage at 5% (fires once per discharge cycle)
        if Defaults[.enableCriticalBatteryAlert] && percentage <= 5 {
            if !tracker.criticalAlertFired {
                tracker.criticalAlertFired = true
                tracker.warningAlertFired = true
                partTrackers[partKey] = tracker
                fireAlert(partName: partName, percentage: percentage, isCritical: true)
                return
            }
        }

        // 3. Warning Stage at threshold (15% default)
        if percentage <= warningThreshold && !tracker.warningAlertFired {
            // Respect 30-minute cooldown
            if let lastTime = tracker.lastWarningTime, Date().timeIntervalSince(lastTime) < 1800 {
                return
            }

            tracker.warningAlertFired = true
            tracker.lastWarningTime = Date()
            partTrackers[partKey] = tracker
            fireAlert(partName: partName, percentage: percentage, isCritical: false)
        }
    }

    private func fireAlert(partName: String, percentage: Int, isCritical: Bool) {
        let payload = AlertPayload(
            kind: .batteryLow(device: "\(state.modelName) (\(partName))", percentage: percentage, isCritical: isCritical),
            title: isCritical ? String(localized: "Almost empty") : String(localized: "\(partName) low"),
            subtitle: String(localized: "\(state.modelName) • \(percentage)% left"),
            iconName: isCritical ? "battery.0" : "battery.25",
            iconColor: isCritical ? .red : .orange,
            dwellDuration: 3.5
        )

        IslandController.shared.showAlert(payload: payload)

        // Route through centralized Live Activity Hub with liquid-drop presentation
        let activity = LiveActivity(
            id: "airpods_\(partName.lowercased())",
            source: "airpods",
            kind: .alert,
            priority: isCritical ? LiveActivityPriority.critical : LiveActivityPriority.alert,
            tint: isCritical ? LiveActivitySeverity.critical.color : LiveActivitySeverity.warning.color,
            duration: 3.5,
            coalescingKey: "airpods_\(partName)",
            payload: LiveActivityPayload(
                title: isCritical ? String(localized: "Almost empty") : String(localized: "\(partName) low"),
                subtitle: String(localized: "\(state.modelName) • \(percentage)% left"),
                iconName: isCritical ? "battery.0" : "battery.25",
                iconColor: isCritical ? .red : .orange,
                value: Double(percentage) / 100.0
            )
        )
        LiveActivityCenter.shared.submit(activity)

        if Defaults[.playLowBatteryAlertSound] {
            NSSound(named: "Basso")?.play()
        }
    }
}
