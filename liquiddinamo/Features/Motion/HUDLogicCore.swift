//
//  HUDLogicCore.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team
//  Pure system-key decoding, HUD formatting, and fail-safe interception logic.
//

import Foundation

/// Semantic media/hardware key decoded from an `NSSystemDefined` event.
public enum MediaKeyCode: Equatable, Hashable, Sendable {
    case volumeUp
    case volumeDown
    case mute
    case brightnessUp
    case brightnessDown
    case keyboardBrightnessUp
    case keyboardBrightnessDown
}

/// Decoded hardware key transition from subtype-8 system events.
public struct HUDKeyPress: Equatable, Sendable {
    public let key: MediaKeyCode
    public let isDown: Bool
    public let isRepeat: Bool

    public init(key: MediaKeyCode, isDown: Bool, isRepeat: Bool = false) {
        self.key = key
        self.isDown = isDown
        self.isRepeat = isRepeat
    }
}

/// Canonical system HUD payload independent of AppKit/SwiftUI views.
public struct LiquidHUDEvent: Equatable, Sendable {
    public var kind: LiquidHUDKind
    public var level: Double
    public var isMuted: Bool
    public var isOn: Bool
    public var deviceName: String?

    public init(
        kind: LiquidHUDKind,
        level: Double = 0,
        isMuted: Bool = false,
        isOn: Bool = false,
        deviceName: String? = nil
    ) {
        self.kind = kind
        self.level = min(1, max(0, level))
        self.isMuted = isMuted
        self.isOn = isOn
        self.deviceName = deviceName
    }
}

/// Pure HUD key decoding, step math, and level formatting helpers.
public enum HUDLogic {

    // MARK: - NX_KEYTYPE constants (IOKit/hidsystem/ev_keymap.h)

    private enum NXKey {
        static let soundUp = 0
        static let soundDown = 1
        static let brightnessUp = 2
        static let brightnessDown = 3
        static let mute = 7
        static let illuminationUp = 21
        static let illuminationDown = 22
    }

    /// Parses `NSEvent.data1` from a subtype-8 system-defined event into a key press.
    /// Layout: upper 16 bits hold the key code; lower word holds key flags where
    /// byte 1 is `0x0A` (down) / `0x0B` (up) and bit 0 indicates auto-repeat.
    public static func parseSystemDefinedKey(data1: Int) -> HUDKeyPress? {
        guard data1 >= 0 else { return nil }
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0x0000_FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isRepeat = (keyFlags & 0x1) == 1

        let isDown: Bool
        switch keyState {
        case 0x0A:
            isDown = true
        case 0x0B:
            isDown = false
        default:
            return nil
        }

        guard let key = mediaKey(forCode: keyCode) else { return nil }
        return HUDKeyPress(key: key, isDown: isDown, isRepeat: isRepeat)
    }

    private static func mediaKey(forCode code: Int) -> MediaKeyCode? {
        switch code {
        case NXKey.soundUp:
            return .volumeUp
        case NXKey.soundDown:
            return .volumeDown
        case NXKey.mute:
            return .mute
        case NXKey.brightnessUp:
            return .brightnessUp
        case NXKey.brightnessDown:
            return .brightnessDown
        case NXKey.illuminationUp:
            return .keyboardBrightnessUp
        case NXKey.illuminationDown:
            return .keyboardBrightnessDown
        default:
            return nil
        }
    }

    /// Maps a decoded key to the corresponding `LiquidHUDKind` interception class.
    public static func hudKind(for key: MediaKeyCode) -> LiquidHUDKind {
        switch key {
        case .volumeUp, .volumeDown, .mute:
            return .volume
        case .brightnessUp, .brightnessDown:
            return .brightness
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            return .keyboardBacklight
        }
    }

    /// Event tap activation policy: passive HUD display (`showNotchOSD`) must never
    /// install a swallowing `CGEvent` tap on its own; only explicit popup suppression does.
    public static func shouldActivateEventTap(
        hideSystemOSD: Bool,
        legacyHUDReplacement: Bool
    ) -> Bool {
        hideSystemOSD || legacyHUDReplacement
    }

    // MARK: - Level Presentation

    /// Filled discrete segment count in `0...total` (rounded to nearest).
    public static func filledSegments(
        level: Double,
        total: Int = 16,
        isMuted: Bool = false
    ) -> Int {
        guard total > 0, !isMuted else { return 0 }
        let clamped = min(1, max(0, level))
        let filled = Int((clamped * Double(total)).rounded())
        return min(total, max(0, filled))
    }

    /// Peak glow threshold classification for HUD progress bars.
    public enum GlowStage: Equatable, Sendable {
        case normal
        case hot
    }

    public static func glowStage(
        level: Double,
        threshold: Double = 0.8,
        isMuted: Bool = false
    ) -> GlowStage {
        guard !isMuted else { return .normal }
        return min(1, max(0, level)) > threshold ? .hot : .normal
    }

    /// Clamped readout text (`"Muted"` when muted, otherwise `"0%"..."100%"`).
    public static func percentText(level: Double, isMuted: Bool = false) -> String {
        if isMuted {
            return "Muted"
        }
        let clamped = min(1, max(0, level))
        return "\(Int((clamped * 100).rounded()))%"
    }

    // MARK: - Step Size

    /// Hardware step size per key press: `1/16` standard or `1/64` for Option+Shift fine adjust.
    public static func step(fine: Bool) -> Double {
        fine ? 1.0 / 64.0 : 1.0 / 16.0
    }
}

/// Pure consecutive-failure backoff state machine guarding against key lockouts when
/// an intercepted hardware write fails repeatedly (e.g., fixed-volume HDMI audio or
/// sandbox-denied brightness APIs).
public enum InterceptSafety {

    public struct State: Equatable, Sendable {
        public var failures: [LiquidHUDKind: Int]
        public var disabled: Set<LiquidHUDKind>

        public static let armed = State()

        public init(
            failures: [LiquidHUDKind: Int] = [:],
            disabled: Set<LiquidHUDKind> = []
        ) {
            self.failures = failures
            self.disabled = disabled
        }
    }

    /// Two consecutive genuine failures back off interception for that HUD class.
    public static let failureThreshold = 2

    /// Records the outcome of a swallowed key press.
    /// Rail hits (`atRail == true`) are legitimate no-ops and reset failure counters.
    public static func recording(
        _ state: State,
        keyClass: LiquidHUDKind,
        changed: Bool,
        atRail: Bool
    ) -> State {
        var next = state
        if changed || atRail {
            next.failures[keyClass] = 0
            return next
        }
        let count = (next.failures[keyClass] ?? 0) + 1
        next.failures[keyClass] = count
        if count >= failureThreshold {
            next.disabled.insert(keyClass)
        }
        return next
    }

    /// Returns whether the interceptor should swallow keys for `keyClass`.
    public static func isIntercepting(_ state: State, keyClass: LiquidHUDKind) -> Bool {
        !state.disabled.contains(keyClass)
    }

    /// Clears failures and backoff for a single key class (if provided) or all classes.
    public static func reset(_ state: State, keyClass: LiquidHUDKind? = nil) -> State {
        guard let keyClass else {
            return .armed
        }
        var next = state
        next.failures[keyClass] = 0
        next.disabled.remove(keyClass)
        return next
    }
}
