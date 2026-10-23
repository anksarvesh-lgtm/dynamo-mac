//
//  WaterPhysicsDebugWindowController.swift
//  LiquidDynamo
//
//  Standalone Window Controller for the Step A Water Physics Debug Inspector.
//

#if DEBUG
import AppKit
import SwiftUI

@MainActor
public final class WaterPhysicsDebugWindowController: NSWindowController {
    public static let shared = WaterPhysicsDebugWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        setupWindow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindow() {
        guard let window = self.window else { return }
        window.title = "LiquidDynamo - Water Physics Model Inspector (Step A)"
        window.contentView = NSHostingView(rootView: WaterPhysicsDebugView())
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
    }

    public func show() {
        guard let window = self.window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
