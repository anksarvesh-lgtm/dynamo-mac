// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// How the Usage tab draws a provider: its mark from theSVG, tinted to sit on the black notch, and
/// an accent gradient for its rings and meters. The accents are OpenNotch's picks: near each brand's
/// color where it has one, and distinct from each other where the brand is plain black or white.
struct ProviderStyle {
    let start: Color
    let end: Color

    var gradient: LinearGradient { LinearGradient(colors: [start, end], startPoint: .leading, endPoint: .trailing) }

    static func of(_ providerID: String) -> ProviderStyle {
        let (start, end): (UInt32, UInt32) =
            switch providerID {
            case "claude": (0xD977_57, 0xF4A2_61)
            case "codex": (0x10A3_7F, 0x5CE0_B8)
            case "cursor": (0x22D3_EE, 0x93C5_FD)
            case "copilot": (0x8B5C_F6, 0xC084_FC)
            case "antigravity": (0x4285_F4, 0x8AB4_F8)
            case "devin": (0x14B8_A6, 0x5EEA_D4)
            case "grok": (0xA1A1_AA, 0xF4F4_F5)
            case "ollama": (0xD6D3_D1, 0xFAFA_F9)
            case "opencode": (0xEC48_99, 0xF9A8_D4)
            case "openrouter": (0x6366_F1, 0xA5B4_FC)
            case "zai": (0x3859_FF, 0x8B9C_FF)
            default: (0x9CA3_AF, 0xE5E7_EB)
            }
        return ProviderStyle(start: Color(hex: start), end: Color(hex: end))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

/// A provider's mark, or its initial when theSVG has no mark for it (Devin).
struct ProviderLogo: View {
    let providerID: String
    let name: String
    var size: CGFloat = 16

    var body: some View {
        if let image = Self.image(for: providerID) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Text(name.prefix(1))
                .font(.system(size: size * 0.7, weight: .bold, design: .rounded))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    /// Marks load once from the module's `Logos` folder; macOS draws SVG natively.
    @MainActor private static var images: [String: NSImage?] = [:]

    @MainActor private static func image(for providerID: String) -> NSImage? {
        if let cached = images[providerID] { return cached }
        let image = Bundle.openUsageResources.url(forResource: providerID, withExtension: "svg", subdirectory: "Logos")
            .flatMap(NSImage.init(contentsOf:))
        image?.isTemplate = true
        images[providerID] = image
        return image
    }
}
