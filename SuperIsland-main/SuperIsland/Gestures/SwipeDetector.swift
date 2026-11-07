import AppKit
import SwiftUI

struct SwipeDetector: ViewModifier {
    let onSwipe: (SwipeDirection) -> Void
    var minimumDistance: CGFloat = 20
    var velocityThreshold: CGFloat = 100

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: minimumDistance)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    let velocity = sqrt(
                        pow(value.velocity.width, 2) + pow(value.velocity.height, 2)
                    )

                    guard velocity > velocityThreshold else { return }

                    if abs(horizontal) > abs(vertical) {
                        onSwipe(horizontal > 0 ? .right : .left)
                    } else {
                        onSwipe(vertical > 0 ? .down : .up)
                    }
                }
        )
    }
}

extension View {
    func onSwipe(
        minimumDistance: CGFloat = 20,
        velocityThreshold: CGFloat = 100,
        perform action: @escaping (SwipeDirection) -> Void
    ) -> some View {
        modifier(SwipeDetector(
            onSwipe: action,
            minimumDistance: minimumDistance,
            velocityThreshold: velocityThreshold
        ))
    }

    func onTrackpadSwipe(
        perform action: @escaping (SwipeDirection) -> Void
    ) -> some View {
        overlay {
            TrackpadSwipeOverlay(onSwipe: action)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Trackpad Two-Finger Swipe

/// Transparent overlay that uses a local event monitor to capture two-finger
/// horizontal trackpad scroll gestures without blocking clicks or taps.
struct TrackpadSwipeOverlay: NSViewRepresentable {
    let onSwipe: (SwipeDirection) -> Void

    func makeNSView(context: Context) -> TrackpadSwipeView {
        let view = TrackpadSwipeView()
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ nsView: TrackpadSwipeView, context: Context) {
        nsView.onSwipe = onSwipe
    }
}

final class TrackpadSwipeView: NSView {
    var onSwipe: ((SwipeDirection) -> Void)?

    private enum ScrollAxis {
        case undecided
        case horizontal
        case vertical
    }

    private var monitor: Any?
    private var accumulatedDeltaX: CGFloat = 0
    private var accumulatedDeltaY: CGFloat = 0
    private var totalAbsDeltaX: CGFloat = 0
    private var totalAbsDeltaY: CGFloat = 0
    private var lockedAxis: ScrollAxis = .undecided
    private var hasFired = false
    private let horizontalLockThreshold: CGFloat = 12
    private let horizontalTriggerThreshold: CGFloat = 22
    private let verticalLockThreshold: CGFloat = 16
    private let horizontalDominanceRatio: CGFloat = 1.25
    private let verticalDominanceRatio: CGFloat = 1.35
    private let gestureTimeout: TimeInterval = 0.35
    private var lastScrollEventTime: TimeInterval = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScroll(event)
                return event
            }
        } else if window == nil {
            removeMonitor()
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard let window, event.window == window,
              event.hasPreciseScrollingDeltas else { return }

        let now = event.timestamp
        if now - lastScrollEventTime > gestureTimeout {
            resetGesture()
        }
        lastScrollEventTime = now

        switch event.phase {
        case .began:
            resetGesture()

        case .ended, .cancelled:
            return

        default:
            break
        }

        // Momentum scrolls can arrive after the primary gesture has already
        // switched tabs. Ignore them so one physical swipe moves exactly once.
        guard event.momentumPhase == [] else { return }

        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        guard deltaX != 0 || deltaY != 0 else { return }

        accumulatedDeltaX += deltaX
        accumulatedDeltaY += deltaY
        totalAbsDeltaX += abs(deltaX)
        totalAbsDeltaY += abs(deltaY)

        updateLockedAxis()
        guard !hasFired, lockedAxis != .vertical else { return }

        if lockedAxis == .horizontal,
           abs(accumulatedDeltaX) >= horizontalTriggerThreshold {
            hasFired = true
            let direction: SwipeDirection = accumulatedDeltaX < 0 ? .left : .right
            DispatchQueue.main.async { [weak self] in
                self?.onSwipe?(direction)
            }
        }
    }

    private func updateLockedAxis() {
        guard lockedAxis == .undecided else { return }

        if totalAbsDeltaX >= horizontalLockThreshold,
           totalAbsDeltaX > totalAbsDeltaY * horizontalDominanceRatio {
            lockedAxis = .horizontal
            return
        }

        if totalAbsDeltaY >= verticalLockThreshold,
           totalAbsDeltaY > totalAbsDeltaX * verticalDominanceRatio {
            lockedAxis = .vertical
        }
    }

    private func resetGesture() {
        accumulatedDeltaX = 0
        accumulatedDeltaY = 0
        totalAbsDeltaX = 0
        totalAbsDeltaY = 0
        lockedAxis = .undecided
        hasFired = false
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit {
        removeMonitor()
    }
}
