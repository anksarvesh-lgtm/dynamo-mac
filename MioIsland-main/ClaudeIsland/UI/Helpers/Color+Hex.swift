//
//  Color+Hex.swift
//  ClaudeIsland
//
//  Hex-string Color initializer. Originally defined inside
//  BuddyReader.swift; lifted here so palette code elsewhere in the
//  app can use it without importing BuddyReader. Behavior is
//  identical to the original 6-character-hex implementation — no
//  API or behavior change.
//

import SwiftUI

extension Color {
    /// Create a `Color` from a 6-character hex string, e.g.
    /// `Color(hex: "CAFF00")`. Any non-alphanumeric characters are
    /// stripped so a leading `#` is tolerated. Strings that are not
    /// exactly 6 hex characters fall back to opaque white to match
    /// the legacy behavior.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }
}
