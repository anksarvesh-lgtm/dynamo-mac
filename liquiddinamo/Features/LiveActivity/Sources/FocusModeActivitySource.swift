//
//  FocusModeActivitySource.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import Combine
import Foundation
import SwiftUI

/// EXPERIMENTAL: Emits LiveActivity alerts when Focus Mode or Do Not Disturb is toggled.
/// Off by default. Clearly marked experimental.
@MainActor
public final class FocusModeActivitySource: LiveActivitySource {
    public let identifier: String = "focus_mode"

    private let subject = PassthroughSubject<LiveActivity, Never>()
    public var activityPublisher: AnyPublisher<LiveActivity, Never> {
        subject.eraseToAnyPublisher()
    }

    private var fileSource: DispatchSourceFileSystemObject?
    private var lastFocusActive: Bool?
    private var isStarted = false

    public static let shared = FocusModeActivitySource()

    private init() {}

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        // 1. Observe distributed notifications from Control Center / DoNotDisturb
        let distCenter = DistributedNotificationCenter.default()
        distCenter.addObserver(
            self,
            selector: #selector(handleFocusNotification),
            name: NSNotification.Name("com.apple.controlcenter.focusStateChanged"),
            object: nil
        )
        distCenter.addObserver(
            self,
            selector: #selector(handleFocusNotification),
            name: NSNotification.Name("com.apple.donotdisturbd.stateChanged"),
            object: nil
        )

        // 2. Observe Assertions.json file for file system change events
        observeAssertionsFile()

        // Initial read
        checkCurrentFocusState()
    }

    public func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
        fileSource?.cancel()
        fileSource = nil
        isStarted = false
    }

    @objc private func handleFocusNotification() {
        DispatchQueue.main.async { [weak self] in
            self?.checkCurrentFocusState()
        }
    }

    private func observeAssertionsFile() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let assertionsPath = home.appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json").path
        let fd = open(assertionsPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in
            self?.checkCurrentFocusState()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.fileSource = source
    }

    private func checkCurrentFocusState() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let assertionsURL = home.appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        guard let data = try? Data(contentsOf: assertionsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            return
        }

        // If there is any active assertion in dataArray, focus mode is active
        var isFocusOn = false
        for item in dataArray {
            if let storeAssertionRecord = item["storeAssertionRecord"] as? [String: Any],
               let assertionDetails = storeAssertionRecord["assertionDetails"] as? [String: Any],
               let modeIdentifier = assertionDetails["assertionDetailsModeIdentifier"] as? String,
               !modeIdentifier.isEmpty {
                isFocusOn = true
                break
            }
        }

        if let prev = lastFocusActive, prev != isFocusOn {
            emitFocusAlert(isActive: isFocusOn)
        }
        lastFocusActive = isFocusOn
    }

    private func emitFocusAlert(isActive: Bool) {
        let title = isActive ? String(localized: "Focus Mode On") : String(localized: "Focus Mode Off")
        let subtitle = isActive ? String(localized: "Do Not Disturb") : String(localized: "Notifications Resumed")
        let icon = isActive ? "moon.fill" : "moon"
        let tint = isActive ? Color.indigo : LiveActivitySeverity.info.color

        let activity = LiveActivity(
            id: "focus_mode_\(isActive ? "on" : "off")",
            source: identifier,
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: tint,
            duration: 2.5,
            coalescingKey: "focus_mode",
            payload: LiveActivityPayload(
                title: title,
                subtitle: subtitle,
                iconName: icon,
                body: isActive ? String(localized: "Silencing notifications and alerts") : String(localized: "Standard alerts restored")
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
    }
}
