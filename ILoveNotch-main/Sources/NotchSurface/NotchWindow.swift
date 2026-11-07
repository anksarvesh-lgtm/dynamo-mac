// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// Fixed-size, transparent, non-activating panel. The window server hit-tests transparent windows
/// by alpha, so clicks on the empty part of the panel fall through to the windows below and only
/// the black notch takes the mouse. Setting `ignoresMouseEvents` (even to false) turns that off,
/// so it is deliberately never touched.
final class NotchWindow: NSPanel {
    /// Escape while the panel has keyboard focus.
    var onCancel: (() -> Void)?

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = true
        level = .statusBar
        // On every Space, full-screen ones too, with or without .fullScreenAuxiliary: PanelCoordinator
        // hides the notch on a display a full-screen app fills.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        // Only views that need the keyboard, like text fields, make the panel key.
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        // Escape (key code 53) closes the notch, unless it is cancelling an input-method composition.
        let composing = (firstResponder as? NSTextView)?.hasMarkedText() ?? false
        if event.type == .keyDown, event.keyCode == 53, !composing {
            onCancel?()
            return
        }
        super.sendEvent(event)
    }
}

/// Hands the first click straight to SwiftUI; the panel is rarely key when the click arrives.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
