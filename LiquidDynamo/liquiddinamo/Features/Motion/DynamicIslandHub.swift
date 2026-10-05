//
//  DynamicIslandHub.swift
//  LiquidDynamo
//
//  Created for Dynamic Island Status & Notification System
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

/// Central intelligent status hub orchestrating all dynamic expansion triggers
/// around the MacBook notch with adaptive Liquid Glass sizing and priority scheduling.
@MainActor
public final class DynamicIslandHub: ObservableObject {
    public static let shared = DynamicIslandHub()

    // MARK: - State Properties

    @Published public private(set) var activeDownload: DownloadActivityState? = nil
    @Published public private(set) var activePrivacySession: PrivacySessionState? = nil

    private var cancellables = Set<AnyCancellable>()
    private var lastObservedTrack: String = ""
    private var lastObservedVolume: Float = -1.0
    private var lastVolumeChangeTime: Date = .distantPast

    public struct DownloadActivityState: Identifiable, Sendable {
        public let id: String
        public var fileName: String
        public var progress: Double
        public var speed: String
        public var isPaused: Bool
    }

    public struct PrivacySessionState: Identifiable, Sendable {
        public let id: String
        public var type: String // "Microphone", "Camera", "Screen Recording"
        public var appName: String
        public var startTime: Date
    }

    private init() {
        setupMusicTriggers()
        setupVolumeTriggers()
        setupBatteryAndPowerTriggers()
        setupBluetoothTriggers()
        setupNotificationHubTriggers()
    }

    // MARK: - 1. Music Playback & Track Change Triggers

    private func setupMusicTriggers() {
        Publishers.CombineLatest(MusicManager.shared.$songTitle, MusicManager.shared.$isPlaying)
            .receive(on: RunLoop.main)
            .sink { [weak self] songTitle, isPlaying in
                guard let self = self else { return }
                guard isPlaying, !songTitle.isEmpty else { return }

                // Check if track actually changed
                if songTitle != self.lastObservedTrack {
                    self.lastObservedTrack = songTitle
                    self.triggerTrackChangeAnnouncement(
                        title: songTitle,
                        artist: MusicManager.shared.artistName
                    )
                }
            }
            .store(in: &cancellables)
    }

    public func triggerTrackChangeAnnouncement(title: String, artist: String) {
        guard IslandController.shared.state != .expanded else { return }

        let payload = AlertPayload(
            id: "music.trackChange.\(title)",
            kind: .musicTrackChange(title: title, artist: artist),
            title: title,
            subtitle: artist,
            iconName: "music.note",
            iconColor: Defaults[.playerColorTinting] ? Color(nsColor: MusicManager.shared.avgColor) : .green,
            dwellDuration: 3.5,
            customSize: CGSize(width: 440, height: 60),
            action: {
                IslandController.shared.setExpanded(view: .home)
            }
        )

        IslandController.shared.showAlert(payload: payload)
    }

    // MARK: - 2. Volume & Audio Control Triggers

    private func setupVolumeTriggers() {
        VolumeManager.shared.$rawVolume
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] newVolume in
                guard let self = self else { return }
                // Avoid redundant bursts when notch is already open
                guard IslandController.shared.state != .expanded else { return }

