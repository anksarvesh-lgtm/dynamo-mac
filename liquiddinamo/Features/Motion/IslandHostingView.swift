//
//  IslandHostingView.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import SwiftUI
import Defaults

/// Custom NSHostingView that dynamically restricts mouse hit-testing strictly to the visible
/// Dynamic Island shape and satellite bubbles. Transparent window areas return `nil`, allowing
/// mouse clicks and hover gestures to pass directly through to desktop windows underneath.
public final class IslandHostingView<Content: View>: NSHostingView<Content> {
    public required init(rootView: Content) {
        super.init(rootView: rootView)
        self.sizingOptions = []
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        super.init(coder: coder)
        self.sizingOptions = []
    }

    /// Suppress SwiftUI NSHostingView from triggering internal window resizing loops during animated layout passes
    @objc func windowDidLayout() {
        // Controlled explicitly by IslandController / AppDelegate
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window = self.window else { return nil }
        guard IslandController.shared.containsPointInVisibleShape(point, inWindow: window) else {
            return nil
        }
        if let view = super.hitTest(point) {
            return view
        }
        return self
    }

    private var trackingArea: NSTrackingArea?

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let newArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
        trackingArea = newArea
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        IslandController.shared.checkCursorHover(screenPoint: NSEvent.mouseLocation)
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        IslandController.shared.checkCursorHover(screenPoint: NSEvent.mouseLocation)
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        IslandController.shared.checkCursorHover(screenPoint: NSEvent.mouseLocation)
    }

    public override func scrollWheel(with event: NSEvent) {
        if let appDelegate = AppDelegate.shared,
           appDelegate.handleScrollGesture(event: event, mouseLocation: NSEvent.mouseLocation) {
            return
        }
        super.scrollWheel(with: event)
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    public override func mouseDown(with event: NSEvent) {
        if IslandController.shared.state != .expanded {
            guard let window = self.window,
                  let screen = window.screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
                super.mouseDown(with: event)
                return
            }
            let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
            let hitRects = NotchSafeAreaEngine.shared.collapsedWingHitRects(for: screen)

            if Defaults[.leftWingMetric] != .none && hitRects.leftWingRect.contains(screenPoint) {
                NotificationCenter.default.post(name: .toggleSideReadoutDetails, object: "left")
                return
            } else if Defaults[.rightWingMetric] != .none && hitRects.rightWingRect.contains(screenPoint) {
                NotificationCenter.default.post(name: .toggleSideReadoutDetails, object: "right")
                return
            } else if hitRects.notchRect.contains(screenPoint) {
                // Clicking the physical notch area explicitly opens and pins the dashboard
                IslandController.shared.setExpanded(pin: true)
                return
            }
        } else {
            IslandController.shared.cancelHoverCollapse()
            IslandController.shared.isPinnedOpen = true
            if LiquidViewModel.shared.notchState != .open {
                LiquidViewModel.shared.open(pinned: true)
            }
            if let appDelegate = AppDelegate.shared, appDelegate.vm.notchState != .open {
                appDelegate.vm.open(pinned: true)
            }
        }
        super.mouseDown(with: event)
    }
}
