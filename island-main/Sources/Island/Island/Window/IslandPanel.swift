import AppKit
import SwiftUI

/// Borderless, non-activating panel. It only becomes key while search needs the keyboard,
/// so normal use never steals focus from the frontmost app.
final class IslandPanel: NSPanel {
    var allowsKey = false

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    // Borderless windows are normally pushed below the menu bar; the Island must sit on the notch.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isFloatingPanel = true
        level = .statusBar // after isFloatingPanel, which resets the level to .floating
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        animationBehavior = .none
        title = "Island"
        setAccessibilityLabel("Island")
    }
}

/// Accepts the first click so buttons work without first activating the (inactive) panel.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
