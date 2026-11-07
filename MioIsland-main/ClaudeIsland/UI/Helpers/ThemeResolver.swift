//
//  ThemeResolver.swift
//  ClaudeIsland
//
//  Centralized semantic theme access for SwiftUI surfaces.
//

import SwiftUI

struct ThemeResolver {
    let theme: NotchThemeID
    let tokens: ThemeTokens

    init(theme: NotchThemeID) {
        self.theme = theme
        self.tokens = ThemeTokens.for(theme)
    }

    var background: Color { tokens.chrome.background.color }
    var overlay: Color { tokens.chrome.overlay.color }
    var border: Color { tokens.chrome.border.color }

    var primaryText: Color { tokens.text.primary.color }
    var secondaryText: Color { tokens.text.secondary.color }
    var mutedText: Color { tokens.text.muted.color }
    var inverseText: Color { tokens.text.inverse.color }

    var idleColor: Color { tokens.status.idle.color }
    var workingColor: Color { tokens.status.working.color }
    var needsYouColor: Color { tokens.status.needsYou.color }
    var errorColor: Color { tokens.status.error.color }
    var doneColor: Color { tokens.status.done.color }
    var thinkingColor: Color { tokens.status.thinking.color }

    var agentBadgeText: Color { tokens.badges.agentText.color }
    var agentBadgeFill: Color { tokens.badges.agentFill.color }
    var terminalBadgeText: Color { tokens.badges.terminalText.color }
    var terminalBadgeFill: Color { tokens.badges.terminalFill.color }
    var subduedBadgeText: Color { tokens.badges.subduedText.color }
    var subduedBadgeFill: Color { tokens.badges.subduedFill.color }

    var usageText: Color { tokens.usage.text.color }
    var usageTrack: Color { tokens.usage.track.color }
    var usageFill: Color { tokens.usage.fill.color }
    var usageBorder: Color { tokens.usage.border.color }

    var chatBodyText: Color { tokens.chat.bodyText.color }
    var chatSecondaryText: Color { tokens.chat.secondaryText.color }
    var chatBubbleText: Color { tokens.chat.bubbleText.color }
    var chatBubbleFill: Color { tokens.chat.bubbleFill.color }
    var assistantDot: Color { tokens.chat.assistantDot.color }

    var isRetroArcade: Bool { theme == .retroArcade }
}
