//
//  HardwareSensorMonitor.swift
//  LiquidDynamo
//
//  Monitors system-wide hardware sensors:
//  - Camera active (CoreMediaIO) -> Subtle flowing green liquid
//  - Microphone active (CoreAudio) -> Subtle flowing blue liquid
//  - Screen recording active (Window Server / ScreenCapture) -> Subtle flowing orange liquid
//

import AppKit
import Combine
import CoreAudio
import CoreGraphics
import CoreMediaIO
import Foundation
import SwiftUI

@MainActor
public final class HardwareSensorMonitor: ObservableObject {
    public static let shared = HardwareSensorMonitor()

    @Published public private(set) var isCameraActive: Bool = false
    @Published public private(set) var isMicrophoneActive: Bool = false
    @Published public private(set) var isScreenRecordingActive: Bool = false

    /// Dynamic liquid glow color matching active sensor states
    public var activeSensorLiquidColor: Color? {
        if isCameraActive {
            return Color.green
        } else if isScreenRecordingActive {
            return Color.orange
        } else if isMicrophoneActive {
            return Color.blue
        }
        return nil
    }

    private var pollTimer: Timer?
    private var privacyObserver: Defaults.Observation?

    private init() {
        privacyObserver = Defaults.observe(.privacyIndicatorsEnabled) { [weak self] change in
            if change.newValue {
                self?.startMonitoring()
            } else {
                self?.stopMonitoring()
            }
        }
        if Defaults[.privacyIndicatorsEnabled] {
            startMonitoring()
        }
    }

    public func startMonitoring() {
        guard Defaults[.privacyIndicatorsEnabled] else {
            stopMonitoring()
            return
        }
        stopMonitoring()
        checkSensors()
        let timer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkSensors()
            }
        }
        timer.tolerance = 0.5
        pollTimer = timer
    }

    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    public func checkSensors() {
        self.isCameraActive = queryCameraActive()
        self.isMicrophoneActive = queryMicrophoneActive()
        self.isScreenRecordingActive = queryScreenRecordingActive()
    }

    // MARK: - CoreMediaIO Camera Query

    private func queryCameraActive() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        let status = CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )

        guard status == 0, dataSize > 0 else { return false }

        let deviceCount = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: deviceCount)
        let getStatus = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            0,
            nil,
            dataSize,
            &dataSize,
            &devices
        )

        guard getStatus == 0 else { return false }

        for dev in devices {
            var runAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            var isRunning: UInt32 = 0
            var runSize = UInt32(MemoryLayout<UInt32>.size)
            let rStatus = CMIOObjectGetPropertyData(
                dev,
                &runAddress,
                0,
                nil,
                runSize,
                &runSize,
                &isRunning
            )
            if rStatus == 0 && isRunning == 1 {
                return true
            }
        }
        return false
    }

    // MARK: - CoreAudio Microphone Query

    private func queryMicrophoneActive() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == 0, deviceID != 0 else { return false }

        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
        let runStatus = AudioObjectGetPropertyData(
            deviceID,
            &runningAddress,
            0,
            nil,
            &isRunningSize,
            &isRunning
        )

        return runStatus == 0 && isRunning == 1
    }

    // MARK: - Screen Recording Query

    private func queryScreenRecordingActive() -> Bool {
        if let windowList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] {
            let recordingOwners = ["screencapture", "screencaptured", "replayd"]
            for info in windowList {
                if let owner = info[kCGWindowOwnerName as String] as? String {
                    let lower = owner.lowercased()
                    if recordingOwners.contains(lower) {
                        return true
                    }
                }
            }
        }
        return false
    }
}
