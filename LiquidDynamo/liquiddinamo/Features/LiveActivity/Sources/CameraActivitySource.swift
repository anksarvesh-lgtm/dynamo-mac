//
//  CameraActivitySource.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import Combine
import CoreMediaIO
import Foundation
import SwiftUI

/// Emits LiveActivity alerts when the camera hardware is active or accessed by another application.
/// Uses CoreMediaIO kCMIODevicePropertyDeviceIsRunningSomewhere with zero polling.
@MainActor
public final class CameraActivitySource: LiveActivitySource {
    public let identifier: String = "camera"

    private let subject = PassthroughSubject<LiveActivity, Never>()
    public var activityPublisher: AnyPublisher<LiveActivity, Never> {
        subject.eraseToAnyPublisher()
    }

    private var deviceListeners: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]
    private var isCameraActive: Bool = false
    private var isStarted = false

    public static let shared = CameraActivitySource()

    private init() {}

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        bindCameraDevices()
    }

    public func stop() {
        unbindCameraDevices()
        isStarted = false
    }

    // MARK: - CoreMediaIO Device Binding

    private func bindCameraDevices() {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &addr,
            0,
            nil,
            &size
        ) == noErr, size > 0 else {
            return
        }

        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &addr,
            0,
            nil,
            size,
            &dataUsed,
            &devices
        ) == noErr else {
            return
        }

        for devID in devices {
            var rAddr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
            )

            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.evaluateCameraActivity(deviceID: devID)
                }
            }

            let status = CMIOObjectAddPropertyListenerBlock(devID, &rAddr, DispatchQueue.main, block)
            if status == noErr {
                deviceListeners[devID] = block
            }

            // Initial check
            evaluateCameraActivity(deviceID: devID)
        }
    }

    private func unbindCameraDevices() {
        for (devID, block) in deviceListeners {
            var rAddr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
            )
            CMIOObjectRemovePropertyListenerBlock(devID, &rAddr, DispatchQueue.main, block)
        }
        deviceListeners.removeAll()
    }

    // MARK: - State Evaluation

    private func evaluateCameraActivity(deviceID: CMIOObjectID) {
        var running: UInt32 = 0
        let rSize = UInt32(MemoryLayout<UInt32>.size)
        var rUsed: UInt32 = 0
        var rAddr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )

        guard CMIOObjectGetPropertyData(deviceID, &rAddr, 0, nil, rSize, &rUsed, &running) == noErr else {
            return
        }

        let active = (running != 0)
        guard active != isCameraActive else { return }
        self.isCameraActive = active

        if active {
            let appName = resolveCameraApp(for: deviceID)
            emitCameraAlert(active: true, appName: appName)
        } else {
            emitCameraAlert(active: false, appName: nil)
        }
    }

    private func resolveCameraApp(for deviceID: CMIOObjectID) -> String {
        // 1. Check HogMode PID
        var hogPID: pid_t = 0
        let hogSize = UInt32(MemoryLayout<pid_t>.size)
        var hogUsed: UInt32 = 0
        var hogAddr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyHogMode),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )

        if CMIOObjectGetPropertyData(deviceID, &hogAddr, 0, nil, hogSize, &hogUsed, &hogPID) == noErr,
           hogPID > 0,
           let app = NSRunningApplication(processIdentifier: hogPID)?.localizedName {
            return app
        }

        // 2. Identify running video conferencing or camera apps
        let knownCameraAppBundles = [
            "com.apple.FaceTime": "FaceTime",
            "com.apple.PhotoBooth": "Photo Booth",
            "us.zoom.xos": "Zoom",
            "com.microsoft.teams2": "Microsoft Teams",
            "com.microsoft.teams": "Microsoft Teams",
            "com.google.Chrome": "Google Chrome",
            "com.tinyspeck.slackmacgap": "Slack",
            "com.cisco.webexmeetingsapp": "Webex",
            "com.obsproject.obs-studio": "OBS Studio"
        ]

        let runningApps = NSWorkspace.shared.runningApplications
        for (bundleID, name) in knownCameraAppBundles {
            if runningApps.contains(where: { $0.bundleIdentifier == bundleID && !$0.isTerminated }) {
                return name
            }
        }

        return String(localized: "Another Application")
    }

    // MARK: - Activity Emission

    private func emitCameraAlert(active: Bool, appName: String?) {
        let title = active ? String(localized: "Camera Active") : String(localized: "Camera Off")
        let subtitle = active ? (appName ?? String(localized: "Camera in use")) : String(localized: "Stream stopped")
        let body = active
            ? (appName != nil ? String(localized: "\(appName!) is accessing your camera") : String(localized: "A camera is currently active"))
            : String(localized: "Camera access stopped")
        let icon = active ? "camera.fill" : "camera"
        let tint: Color = active ? LiveActivitySeverity.warning.color : LiveActivitySeverity.info.color

        let activity = LiveActivity(
            id: "camera_in_use_\(active ? "on" : "off")",
            source: identifier,
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: tint,
            duration: 3.5,
            coalescingKey: "camera_alert",
            payload: LiveActivityPayload(
                title: title,
                subtitle: subtitle,
                iconName: icon,
                body: body
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
    }
}
