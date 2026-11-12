//
//  LiquidDynamoWindow.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team
//

import Cocoa
import Combine
import Defaults

class LiquidDynamoWindow: NSPanel {
    private var observers: Set<AnyCancellable> = []

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )

        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        appearance = NSAppearance(named: .darkAqua)

        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]

        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false

        updateSharingType()
        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)
    }

    private func updateSharingType() {
        sharingType = Defaults[.hideFromScreenRecording] ? .none : .readWrite
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    public static var allowsKeyWindow: Bool = false
    public var customCanBecomeKey: Bool = false

    override var canBecomeKey: Bool {
        customCanBecomeKey || Self.allowsKeyWindow
    }

    override var canBecomeMain: Bool {
        false
    }
}
