//
//  AudioActivitySource.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import Combine
import CoreAudio
import Foundation
import SwiftUI

/// Emits LiveActivity events for Volume, Mute, and Audio Output Device changes via CoreAudio listeners.
/// Reuses VolumeManager.shared for CoreAudio bindings without polling.
@MainActor
public final class AudioActivitySource: LiveActivitySource {
    public let identifier: String = "volume"

    private let subject = PassthroughSubject<LiveActivity, Never>()
    public var activityPublisher: AnyPublisher<LiveActivity, Never> {
        subject.eraseToAnyPublisher()
    }

    private var cancellables = Set<AnyCancellable>()
    private var lastKnownDeviceID: AudioObjectID? = nil
    private var isStarted = false

    public static let shared = AudioActivitySource()

    private init() {}

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        let volumeMgr = VolumeManager.shared

        // 1. Observe Volume Changes
        volumeMgr.$rawVolume
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] volume in
                guard let self = self else { return }
                self.emitVolumeHUD(level: volume, isMuted: volumeMgr.isMuted)
            }
            .store(in: &cancellables)

        // 2. Observe Mute Toggles
        volumeMgr.$isMuted
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] isMuted in
                guard let self = self else { return }
                self.emitVolumeHUD(level: volumeMgr.rawVolume, isMuted: isMuted)
            }
            .store(in: &cancellables)

        // 3. Observe Audio Output Device Changes
        volumeMgr.$currentOutputDevice
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] device in
                guard let self = self, let device = device else { return }
                // Avoid firing on initial launch registration
                if let lastID = self.lastKnownDeviceID, lastID == device.id {
                    return
                }
                self.lastKnownDeviceID = device.id
                self.emitOutputDeviceChange(device: device)
            }
            .store(in: &cancellables)

        if let current = volumeMgr.currentOutputDevice {
            lastKnownDeviceID = current.id
        }
    }

    public func stop() {
        cancellables.removeAll()
        isStarted = false
    }

    // MARK: - Emitting Helpers

    private func emitVolumeHUD(level: Float, isMuted: Bool) {
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

        let activity = LiveActivity(
            id: "volume_hud",
            source: "volume",
            kind: .hud,
            priority: LiveActivityPriority.hud,
            tint: .accentColor,
            duration: 1.5,
            coalescingKey: "volume",
            payload: LiveActivityPayload(
                title: String(localized: "Volume"),
                subtitle: isMuted ? String(localized: "Muted") : "\(Int(round(level * 100)))%",
                iconName: icon,
                value: Double(isMuted ? 0 : level),
                isDraggable: true,
                action: {
                    VolumeManager.shared.toggleMuteAction()
                }
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
    }

    private func emitOutputDeviceChange(device: AudioOutputDevice) {
        let activity = LiveActivity(
            id: "audio_output_\(device.id)",
            source: "audio_output",
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: LiveActivitySeverity.info.color,
            duration: 2.5,
            coalescingKey: "audio_output",
            payload: LiveActivityPayload(
                title: device.name,
                subtitle: String(localized: "Audio Output Device"),
                iconName: device.iconName,
                body: String(localized: "Switched system sound output to \(device.name)")
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
    }
}
