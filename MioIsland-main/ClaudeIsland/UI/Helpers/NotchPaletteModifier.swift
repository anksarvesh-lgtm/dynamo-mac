//
//  NotchPaletteModifier.swift
//  ClaudeIsland
//
//  Root-level and call-site view modifiers for applying the notch
//  palette with a properly scoped 0.3s color crossfade on theme
//  change. Using `.animation(_:value:)` scoped to the color-bearing
//  modifiers means theme transitions do not stack on top of the
//  width spring and never retrigger geometry animations.
//
//  Spec: docs/superpowers/specs/2026-04-08-notch-customization-design.md
//  section 4.4.
//
//  Deviation from spec: the spec describes
//  `@EnvironmentObject var store`. Because the CodeIsland notch
//  uses an imperatively-created `NSHostingView<NotchView>` with a
//  strictly-typed generic, adding `.environmentObject(_:)` would
//  change the generic type of the root view and break the
//  `PassThroughHostingView<NotchView>` declaration. As a pragmatic
//  alternative we observe `NotchCustomizationStore.shared`
//  directly via `@ObservedObject`; the MainActor singleton shape
//  makes this equivalent for runtime behavior.
//

import SwiftUI

struct NotchPaletteModifier: ViewModifier {
    @ObservedObject var store: NotchCustomizationStore = .shared

    func body(content: Content) -> some View {
        let theme = ThemeResolver(theme: store.customization.theme)
        content
            .foregroundStyle(theme.primaryText)
            .background(theme.background)
            .animation(.easeInOut(duration: 0.3), value: store.customization.theme)
    }
}

struct NotchSecondaryForegroundModifier: ViewModifier {
    @ObservedObject var store: NotchCustomizationStore = .shared

    func body(content: Content) -> some View {
        let theme = ThemeResolver(theme: store.customization.theme)
        content
            .foregroundStyle(theme.secondaryText)
            .animation(.easeInOut(duration: 0.3), value: store.customization.theme)
    }
}

extension View {
    /// Apply the base foreground / background palette at the
    /// NotchView root. Animates across 0.3s on theme change.
    func notchPalette() -> some View { modifier(NotchPaletteModifier()) }

    /// Apply the dimmer secondary foreground color to child views
    /// such as timestamps or percentage indicators. Inherits the
    /// same 0.3s theme crossfade.
    func notchSecondaryForeground() -> some View {
        modifier(NotchSecondaryForegroundModifier())
    }
}
