import AppKit
import Carbon.HIToolbox
import Foundation
import IslandCore

/// System-wide shortcut via Carbon's RegisterEventHotKey — public, and needs no Accessibility permission.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private let hotKeyID: UInt32
    private(set) var registered: IslandShortcut?
    private(set) var lastError: OSStatus = noErr
    private static var nextID: UInt32 = 1

    init(action: @escaping () -> Void) {
        self.action = action
        hotKeyID = Self.nextID
        Self.nextID += 1
    }

    var isRegistered: Bool { ref != nil }

    func register(_ shortcut: IslandShortcut?) {
        unregister()
        guard let shortcut else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), { _, event, ctx in
                guard let ctx, let event else { return OSStatus(eventNotHandledErr) }
                var pressed = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &pressed)
                let hk = Unmanaged<HotKey>.fromOpaque(ctx).takeUnretainedValue()
                // Every HotKey instance sees every hot-key event; only react to our own id.
                guard pressed.signature == HotKey.signature, pressed.id == hk.hotKeyID else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async { MainActor.assumeIsolated { hk.action() } }
                return noErr
            }, 1, &spec, selfPtr, &handler)
        }
        let id = EventHotKeyID(signature: Self.signature, id: hotKeyID)
        lastError = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        registered = lastError == noErr ? shortcut : nil
    }

    nonisolated static let signature = OSType(0x49534C44) // 'ISLD'

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        registered = nil
    }

    /// Converts AppKit modifier flags to Carbon's mask.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    static func display(keyCode: UInt16, characters: String?, flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        let names: [UInt16: String] = [49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        return s + (names[keyCode] ?? (characters ?? "?").uppercased())
    }
}
