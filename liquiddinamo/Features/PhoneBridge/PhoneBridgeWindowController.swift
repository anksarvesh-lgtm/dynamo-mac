//
//  PhoneBridgeWindowController.swift
//  LiquidDynamo
//
//  Dedicated App Window Controller for Phone Bridge & OpenMTP.
//  Presents the full dual-pane / folder manager UI directly in an AppKit window,
//  bypassing Finder and providing full desktop file management.
//

import AppKit
import SwiftUI

public final class PhoneBridgeWindowController: NSWindowController {
    public static let shared = PhoneBridgeWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 150, y: 150, width: 880, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
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
        window.title = "Phone Bridge"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 650, height: 480)

        let rootView = PhoneBridgeStandaloneWindowView()
        window.contentView = NSHostingView(rootView: rootView)
    }

    public func showWindow() {
        guard let window = self.window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        PhoneBridgeEngine.shared.scanDevices()
    }
}

public struct PhoneBridgeStandaloneWindowView: View {
    @ObservedObject private var engine = PhoneBridgeEngine.shared

    public init() {}

    public var body: some View {
        ZStack {
            VisualEffectBackdropView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Window Title Bar
                HStack(spacing: 10) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.24, green: 0.86, blue: 0.52))

                    Text("Phone Bridge")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    if let dev = engine.selectedDevice {
                        Text("• \(dev.displayName)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.green)
                    }

                    Spacer()

                    Button {
                        PhoneBridgeWindowController.shared.window?.close()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider()
                    .background(Color.white.opacity(0.12))

                // Full File Manager UI
                PhoneBridgeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 650, minHeight: 480)
    }
}

// MARK: - Backward Compatibility Aliases
public typealias FileDroidWindowController = PhoneBridgeWindowController
public typealias FileDroidStandaloneWindowView = PhoneBridgeStandaloneWindowView
