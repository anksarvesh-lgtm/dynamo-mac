// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics

public final class RemoteInputController: @unchecked Sendable {
    private let lock = NSLock()

    // Tracking active states to prevent stuck inputs
    private var isLeftButtonHeld: Bool = false
    private var isRightButtonHeld: Bool = false
    private var isOtherButtonHeld: Bool = false
    private var heldModifiers: Set<CGKeyCode> = []

    public init() {}

    // MARK: - Pointer Movement
    public func handlePointerMove(deltaX: Double, deltaY: Double) {
        lock.lock()
        let isDragging = isLeftButtonHeld
        lock.unlock()

        let currentPos = CGEvent(source: nil)?.location ?? .zero
        let newX = max(0, currentPos.x + CGFloat(deltaX))
        let newY = max(0, currentPos.y + CGFloat(deltaY))
        let newPos = CGPoint(x: newX, y: newY)

        let eventType: CGEventType = isDragging ? .leftMouseDragged : .mouseMoved
        let mouseButton: CGMouseButton = isDragging ? .left : .left

        if let event = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: newPos,
            mouseButton: mouseButton
        ) {
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Mouse Clicks
    public func handleLeftClick(clicks: Int = 1) {
        let currentPos = CGEvent(source: nil)?.location ?? .zero

        for i in 1...clicks {
            if let down = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: currentPos,
                mouseButton: .left
            ) {
                down.setIntegerValueField(.mouseEventClickState, value: Int64(i))
                down.post(tap: .cghidEventTap)
            }

            if let up = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: currentPos,
                mouseButton: .left
            ) {
                up.setIntegerValueField(.mouseEventClickState, value: Int64(i))
                up.post(tap: .cghidEventTap)
            }
        }
    }

    public func handleRightClick() {
        let currentPos = CGEvent(source: nil)?.location ?? .zero

        if let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseDown,
            mouseCursorPosition: currentPos,
            mouseButton: .right
        ) {
            down.setIntegerValueField(.mouseEventClickState, value: 1)
            down.post(tap: .cghidEventTap)
        }

        if let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseUp,
            mouseCursorPosition: currentPos,
            mouseButton: .right
        ) {
            up.setIntegerValueField(.mouseEventClickState, value: 1)
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Button Down / Up (Drag operations)
    public func handlePointerDown(button: PointerButtonPayload.Button) {
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        lock.lock()
        defer { lock.unlock() }

        switch button {
        case .left:
            isLeftButtonHeld = true
            if let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: currentPos, mouseButton: .left) {
                event.post(tap: .cghidEventTap)
            }
        case .right:
            isRightButtonHeld = true
            if let event = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: currentPos, mouseButton: .right) {
                event.post(tap: .cghidEventTap)
            }
        case .middle:
            isOtherButtonHeld = true
            if let event = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: currentPos, mouseButton: .center) {
                event.post(tap: .cghidEventTap)
            }
        }
    }

    public func handlePointerUp(button: PointerButtonPayload.Button) {
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        lock.lock()
        defer { lock.unlock() }

        switch button {
        case .left:
            isLeftButtonHeld = false
            if let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: currentPos, mouseButton: .left) {
                event.post(tap: .cghidEventTap)
            }
        case .right:
            isRightButtonHeld = false
            if let event = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: currentPos, mouseButton: .right) {
                event.post(tap: .cghidEventTap)
            }
        case .middle:
            isOtherButtonHeld = false
            if let event = CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp, mouseCursorPosition: currentPos, mouseButton: .center) {
                event.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Scrolling
    public func handleScroll(deltaX: Double, deltaY: Double, isContinuous: Bool) {
        // CGEvent scroll wheel pixel units
        let dy = Int32(deltaY)
        let dx = Int32(deltaX)
        if dy == 0 && dx == 0 { return }

        if let scroll = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: dy,
            wheel2: dx,
            wheel3: 0
        ) {
            scroll.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Swipes (macOS native shortcuts)
    public func handleSwipe(direction: SwipePayload.Direction, fingers: Int) {
        // macOS standard shortcut emulation:
        // 3/4 finger swipe up -> Mission Control (Ctrl + Up)
        // 3/4 finger swipe down -> App Exposé (Ctrl + Down)
        // 3/4 finger swipe left -> Previous Space (Ctrl + Left)
        // 3/4 finger swipe right -> Next Space (Ctrl + Right)
        let keyCode: CGKeyCode
        switch direction {
        case .up: keyCode = 126 // Up Arrow
        case .down: keyCode = 125 // Down Arrow
        case .left: keyCode = 123 // Left Arrow
        case .right: keyCode = 124 // Right Arrow
        }

        postKeyCombo(keyCode: keyCode, modifiers: [.maskControl])
    }

    private func postKeyCombo(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        if let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) {
            down.flags = modifiers
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            up.flags = modifiers
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Critical Fail-Safe Release (Rule 10 & Section 22)
    /// Guarantees that on disconnect, crash, or timeout, no mouse buttons or modifier keys remain stuck.
    public func emergencyInputCleanup() {
        lock.lock()
        let currentPos = CGEvent(source: nil)?.location ?? .zero
        let wasLeftHeld = isLeftButtonHeld
        let wasRightHeld = isRightButtonHeld
        let wasOtherHeld = isOtherButtonHeld
        let modifiersToRelease = heldModifiers

        isLeftButtonHeld = false
        isRightButtonHeld = false
        isOtherButtonHeld = false
        heldModifiers.removeAll()
        lock.unlock()

        if wasLeftHeld {
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: currentPos, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        if wasRightHeld {
            CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: currentPos, mouseButton: .right)?.post(tap: .cghidEventTap)
        }
        if wasOtherHeld {
            CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp, mouseCursorPosition: currentPos, mouseButton: .center)?.post(tap: .cghidEventTap)
        }

        for key in modifiersToRelease {
            CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)?.post(tap: .cghidEventTap)
        }
    }

    public var buttonStateSummary: String {
        lock.lock()
        defer { lock.unlock() }
        return "Left: \(isLeftButtonHeld), Right: \(isRightButtonHeld), Modifiers: \(heldModifiers.count)"
    }
}

