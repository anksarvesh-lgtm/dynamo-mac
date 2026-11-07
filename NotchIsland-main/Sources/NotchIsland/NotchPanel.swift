import AppKit
import Combine
import SwiftUI

/// Transparent, always-on-top, non-activating panel pinned to the top-centre of the notched screen.
/// It resizes with the island layout so it never swallows clicks on the rest of the menu bar.
final class NotchPanel: NSPanel {
    private let state: IslandState
    private var cancellables = Set<AnyCancellable>()
    private var shrinkWork: DispatchWorkItem?

    init(state: IslandState) {
        self.state = state
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        appearance = NSAppearance(named: .darkAqua)   // text fields, menus and carets match the black surface
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        contentView = NSHostingView(rootView: NotchView(state: state))

        state.$layout
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] layout in self?.reposition(layout: layout) }
            .store(in: &cancellables)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private var hiddenByPolicy = false

    func show() {
        reposition()
        orderFrontRegardless()
    }

    /// Hidden over full-screen apps / listed apps (see Settings → Visibility).
    func setHiddenByPolicy(_ hidden: Bool) {
        guard hidden != hiddenByPolicy else { return }
        hiddenByPolicy = hidden
        if hidden { orderOut(nil) } else { reposition() }
    }

    func reposition(layout: IslandLayout? = nil) {
        let geo = NotchGeometry.current
        let layout = layout ?? state.layout
        let size = layout.panelSize(geo)

        let sf = geo.screen.frame
        let target = NSRect(x: (sf.midX - size.width / 2).rounded(),
                            y: sf.maxY - size.height,
                            width: size.width, height: size.height)

        shrinkWork?.cancel()
        if target.width < frame.width || target.height < frame.height {
            // Let the SwiftUI collapse animation finish before clipping the window.
            let work = DispatchWorkItem { [weak self] in self?.setFrame(target, display: true) }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        } else {
            setFrame(target, display: true)
        }

        guard !hiddenByPolicy else { return }
        if layout.isOpen {
            makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            orderFrontRegardless()
        }
    }

    override func resignKey() {
        super.resignKey()
        if ProcessInfo.processInfo.environment["NOTCHISLAND_DEBUG"] != nil {
            NSLog("NotchIsland: panel resigned key (frontmost: %@)", NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")
        }
        if state.isLauncherOpen { state.closeLauncher() }
        if state.isShadeOpen { state.closeShade() }
    }

    /// Esc closes the shade (the launcher handles its own Esc through the text field).
    override func cancelOperation(_ sender: Any?) {
        if state.isShadeOpen { state.closeShade() }
        else if state.isLauncherOpen { state.closeLauncher() }
    }
}
