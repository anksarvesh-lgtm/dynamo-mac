// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing

@testable import NotchSurface

/// Windows as the window server lists them, in its top-left coordinates.
private func window(_ frame: CGRect, layer: Int = 0) -> [String: Any] {
    [kCGWindowLayer as String: layer, kCGWindowBounds as String: frame.dictionaryRepresentation]
}

private let macBook = CGRect(x: 0, y: 0, width: 1512, height: 982)
/// A notchless display to the right of the MacBook.
private let external = CGRect(x: 1512, y: -200, width: 2560, height: 1440)

struct FullScreenTests {
    @Test func aFullScreenAppHidesTheNotchOnADisplayWithoutOne() {
        #expect(PanelCoordinator.isFilled(external, by: [window(external)]))
        #expect(!PanelCoordinator.isFilled(macBook, by: [window(external)]), "only on its own display")
    }

    /// As measured on a 14" MacBook Pro: full screen stops below the camera, so the notch stays.
    @Test func aNotchedDisplayKeepsItsNotch() {
        #expect(!PanelCoordinator.isFilled(macBook, by: [window(CGRect(x: 0, y: 33, width: 1512, height: 949))]))
    }

    @Test func onlyAppWindowsCount() {
        let zoomed = CGRect(x: 1512, y: -175, width: 2560, height: 1415)  // below the menu bar
        #expect(!PanelCoordinator.isFilled(external, by: [window(zoomed)]))
        #expect(!PanelCoordinator.isFilled(external, by: [window(external, layer: 25)]), "the notch itself")
        #expect(!PanelCoordinator.isFilled(external, by: [[kCGWindowLayer as String: 0]]), "no bounds")
    }
}
