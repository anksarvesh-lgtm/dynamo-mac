// SPDX-License-Identifier: MIT
// Adapted from OpenUsage (https://github.com/robinebers/openusage) at 4ce7887.
// Copyright (c) Robin Ebers and contributors. MIT License; see THIRD_PARTY_NOTICES.md.
// swift-format-ignore-file

import Foundation
import Testing
@testable import NotchUsage

struct OpenUsageISO8601Tests {
    @Test func parsesZuluISO() {
        let date = OpenUsageISO8601.date(from: "2099-01-01T00:00:00.000Z")
        #expect(date != nil)
    }

    @Test func normalizesMicrosecondsWithoutTimezoneLikeClaudeAPI() {
        let date = OpenUsageISO8601.date(from: "2099-01-01T00:00:00.123456")
        #expect(date != nil)
        #expect(OpenUsageISO8601.string(from: date!) == "2099-01-01T00:00:00.123Z")
    }

    @Test func normalizesSpaceSeparatedUTC() {
        let date = OpenUsageISO8601.date(from: "2099-01-01 00:00:00 UTC")
        #expect(date != nil)
    }
}
