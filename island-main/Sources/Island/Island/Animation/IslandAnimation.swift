import SwiftUI

/// Single place for Island motion. Springs are interruptible: retargeting mid-flight preserves velocity,
/// so hovering in/out quickly never "restarts" the morph.
enum IslandAnimation {
    /// SwiftUI only animates *content* now (Core Animation owns the outline spring), so this is short.
    static func contentChange(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.24)
    }

    /// General morph (activity changes, resizes).
    static func morph(reduceMotion: Bool, speed: Double) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.18) }
        let s = max(0.5, min(2, speed))
        return .spring(response: 0.36 / s, dampingFraction: 0.84)
    }

    /// Opening: quick with a hint of overshoot, like the iPhone island.
    static func expand(reduceMotion: Bool, speed: Double) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.18) }
        return .spring(response: 0.34 / max(0.5, min(2, speed)), dampingFraction: 0.74)
    }

    /// Closing: crisp, no bounce, so the Island settles cleanly into the notch.
    static func collapse(reduceMotion: Bool, speed: Double) -> Animation {
        if reduceMotion { return .easeIn(duration: 0.16) }
        return .spring(response: 0.30 / max(0.5, min(2, speed)), dampingFraction: 0.95)
    }

    static func content(reduceMotion: Bool, speed: Double) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.15) }
        return .spring(response: 0.36 / max(0.5, min(2, speed)), dampingFraction: 0.9)
    }

    /// Insert/removal transition for content inside the morphing surface.
    ///
    /// It carries no animation of its own, so content moves on the *same* spring as the Island's outline.
    /// Opacity is phased on that shared progress: outgoing content is fully gone by the halfway point and
    /// incoming content only starts appearing after it, so compact and expanded never overlap. Content
    /// also sharpens from a light blur and grows from the top edge, like the iPhone island.
    static func contentTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        // Built-in, render-only effects (no per-frame body evaluation). Removal is quick, insertion waits
        // for it, so compact and expanded never overlap.
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                .animation(.easeOut(duration: 0.24).delay(0.1)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                .animation(.easeIn(duration: 0.08)))
    }
}

/// Animatable content-morph state; `progress` 0 = hidden, 1 = settled.
struct MorphContent: ViewModifier, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = min(1, max(0, progress))
        // Visible only in the second half of the shared spring.
        let opacity = max(0, (p - 0.5) / 0.5)
        content
            .opacity(opacity)
            .scaleEffect(0.9 + 0.1 * p, anchor: .top)
    }
}
