//
//  PowerActivitySource.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import Combine
import Foundation
import SwiftUI

/// Emits LiveActivity alerts for power events: plugged in, charging started/stopped,
/// and low battery thresholds adhering to the 15% (warning) and 5% (critical) rules.
/// Reuses BatteryActivityManager.shared and BatteryStatusViewModel.shared.
@MainActor
public final class PowerActivitySource: LiveActivitySource {
    public let identifier: String = "battery"

    private let subject = PassthroughSubject<LiveActivity, Never>()
    public var activityPublisher: AnyPublisher<LiveActivity, Never> {
        subject.eraseToAnyPublisher()
    }

    private var cancellables = Set<AnyCancellable>()
    private var wasPluggedIn: Bool?
    private var wasCharging: Bool?
    private var lastEmittedLevelWarning: Int? // 15 or 5
    private var isStarted = false

    public static let shared = PowerActivitySource()

    private init() {}

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        let batteryVM = BatteryStatusViewModel.shared
        wasPluggedIn = batteryVM.isPluggedIn
        wasCharging = batteryVM.isCharging

        // 1. Observe Plugged-in state
        batteryVM.$isPluggedIn
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isPlugged in
                guard let self = self else { return }
                if self.wasPluggedIn != nil && self.wasPluggedIn != isPlugged {
                    self.emitPowerSourceChanged(isPluggedIn: isPlugged, level: Int(batteryVM.levelBattery))
                }
                self.wasPluggedIn = isPlugged
            }
            .store(in: &cancellables)

        // 2. Observe Charging state
        batteryVM.$isCharging
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isCharging in
                guard let self = self else { return }
                if self.wasCharging != nil && self.wasCharging != isCharging {
                    self.emitChargingChanged(isCharging: isCharging, level: Int(batteryVM.levelBattery))
                }
                self.wasCharging = isCharging
            }
            .store(in: &cancellables)

        // 3. Observe Battery Level (15% and 5% threshold rules)
        batteryVM.$levelBattery
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                self?.evaluateBatteryLevelRules(Int(level), isCharging: batteryVM.isCharging)
            }
            .store(in: &cancellables)
    }

    public func stop() {
        cancellables.removeAll()
        isStarted = false
    }

    // MARK: - Rule Evaluation

    private func evaluateBatteryLevelRules(_ level: Int, isCharging: Bool) {
        guard !isCharging else {
            lastEmittedLevelWarning = nil
            return
        }

        if level <= 5 {
            if lastEmittedLevelWarning != 5 {
                lastEmittedLevelWarning = 5
                emitCriticalBatteryAlert(level: level)
            }
        } else if level <= 15 {
            if lastEmittedLevelWarning != 15 && lastEmittedLevelWarning != 5 {
                lastEmittedLevelWarning = 15
                emitLowBatteryAlert(level: level)
            }
        } else {
            // Reset state if charged back up above 15%
            lastEmittedLevelWarning = nil
        }
    }

    // MARK: - Activity Emission

    private func emitPowerSourceChanged(isPluggedIn: Bool, level: Int) {
        let title = isPluggedIn ? String(localized: "Power Connected") : String(localized: "Power Disconnected")
        let subtitle = isPluggedIn ? String(localized: "Charging at \(level)%") : String(localized: "Running on battery (\(level)%)")
        let icon = isPluggedIn ? "powerplug.fill" : "battery.100"
        let tint = LiveActivitySeverity.info.color

        let activity = LiveActivity(
            id: "power_source_\(isPluggedIn ? "plugged" : "unplugged")",
            source: identifier,
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: tint,
            duration: 3.0,
            coalescingKey: "battery_power",
            payload: LiveActivityPayload(
                title: title,
                subtitle: subtitle,
                iconName: icon,
                body: isPluggedIn ? String(localized: "Power adapter attached") : String(localized: "Switched to battery power")
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
    }

    private func emitChargingChanged(isCharging: Bool, level: Int) {
        guard wasPluggedIn == true else { return } // Avoid double emit on unplug

        let title = isCharging ? String(localized: "Charging Started") : String(localized: "Charging Paused")
        let subtitle = "\(level)%"
        let icon = isCharging ? "bolt.battery.fill" : "battery.100"

        let activity = LiveActivity(
            id: "charging_state_\(isCharging ? "on" : "off")",
            source: identifier,
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: LiveActivitySeverity.info.color,
            duration: 3.0,
            coalescingKey: "battery_charging",
            payload: LiveActivityPayload(
                title: title,
                subtitle: subtitle,
                iconName: icon,
                body: isCharging ? String(localized: "Battery is currently charging") : String(localized: "Optimized battery charging or battery full")
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
    }

    private func emitLowBatteryAlert(level: Int) {
        let activity = LiveActivity(
            id: "battery_low_15",
            source: identifier,
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: LiveActivitySeverity.warning.color,
            duration: 4.5,
            coalescingKey: "battery_threshold",
            payload: LiveActivityPayload(
                title: String(localized: "Battery Low"),
                subtitle: "\(level)% left",
                iconName: "battery.25",
                body: String(localized: "Connect to power soon to keep working.")
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
    }

    private func emitCriticalBatteryAlert(level: Int) {
        let activity = LiveActivity(
            id: "battery_critical_5",
            source: identifier,
            kind: .alert,
            priority: LiveActivityPriority.critical,
            tint: LiveActivitySeverity.critical.color,
            duration: 6.0,
            coalescingKey: "battery_threshold",
            payload: LiveActivityPayload(
                title: String(localized: "Almost Empty"),
                subtitle: "\(level)% left. It may shut down soon.",
                iconName: "battery.0",
                body: String(localized: "Connect your Mac to power immediately.")
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
    }
}
