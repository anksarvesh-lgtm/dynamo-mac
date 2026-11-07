// SPDX-License-Identifier: MIT
// Adapted from OpenUsage (https://github.com/robinebers/openusage) at 4ce7887.
// Copyright (c) Robin Ebers and contributors. MIT License; see THIRD_PARTY_NOTICES.md.
// swift-format-ignore-file

import Foundation

enum WidgetDisplayMode: String, Hashable, Sendable, CaseIterable {
    case used
    case remaining

    /// "Left" mirrors the legacy app's wording for remaining headroom.
    var label: String {
        switch self {
        case .used: return "Used"
        case .remaining: return "Left"
        }
    }

    mutating func toggle() {
        self = self == .used ? .remaining : .used
    }
}
