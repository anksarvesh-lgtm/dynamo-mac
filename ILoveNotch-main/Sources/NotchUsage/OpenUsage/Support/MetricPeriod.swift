// SPDX-License-Identifier: MIT
// Adapted from OpenUsage (https://github.com/robinebers/openusage) at 4ce7887.
// Copyright (c) Robin Ebers and contributors. MIT License; see THIRD_PARTY_NOTICES.md.
// swift-format-ignore-file

import Foundation

/// Canonical usage-window lengths in milliseconds, defined once and shared by the providers so the
/// same window (5h session, 1 day, 7 days, 30-day billing cycle) isn't re-spelled as a magic number
/// in each mapper.
enum MetricPeriod {
    static let sessionMs = 5 * 60 * 60 * 1000
    static let dayMs = 24 * 60 * 60 * 1000
    static let weekMs = 7 * dayMs
    static let monthMs = 30 * dayMs
}
