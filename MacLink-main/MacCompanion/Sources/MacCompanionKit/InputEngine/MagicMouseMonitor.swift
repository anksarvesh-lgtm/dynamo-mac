// SPDX-License-Identifier: MIT
import AppKit

public struct MagicMouseState: Sendable, Equatable {
    public var isConnected: Bool = true
    public var lastScrollDeltaX: CGFloat = 0
    public var lastScrollDeltaY: CGFloat = 0
    public var isMomentumActive: Bool = false
    public var lastSwipeDirection: String? = nil

    /// Explicit architectural requirement (Part 5, Section 10 & Rule 6):
    /// Never pretend Magic Mouse has Force Touch.
    public let isForceTouchSupported: Bool = false

    public init() {}
}

public final class MagicMouseMonitor: @unchecked Sendable {
    public private(set) var state = MagicMouseState()
    private let lock = NSLock()

    public var onStateChanged: ((MagicMouseState) -> Void)?

    public init() {}

    public func recordScroll(deltaX: CGFloat, deltaY: CGFloat, momentum: Bool) {
        lock.lock()
        state.lastScrollDeltaX = deltaX
        state.lastScrollDeltaY = deltaY
        state.isMomentumActive = momentum
        let current = state
        lock.unlock()
        onStateChanged?(current)
    }

    public func recordSwipe(direction: String) {
        lock.lock()
        state.lastSwipeDirection = direction
        let current = state
        lock.unlock()
        onStateChanged?(current)
    }
}

