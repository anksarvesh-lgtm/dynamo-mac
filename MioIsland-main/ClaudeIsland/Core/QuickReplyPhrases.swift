//
//  QuickReplyPhrases.swift
//  ClaudeIsland
//
//  User-editable list of short reply phrases shown on the Claude Stop
//  variant of the Completion Panel. Invariants: ≥ 1 and ≤ 6 entries.
//  Spec §5.6 (Variant A) + §5.8 (Settings phrases editor).
//

import Foundation

struct QuickReplyPhrase: Codable, Equatable, Identifiable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

enum QuickReplyPhrases {
    static let minCount = 1
    static let maxCount = 6

    private static let key = "quickReplyPhrases.v1"

    static var factoryDefaults: [QuickReplyPhrase] {
        [
            QuickReplyPhrase(text: L10n.qrPhraseContinue),
            QuickReplyPhrase(text: L10n.qrPhraseOK),
            QuickReplyPhrase(text: L10n.qrPhraseExplain),
            QuickReplyPhrase(text: L10n.qrPhraseRetry)
        ]
    }

    /// Enforce spec §5.8 invariants: ≥1 ≤6. Pure; no UserDefaults access.
    static func clamp(_ phrases: [QuickReplyPhrase]) -> [QuickReplyPhrase] {
        var out = phrases
        if out.count > maxCount { out = Array(out.prefix(maxCount)) }
        if out.isEmpty { out = factoryDefaults }
        return out
    }

    static var current: [QuickReplyPhrase] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([QuickReplyPhrase].self, from: data),
                  !decoded.isEmpty else {
                return factoryDefaults
            }
            return decoded
        }
        set {
            let clamped = clamp(newValue)
            if let data = try? JSONEncoder().encode(clamped) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
