// SPDX-License-Identifier: MIT
// Adapted from OpenUsage (https://github.com/robinebers/openusage) at 4ce7887.
// Copyright (c) Robin Ebers and contributors. MIT License; see THIRD_PARTY_NOTICES.md.
// swift-format-ignore-file

import Foundation

/// Whether a provider's daily spend history may be added across Macs. Every provider with shared
/// spend tiles declares this explicitly so a future account-wide source cannot silently double-count.
struct UsageHistoryDescriptor: Hashable, Sendable {
    enum Scope: String, Hashable, Sendable {
        case machineLocal
        case accountWide
    }

    let scope: Scope
    let estimatedCost: Bool
    let sourceNote: String
}

extension WidgetDescriptor {
    /// Classifies the provider's normalized daily history beside its other machine-facing exports.
    func exportingHistory(
        scope: UsageHistoryDescriptor.Scope,
        estimatedCost: Bool,
        sourceNote: String
    ) -> WidgetDescriptor {
        var copy = self
        copy.historyResource = UsageHistoryDescriptor(
            scope: scope,
            estimatedCost: estimatedCost,
            sourceNote: sourceNote
        )
        return copy
    }
}
