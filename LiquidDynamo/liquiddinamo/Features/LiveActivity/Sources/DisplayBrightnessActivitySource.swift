//
//  DisplayBrightnessActivitySource.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import Combine
import Foundation
import SwiftUI

/// Emits LiveActivity HUD events for every connected display and keyboard backlight.
/// Reuses MultiDisplayBrightnessService, BrightnessManager, and KeyboardBacklightManager.
@MainActor
public final class DisplayBrightnessActivitySource: LiveActivitySource {
    public let identifier: String = "brightness"

    private let subject = PassthroughSubject<LiveActivity, Never>()
    public var activityPublisher: AnyPublisher<LiveActivity, Never> {
        subject.eraseToAnyPublisher()
    }

    private var cancellables = Set<AnyCancellable>()
    private var displayCancellables: [CGDirectDisplayID: AnyCancellable] = [:]
    private var isStarted = false

    public static let shared = DisplayBrightnessActivitySource()

    private init() {}

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        // 1. Observe Main Display BrightnessManager
        BrightnessManager.shared.$rawBrightness
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] brightness in
                guard let self = self else { return }
                self.emitDisplayBrightness(name: String(localized: "Brightness"), value: brightness, displayID: 0)
            }
            .store(in: &cancellables)

        // 2. Observe MultiDisplayBrightnessService displays
        MultiDisplayBrightnessService.shared.$displays
            .receive(on: RunLoop.main)
            .sink { [weak self] displays in
                self?.bindMultiDisplays(displays)
            }
            .store(in: &cancellables)

        // 3. Observe Keyboard Backlight
        KeyboardBacklightManager.shared.$rawBrightness
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] brightness in
                guard let self = self else { return }
                self.emitKeyboardBrightness(value: brightness)
            }
            .store(in: &cancellables)
    }

    public func stop() {
        cancellables.removeAll()
        displayCancellables.removeAll()
        isStarted = false
    }

    private func bindMultiDisplays(_ displays: [ManagedDisplay]) {
        // Observe each managed display's brightness published property
        for display in displays {
            guard displayCancellables[display.id] == nil else { continue }
            let id = display.id
            let name = display.name
            let cancellable = display.$brightness
                .dropFirst()
                .receive(on: RunLoop.main)
                .sink { [weak self] value in
                    self?.emitDisplayBrightness(name: name, value: value, displayID: id)
                }
            displayCancellables[id] = cancellable
        }
    }

    private func emitDisplayBrightness(name: String, value: Float, displayID: CGDirectDisplayID) {
        let clamped = max(0, min(1, Double(value)))
        let icon: String = clamped > 0.5 ? "sun.max.fill" : "sun.min.fill"

        let activity = LiveActivity(
            id: "brightness_hud_\(displayID)",
            source: "brightness",
            kind: .hud,
            priority: LiveActivityPriority.hud,
            tint: .orange,
            duration: 1.5,
            coalescingKey: "brightness_\(displayID)",
            payload: LiveActivityPayload(
                title: name,
                subtitle: "\(Int(round(clamped * 100)))%",
                iconName: icon,
                value: clamped,
                isDraggable: true
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
    }

    private func emitKeyboardBrightness(value: Float) {
        let clamped = max(0, min(1, Double(value)))
        let activity = LiveActivity(
            id: "keyboard_brightness_hud",
            source: "keyboard_brightness",
            kind: .hud,
            priority: LiveActivityPriority.hud,
            tint: .cyan,
            duration: 1.5,
            coalescingKey: "keyboard_brightness",
            payload: LiveActivityPayload(
                title: String(localized: "Keyboard"),
                subtitle: "\(Int(round(clamped * 100)))%",
                iconName: "keyboard",
                value: clamped,
                isDraggable: true
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
    }
}
