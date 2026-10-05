//
//  MotionTuningWindowController.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

#if DEBUG
import AppKit
import SwiftUI

public final class MotionTuningWindowController: NSWindowController {
    public static let shared = MotionTuningWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 440, height: 680),
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
        window.title = "Dynamic Island Motion Tuner"
        window.contentView = NSHostingView(rootView: MotionTuningPanelView())
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
