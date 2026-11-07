// SPDX-License-Identifier: MIT
import AppKit
import ApplicationServices
import NotchCore

/// A volume key on the keyboard.
public enum VolumeKey: Equatable, Sendable {
    case up, down, mute
}

/// Catches the volume keys so the notch can show the change instead of macOS's own display. It's a
/// CGEvent tap on system-defined events, which needs Accessibility access; without it `start()`
/// returns false and the keys work as usual. The tap only sees those events and passes everything
/// but the three volume keys straight through.
@MainActor
public final class VolumeKeyTap {
    /// A volume key went down (or repeated); `fine` is Option-Shift for quarter steps.
    public var onKey: ((VolumeKey, _ fine: Bool) -> Void)?
    public var isRunning: Bool { tap != nil }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    public init() {}

    /// Whether macOS lets OpenNotch watch keyboard events.
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks macOS to show its Accessibility prompt, which leads to System Settings.
    public static func requestTrust() {
        // kAXTrustedCheckOptionPrompt's value; the global itself isn't concurrency-safe in Swift 6.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Starts watching; false when Accessibility access is missing.
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let keys = Unmanaged<VolumeKeyTap>.fromOpaque(context).takeUnretainedValue()
            let handled = MainActor.assumeIsolated { keys.handle(type, event) }
            return handled ? nil : Unmanaged.passUnretained(event)
        }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: CGEventMask(1 << Self.systemDefined), callback: callback, userInfo: context)
        else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        self.source = source
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// NX_SYSDEFINED: media and volume keys arrive as system-defined events.
    private static let systemDefined = 14

    /// Reads a system-defined event's `data1`: the key in the high 16 bits, and in the low 16 its
    /// state (0xA down, 0xB up) and a repeat flag.
    nonisolated static func volumeKey(data1: Int) -> (key: VolumeKey, isDown: Bool)? {
        let key: VolumeKey
        switch (data1 & 0xFFFF_0000) >> 16 {
        case 0: key = .up  // NX_KEYTYPE_SOUND_UP
        case 1: key = .down  // NX_KEYTYPE_SOUND_DOWN
        case 7: key = .mute  // NX_KEYTYPE_MUTE
        default: return nil
        }
        let state = (data1 & 0xFF00) >> 8
        guard state == 0xA || state == 0xB else { return nil }
        return (key, state == 0xA)
    }

    /// Takes a volume key's press and release so macOS doesn't also show its display.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type.rawValue == Self.systemDefined, let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8,
            let (key, isDown) = Self.volumeKey(data1: nsEvent.data1)
        else { return false }
        if isDown {
            onKey?(key, event.flags.contains(.maskAlternate) && event.flags.contains(.maskShift))
        }
        return true
    }
}