                let now = Date()
                if abs(newVolume - self.lastObservedVolume) > 0.01 || now.timeIntervalSince(self.lastVolumeChangeTime) > 0.15 {
                    self.lastObservedVolume = newVolume
                    self.lastVolumeChangeTime = now
                    self.triggerVolumeHUD(volume: Double(newVolume), isMuted: VolumeManager.shared.isMuted)
                }
            }
            .store(in: &cancellables)
    }

    public func triggerVolumeHUD(volume: Double, isMuted: Bool) {
        let payload = AlertPayload(
            id: "system.hud.volume",
            kind: .systemHUD(
                title: isMuted ? "Muted" : "Volume",
                icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                value: isMuted ? 0.0 : volume
            ),
            title: isMuted ? "Muted" : "Volume",
            subtitle: "\(Int(volume * 100))%",
            iconName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
            iconColor: isMuted ? .red : .accentColor,
            dwellDuration: 2.0,
            customSize: CGSize(width: 390, height: 50),
            progress: isMuted ? 0.0 : volume,
            action: {
                IslandController.shared.setExpanded(view: .displaySound)
            }
        )

        IslandController.shared.showAlert(payload: payload)
    }

    // MARK: - 3. Battery & Power Status Triggers

    private func setupBatteryAndPowerTriggers() {
        // Charging state changes
        BatteryStatusViewModel.shared.$isCharging
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] isCharging in
                guard let self = self else { return }
                guard IslandController.shared.state != .expanded else { return }
                let level = Double(BatteryStatusViewModel.shared.levelBattery) / 100.0

                if isCharging {
                    self.triggerChargingAlert(level: level)
                }
            }
            .store(in: &cancellables)

        // Low battery state changes
        BatteryStatusViewModel.shared.$levelBattery
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                guard let self = self else { return }
                guard IslandController.shared.state != .expanded else { return }
                let isPlugged = BatteryStatusViewModel.shared.isPluggedIn
                let intLevel = Int(level)

                if !isPlugged && (intLevel == 15 || intLevel == 5) {
                    self.triggerLowBatteryAlert(percentage: intLevel, isCritical: intLevel <= 5)
                }
            }
            .store(in: &cancellables)
    }

    public func triggerChargingAlert(level: Double) {
        let payload = AlertPayload(
            id: "power.charging",
            kind: .chargingConnected(level: level),
            title: "Charging Started",
            subtitle: "\(Int(level * 100))% Available",
            iconName: "bolt.fill",
            iconColor: .green,
            dwellDuration: 3.5,
            customSize: CGSize(width: 380, height: 52),
            progress: level
        )
        IslandController.shared.showAlert(payload: payload)
    }

    public func triggerLowBatteryAlert(percentage: Int, isCritical: Bool) {
        let payload = AlertPayload(
            id: "power.lowBattery",
            kind: .batteryLow(device: "MacBook", percentage: percentage, isCritical: isCritical),
            title: isCritical ? "Critical Battery" : "Low Battery",
            subtitle: "\(percentage)% remaining. Connect power soon.",
            iconName: "battery.25",
            iconColor: isCritical ? .red : .orange,
            dwellDuration: 4.5,
            customSize: CGSize(width: 400, height: 54)
        )
        IslandController.shared.showAlert(payload: payload)
    }

    // MARK: - 4. Bluetooth & AirPods Triggers

    private func setupBluetoothTriggers() {
        BluetoothService.shared.$lastConnectedDeviceName
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] deviceName in
                guard let self = self, !deviceName.isEmpty else { return }
                guard IslandController.shared.state != .expanded else { return }

                let isAirPods = deviceName.localizedCaseInsensitiveContains("AirPods")
                if isAirPods {
                    self.triggerAirPodsAlert(
                        name: deviceName,
                        left: 85,
                        right: 85,
                        caseLevel: 90
                    )
                } else {
                    self.triggerDeviceConnectedAlert(
                        name: deviceName,
                        icon: "headphones"
                    )
                }
            }
            .store(in: &cancellables)
    }

    public func triggerAirPodsAlert(name: String, left: Int? = 85, right: Int? = 85, caseLevel: Int? = 90) {
        let payload = AlertPayload(
            id: "bluetooth.airpods.\(name)",
            kind: .airPodsConnected(name: name, batteryLeft: left, batteryRight: right, batteryCase: caseLevel),
            title: name,
            subtitle: "Connected",
            iconName: "airpodspro",
            iconColor: .white,
            dwellDuration: 4.0,
            customSize: CGSize(width: 410, height: 54),
            action: {
                IslandController.shared.setExpanded(view: .bluetooth)
            }
        )
        IslandController.shared.showAlert(payload: payload)
    }

    public func triggerDeviceConnectedAlert(name: String, icon: String = "headphones") {
        let payload = AlertPayload(
            id: "bluetooth.device.\(name)",
            kind: .deviceConnected(name: name, icon: icon),
            title: name,
            subtitle: "Connected",
            iconName: icon,
            iconColor: .blue,
            dwellDuration: 3.5,
            customSize: CGSize(width: 380, height: 52),
            action: {
                IslandController.shared.setExpanded(view: .bluetooth)
            }
        )
        IslandController.shared.showAlert(payload: payload)
    }

    // MARK: - 5. Downloads & File Transfers Triggers

    public func showDownload(fileName: String, progress: Double, speed: String = "5.2 MB/s") {
        let download = DownloadActivityState(
            id: "download.\(fileName)",
            fileName: fileName,
            progress: progress,
            speed: speed,
            isPaused: false
        )
        self.activeDownload = download

        let payload = AlertPayload(
            id: download.id,
            kind: .downloadProgress(fileName: fileName, progress: progress, speed: speed),
            title: fileName,
            subtitle: "\(Int(progress * 100))% • \(speed)",
            iconName: "arrow.down.circle.fill",
            iconColor: .cyan,
            dwellDuration: 4.0,
            customSize: CGSize(width: 420, height: 56),
            progress: progress,
            action: {
                IslandController.shared.setExpanded(view: .shelf)
            }
        )
        IslandController.shared.showAlert(payload: payload)
    }

    public func completeDownload(fileName: String) {
        let payload = AlertPayload(
            id: "download.complete.\(fileName)",
            kind: .custom(title: "Download Complete", subtitle: fileName, icon: "checkmark.circle.fill"),
            title: "Download Complete",
            subtitle: fileName,
            iconName: "checkmark.circle.fill",
            iconColor: .green,
            dwellDuration: 3.0,
            customSize: CGSize(width: 380, height: 50),
            action: {
                IslandController.shared.setExpanded(view: .shelf)
            }
        )
        IslandController.shared.showAlert(payload: payload)
        activeDownload = nil
    }

    // MARK: - 6. Notifications & Messages Triggers

    private func setupNotificationHubTriggers() {
        // Notifications submitted to LiveActivityCenter are rendered via
        // LiveActivityNotificationCardView in belowArea with interactive actions.
    }

    public func triggerNotificationCard(appName: String, sender: String, message: String) {
        guard IslandController.shared.state != .expanded else { return }

        let payload = AlertPayload(
            id: "notification.\(UUID().uuidString)",
            kind: .notification(appName: appName, sender: sender, message: message),
            title: sender,
            subtitle: message,
            iconName: "bell.fill",
            iconColor: .orange,
            dwellDuration: 4.0,
            customSize: CGSize(width: 420, height: 60)
        )
        IslandController.shared.showAlert(payload: payload)
    }

    // MARK: - 7. Microphone, Camera & Screen Recording Triggers

    public func triggerPrivacyAlert(type: String, appName: String) {
        let payload = AlertPayload(
            id: "privacy.\(type)",
            kind: .privacyIndicator(type: type, appName: appName),
            title: "\(type) in Use",
            subtitle: "by \(appName)",
            iconName: type.lowercased().contains("screen") ? "record.circle" : (type.lowercased().contains("mic") ? "mic.fill" : "camera.fill"),
            iconColor: type.lowercased().contains("mic") ? .orange : (type.lowercased().contains("screen") ? .red : .green),
            dwellDuration: 3.5,
            customSize: CGSize(width: 360, height: 48)
        )
        IslandController.shared.showAlert(payload: payload)
    }
}
