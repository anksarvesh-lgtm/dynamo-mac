import AppKit

/// Measures the physical notch on the built-in display.
struct NotchGeometry {
    let screen: NSScreen

    static var current: NotchGeometry {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        return NotchGeometry(screen: screen)
    }

    var hasNotch: Bool { screen.safeAreaInsets.top > 0 }

    /// Height of the notch (equals the menu bar height on notched Macs). Falls back to 32pt.
    var notchHeight: CGFloat { hasNotch ? screen.safeAreaInsets.top : 32 }

    /// Width between the two menu-bar "ears". Falls back to 200pt on non-notch Macs.
    var notchWidth: CGFloat {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return right.minX - left.maxX
        }
        return 200
    }
}
