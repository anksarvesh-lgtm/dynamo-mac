//
//  ThemeTokens.swift
//  ClaudeIsland
//
//  Semantic theme tokens used by notch, sessions list, chat surfaces,
//  and future plugin-provided themes.
//

import SwiftUI

struct ThemeColorToken: Equatable, Codable {
    let hex: String

    init(hex: String) {
        self.hex = hex.uppercased()
    }

    var color: Color { Color(hex: hex) }

    static let black = ThemeColorToken(hex: "000000")
    static let white = ThemeColorToken(hex: "FFFFFF")
}

struct ThemeChromeTokens: Equatable, Codable {
    let background: ThemeColorToken
    let overlay: ThemeColorToken
    let border: ThemeColorToken
}

struct ThemeTextTokens: Equatable, Codable {
    let primary: ThemeColorToken
    let secondary: ThemeColorToken
    let muted: ThemeColorToken
    let inverse: ThemeColorToken
}

struct ThemeStatusTokens: Equatable, Codable {
    let idle: ThemeColorToken
    let working: ThemeColorToken
    let needsYou: ThemeColorToken
    let error: ThemeColorToken
    let done: ThemeColorToken
    let thinking: ThemeColorToken
}

struct ThemeBadgeTokens: Equatable, Codable {
    let agentText: ThemeColorToken
    let agentFill: ThemeColorToken
    let terminalText: ThemeColorToken
    let terminalFill: ThemeColorToken
    let subduedText: ThemeColorToken
    let subduedFill: ThemeColorToken
}

struct ThemeUsageTokens: Equatable, Codable {
    let text: ThemeColorToken
    let track: ThemeColorToken
    let fill: ThemeColorToken
    let border: ThemeColorToken
}

struct ThemeChatTokens: Equatable, Codable {
    let bodyText: ThemeColorToken
    let secondaryText: ThemeColorToken
    let bubbleText: ThemeColorToken
    let bubbleFill: ThemeColorToken
    let assistantDot: ThemeColorToken
}

struct ThemeTokens: Equatable, Codable {
    let chrome: ThemeChromeTokens
    let text: ThemeTextTokens
    let status: ThemeStatusTokens
    let badges: ThemeBadgeTokens
    let usage: ThemeUsageTokens
    let chat: ThemeChatTokens
}

extension ThemeTokens {
    static func `for`(_ id: NotchThemeID) -> ThemeTokens {
        ThemeRegistry.shared.descriptor(for: id).tokens
    }
}
