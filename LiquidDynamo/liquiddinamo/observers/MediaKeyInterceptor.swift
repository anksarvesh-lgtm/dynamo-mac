//
//  MediaKeyInterceptor.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-23.
//  Updated for OSD and robust Accessibility event tap lifecycle.
//

import Foundation
import AppKit
import ApplicationServices
import Defaults
import AVFoundation
import Combine

private let kSystemDefinedEventType = CGEventType(rawValue: 14)!

public enum OSDInterceptionStatus: String, Equatable {
    case disabled = "Disabled"
    case enabled = "Enabled"
    case needsPermission = "Needs permission"
    case repairNeeded = "Permission repair needed"
    case unsupported = "Not supported"
}

@MainActor
final class MediaKeyInterceptor: ObservableObject {
    static let shared = MediaKeyInterceptor()
    
    private enum NXKeyType: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case keyboardBrightnessUp = 21
        case keyboardBrightnessDown = 22
    }
    
    @Published public private(set) var status: OSDInterceptionStatus = .disabled
    @Published public private(set) var isTapActive: Bool = false
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let step: Float = 1.0 / 16.0
    private var audioPlayer: AVAudioPlayer?
    private var permissionPollTimer: Timer?
    
    private init() {
        // Log startup status
        logDiagnostics(context: "Init")
    }
    
    // MARK: - Diagnostics & Logging
    
    public func logDiagnostics(context: String = "Diagnostics") {
        let axTrustedDirect = AXIsProcessTrusted()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let axTrustedWithOptions = AXIsProcessTrustedWithOptions(options)
        
        let tapCreated = (eventTap != nil)
        var tapEnabled = false
        if let eventTap = eventTap {
            tapEnabled = CGEvent.tapIsEnabled(tap: eventTap)
        }
        
        let storedHideSystemOSD = Defaults[.hideSystemOSD]
        let defaultHideSystemOSD = false
        let storedShowNotchOSD = Defaults[.showNotchOSD]
        let defaultShowNotchOSD = true
        
        NSLog("📊 [MediaKeyInterceptor:\(context)] " +
              "AXIsProcessTrusted: \(axTrustedDirect), " +
              "AXIsProcessTrustedWithOptions: \(axTrustedWithOptions), " +
              "eventTapCreated: \(tapCreated), " +
              "CGEvent.tapIsEnabled: \(tapEnabled), " +
              "stored hideSystemOSD: \(storedHideSystemOSD) (default: \(defaultHideSystemOSD)), " +
              "stored showNotchOSD: \(storedShowNotchOSD) (default: \(defaultShowNotchOSD)), " +
              "currentStatus: \(status.rawValue)")
    }
    
    // MARK: - Accessibility Permission Check
    
    public func isAccessibilityGranted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    public func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        // Also ensure System Settings is opened if not automatically focused
        openAccessibilitySettings()
    }
    
    public func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func restartApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
    
    // MARK: - Event Tap Lifecycle
    
    public func start(promptIfNeeded: Bool = false) async {
        // Ensure user opted into hiding system OSD
        let shouldHide = Defaults[.hideSystemOSD] || Defaults[.hudReplacement]
        guard shouldHide else {
            stop()
            status = .disabled
            return
        }
        
        let trusted = isAccessibilityGranted()
        if !trusted {
            status = .needsPermission
            if promptIfNeeded {
                requestAccessibilityAuthorization()
            }
            startPermissionMonitoring()
            logDiagnostics(context: "Start (NeedsPermission)")
            return
        }
        
        // Try creating event tap
        if eventTap == nil {
            let mask = CGEventMask(1 << kSystemDefinedEventType.rawValue)
            
            // Pass unretained self into the callback
            let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            
            eventTap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, cgEvent, userInfo in
                    guard let userInfo = userInfo else {
                        return Unmanaged.passRetained(cgEvent)
                    }
                    let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                    
                    // Requirement 2: If the tap is disabled by timeout or user input, re-enable it immediately
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        DispatchQueue.main.async {
                            interceptor.reEnableTap()
                        }
                        return Unmanaged.passRetained(cgEvent)
                    }
                    
                    return interceptor.handleEvent(cgEvent)
                },
                userInfo: selfPtr
            )
        }
        
        guard let tap = eventTap else {
            // Requirement 3: macOS says trusted, but tap creation failed -> Repair State!
            // (Stale ad-hoc signature invalidated the TCC grant after rebuild)
            status = .repairNeeded
            isTapActive = false
            startPermissionMonitoring()
            logDiagnostics(context: "Start (RepairNeeded - tap creation failed)")
            return
        }
        
        if runLoopSource == nil {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let runLoopSource = runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
        }
        
        CGEvent.tapEnable(tap: tap, enable: true)
        let isEnabled = CGEvent.tapIsEnabled(tap: tap)
        isTapActive = isEnabled
        status = isEnabled ? .enabled : .repairNeeded
        
        stopPermissionMonitoring()
        logDiagnostics(context: "Start (Finished)")
    }
    
    public func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        isTapActive = false
        status = .disabled
        stopPermissionMonitoring()
        logDiagnostics(context: "Stop")
    }
    
    public func reEnableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        let isEnabled = CGEvent.tapIsEnabled(tap: tap)
        isTapActive = isEnabled
        NSLog("🔄 [MediaKeyInterceptor] Re-enabled media key event tap after timeout. isEnabled: \(isEnabled)")
    }
    
    // MARK: - Permission Change Monitoring
    
    private func startPermissionMonitoring() {
        guard permissionPollTimer == nil else { return }
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard Defaults[.hideSystemOSD] || Defaults[.hudReplacement] else {
                    self.stopPermissionMonitoring()
                    return
                }
                
                let isTrusted = self.isAccessibilityGranted()
                if isTrusted && self.status != .enabled {
                    NSLog("🔓 [MediaKeyInterceptor] Accessibility permission change detected! Re-attempting event tap start...")
                    await self.start(promptIfNeeded: false)
                } else if !isTrusted && self.status == .enabled {
                    NSLog("🔒 [MediaKeyInterceptor] Accessibility permission revoked while running!")
                    self.stop()
                    self.status = .needsPermission
                }
            }
        }
    }
    
    private func stopPermissionMonitoring() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard cgEvent.type != .null else {
            return Unmanaged.passRetained(cgEvent)
        }
        guard let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passRetained(cgEvent)
        }
        
        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let stateByte = ((data1 & 0xFF00) >> 8)
        
        // 0xA = key down, 0xB = key up. Only intercept key down.
        guard stateByte == 0xA,
              let keyType = NXKeyType(rawValue: keyCode) else {
            return Unmanaged.passRetained(cgEvent)
        }
        
        let flags = nsEvent.modifierFlags
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)
        let command = flags.contains(.command)
        
        // Handle option key action (without shift)
        if option && !shift {
            if handleOptionAction(for: keyType, command: command) {
                // Suppress system popup
                return nil
            }
        }
        
        // Handle normal key press: apply change ourselves and suppress system popup
        handleKeyPress(keyType: keyType, option: option, shift: shift, command: command)
        return nil
    }
    
    private func handleOptionAction(for keyType: NXKeyType, command: Bool) -> Bool {
        let action = Defaults[.optionKeyAction]
        
        switch action {
        case .openSettings:
            openSystemSettings(for: keyType, command: command)
            return true
        case .showHUD:
            showHUD(for: keyType, command: command)
            return true
        case .none:
            return true
        }
    }
    
    private func prepareAudioPlayerIfNeeded() {
        guard audioPlayer == nil else { return }

        let defaultPath = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        if FileManager.default.fileExists(atPath: defaultPath) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: defaultPath))
            } catch {
                NSLog("⚠️ [MediaKeyInterceptor] Failed to init AVAudioPlayer with default path \(defaultPath): \(error.localizedDescription)")
            }
        }

        if let player = audioPlayer {
            player.volume = 1.0
            player.numberOfLoops = 0
            player.prepareToPlay()
        }
    }

    private func playFeedbackSound() {
        guard let feedback = UserDefaults.standard.persistentDomain(forName: "NSGlobalDomain")?["com.apple.sound.beep.feedback"] as? Int,
              feedback == 1 else { return }

        prepareAudioPlayerIfNeeded()
        guard let player = audioPlayer else { return }
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        player.play()
    }

    private func handleKeyPress(keyType: NXKeyType, option: Bool, shift: Bool, command: Bool) {
        let stepDivisor: Float = (option && shift) ? 4.0 : 1.0
        
        switch keyType {
        case .soundUp:
            playFeedbackSound()
            VolumeManager.shared.increase(stepDivisor: stepDivisor)
        case .soundDown:
            playFeedbackSound()
            VolumeManager.shared.decrease(stepDivisor: stepDivisor)
        case .mute:
            VolumeManager.shared.toggleMuteAction()
        case .brightnessUp, .keyboardBrightnessUp:
            let delta = step / stepDivisor
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessUp || command)
        case .brightnessDown, .keyboardBrightnessDown:
            let delta = -(step / stepDivisor)
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessDown || command)
        }
    }
    
    private func adjustBrightness(delta: Float, keyboard: Bool) {
        if keyboard {
            KeyboardBacklightManager.shared.setRelative(delta: delta)
        } else {
            BrightnessManager.shared.setRelative(delta: delta)
        }
    }
    
    private func showHUD(for keyType: NXKeyType, command: Bool) {
        switch keyType {
        case .soundUp, .soundDown, .mute:
            let v = VolumeManager.shared.rawVolume
            LiquidViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(v))
        case .brightnessUp, .brightnessDown:
            if command {
                let v = KeyboardBacklightManager.shared.rawBrightness
                LiquidViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
            } else {
                let v = BrightnessManager.shared.rawBrightness
                LiquidViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(v))
            }
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            let v = KeyboardBacklightManager.shared.rawBrightness
            LiquidViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
        }
    }
    
    private func openSystemSettings(for keyType: NXKeyType, command: Bool) {
        let urlString: String
        switch keyType {
        case .soundUp, .soundDown, .mute:
            urlString = "x-apple.systempreferences:com.apple.preference.sound"
        case .brightnessUp, .brightnessDown:
            urlString = command ? "x-apple.systempreferences:com.apple.preference.keyboard" : "x-apple.systempreferences:com.apple.preference.displays"
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
        }
        
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
