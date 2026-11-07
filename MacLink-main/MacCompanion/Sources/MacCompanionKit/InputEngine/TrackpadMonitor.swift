// SPDX-License-Identifier: MIT
import AppKit

public struct TrackpadState: Sendable, Equatable {
    public var activeTouchCount: Int = 0
    public var isTouching: Bool = false
    public var magnification: CGFloat = 1.0
    public var rotationDegrees: CGFloat = 0.0
    public var currentForceStage: ForceTouchStage = .resting
    public var lastPressure: Float = 0.0
    public var lastScrollPhase: NSEvent.Phase = []

    public init() {}
}

public final class TrackpadMonitor: @unchecked Sendable {
    public private(set) var state = TrackpadState()
    private let lock = NSLock()

    public var onStateChanged: ((TrackpadState) -> Void)?

    public init() {}

    public func updateTouches(count: Int) {
        lock.lock()
        state.activeTouchCount = count
        state.isTouching = count > 0
        let current = state
        lock.unlock()
        onStateChanged?(current)
    }

    public func updateMagnification(_ mag: CGFloat) {
        lock.lock()
        state.magnification = mag
        let current = state
        lock.unlock()
        onStateChanged?(current)
    }

    public func updateRotation(_ degrees: CGFloat) {
        lock.lock()
        state.rotationDegrees = degrees
        let current = state
        lock.unlock()
        onStateChanged?(current)
    }

    public func updatePressure(stage: Int, pressure: Float) {
        lock.lock()
        state.currentForceStage = ForceTouchStage(rawValue: stage) ?? .resting
        state.lastPressure = pressure
        let current = state
        lock.unlock()
        onStateChanged?(current)
    }
}

