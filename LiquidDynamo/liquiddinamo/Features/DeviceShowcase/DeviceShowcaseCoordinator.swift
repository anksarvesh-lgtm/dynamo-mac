//
//  DeviceShowcaseCoordinator.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

/// Coordinates the presentation and auto-dismissal of the 3D device showcase popup in the collapsed notch.
@MainActor
public final class DeviceShowcaseCoordinator: ObservableObject {
    public static let shared = DeviceShowcaseCoordinator()

    @Published public private(set) var currentDevice: DeviceIdentity?
    @Published public private(set) var isShowing: Bool = false
    @Published public var isHovering: Bool = false {
        didSet {
            handleHoverChanged()
        }
    }

    private var dismissTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupDeviceEventObserver()
    }

    private func setupDeviceEventObserver() {
        DeviceMonitor.shared.eventSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                guard event.type == .connected else { return }
                self.handleDeviceConnected(event.device)
            }
            .store(in: &cancellables)
    }

    // MARK: - Presentation Lifecycle

    public func handleDeviceConnected(_ device: DeviceIdentity) {
        // Respect settings toggle
        guard Defaults[.enableDeviceShowcasePopup] else { return }

        // Only present when notch is collapsed
        guard LiquidViewModel.shared.notchState == .closed else { return }

        // Update active device
        self.currentDevice = device

        // Pre-warm renderer
        SceneKitDeviceRenderer.shared.resumeRendering()

        // Haptic feedback
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)

        // Expand collapsed notch
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            self.isShowing = true
        }

        scheduleDismissal(seconds: 4.0)
    }

    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            self.isShowing = false
            self.currentDevice = nil
        }

        // Pause SceneKit renderer when popup closes to guarantee zero idle CPU
        SceneKitDeviceRenderer.shared.pauseRendering()
    }

    // MARK: - Hover & Timer Management

    private func handleHoverChanged() {
        if isHovering {
            // Cancel auto-dismissal while user hovers over the popup
            dismissTask?.cancel()
            dismissTask = nil
        } else if isShowing {
            // Re-schedule dismissal when cursor leaves
            scheduleDismissal(seconds: 2.5)
        }
    }

    private func scheduleDismissal(seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let nanoseconds = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            guard !self.isHovering else { return }
            self.dismiss()
        }
    }
}
