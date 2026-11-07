// SPDX-License-Identifier: MIT
import Observation

/// What the surface sees at the moment a hover deadline fires.
public struct PointerCheck: Sendable {
    /// The cursor is over the notch right now.
    public var isInside: Bool
    /// A mouse button is held: a drag or a resize is in progress.
    public var isButtonDown: Bool

    public init(isInside: Bool, isButtonDown: Bool) {
        self.isInside = isInside
        self.isButtonDown = isButtonDown
    }
}

/// Runs one display's notch on the main actor: feeds events through the reducer and runs its
/// deadline effects on cancellable one-shot timers (never a polling loop).
@MainActor
@Observable
public final class NotchEngine {
    public private(set) var state = NotchState()

    /// Called after every presentation change, for example to update the panel and the features.
    @ObservationIgnored
    public var onPresentationChange: ((_ old: NotchPresentationState, _ new: NotchPresentationState) -> Void)?

    /// Asked when a hover deadline fires. Tracking-area events can go missing or arrive spuriously
    /// while views update, so the surface answers from the real cursor position.
    @ObservationIgnored public var pointerCheck: (() -> PointerCheck)?

    @ObservationIgnored private var timers: [Deadline: Task<Void, Never>] = [:]

    public init() {}

    public func send(_ event: NotchEvent) {
        let signpostID = Log.signposter.makeSignpostID()
        let interval = Log.signposter.beginInterval(
            "event", id: signpostID, "\(String(describing: event), privacy: .public)")
        defer { Log.signposter.endInterval("event", interval) }

        // A deadline event consumes its timer, whether the timer fired or a test injected it.
        if case .deadline(let deadline) = event { timers.removeValue(forKey: deadline)?.cancel() }

        let old = state
        var new = old
        let effects = new.handle(event)
        if new != old { state = new }
        if new.presentation != old.presentation {
            Log.state.debug(
                "\(String(describing: event), privacy: .public): \(String(describing: old.presentation), privacy: .public) → \(String(describing: new.presentation), privacy: .public)"
            )
            onPresentationChange?(old.presentation, new.presentation)
        }
        for effect in effects { run(effect) }
    }

    /// Deadlines with a live timer.
    var pendingDeadlines: Set<Deadline> { Set(timers.keys) }

    /// A timer fired. Hover deadlines check the real pointer first: a missed "entered" can't
    /// collapse a notch the pointer is on, a stray one can't open a notch it isn't on, and nothing
    /// collapses while a mouse button is held.
    func fire(_ deadline: Deadline) {
        timers.removeValue(forKey: deadline)?.cancel()
        if let check = pointerCheck?() {
            switch deadline {
            case .collapseGrace where check.isInside: return send(.pointerEntered)
            case .collapseGrace where check.isButtonDown: return send(.pointerExited)  // look again later
            case .hoverDwell where !check.isInside: return send(.pointerExited)
            default: break
            }
        }
        send(.deadline(deadline))
    }

    private func run(_ effect: NotchEffect) {
        switch effect {
        case .schedule(let deadline, let delay):
            timers[deadline]?.cancel()
            // Sleep off the main actor so a cancelled timer never wakes the main thread; only a timer
            // that fires hops back. Tolerance lets macOS coalesce the wakeup (Apple's energy guidance).
            timers[deadline] = Task.detached { [weak self] in
                do { try await Task.sleep(for: delay, tolerance: delay / 10) } catch { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self?.fire(deadline)
                }
            }
        case .cancel(let deadline):
            timers.removeValue(forKey: deadline)?.cancel()
        }
    }
}
