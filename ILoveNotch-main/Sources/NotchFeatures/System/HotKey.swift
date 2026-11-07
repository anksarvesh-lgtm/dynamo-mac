// SPDX-License-Identifier: MIT
import AppKit
import Carbon.HIToolbox
import NotchCore
import Observation

/// A global keyboard shortcut through Carbon's hot keys: public, no permission needed, allowed in
/// the App Sandbox, and silent between presses (the window server delivers only our key).
@MainActor
@Observable
public final class HotKey {
    /// The shortcut went down.
    @ObservationIgnored public var onPress: (() -> Void)?
    /// What to listen for; nil listens for nothing.
    public var shortcut: KeyShortcut? {
        didSet { if shortcut != oldValue { update() } }
    }
    /// Stops listening without forgetting the shortcut, for example while Settings records a new one.
    public var isPaused = false {
        didSet { if isPaused != oldValue { update() } }
    }
    /// False when another app already has the shortcut.
    public private(set) var isAvailable = true

    @ObservationIgnored private var registration: EventHotKeyRef?
    @ObservationIgnored private let id: UInt32
    private static var registered: [UInt32: HotKey] = [:]
    private static var handler: EventHandlerRef?
    private static var lastID: UInt32 = 0
    private static let signature: OSType = 0x494C_4E4B  // "ILNK"

    public init() {
        Self.lastID += 1
        id = Self.lastID
    }

    private func update() {
        if let registration { UnregisterEventHotKey(registration) }
        registration = nil
        Self.registered[id] = nil
        isAvailable = true
        guard let shortcut, !isPaused else { return }
        Self.installHandler()
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else {
            Log.features.error("Couldn't register \(shortcut.display, privacy: .public): \(status, privacy: .public)")
            isAvailable = false
            return
        }
        registration = reference
        Self.registered[id] = self
    }

    /// One handler for every hot key, installed on first use; it finds the key by its id.
    private static func installHandler() {
        guard handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var key = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &key)
                // The application event target calls back on the main thread.
                MainActor.assumeIsolated { HotKey.registered[key.id]?.onPress?() }
                return noErr
            }, 1, &pressed, nil, &handler)
    }
}

extension KeyShortcut {
    /// Escape, alone, for closing what a shortcut opened.
    public static let escape = KeyShortcut(keyCode: UInt32(kVK_Escape), modifiers: 0, key: "⎋")
    /// Control-Option-N, which starts a new note.
    public static let newNote = KeyShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: control | option, key: "N")

    /// The shortcut a key press makes, or nil without Command, Option, or Control: a shortcut
    /// plain typing could set off isn't one.
    public init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.isDisjoint(with: [.command, .option, .control]) else { return nil }
        let carbon: [(NSEvent.ModifierFlags, UInt32)] = [
            (.command, Self.command), (.shift, Self.shift), (.option, Self.option), (.control, Self.control),
        ]
        let modifiers = carbon.filter { flags.contains($0.0) }.reduce(0) { $0 | $1.1 }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: Self.name(of: event))
    }

    /// What a key is called in a shortcut: its character on this keyboard, or a symbol or name for
    /// keys that don't type one.
    static func name(of event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        default: break
        }
        let character = event.charactersIgnoringModifiers?.unicodeScalars.first?.value ?? 0
        switch Int(character) {
        case NSUpArrowFunctionKey: return "↑"
        case NSDownArrowFunctionKey: return "↓"
        case NSLeftArrowFunctionKey: return "←"
        case NSRightArrowFunctionKey: return "→"
        case NSF1FunctionKey...NSF35FunctionKey: return "F\(Int(character) - NSF1FunctionKey + 1)"
        default: return event.charactersIgnoringModifiers?.uppercased() ?? "?"
        }
    }
}
