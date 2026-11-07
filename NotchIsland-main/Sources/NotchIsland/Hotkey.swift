import AppKit
import CoreGraphics

enum Hotkey {
    static func describe(keyCode: Int, flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + keyName(keyCode)
    }

    static func keyName(_ code: Int) -> String {
        let names: [Int: String] = [
            49: "Space", 36: "↩", 53: "Esc", 48: "⇥", 51: "⌫", 117: "⌦", 76: "⌅",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12", 50: "`", 27: "-", 24: "=", 33: "[",
            30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/",
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
            40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
            32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        ]
        return names[code] ?? "Key \(code)"
    }
}

/// Global hotkey through a CGEvent tap, which swallows the keystroke so the app behind doesn't
/// also see it (an NSEvent monitor can only observe). Needs Accessibility; `start()` returns
/// false without it and the caller falls back to monitors.
final class HotkeyManager {
    var onTrigger: (() -> Void)?
    private(set) var isActive = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var keyCode: Int64 = 49
    private var flags: CGEventFlags = .maskAlternate

    func configure(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = Int64(keyCode)
        var f: CGEventFlags = []
        if modifiers.contains(.command) { f.insert(.maskCommand) }
        if modifiers.contains(.option) { f.insert(.maskAlternate) }
        if modifiers.contains(.control) { f.insert(.maskControl) }
        if modifiers.contains(.shift) { f.insert(.maskShift) }
        flags = f
    }

    @discardableResult
    func start() -> Bool {
        stop()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: hotkeyTapCallback, userInfo: refcon) else {
            isActive = false
            return false
        }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        source = src
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        isActive = false
    }

    /// Returns true when the event was ours and should be swallowed.
    fileprivate func handle(_ event: CGEvent, type: CGEventType) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == keyCode else { return false }
        let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        guard event.flags.intersection(relevant) == flags else { return false }
        DispatchQueue.main.async { self.onTrigger?() }
        return true
    }
}

private func hotkeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                               refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handle(event, type: type) ? nil : Unmanaged.passUnretained(event)
}
