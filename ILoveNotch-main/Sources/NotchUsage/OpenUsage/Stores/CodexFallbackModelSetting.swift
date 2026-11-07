// SPDX-License-Identifier: MIT
// Adapted from OpenUsage (https://github.com/robinebers/openusage) at 4ce7887.
// Copyright (c) Robin Ebers and contributors. MIT License; see THIRD_PARTY_NOTICES.md.
// swift-format-ignore-file

import Foundation

enum CodexFallbackModelSetting {
    static let key = "openusage.codex.fallbackModel"
    static let none = ""

    static func current(defaults: UserDefaults = .standard) -> String? {
        let value = defaults.string(forKey: key) ?? none
        return value.isEmpty ? nil : value
    }
}

/// Recalculate for a changed choice or availability, including a saved choice when settings open.
struct CodexFallbackPricingRefreshState {
    private var previous: Selection?

    mutating func update(model: String, options: [PricingFallbackOption]) -> Bool {
        let selection = Selection(model: model, available: options.contains { $0.id == model })
        defer { previous = selection }
        return previous != selection && (previous != nil || !model.isEmpty)
    }

    private struct Selection: Equatable {
        let model: String
        let available: Bool
    }
}
