#!/usr/bin/env swift
import Foundation

struct QuickReplyPhrase: Codable, Equatable, Identifiable {
    let id: UUID; var text: String
    init(id: UUID = UUID(), text: String) { self.id = id; self.text = text }
}
enum QuickReplyPhrases {
    static let minCount = 1, maxCount = 6
    static let factoryDefaults: [QuickReplyPhrase] = [
        .init(text: "Continue"), .init(text: "OK"),
        .init(text: "Explain more"), .init(text: "Retry")
    ]
    static func clamp(_ phrases: [QuickReplyPhrase]) -> [QuickReplyPhrase] {
        var out = phrases
        if out.count > maxCount { out = Array(out.prefix(maxCount)) }
        if out.isEmpty { out = factoryDefaults }
        return out
    }
}

var passed = 0, failed = 0
func check(_ cond: @autoclosure () -> Bool, _ desc: String, line: UInt = #line) {
    if cond() { passed += 1; print("  ✓ \(desc)") }
    else { failed += 1; print("  ✗ \(desc) (line \(line))") }
}
func p(_ s: String) -> QuickReplyPhrase { .init(text: s) }

check(QuickReplyPhrases.clamp([]).count == 4, "empty → factoryDefaults (4)")
check(QuickReplyPhrases.clamp([p("a")]).count == 1, "1 phrase stays 1")
check(QuickReplyPhrases.clamp([p("a"), p("b"), p("c"), p("d"), p("e"), p("f")]).count == 6, "6 stays 6")
check(QuickReplyPhrases.clamp([p("a"), p("b"), p("c"), p("d"), p("e"), p("f"), p("g")]).count == 6, "7 trimmed to 6")
check(QuickReplyPhrases.clamp((1...10).map { p("p\($0)") }).count == 6, "10 trimmed to 6")

let huge = (1...10).map { p("p\($0)") }
let trimmed = QuickReplyPhrases.clamp(huge)
check(trimmed.first?.text == "p1", "first kept on trim")
check(trimmed.last?.text == "p6", "prefix kept on trim")

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
