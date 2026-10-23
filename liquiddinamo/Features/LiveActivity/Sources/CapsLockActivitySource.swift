//
//  CapsLockActivitySource.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import Combine
import CoreGraphics
import Foundation
import SwiftUI

/// Emits LiveActivity alerts when the Caps Lock key is toggled ON or OFF.
///
/// PERMISSION REQUIREMENT:
/// - Reading instantaneous state: `CGEventSourceFlagsState` requires NO special permission.
/// - Global background event monitoring: `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)`
///   requires **macOS Accessibility Permission** (`AXIsProcessTrusted()`).
/// - If Accessibility permission has not been granted by the user, global key events cannot be intercepted
///   while third-party applications are focused. A local monitor (`addLocalMonitorForEvents`) is also maintained
///   as a fallback when LiquidDynamo has focus.
@MainActor
public final class CapsLockActivitySource: LiveActivitySource {
    public let identifier: String = "caps_lock"

    private let subject = PassthroughSubject<LiveActivity, Never>()
    public var activityPublisher: AnyPublisher<LiveActivity, Never> {
        subject.eraseToAnyPublisher()
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastKnownCapsLockState: Bool = false
    private var isStarted = false

    public static let shared = CapsLockActivitySource()

    private init() {}

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        lastKnownCapsLockState = currentCapsLockState()

        // 1. Global monitor (requires Accessibility permission for background intercept)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleFlagsChanged(event)
            }
        }

        // 2. Local monitor (works when the app is focused, no special permission)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleFlagsChanged(event)
            }
            return event
        }
    }

    public func stop() {
        if let g = globalMonitor {
            NSEvent.removeMonitor(g)
            globalMonitor = nil
        }
        if let l = localMonitor {
            NSEvent.removeMonitor(l)
            localMonitor = nil
        }
        isStarted = false
    }

    // MARK: - State Inspection

    public func currentCapsLockState() -> Bool {
        return CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let isCapsLockOn = event.modifierFlags.contains(.capsLock)
        guard isCapsLockOn != lastKnownCapsLockState else { return }
        lastKnownCapsLockState = isCapsLockOn

        emitCapsLockAlert(isOn: isCapsLockOn)
    }

    // MARK: - Emission

    private func emitCapsLockAlert(isOn: Bool) {
        let title = isOn ? String(localized: "Caps Lock On") : String(localized: "Caps Lock Off")
        let icon = isOn ? "capslock.fill" : "capslock"

        let activity = LiveActivity(
            id: "caps_lock_\(isOn ? "on" : "off")",
            source: identifier,
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: LiveActivitySeverity.info.color,
            duration: 2.0,
            coalescingKey: "caps_lock",
            payload: LiveActivityPayload(
                title: title,
                subtitle: String(localized: "Keyboard"),
                iconName: icon,
                body: isOn ? String(localized: "Capital letters enabled") : String(localized: "Standard typing mode")
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
    }
}
