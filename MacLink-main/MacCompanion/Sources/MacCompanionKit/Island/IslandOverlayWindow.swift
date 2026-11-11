// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

public final class IslandOverlayWindow: NSPanel {
    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false

        let contentView = IslandOverlayContentView()
        self.contentView = NSHostingView(rootView: contentView)

        repositionAtScreenTop()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged() {
        repositionAtScreenTop()
    }

    public func repositionAtScreenTop() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let width: CGFloat = 340
        let height: CGFloat = 44
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.origin.y + screenFrame.height - height - 4
        self.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

public struct IslandOverlayContentView: View {
    @ObservedObject private var keepAwake = KeepAwakeManager.shared

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            // Left glyph: Keep Awake status or Island icon
            if keepAwake.isActive {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.yellow)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 2) {
                if keepAwake.isActive {
                    Text("Keep Awake · \(keepAwake.remainingFormatted)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                } else {
                    Text("MacLink Island")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }

            Spacer()

            if keepAwake.isActive {
                Button(action: {
                    keepAwake.stop()
                }) {
                    Text("Stop")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.92))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}
