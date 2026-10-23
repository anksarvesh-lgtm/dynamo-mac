//
//  PlexoBandwidthManager.swift
//  LiquidDynamo
//
//  Bandwidth management, rate limiting, Slow Mode, and scheduling for Plexo.
//  Faithfully ports Plexo's bandwidth controls:
//  - Global & per-network speed limits
//  - Slow Mode toggle for video calls & streaming
//  - Download scheduling (off-peak hours)
//  - Data allowances & tracking
//

import Combine
import Foundation

@MainActor
public final class PlexoBandwidthManager: ObservableObject {
    public static let shared = PlexoBandwidthManager()

    @Published public var settings: PlexoBandwidthSettings {
        didSet { saveSettings() }
    }

    private var scheduleCheckTimer: Timer?
    private let settingsKey = "plexoBandwidthSettings"

    private init() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(PlexoBandwidthSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = PlexoBandwidthSettings()
        }

        startScheduleTimer()
    }

    deinit {
        scheduleCheckTimer?.invalidate()
    }

    public func toggleSlowMode() {
        settings.isSlowModeActive.toggle()
    }

    public func setGlobalSpeedLimit(mbps: Double?) {
        if let mbps = mbps, mbps > 0 {
            settings.globalSpeedLimitBytesPerSec = mbps * 1024 * 1024
        } else {
            settings.globalSpeedLimitBytesPerSec = nil
        }
    }

    public var effectiveGlobalLimit: Double? {
        if settings.isSlowModeActive {
            return settings.slowModeSpeedLimitBytesPerSec
        }
        return settings.globalSpeedLimitBytesPerSec
    }

    // MARK: - Download Scheduling

    private func startScheduleTimer() {
        scheduleCheckTimer?.invalidate()
        scheduleCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateSchedule()
            }
        }
    }

    private func evaluateSchedule() {
        guard settings.isScheduleActive else { return }
        let currentHour = Calendar.current.component(.hour, from: Date())
        let inSchedule: Bool = {
            if settings.scheduleStartHour <= settings.scheduleEndHour {
                return currentHour >= settings.scheduleStartHour && currentHour < settings.scheduleEndHour
            } else {
                // Wraps across midnight (e.g. 23 to 7)
                return currentHour >= settings.scheduleStartHour || currentHour < settings.scheduleEndHour
            }
        }()

        if inSchedule {
            // Auto-resume paused queued downloads
            for task in PlexoDownloadEngine.shared.activeTasks where task.state == .paused {
                PlexoDownloadEngine.shared.resumeDownload(id: task.id)
            }
        } else {
            // Pause active downloads outside scheduled window
            for task in PlexoDownloadEngine.shared.activeTasks where task.state == .downloading {
                PlexoDownloadEngine.shared.pauseDownload(id: task.id)
            }
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
}
