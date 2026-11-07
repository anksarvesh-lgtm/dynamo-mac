// SPDX-License-Identifier: MIT
// Adapted from OpenUsage (https://github.com/robinebers/openusage) at 4ce7887.
// Copyright (c) Robin Ebers and contributors. MIT License; see THIRD_PARTY_NOTICES.md.
// swift-format-ignore-file

import Foundation

/// Global choice for how reset countdowns read across every bounded row: a relative duration
/// ("Resets in 4d 17h") or a concrete wall-clock time ("Resets tomorrow at 9:00 AM"). Ported from the
/// original OpenUsage's `resetTimerDisplayMode` setting; toggled by clicking any reset label.
/// The labels avoid relative/absolute jargon: they're what each mode looks like.
enum ResetDisplayMode: String, Hashable, Sendable, CaseIterable {
    case relative
    case absolute

    var label: String {
        switch self {
        case .relative: return "Countdown"
        case .absolute: return "Exact Time"
        }
    }

    mutating func toggle() {
        self = self == .relative ? .absolute : .relative
    }
}
