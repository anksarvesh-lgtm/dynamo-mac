//
//  MicrophoneActivitySource.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import Combine
import CoreAudio
import Foundation
import SwiftUI

/// Emits LiveActivity alerts when the microphone is muted/unmuted or when another app actively records audio.
/// Implemented entirely via public CoreAudio listeners (kAudioHardwarePropertyProcessObjectList and
/// kAudioProcessPropertyIsRunningInput) with zero polling.
@MainActor
public final class MicrophoneActivitySource: LiveActivitySource {
    public let identifier: String = "microphone"

    private let subject = PassthroughSubject<LiveActivity, Never>()
    public var activityPublisher: AnyPublisher<LiveActivity, Never> {
        subject.eraseToAnyPublisher()
    }

    private var processListListenerBlock: AudioObjectPropertyListenerBlock?
    private var inputMuteListenerBlock: AudioObjectPropertyListenerBlock?
    private var currentInputDeviceID: AudioObjectID = kAudioObjectUnknown

    private var currentlyActiveApps: Set<String> = []
    private var isMuted: Bool = false
    private var isStarted = false

    public static let shared = MicrophoneActivitySource()

    private init() {}

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        setupProcessListener()
        setupInputDeviceMuteListener()
        checkActiveProcesses()
    }

    public func stop() {
        teardownProcessListener()
        teardownInputMuteListener()
        isStarted = false
    }

    // MARK: - CoreAudio Listeners

    private func setupProcessListener() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.checkActiveProcesses()
            }
        }
        self.processListListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            DispatchQueue.main,
            block
        )
    }

    private func teardownProcessListener() {
        if let block = processListListenerBlock {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyProcessObjectList,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &addr,
                DispatchQueue.main,
                block
            )
            processListListenerBlock = nil
        }
    }

    private func setupInputDeviceMuteListener() {
        var defaultInputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var inputID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddr,
            0,
            nil,
            &size,
            &inputID
        ) == noErr, inputID != kAudioObjectUnknown else {
            return
        }

        self.currentInputDeviceID = inputID

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.checkInputMuteState()
            }
        }
        self.inputMuteListenerBlock = block

        AudioObjectAddPropertyListenerBlock(inputID, &muteAddr, DispatchQueue.main, block)
        checkInputMuteState()
    }

    private func teardownInputMuteListener() {
        if let block = inputMuteListenerBlock, currentInputDeviceID != kAudioObjectUnknown {
            var muteAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(currentInputDeviceID, &muteAddr, DispatchQueue.main, block)
            inputMuteListenerBlock = nil
            currentInputDeviceID = kAudioObjectUnknown
        }
    }

    // MARK: - State Checks

    private func checkInputMuteState() {
        guard currentInputDeviceID != kAudioObjectUnknown else { return }

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        if AudioObjectGetPropertyData(currentInputDeviceID, &muteAddr, 0, nil, &size, &muted) == noErr {
            let nowMuted = (muted != 0)
            if nowMuted != isMuted {
                self.isMuted = nowMuted
                emitMuteAlert(isMuted: nowMuted)
            }
        }
    }

    private func checkActiveProcesses() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size
        ) == noErr, size > 0 else {
            return
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var processIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size,
            &processIDs
        ) == noErr else {
            return
        }

        var activeAppNames = Set<String>()
        let myPID = ProcessInfo.processInfo.processIdentifier

        for procObj in processIDs {
            var isRunningInput: UInt32 = 0
            var inSize = UInt32(MemoryLayout<UInt32>.size)
            var inAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            if AudioObjectGetPropertyData(procObj, &inAddr, 0, nil, &inSize, &isRunningInput) == noErr,
               isRunningInput > 0 {
                var procPID: pid_t = 0
                var pidSize = UInt32(MemoryLayout<pid_t>.size)
                var pidAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioProcessPropertyPID,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                if AudioObjectGetPropertyData(procObj, &pidAddr, 0, nil, &pidSize, &procPID) == noErr,
                   procPID > 0 && procPID != myPID {
                    let appName = NSRunningApplication(processIdentifier: procPID)?.localizedName ?? "App (\(procPID))"
                    activeAppNames.insert(appName)
                }
            }
        }

        // Detect newly started recording apps
        let newlyStarted = activeAppNames.subtracting(currentlyActiveApps)
        if let first = newlyStarted.first {
            emitMicInUseAlert(appName: first, totalCount: activeAppNames.count)
        }

        self.currentlyActiveApps = activeAppNames
    }

    // MARK: - Activity Emission

    private func emitMuteAlert(isMuted: Bool) {
        let title = isMuted ? String(localized: "Microphone Muted") : String(localized: "Microphone Unmuted")
        let icon = isMuted ? "mic.slash.fill" : "mic.fill"
        let tint: Color = isMuted ? LiveActivitySeverity.critical.color : LiveActivitySeverity.info.color

        let activity = LiveActivity(
            id: "mic_mute_\(UUID().uuidString)",
            source: identifier,
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: tint,
            duration: 2.5,
            coalescingKey: "mic_mute",
            payload: LiveActivityPayload(
                title: title,
                subtitle: String(localized: "System Microphone"),
                iconName: icon,
                body: isMuted ? String(localized: "Input audio is silenced") : String(localized: "Input audio is live")
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
    }

    private func emitMicInUseAlert(appName: String, totalCount: Int) {
        let title = String(localized: "Microphone Active")
        let subtitle = totalCount > 1
            ? String(localized: "\(appName) and \(totalCount - 1) other apps")
            : appName
        let body = String(localized: "\(appName) is using your microphone")

        let activity = LiveActivity(
            id: "mic_in_use_\(appName)",
            source: identifier,
            kind: .alert,
            priority: LiveActivityPriority.alert,
            tint: LiveActivitySeverity.warning.color,
            duration: 3.5,
            coalescingKey: "mic_in_use",
            payload: LiveActivityPayload(
                title: title,
                subtitle: subtitle,
                iconName: "mic.fill",
                body: body
            ),
            pauseDismissalOnHover: true
        )
        subject.send(activity)
    }
}
