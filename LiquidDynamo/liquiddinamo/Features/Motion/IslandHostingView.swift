//
//  IslandHostingView.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import SwiftUI

/// Custom NSHostingView that dynamically restricts mouse hit-testing strictly to the visible
/// Dynamic Island shape and satellite bubbles. Transparent window areas return `nil`, allowing
/// mouse clicks and hover gestures to pass directly through to desktop windows underneath.
public final class IslandHostingView<Content: View>: NSHostingView<Content> {
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window = self.window else { return nil }
        guard IslandController.shared.containsPointInVisibleShape(point, inWindow: window) else {
            return nil
        }
        return super.hitTest(point)
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
