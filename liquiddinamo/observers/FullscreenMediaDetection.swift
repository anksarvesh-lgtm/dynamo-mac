//
//  FullscreenMediaDetection.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import Combine
import CoreGraphics
import Defaults
import Foundation

@MainActor
final class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()

    @Published var fullscreenStatus: [String: Bool] = [:]

    nonisolated(unsafe) private var workspaceObservers: [NSObjectProtocol] = []
    nonisolated(unsafe) private var defaultObservers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    nonisolated(unsafe) private var reconciliationTask: Task<Void, Never>?

    private init() {
        setupObservers()
        evaluateNow()
        startPeriodicReconciliation()
    }

    deinit {
        reconciliationTask?.cancel()
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        for token in defaultObservers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func setupObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        let workspaceEvents: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in workspaceEvents {
            let token = wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.evaluateNow()
                }
            }
            workspaceObservers.append(token)
        }

        let screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateNow()
            }
        }
        defaultObservers.append(screenToken)

        Defaults.publisher(.hideNotchOption)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.evaluateNow()
            }
            .store(in: &cancellables)

        MusicManager.shared.$bundleIdentifier
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.evaluateNow()
            }
            .store(in: &cancellables)
    }

    private func startPeriodicReconciliation() {
        reconciliationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { break }
                self?.evaluateNow()
            }
        }
    }

    func evaluateNow() {
        let screens: [FullscreenScreenDescriptor] = NSScreen.screens.compactMap { screen in
            guard let uuid = screen.displayUUID else { return nil }
            let topInset: CGFloat
            if #available(macOS 12.0, *) {
                topInset = screen.safeAreaInsets.top
            } else {
                topInset = 0
            }
            return FullscreenScreenDescriptor(
                screenUUID: uuid,
                frame: screen.frame,
                safeAreaTopInset: topInset
            )
        }

        let policy: FullscreenDetectionPolicy
        switch Defaults[.hideNotchOption] {
        case .always:
            policy = .always
        case .nowPlayingOnly:
            policy = .nowPlayingOnly
        case .never:
            policy = .never
        }

        let primaryHeight = FullscreenDetectorEvaluator.primaryHeight(for: screens)
        let windows = Self.captureOnScreenWindows()
        let selfPID = ProcessInfo.processInfo.processIdentifier

        let nextStatus = FullscreenDetectorEvaluator.evaluate(
            screens: screens,
            windows: windows,
            primaryScreenHeight: primaryHeight,
            excludedPID: selfPID,
            policy: policy,
            activeMediaBundleIdentifier: MusicManager.shared.bundleIdentifier
        )

        if nextStatus != fullscreenStatus {
            fullscreenStatus = nextStatus
        }
    }

    private static func captureOnScreenWindows() -> [FullscreenWindowDescriptor] {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var bundleCache: [Int32: String?] = [:]
        var descriptors: [FullscreenWindowDescriptor] = []
        descriptors.reserveCapacity(infoList.count)

        for info in infoList {
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let layerNumber = info[kCGWindowLayer as String] as? NSNumber,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
                continue
            }

            let pid = pidNumber.int32Value
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
            let ownerName = info[kCGWindowOwnerName as String] as? String

            let bundleID: String?
            if let cached = bundleCache[pid] {
                bundleID = cached
            } else {
                let resolved = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                bundleCache[pid] = resolved
                bundleID = resolved
            }

            descriptors.append(
                FullscreenWindowDescriptor(
                    ownerPID: pid,
                    ownerBundleIdentifier: bundleID,
                    ownerName: ownerName,
                    bounds: bounds,
                    layer: layerNumber.intValue,
                    isOnScreen: isOnScreen
                )
            )
        }

        return descriptors
    }
}
