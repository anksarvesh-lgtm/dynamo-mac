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
    private var lastObservedMuted: Bool = false
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

    private var lastObservedBrightness: Float = -1.0
    private var lastBrightnessChangeTime: Date = .distantPast

    private init() {
        setupMusicTriggers()
        setupVolumeTriggers()
        setupBrightnessTriggers()
        setupBatteryAndPowerTriggers()
        setupBluetoothTriggers()
        setupDeviceMonitoringTriggers()
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
            customSize: CGSize(width: 440, height: 64),
            action: {
                IslandController.shared.setExpanded(view: .home)
            }
        )

        IslandController.shared.showAlert(payload: payload)
    }

    // MARK: - 2. Volume & Audio Control Triggers

    private func setupVolumeTriggers() {
        Publishers.CombineLatest(VolumeManager.shared.$rawVolume, VolumeManager.shared.$isMuted)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] (newVolume, muted) in
                guard let self = self else { return }
                // Only suppress if user has explicitly pinned the dashboard open
                if IslandController.shared.state == .expanded && IslandController.shared.isPinnedOpen {
                    return
                }

                let now = Date()
                if abs(newVolume - self.lastObservedVolume) > 0.005 || muted != self.lastObservedMuted || now.timeIntervalSince(self.lastVolumeChangeTime) > 0.15 {
                    self.lastObservedVolume = newVolume
                    self.lastObservedMuted = muted
                    self.lastVolumeChangeTime = now
                    self.triggerVolumeHUD(volume: Double(newVolume), isMuted: muted)
                }
            }
            .store(in: &cancellables)
    }

    public func triggerVolumeHUD(volume: Double, isMuted: Bool) {
        let level = isMuted ? 0.0 : volume
        let icon: String
        if isMuted || level <= 0.001 {
            icon = "speaker.slash.fill"
        } else if level > 0.66 {
            icon = "speaker.wave.3.fill"
        } else if level > 0.33 {
            icon = "speaker.wave.2.fill"
        } else {
            icon = "speaker.wave.1.fill"
        }

        let payload = AlertPayload(
            id: "system.hud.volume",
            kind: .systemHUD(
                title: isMuted ? "Muted" : "Volume",
                icon: icon,
                value: level
            ),
            title: isMuted ? "Muted" : "Volume",
            subtitle: isMuted ? "Muted" : "\(Int(round(volume * 100)))%",
            iconName: icon,
            iconColor: isMuted ? .red : .accentColor,
            dwellDuration: 2.0,
            customSize: CGSize(width: 390, height: 50),
            progress: level,
            action: {
                IslandController.shared.setExpanded(view: .displaySound)
            }
        )

        IslandController.shared.showAlert(payload: payload)
    }

    // MARK: - Brightness Triggers

    private func setupBrightnessTriggers() {
        BrightnessManager.shared.$rawBrightness
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] newBrightness in
                guard let self = self else { return }
                if IslandController.shared.state == .expanded && IslandController.shared.isPinnedOpen {
                    return
                }

                let now = Date()
                if abs(newBrightness - self.lastObservedBrightness) > 0.005 || now.timeIntervalSince(self.lastBrightnessChangeTime) > 0.15 {
                    self.lastObservedBrightness = newBrightness
                    self.lastBrightnessChangeTime = now
                    self.triggerBrightnessHUD(brightness: Double(newBrightness))
                }
            }
            .store(in: &cancellables)
    }

    public func triggerBrightnessHUD(brightness: Double) {
        let payload = AlertPayload(
            id: "system.hud.brightness",
            kind: .systemHUD(
                title: "Brightness",
                icon: "sun.max.fill",
                value: brightness
            ),
            title: "Brightness",
            subtitle: "\(Int(round(brightness * 100)))%",
            iconName: "sun.max.fill",
            iconColor: .orange,
            dwellDuration: 2.0,
            customSize: CGSize(width: 390, height: 50),
            progress: brightness,
            action: {
                IslandController.shared.setExpanded(view: .displaySound)
            }
        )

        IslandController.shared.showAlert(payload: payload)
    }

    // MARK: - 3. Battery & Power Status Triggers

    private func setupBatteryAndPowerTriggers() {
        let batteryVM = BatteryStatusViewModel.shared

        batteryVM.$isCharging
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isCharging in
                guard let self = self else { return }
                if isCharging {
                    self.triggerChargingAlert(level: Double(batteryVM.levelBattery / 100.0))
                } else if batteryVM.isPluggedIn == false {
                    self.triggerPowerDisconnectedAlert()
                }
            }
            .store(in: &cancellables)

        batteryVM.$levelBattery
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                guard let self = self else { return }
                if !batteryVM.isCharging {
                    if level <= 5 {
                        self.triggerLowBatteryAlert(percentage: Int(level), isCritical: true)
                    } else if level <= 15 {
                        self.triggerLowBatteryAlert(percentage: Int(level), isCritical: false)
                    }
                }
            }
            .store(in: &cancellables)
    }

    public func triggerPowerDisconnectedAlert() {
        let payload = AlertPayload(
            id: "power.disconnected",
            kind: .custom(title: "Power Disconnected", subtitle: "Running on Battery", icon: "battery.100"),
            title: "Power Disconnected",
            subtitle: "Running on Battery",
            iconName: "powerplug",
            iconColor: .orange,
            dwellDuration: 3.0,
            customSize: CGSize(width: 380, height: 52)
        )
        IslandController.shared.showAlert(payload: payload)
    }

    public func triggerChargingAlert(level: Double) {
        // Query adapter type (MagSafe vs USB-C)
        var adapterName = "Charger Connected"
        if let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            let watts = details[kIOPSPowerAdapterWattsKey] as? Int ?? 0
            var isMagSafe = false
            if let desc = details["Description"] as? String, desc.lowercased().contains("magsafe") {
                isMagSafe = true
            }
            if let family = details["FamilyCode"] as? Int {
                let uFamily = UInt32(bitPattern: Int32(truncatingIfNeeded: family))
                if (uFamily & 0xffffff00) == 0xe0004000 || (uFamily & 0xffff0000) == 0xe0000000 {
                    isMagSafe = true
                }
            }
            let wattSuffix = watts > 0 ? " \(watts)W" : ""
            if isMagSafe {
                adapterName = "MagSafe\(wattSuffix)"
            } else {
                adapterName = "USB-C\(wattSuffix)"
            }
        }

        let payload = AlertPayload(
            id: "power.charging",
            kind: .chargingConnected(level: level),
            title: "Charging Started",
            subtitle: "\(adapterName) • \(Int(level * 100))%",
            iconName: "bolt.fill",
            iconColor: .green,
            dwellDuration: 3.8,
            customSize: CGSize(width: 390, height: 54),
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

    // MARK: - 4. Hardware & Bluetooth Device Monitoring

    private func setupDeviceMonitoringTriggers() {
        DeviceMonitor.shared.eventSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self = self else { return }

                if event.type == .connected {
                    if event.device.kind == .monitor || event.device.connectionType == .display {
                        // Dismiss any active popups/alerts to prevent any overlay conflicts
                        DeviceShowcaseCoordinator.shared.dismiss()
                        LiveActivityCenter.shared.dismissAlert()
                        IslandController.shared.dismissAlert()
                        // When display connects, display controls show in directly!
                        IslandController.shared.activeOrganicItem = .device(event.device.stableKey)
                        IslandController.shared.setExpanded(view: .home, pin: true)
                    } else {
                        guard IslandController.shared.state != .expanded else { return }
                        self.triggerDeviceConnectedAlert(device: event.device)
                    }
                } else if event.type == .disconnected {
                    if event.device.kind == .monitor {
                        if case .device(let key) = IslandController.shared.activeOrganicItem, key == event.device.stableKey {
                            IslandController.shared.activeOrganicItem = .none
                        }
                    }
                    guard IslandController.shared.state != .expanded else { return }
                    self.triggerDeviceDisconnectedAlert(device: event.device)
                }
            }
            .store(in: &cancellables)
    }

    public func triggerDeviceConnectedAlert(device: DeviceIdentity) {
        DeviceMemoryRegistry.shared.remember(device: device)

        let isSSD = device.kind == .ssdDrive || device.displayName.localizedCaseInsensitiveContains("SSD") || device.displayName.localizedCaseInsensitiveContains("Disk")
        let isAirPods = device.kind == .earbuds || device.displayName.localizedCaseInsensitiveContains("AirPods")
        let isDisplay = device.kind == .monitor || device.displayName.localizedCaseInsensitiveContains("Display")
        let isPhone = device.kind == .phone || device.displayName.localizedCaseInsensitiveContains("iPhone")
        let isAndroid = device.kind == .androidPhone || device.displayName.localizedCaseInsensitiveContains("Android") || device.displayName.localizedCaseInsensitiveContains("Pixel") || device.displayName.localizedCaseInsensitiveContains("Galaxy")

        let title: String
        let subtitle: String
        let icon: String
        let color: Color
        if isSSD || device.connectionType == .storage {
            title = "\(device.displayName) Connected"
            icon = "externaldrive.connected.to.line.below.fill"
            color = .cyan
            let totalStr = device.formattedCapacity
            let freeStr = device.formattedFreeSpace
            if let total = totalStr, let free = freeStr {
                subtitle = "\(total) Total • \(free) Free"
            } else if let total = totalStr {
                subtitle = "\(total) Total Storage"
            } else {
                subtitle = "External Storage Connected"
            }
        } else if isAirPods {
            title = "AirPods Connected"
            icon = "airpodspro"
            color = .white
            subtitle = device.displayName
        } else if isPhone {
            title = "\(device.displayName) Connected"
            icon = "iphone.gen3"
            color = .blue
            subtitle = "iOS Device Connected"
        } else if isAndroid {
            title = "\(device.displayName) Connected"
            icon = "smartphone"
            color = .green
            subtitle = "Android Device Connected"
        } else if isDisplay {
            title = "\(device.displayName) Connected"
            icon = "display"
            color = .blue
            subtitle = "\(device.model) • Display Controls Ready"
        } else {
            title = "\(device.displayName) Connected"
            icon = "cable.connector"
            color = .cyan
            subtitle = device.displayName
        }

        let payload = AlertPayload(
            id: "device.connected.\(device.stableKey)",
            kind: .deviceConnected(name: device.displayName, icon: icon),
            title: title,
            subtitle: subtitle,
            iconName: icon,
            iconColor: color,
            dwellDuration: 4.5,
            customSize: CGSize(width: 440, height: 60),
            deviceIdentity: device,
            action: {
                if isDisplay {
                    IslandController.shared.activeOrganicItem = .device(device.stableKey)
                    IslandController.shared.setExpanded(view: .home)
                } else {
                    IslandController.shared.setExpanded(view: .devices)
                }
            }
        )
        IslandController.shared.showAlert(payload: payload)
    }

    public func triggerDeviceDisconnectedAlert(device: DeviceIdentity) {
        let payload = AlertPayload(
            id: "device.disconnected.\(device.stableKey)",
            kind: .deviceDisconnected(name: device.displayName, icon: "xmark.circle"),
            title: "Device Disconnected",
            subtitle: device.displayName,
            iconName: "eject.fill",
            iconColor: .orange,
            dwellDuration: 3.0,
            customSize: CGSize(width: 390, height: 50),
            deviceIdentity: device
        )
        IslandController.shared.showAlert(payload: payload)
    }

    // MARK: - 5. Clipboard & Dropper Triggers

    public func triggerClipboardAlert(text: String) {
        guard IslandController.shared.state != .expanded else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = clean.prefix(32) + (clean.count > 32 ? "…" : "")
        let payload = AlertPayload(
            id: "clipboard.copied.\(UUID().uuidString)",
            kind: .clipboardCopied(snippet: clean),
            title: "Copied to Clipboard",
            subtitle: preview.isEmpty ? "Content copied" : String(preview),
            iconName: "doc.on.clipboard.fill",
            iconColor: .cyan,
            dwellDuration: 3.2,
            customSize: CGSize(width: 390, height: 52)
        )
        IslandController.shared.showAlert(payload: payload)
    }

    public func triggerDropperItemAdded(count: Int) {
        let payload = AlertPayload(
            id: "dropper.added.\(UUID().uuidString)",
            kind: .dropperItemAdded(count: count),
            title: "Item Added to Dropper",
            subtitle: "\(count) file\(count > 1 ? "s" : "") available",
            iconName: "tray.and.arrow.down.fill",
            iconColor: .cyan,
            dwellDuration: 3.5,
            customSize: CGSize(width: 390, height: 52),
            action: {
                IslandController.shared.setExpanded(view: .shelf)
            }
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

    // MARK: - 8. Storage & Hydration Triggers

    public func triggerStorageNotice(title: String, subtitle: String) {
        let payload = AlertPayload(
            id: "storage.cleanup",
            kind: .custom(title: title, subtitle: subtitle, icon: "sparkles"),
            title: title,
            subtitle: subtitle,
            iconName: "sparkles",
            iconColor: Color(red: 0.25, green: 0.75, blue: 1.0),
            dwellDuration: 4.5,
            action: {
                SettingsWindowController.shared.showWindow(tab: "StorageCleaner")
            }
        )
        IslandController.shared.showAlert(payload: payload)
    }

    public func triggerHydrationAlert(title: String = "Hydration Reminder", message: String = "Take a sip of water to stay fresh!") {
        let payload = AlertPayload(
            id: "hydration.reminder",
            kind: .custom(title: title, subtitle: message, icon: "drop.fill"),
            title: title,
            subtitle: message,
            iconName: "drop.fill",
            iconColor: Color(red: 0.20, green: 0.70, blue: 1.0),
            dwellDuration: 4.0,
            action: {
                SettingsWindowController.shared.showWindow(tab: "Hydration")
            }
        )
        IslandController.shared.showAlert(payload: payload)
    }

    public func triggerCustomAlert(
        title: String,
        subtitle: String,
        iconName: String = "info.circle.fill",
        tint: Color = .accentColor,
        duration: Double = 3.5,
        action: (() -> Void)? = nil
    ) {
        let payload = AlertPayload(
            id: UUID().uuidString,
            kind: .systemNotification(appName: title, sender: title, message: subtitle),
            title: title,
            subtitle: subtitle,
            iconName: iconName,
            iconColor: tint,
            dwellDuration: duration,
            action: action
        )
        IslandController.shared.showAlert(payload: payload)
    }
}

