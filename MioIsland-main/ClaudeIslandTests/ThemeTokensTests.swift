import XCTest
@testable import ClaudeIsland

final class ThemeTokensTests: XCTestCase {

    func test_retroArcadeUsesLayeredGreenBlocksWithBlackText() {
        let tokens = ThemeTokens.for(.retroArcade)

        XCTAssertEqual(tokens.chrome.background, ThemeColorToken(hex: "10B981"))
        XCTAssertEqual(tokens.chrome.overlay, ThemeColorToken(hex: "6EE7B7"))
        XCTAssertEqual(tokens.chrome.border, ThemeColorToken(hex: "065F46"))

        XCTAssertEqual(tokens.text.primary, .black)
        XCTAssertEqual(tokens.text.secondary, .black)
        XCTAssertEqual(tokens.text.muted, .black)

        XCTAssertEqual(tokens.badges.agentFill, ThemeColorToken(hex: "A7F3D0"))
        XCTAssertEqual(tokens.badges.terminalFill, ThemeColorToken(hex: "6EE7B7"))
        XCTAssertEqual(tokens.badges.subduedFill, ThemeColorToken(hex: "86EFAC"))

        XCTAssertEqual(tokens.usage.track, ThemeColorToken(hex: "A7F3D0"))
        XCTAssertEqual(tokens.usage.fill, ThemeColorToken(hex: "064E3B"))
        XCTAssertEqual(tokens.chat.bubbleFill, ThemeColorToken(hex: "A7F3D0"))
    }

    func test_paletteCompatibilityStillMatchesThemeTokens() {
        let palette = NotchPalette.for(.retroArcade)
        let tokens = ThemeTokens.for(.retroArcade)

        XCTAssertEqual(palette.bg, tokens.chrome.background.color)
        XCTAssertEqual(palette.fg, tokens.text.primary.color)
        XCTAssertEqual(palette.secondaryFg, tokens.text.secondary.color)
        XCTAssertEqual(palette.accent, tokens.status.idle.color)
    }

    func test_neonTokyoUsesCyberpunkPalette() {
        let tokens = ThemeTokens.for(.neonTokyo)

        XCTAssertEqual(tokens.chrome.background, ThemeColorToken(hex: "070B1A"))
        XCTAssertEqual(tokens.status.idle, ThemeColorToken(hex: "FF2FAE"))
        XCTAssertEqual(tokens.status.working, ThemeColorToken(hex: "00E5FF"))
        XCTAssertEqual(tokens.status.done, ThemeColorToken(hex: "C084FC"))
        XCTAssertEqual(tokens.badges.agentFill, ThemeColorToken(hex: "2A1144"))
        XCTAssertEqual(tokens.chat.assistantDot, ThemeColorToken(hex: "00E5FF"))
    }

    func test_sakuraUsesSoftPinkPalette() {
        let tokens = ThemeTokens.for(.sakura)

        XCTAssertEqual(tokens.chrome.background, ThemeColorToken(hex: "FFF4FB"))
        XCTAssertEqual(tokens.chrome.overlay, ThemeColorToken(hex: "FFE3F2"))
        XCTAssertEqual(tokens.text.primary, ThemeColorToken(hex: "7A3558"))
        XCTAssertEqual(tokens.status.idle, ThemeColorToken(hex: "F472B6"))
        XCTAssertEqual(tokens.status.done, ThemeColorToken(hex: "EC4899"))
        XCTAssertEqual(tokens.chat.bubbleFill, ThemeColorToken(hex: "FFF0F8"))
    }
}
