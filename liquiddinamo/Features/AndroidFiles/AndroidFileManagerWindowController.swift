//
//  AndroidFileManagerWindowController.swift
//  LiquidDynamo
//
//  AppKit Window Controller for the in-app Android File Manager.
//  Presents a dedicated resizable desktop window per connected Android device serial,
//  brings existing windows to focus on re-tap, and safely isolates window lifecycle
//  from the Dynamic Island notch overlay.
//

import AppKit
import Foundation
import SwiftUI

public final class AndroidFileManagerWindowController: NSWindowController, NSWindowDelegate {
    public let deviceSerial: String
    public let viewModel: AndroidFileManagerViewModel

    public init(
        deviceSerial: String,
        deviceName: String,
        deviceModel: String = "",
        client: ADBClient? = nil
    ) {
        self.deviceSerial = deviceSerial
        self.viewModel = AndroidFileManagerViewModel(
            deviceSerial: deviceSerial,
            deviceName: deviceName,
            deviceModel: deviceModel,
            client: client
        )

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 920, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.delegate = self
        setupWindow(title: "\(deviceName) Files")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindow(title: String) {
        guard let window = self.window else { return }
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: 500)

        let rootView = AndroidFileManagerView(viewModel: viewModel)
        window.contentView = NSHostingView(rootView: rootView)
    }

    public func showWindow() {
        guard let window = self.window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        viewModel.refresh()
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        AndroidThumbnailCache.shared.cancelAllPending()
    }
}

// MARK: - Window Manager Singleton

@MainActor
public final class AndroidFileManagerWindowManager: ObservableObject {
    public static let shared = AndroidFileManagerWindowManager()

    private var activeControllers: [String: AndroidFileManagerWindowController] = [:]

    private init() {}

    /// Opens or brings to front the dedicated file manager window for a given Android device.
    /// Does NOT collapse or unpin the notch island.
    public func openWindow(
        for deviceSerial: String,
        deviceName: String,
        deviceModel: String = "",
        client: ADBClient? = nil
    ) {
        if let existing = activeControllers[deviceSerial] {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            existing.viewModel.refresh()
            return
        }

        let controller = AndroidFileManagerWindowController(
            deviceSerial: deviceSerial,
            deviceName: deviceName,
            deviceModel: deviceModel,
            client: client
        )
        activeControllers[deviceSerial] = controller
        controller.showWindow()
    }

    public func closeWindow(for deviceSerial: String) {
        activeControllers[deviceSerial]?.close()
        activeControllers.removeValue(forKey: deviceSerial)
    }

    public func closeAllWindows() {
        for (_, ctrl) in activeControllers {
            ctrl.close()
        }
        activeControllers.removeAll()
    }
}
