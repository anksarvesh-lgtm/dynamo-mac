//
//  MediaKeyInterceptor.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team
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
    
    @Published public private(set) var status: OSDInterceptionStatus = .disabled
    @Published public private(set) var isTapActive: Bool = false
    @Published public private(set) var backedOffClasses: Set<LiquidHUDKind> = []
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var audioPlayer: AVAudioPlayer?
    private var permissionPollTimer: Timer?
    private var safetyState: InterceptSafety.State = .armed
    private var audioDeviceObserver: NSObjectProtocol?
    private var screenParamsObserver: NSObjectProtocol?
    
    private init() {
        audioDeviceObserver = NotificationCenter.default.addObserver(
            forName: .defaultAudioOutputDeviceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetInterceptSafety(for: .volume)
            }
        }
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetInterceptSafety(for: .brightness)
            }
        }
        logDiagnostics(context: "Init")
    }

    public func resetInterceptSafety(for keyClass: LiquidHUDKind? = nil) {
        safetyState = InterceptSafety.reset(safetyState, keyClass: keyClass)
        if backedOffClasses != safetyState.disabled {
            backedOffClasses = safetyState.disabled
        }
    }

    private func recordSafetyOutcome(for keyClass: LiquidHUDKind, changed: Bool, atRail: Bool) {
        safetyState = InterceptSafety.recording(
            safetyState,
            keyClass: keyClass,
            changed: changed,
            atRail: atRail
        )
        if backedOffClasses != safetyState.disabled {
            backedOffClasses = safetyState.disabled
            NSLog("⚠️ [MediaKeyInterceptor] Backed off interception for \(keyClass) after consecutive hardware write failures; passing future keys to macOS.")
        }
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
              "backedOff: \(backedOffClasses), " +
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
        // Only activate a key-swallowing tap when popup suppression is explicitly requested.
        let shouldHide = HUDLogic.shouldActivateEventTap(
            hideSystemOSD: Defaults[.hideSystemOSD],
            legacyHUDReplacement: Defaults[.hudReplacement]
        )
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
        
        // Try creating event tap with dual-tier fallback (.cghidEventTap -> .cgSessionEventTap)
        if eventTap == nil {
            let mask = CGEventMask(1 << kSystemDefinedEventType.rawValue)
            
            // Pass unretained self into the callback
            let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            
            let tapCallback: CGEventTapCallBack = { _, type, cgEvent, userInfo in
                guard let userInfo = userInfo else {
                    return Unmanaged.passRetained(cgEvent)
                }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                
                // If the tap is disabled by timeout or user input, re-enable it immediately
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    DispatchQueue.main.async {
                        interceptor.reEnableTap()
                    }
                    return Unmanaged.passRetained(cgEvent)
                }
                
                return interceptor.handleEvent(cgEvent)
            }
            
            var createdTap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: tapCallback,
                userInfo: selfPtr
            )
            
            if createdTap == nil {
                NSLog("⚠️ [MediaKeyInterceptor] .cghidEventTap creation failed, attempting .cgSessionEventTap fallback...")
                createdTap = CGEvent.tapCreate(
                    tap: .cgSessionEventTap,
                    place: .headInsertEventTap,
                    options: .defaultTap,
                    eventsOfInterest: mask,
                    callback: tapCallback,
                    userInfo: selfPtr
                )
            }
            
            eventTap = createdTap
        }
        
        guard let tap = eventTap else {
            // macOS says trusted, but tap creation failed -> Repair state needed
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
        if isEnabled {
            resetInterceptSafety()
        }
        
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
        resetInterceptSafety()
        stopPermissionMonitoring()
        logDiagnostics(context: "Stop")
    }
    
    public func reEnableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        let isEnabled = CGEvent.tapIsEnabled(tap: tap)
        isTapActive = isEnabled
        if isEnabled {
            resetInterceptSafety()
        }
        NSLog("🔄 [MediaKeyInterceptor] Re-enabled media key event tap after timeout. isEnabled: \(isEnabled)")
    }
    
    // MARK: - Permission Change Monitoring
    
    private func startPermissionMonitoring() {
        guard permissionPollTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard HUDLogic.shouldActivateEventTap(
                    hideSystemOSD: Defaults[.hideSystemOSD],
                    legacyHUDReplacement: Defaults[.hudReplacement]
                ) else {
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
        timer.tolerance = 1.0
        permissionPollTimer = timer
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
        
        guard let decoded = HUDLogic.parseSystemDefinedKey(data1: nsEvent.data1),
              decoded.isDown else {
            return Unmanaged.passRetained(cgEvent)
        }
        
        let flags = nsEvent.modifierFlags
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)
        let command = flags.contains(.command)
        
        // Option without Shift opens system settings or shows the current HUD without mutating hardware.
        if option && !shift {
            if handleOptionAction(for: decoded.key, command: command) {
                return nil
            }
        }

        let effectiveClass: LiquidHUDKind = (command && (decoded.key == .brightnessUp || decoded.key == .brightnessDown))
            ? .keyboardBacklight
            : HUDLogic.hudKind(for: decoded.key)

        guard InterceptSafety.isIntercepting(safetyState, keyClass: effectiveClass) else {
            return Unmanaged.passRetained(cgEvent)
        }

        let shouldSuppressSystemPopup = handleKeyPress(
            key: decoded.key,
            effectiveClass: effectiveClass,
            option: option,
            shift: shift,
            command: command
        )
        return shouldSuppressSystemPopup ? nil : Unmanaged.passRetained(cgEvent)
    }
    
    private func handleOptionAction(for key: MediaKeyCode, command: Bool) -> Bool {
        let action = Defaults[.optionKeyAction]
        
        switch action {
        case .openSettings:
            openSystemSettings(for: key, command: command)
            return true
        case .showHUD:
            showHUD(for: key, command: command)
            return true
        case .none:
            return false
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

    private func handleKeyPress(
        key: MediaKeyCode,
        effectiveClass: LiquidHUDKind,
        option: Bool,
        shift: Bool,
        command: Bool
    ) -> Bool {
        let fine = option && shift
        let stepDivisor: Float = fine ? 4.0 : 1.0
        let delta = Float(HUDLogic.step(fine: fine))
        
        switch key {
        case .volumeUp:
            let outcome = VolumeManager.shared.increaseVerified(stepDivisor: stepDivisor)
            recordSafetyOutcome(for: .volume, changed: outcome.changed, atRail: outcome.atRail)
            if outcome.changed || outcome.atRail {
                playFeedbackSound()
                return true
            }
            return false

        case .volumeDown:
            let outcome = VolumeManager.shared.decreaseVerified(stepDivisor: stepDivisor)
            recordSafetyOutcome(for: .volume, changed: outcome.changed, atRail: outcome.atRail)
            if outcome.changed || outcome.atRail {
                playFeedbackSound()
                return true
            }
            return false

        case .mute:
            let ok = VolumeManager.shared.toggleMuteVerified()
            recordSafetyOutcome(for: .volume, changed: ok, atRail: false)
            return ok

        case .brightnessUp:
            return adjustBrightnessVerified(
                delta: delta,
                effectiveClass: effectiveClass,
                keyboard: command
            )

        case .brightnessDown:
            return adjustBrightnessVerified(
                delta: -delta,
                effectiveClass: effectiveClass,
                keyboard: command
            )

        case .keyboardBrightnessUp:
            return adjustBrightnessVerified(
                delta: delta,
                effectiveClass: .keyboardBacklight,
                keyboard: true
            )

        case .keyboardBrightnessDown:
            return adjustBrightnessVerified(
                delta: -delta,
                effectiveClass: .keyboardBacklight,
                keyboard: true
            )
        }
    }
    
    private func adjustBrightnessVerified(
        delta: Float,
        effectiveClass: LiquidHUDKind,
        keyboard: Bool
    ) -> Bool {
        if keyboard {
            KeyboardBacklightManager.shared.setRelativeWithSafetyReport(delta: delta) { [weak self] changed, atRail in
                self?.recordSafetyOutcome(for: effectiveClass, changed: changed, atRail: atRail)
            }
            return true
        }

        if let directOutcome = BrightnessManager.shared.setRelativeWithSafetyReport(
            delta: delta,
            onAsyncOutcome: { [weak self] changed, atRail in
                self?.recordSafetyOutcome(for: .brightness, changed: changed, atRail: atRail)
            }
        ) {
            recordSafetyOutcome(for: .brightness, changed: directOutcome.changed, atRail: directOutcome.atRail)
            return directOutcome.changed || directOutcome.atRail
        }
        return true
    }
    
    private func showHUD(for key: MediaKeyCode, command: Bool) {
        switch key {
        case .volumeUp, .volumeDown, .mute:
            let v = VolumeManager.shared.rawVolume
            let isMuted = VolumeManager.shared.isMuted
            DynamicIslandHub.shared.triggerVolumeHUD(volume: Double(v), isMuted: isMuted)
        case .brightnessUp, .brightnessDown:
            if command {
                let v = KeyboardBacklightManager.shared.rawBrightness
                LiquidViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
            } else {
                let v = BrightnessManager.shared.rawBrightness
                DynamicIslandHub.shared.triggerBrightnessHUD(brightness: Double(v))
            }
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            let v = KeyboardBacklightManager.shared.rawBrightness
            LiquidViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
        }
    }
    
    private func openSystemSettings(for key: MediaKeyCode, command: Bool) {
        let urlString: String
        switch key {
        case .volumeUp, .volumeDown, .mute:
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
