//
//  LiquidBlobDebugWindowController.swift
//  LiquidDynamo
//
//  Window Controller for the Step B Multi-Blob Liquid Inspector.
//

#if DEBUG
import AppKit
import SwiftUI

@MainActor
public final class LiquidBlobDebugWindowController: NSWindowController {
    public static let shared = LiquidBlobDebugWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 960, height: 500),
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
        window.title = "LiquidDynamo Step B - Multi-Blob Liquid Field Inspector"
        window.contentView = NSHostingView(rootView: LiquidBlobDebugView())
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
