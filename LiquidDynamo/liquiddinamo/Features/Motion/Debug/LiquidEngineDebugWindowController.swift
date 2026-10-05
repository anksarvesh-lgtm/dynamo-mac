//
//  LiquidEngineDebugWindowController.swift
//  LiquidDynamo
//
//  Standalone Window Controller for Liquid Island Metal SDF Debug View.
//

#if DEBUG
import AppKit
import SwiftUI

@MainActor
public final class LiquidEngineDebugWindowController: NSWindowController {
    public static let shared = LiquidEngineDebugWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1010, height: 460),
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
        window.title = "Liquid Island Metal SDF Engine Inspector"
        window.contentView = NSHostingView(rootView: LiquidEngineDebugView())
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
