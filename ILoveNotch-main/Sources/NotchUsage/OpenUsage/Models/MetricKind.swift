// SPDX-License-Identifier: MIT
// Adapted from OpenUsage (https://github.com/robinebers/openusage) at 4ce7887.
// Copyright (c) Robin Ebers and contributors. MIT License; see THIRD_PARTY_NOTICES.md.
// swift-format-ignore-file

import Foundation

/// How a metric's number is formatted. Mirrors OpenUsage's `format.kind`.
///
/// `String`-backed and `Codable` so it can ride on a `MetricValue` carried inside a cached
/// `MetricLine` (see `MetricValue`).
enum MetricKind: String, Hashable, Sendable, Codable {
    case percent      // used is 0...100
    case dollars      // used is an amount in USD
    case count        // used is an absolute count (with an optional suffix)
}
