//
//  LockScreenIslandService.swift
//  LiquidDynamo
//
//  Manages Lock Screen Dynamic Island widgets and ambient status overlays.
//  Merged from Atoll.
//

import AppKit
import Combine
import SwiftUI

@MainActor
public final class LockScreenIslandService: ObservableObject {
    public static let shared = LockScreenIslandService()

    @Published public private(set) var isScreenLocked: Bool = false
    private var lockObserver: Any?
    private var unlockObserver: Any?
    private var overlayWindow: NSWindow?

    private init() {
        setupObservers()
    }

    private func setupObservers() {
        let center = DistributedNotificationCenter.default()

        lockObserver = center.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isScreenLocked = true
                self?.showLockScreenOverlay()
            }
        }

        unlockObserver = center.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isScreenLocked = false
                self?.hideLockScreenOverlay()
            }
        }
    }

    public func showLockScreenOverlay() {
        guard overlayWindow == nil, let screen = NSScreen.main else { return }

        let window = NSWindow(
            contentRect: NSRect(x: screen.frame.midX - 140, y: screen.frame.maxY - 70, width: 280, height: 44),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(Int(CGWindowLevelKey.overlayWindow.rawValue))
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true

        let hosting = NSHostingView(rootView: LockScreenIslandView())
        window.contentView = hosting
        window.orderFront(nil)
        self.overlayWindow = window
    }

    public func hideLockScreenOverlay() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }
}

public struct LockScreenIslandView: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .foregroundColor(.green)
                .font(.system(size: 13, weight: .bold))

            Text("Charging • 92%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            Image(systemName: "music.note")
                .foregroundColor(.white.opacity(0.7))
                .font(.system(size: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

