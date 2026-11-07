//
//  NotchTheme.swift
//  ClaudeIsland
//
//  Palette definitions for the built-in notch themes. Palette
//  colors drive the notch background, primary foreground (text,
//  icons), and the dimmer secondary foreground (timestamps,
//  percentage indicators). Status colors (success / warning / error)
//  are intentionally NOT part of the palette — they preserve
//  semantic meaning across themes and live in Assets.xcassets
//  under NotchStatus/.
//
//  v2 line-up (2026-04-20): Classic + six themes designed via
//  Claude Design (see /tmp/codeisland-themes/island/project/themes.jsx
//  for the full spec including per-state dots, corner SVGs, and
//  custom fonts — not all of which the NotchPalette 3-field shape
//  expresses today). The 3 fields below ARE the safe subset that
//  every call site already consumes.
//

import SwiftUI

struct NotchPalette: Equatable {
    let bg: Color
    let fg: Color
    let secondaryFg: Color
    /// Signature tint for idle-state dots, buddy highlights, and theme
    /// preview swatches. NOT used for semantic status (red/amber/green for
    /// error/attention/success) — those stay universal across themes.
    let accent: Color
}

extension NotchPalette {
    /// Lookup the palette for a given theme ID. All cases are
    /// defined inline so adding a theme means touching exactly one
    /// switch statement.
    static func `for`(_ id: NotchThemeID) -> NotchPalette {
        let tokens = ThemeTokens.for(id)
        return NotchPalette(
            bg: tokens.chrome.background.color,
            fg: tokens.text.primary.color,
            secondaryFg: tokens.text.secondary.color,
            accent: tokens.status.idle.color
        )
    }
}

extension NotchThemeID {
    /// Human-readable English display name for the theme picker.
    /// Localized display names are resolved separately in the
    /// settings view so this file does not depend on L10n.
    var displayName: String {
        ThemeRegistry.shared.displayName(for: self)
    }
}
