//
//  NotchFontModifier.swift
//  ClaudeIsland
//
//  Relative-scale font helper for notch text. Multiplies a base
//  point size by the current FontScale multiplier (0.85 / 1.0 /
//  1.15 / 1.3) so user preference flows through to every call site
//  via the observed store. Matches the existing
//  `.font(.system(size: N, weight:, design:))` API surface for
//  drop-in replacement.
//
//  Spec: docs/superpowers/specs/2026-04-08-notch-customization-design.md
//  section 5.4.
//

import SwiftUI

struct NotchFontModifier: ViewModifier {
    @ObservedObject var store: NotchCustomizationStore = .shared
    let baseSize: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(
            .system(
                size: baseSize * store.customization.fontScale.multiplier,
                weight: weight,
                design: design
            )
        )
    }
}

extension View {
    /// Replacement for `.font(.system(size: baseSize, weight:, design:))`
    /// that respects the user's `FontScale` setting. Default weight is
    /// `.medium` and default design is `.monospaced` to match the
    /// existing notch typography.
    func notchFont(
        _ baseSize: CGFloat,
        weight: Font.Weight = .medium,
        design: Font.Design = .monospaced
    ) -> some View {
        modifier(NotchFontModifier(baseSize: baseSize, weight: weight, design: design))
    }
}
