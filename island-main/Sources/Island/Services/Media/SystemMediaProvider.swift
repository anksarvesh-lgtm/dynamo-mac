import AppKit
import ApplicationServices
import IslandCore

/// System-wide fallback: sends the hardware media keys (play/pause, next, previous), which macOS routes
/// to whichever app currently owns Now Playing. macOS has no public API to *read* system Now Playing,
/// so this provider never produces a MediaActivity — it only controls. Posting key events requires the
/// user to grant Accessibility access; without it, this does nothing.
@MainActor
enum SystemMediaProvider {
    enum Key: Int32 { case playPause = 16, next = 17, previous = 18 } // NX_KEYTYPE_*

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @discardableResult
    static func send(_ key: Key) -> Bool {
        guard isTrusted else { return false }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key.rawValue << 16) | ((down ? 0xA : 0xB) << 8))
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                                 windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1) else { return false }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        return true
    }
}
