//
//  LiveActivitySimulator.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

#if DEBUG
import Combine
import Foundation
import SwiftUI

/// DEBUG-only simulator engine for testing all LiveActivity types, coalescing,
/// priority preemption, hover pause, and drop animations on demand.
@MainActor
public final class LiveActivitySimulator: ObservableObject {
    public static let shared = LiveActivitySimulator()

    private var progressTask: Task<Void, Never>?
    private var volumeSweepTask: Task<Void, Never>?

    private init() {}

    // MARK: - 1. Rapid Volume Sweep (Coalescing Test)

    public func fireRapidVolumeSweep() {
        volumeSweepTask?.cancel()
        volumeSweepTask = Task { @MainActor in
            var current: Double = 0.20
            while current <= 0.95 {
                let activity = LiveActivity(
                    id: "sim_volume",
                    source: "volume",
                    kind: .hud,
                    priority: LiveActivityPriority.hud,
                    tint: .accentColor,
                    duration: 1.5,
                    coalescingKey: "volume",
                    payload: LiveActivityPayload(
                        title: "Volume",
                        subtitle: "\(Int(round(current * 100)))%",
                        iconName: current > 0.6 ? "speaker.wave.3.fill" : "speaker.wave.2.fill",
                        value: current,
                        isDraggable: true
                    ),
                    pauseDismissalOnHover: true
                )
                LiveActivityCenter.shared.submit(activity)
                current += 0.12
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    // MARK: - 2. Audio Output Device Change

    public func fireAudioOutputDeviceChange(name: String = "AirPods Max", icon: String = "headphones") {
        let activity = LiveActivity(
            id: "sim_audio_output",
            source: "audio_output",
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: LiveActivitySeverity.info.color,
            duration: 2.5,
            coalescingKey: "audio_output",
            payload: LiveActivityPayload(
                title: name,
                subtitle: String(localized: "Audio Output Device"),
                iconName: icon,
                body: String(localized: "Audio routed to \(name)")
            ),
            pauseDismissalOnHover: true
        )
        LiveActivityCenter.shared.submit(activity)
    }

    // MARK: - 3. Display Brightness (Multi-Display) & Keyboard Backlight

    public func fireDisplayBrightness(name: String = "Studio Display", value: Double = 0.75) {
        let activity = LiveActivity(
            id: "sim_brightness",
            source: "brightness",
            kind: .hud,
            priority: LiveActivityPriority.hud,
            tint: .orange,
            duration: 1.5,
            coalescingKey: "brightness_sim",
            payload: LiveActivityPayload(
                title: name,
                subtitle: "\(Int(round(value * 100)))%",
                iconName: "sun.max.fill",
                value: value,
                isDraggable: true
            ),
            pauseDismissalOnHover: true
        )
        LiveActivityCenter.shared.submit(activity)
    }

    public func fireKeyboardBacklight(value: Double = 0.60) {
        let activity = LiveActivity(
            id: "sim_keyboard_brightness",
            source: "keyboard_brightness",
            kind: .hud,
            priority: LiveActivityPriority.hud,
            tint: .cyan,
            duration: 1.5,
            coalescingKey: "keyboard_brightness",
            payload: LiveActivityPayload(
                title: String(localized: "Keyboard"),
                subtitle: "\(Int(round(value * 100)))%",
                iconName: "keyboard",
                value: value,
                isDraggable: true
            ),
            pauseDismissalOnHover: true
        )
        LiveActivityCenter.shared.submit(activity)
    }

    // MARK: - 4. Microphone Mute & Mic In-Use

    public func fireMicrophoneInUse(appName: String = "Zoom") {
        let activity = LiveActivity(
            id: "sim_mic_in_use",
            source: "microphone",
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: LiveActivitySeverity.warning.color,
            duration: 3.5,
            coalescingKey: "mic_in_use",
            payload: LiveActivityPayload(
                title: String(localized: "Microphone Active"),
                subtitle: appName,
                iconName: "mic.fill",
                body: String(localized: "\(appName) is actively recording audio")
            ),
            pauseDismissalOnHover: true
        )
        LiveActivityCenter.shared.submit(activity)
    }

    public func fireMicrophoneMute(isMuted: Bool = true) {
        let activity = LiveActivity(
            id: "sim_mic_mute",
            source: "microphone",
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: isMuted ? LiveActivitySeverity.critical.color : LiveActivitySeverity.info.color,
            duration: 2.5,
            coalescingKey: "mic_mute",
            payload: LiveActivityPayload(
                title: isMuted ? String(localized: "Microphone Muted") : String(localized: "Microphone Unmuted"),
                subtitle: String(localized: "System Microphone"),
                iconName: isMuted ? "mic.slash.fill" : "mic.fill",
                body: isMuted ? String(localized: "Hardware audio input silenced") : String(localized: "Hardware audio input live")
            ),
            pauseDismissalOnHover: true
        )
        LiveActivityCenter.shared.submit(activity)
    }

    // MARK: - 5. Camera In-Use

    public func fireCameraInUse(appName: String = "FaceTime") {
        let activity = LiveActivity(
            id: "sim_camera_in_use",
            source: "camera",
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: LiveActivitySeverity.warning.color,
            duration: 3.5,
            coalescingKey: "camera_alert",
            payload: LiveActivityPayload(
                title: String(localized: "Camera Active"),
                subtitle: appName,
                iconName: "camera.fill",
                body: String(localized: "\(appName) is accessing your camera")
            ),
            pauseDismissalOnHover: true
        )
        LiveActivityCenter.shared.submit(activity)
    }

    // MARK: - 6. Battery & Charging

    public func firePowerPluggedIn(level: Int = 68) {
        let activity = LiveActivity(
            id: "sim_power_plugged",
            source: "battery",
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: LiveActivitySeverity.info.color,
            duration: 3.0,
            coalescingKey: "battery_power",
            payload: LiveActivityPayload(
                title: String(localized: "Power Connected"),
                subtitle: "Charging at \(level)%",
                iconName: "powerplug.fill",
                body: String(localized: "Power adapter attached")
            ),
            pauseDismissalOnHover: true
        )
        LiveActivityCenter.shared.submit(activity)
    }

    public func fireLowBattery15() {
        let activity = LiveActivity(
            id: "sim_low_battery_15",
            source: "battery",
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: LiveActivitySeverity.warning.color,
            duration: 4.5,
            coalescingKey: "battery_threshold",
            payload: LiveActivityPayload(
                title: String(localized: "Battery Low"),
                subtitle: "15% left",
                iconName: "battery.25",
                body: String(localized: "Connect to power soon to keep working.")
            ),
            pauseDismissalOnHover: true
        )
        LiveActivityCenter.shared.submit(activity)
    }

    public func fireCriticalBattery5() {
        let activity = LiveActivity(
            id: "sim_crit_battery_5",
            source: "battery",
            kind: .alert,
            priority: LiveActivityPriority.critical,
            tint: LiveActivitySeverity.critical.color,
            duration: 6.0,
            coalescingKey: "battery_threshold",
            payload: LiveActivityPayload(
                title: String(localized: "Almost Empty"),
                subtitle: "4% left. It may shut down soon.",
                iconName: "battery.0",
                body: String(localized: "Connect your Mac to power immediately.")
            ),
            pauseDismissalOnHover: true
        )
        LiveActivityCenter.shared.submit(activity)
    }

    // MARK: - 7. Caps Lock Toggle

    public func fireCapsLockToggle(isOn: Bool = true) {
        let activity = LiveActivity(
            id: "sim_caps_lock",
            source: "caps_lock",
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: LiveActivitySeverity.info.color,
            duration: 2.0,
            coalescingKey: "caps_lock",
            payload: LiveActivityPayload(
                title: isOn ? String(localized: "Caps Lock On") : String(localized: "Caps Lock Off"),
                subtitle: String(localized: "Keyboard"),
                iconName: isOn ? "capslock.fill" : "capslock",
                body: isOn ? String(localized: "Capital letters enabled") : String(localized: "Standard typing mode")
            ),
            pauseDismissalOnHover: true
        )
        LiveActivityCenter.shared.submit(activity)
    }

    // MARK: - 8. Timer & Pomodoro Progress Ring

    public func firePomodoroSession() {
        TimerActivitySource.shared.startPomodoro(focusMinutes: 25)
    }

    // MARK: - 9. Upcoming Calendar Event

    public func fireUpcomingCalendarEvent(title: String = "Sprint Demo & Review", minutesAway: Int = 5) {
        let activity = LiveActivity(
            id: "sim_calendar_event",
            source: "calendar_events",
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: .blue,
            duration: 5.0,
            coalescingKey: "calendar_upcoming",
            payload: LiveActivityPayload(
                title: title,
                subtitle: String(localized: "Starts in \(minutesAway) minutes"),
                iconName: "calendar.badge.clock",
                body: String(localized: "Video call link ready • Google Meet"),
                actionTitle: String(localized: "Join"),
                action: {
                    print("Simulated calendar action clicked")
                }
            ),
            pauseDismissalOnHover: true
        )
        LiveActivityCenter.shared.submit(activity)
    }

    // MARK: - 10. Network & VPN Status

    public func fireNetworkConnected() {
        let activity = LiveActivity(
            id: "sim_net_online",
            source: "network",
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: LiveActivitySeverity.info.color,
            duration: 3.0,
            coalescingKey: "network_status",
            payload: LiveActivityPayload(
                title: String(localized: "Connected to Network"),
                subtitle: "Wi-Fi · 5 GHz",
                iconName: "wifi",
                body: String(localized: "High-speed internet active")
            ),
            pauseDismissalOnHover: true
        )
        LiveActivityCenter.shared.submit(activity)
    }

    public func fireNetworkDisconnected() {
        let activity = LiveActivity(
            id: "sim_net_offline",
            source: "network",
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: LiveActivitySeverity.warning.color,
            duration: 3.0,
            coalescingKey: "network_status",
            payload: LiveActivityPayload(
                title: String(localized: "Network Disconnected"),
                subtitle: String(localized: "No Internet Connection"),
                iconName: "wifi.slash",
                body: String(localized: "Your Mac is currently offline")
            ),
            pauseDismissalOnHover: true
        )
        LiveActivityCenter.shared.submit(activity)
    }

    public func fireVPNConnected() {
        let activity = LiveActivity(
            id: "sim_vpn_connected",
            source: "network",
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: LiveActivitySeverity.info.color,
            duration: 3.0,
            coalescingKey: "network_status",
            payload: LiveActivityPayload(
                title: String(localized: "VPN Connected"),
                subtitle: "WireGuard · utun3",
                iconName: "shield.lefthalf.filled",
                body: String(localized: "Secure encrypted tunnel active")
            ),
            pauseDismissalOnHover: true
        )
        LiveActivityCenter.shared.submit(activity)
    }

    // MARK: - 11. Focus Mode (Experimental)

    public func fireFocusModeToggle(isOn: Bool = true) {
        let activity = LiveActivity(
            id: "sim_focus_mode",
            source: "focus_mode",
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: isOn ? .indigo : LiveActivitySeverity.info.color,
            duration: 2.5,
            coalescingKey: "focus_mode",
            payload: LiveActivityPayload(
                title: isOn ? String(localized: "Focus Mode On") : String(localized: "Focus Mode Off"),
                subtitle: String(localized: "Do Not Disturb"),
                iconName: isOn ? "moon.fill" : "moon",
                body: isOn ? String(localized: "Silencing notifications and alerts") : String(localized: "Standard alerts restored")
            ),
            pauseDismissalOnHover: true
        )
        LiveActivityCenter.shared.submit(activity)
    }

    // MARK: - Legacy Simulator Triggers

    public func fireTwoAlertsAtOnce() {
        let alert1 = LiveActivity(
            id: "sim_airpods_\(UUID().uuidString.prefix(4))",
            source: "airpods",
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: LiveActivitySeverity.info.color,
            duration: 3.5,
            payload: LiveActivityPayload(
                title: "AirPods Pro",
                subtitle: "Connected · 92%",
                iconName: "headphones",
                value: 0.92
            )
        )
        let alert2 = LiveActivity(
            id: "sim_battery_\(UUID().uuidString.prefix(4))",
            source: "battery",
            kind: .alert,
            priority: 85,
            tint: LiveActivitySeverity.warning.color,
            duration: 4.0,
            payload: LiveActivityPayload(
                title: "Magic Keyboard",
                subtitle: "12% left · Charge soon",
                iconName: "keyboard",
                value: 0.12
            )
        )
        LiveActivityCenter.shared.submit(alert1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            LiveActivityCenter.shared.submit(alert2)
        }
    }

    public func fireLongNotification() {
        let activity = LiveActivity(
            id: "sim_notif_\(UUID().uuidString.prefix(4))",
            source: "notifications",
            kind: .notification,
            priority: LiveActivityPriority.notification,
            tint: .blue,
            duration: 5.0,
            payload: LiveActivityPayload(
                title: "Slack · #design-critique",
                subtitle: "Sarah Miller (Lead Designer)",
                iconName: "bubble.left.and.bubble.right.fill",
                body: "Just pushed the new dynamic notch specifications for macOS. Please take a look at the attached drops and let me know if we need tighter physics.",
                actionTitle: "Reply",
                action: { print("Simulated Reply tapped") },
                secondaryActionTitle: "Mark as Read",
                secondaryAction: { print("Simulated Mark as Read tapped") }
            ),
            pauseDismissalOnHover: true
        )
        LiveActivityCenter.shared.submit(activity)
    }

    public func fireProgressDownload() {
        progressTask?.cancel()
        progressTask = Task { @MainActor in
            var pct: Double = 0.05
            while pct <= 1.0 {
                let activity = LiveActivity(
                    id: "sim_download",
                    source: "downloads",
                    kind: .progress,
                    priority: LiveActivityPriority.progress,
                    tint: .effectiveAccent,
                    duration: pct >= 1.0 ? 2.0 : nil,
                    coalescingKey: "sim_download",
                    payload: LiveActivityPayload(
                        title: "Xcode_16_Beta.dmg",
                        subtitle: pct >= 1.0 ? "Completed" : "\(Int(pct * 100))% • 45 MB/s",
                        iconName: pct >= 1.0 ? "checkmark.circle.fill" : "arrow.down.circle.fill",
                        value: pct,
                        progressTotal: 100,
                        progressCurrent: pct * 100
                    ),
                    pauseDismissalOnHover: true
                )
                LiveActivityCenter.shared.submit(activity)
                if pct >= 1.0 { break }
                pct += 0.05
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    public func fireOngoingTimer() {
        TimerActivitySource.shared.startTimer(seconds: 120, title: "Egg Timer")
    }

    public func fireBluetoothConnect() {
        fireBluetoothConnection()
    }

    public func fireBluetoothConnection() {
        let activity = LiveActivity(
            id: "sim_bt_\(UUID().uuidString.prefix(4))",
            source: "bluetooth",
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: LiveActivitySeverity.info.color,
            duration: 3.0,
            payload: LiveActivityPayload(
                title: "MX Master 3S",
                subtitle: "Connected",
                iconName: "magicmouse.fill"
            )
        )
        LiveActivityCenter.shared.submit(activity)
    }

    public func fireLowBattery() {
        fireLowBattery15()
    }

    public func fireCriticalBattery() {
        fireCriticalBattery5()
    }
}
#endif
