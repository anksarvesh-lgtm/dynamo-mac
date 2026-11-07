//
//  CompletionPanelStateTests.swift
//  ClaudeIslandTests
//
//  Reference tests for CompletionPanelState pure priority queue.
//  Note (2026-04-22): project has no XCTest target. This file compiles
//  only when a test target is wired up. Runtime authority is
//  scripts/test-completion-panel-state.swift.
//

import XCTest
@testable import ClaudeIsland

final class CompletionPanelStateTests: XCTestCase {
    private func claudeEntry(_ id: String, summary: String = "s") -> CompletionEntry {
        .init(stableId: id, projectName: "Proj", variant: .claudeStop(summary: summary))
    }
    private func subagentEntry(_ id: String) -> CompletionEntry {
        .init(stableId: id, projectName: "Proj", variant: .subagentDone(subagents: []))
    }
    private func pendingEntry(_ id: String, tool: String = "Bash") -> CompletionEntry {
        .init(stableId: id, projectName: "Proj", variant: .pendingTool(request: ToolApprovalRequest(toolName: tool, argumentsSummary: "x", riskLevel: .low)))
    }

    func testEmptyState() {
        let s = CompletionPanelState()
        XCTAssertNil(s.front); XCTAssertEqual(s.pendingCount, 0); XCTAssertEqual(s.totalQueued, 0)
    }
    func testSingleEnqueueBumpsTimer() {
        var s = CompletionPanelState(); let t = s.timerToken
        s.enqueue(claudeEntry("A"))
        XCTAssertEqual(s.front?.stableId, "A"); XCTAssertEqual(s.timerToken, t &+ 1)
    }
    func testSecondEnqueueReplacesOlderClaudeStop() {
        var s = CompletionPanelState(); s.enqueue(claudeEntry("A"))
        let t = s.timerToken; s.enqueue(claudeEntry("B"))
        XCTAssertEqual(s.front?.stableId, "B"); XCTAssertEqual(s.pendingCount, 0); XCTAssertEqual(s.timerToken, t &+ 1)
    }
    func testSameSessionUpdatePreservesId() {
        var s = CompletionPanelState(); s.enqueue(claudeEntry("A")); let id = s.front?.id; let t = s.timerToken
        s.enqueue(CompletionEntry(stableId: "A", projectName: "Proj", variant: .claudeStop(summary: "updated")))
        XCTAssertEqual(s.front?.id, id); XCTAssertEqual(s.timerToken, t)
        if case .claudeStop(let sum) = s.front!.variant { XCTAssertEqual(sum, "updated") } else { XCTFail() }
    }
    func testPreemptOldFrontToPending() {
        var s = CompletionPanelState(); s.enqueue(claudeEntry("A")); let t = s.timerToken
        s.enqueue(pendingEntry("B"))
        XCTAssertEqual(s.front?.stableId, "B"); XCTAssertEqual(s.pending.first?.stableId, "A"); XCTAssertEqual(s.timerToken, t &+ 1)
    }
    func testLowerPriorityGoesToPending() {
        var s = CompletionPanelState(); s.enqueue(pendingEntry("A")); let t = s.timerToken
        s.enqueue(subagentEntry("B"))
        XCTAssertEqual(s.front?.stableId, "A"); XCTAssertEqual(s.timerToken, t)
    }
    func testClaudeStopPreemptsOlderClaudeStopAcrossSessions() {
        var s = CompletionPanelState(); s.enqueue(claudeEntry("A")); let t = s.timerToken
        s.enqueue(claudeEntry("B"))
        XCTAssertEqual(s.front?.stableId, "B"); XCTAssertEqual(s.pendingCount, 0); XCTAssertEqual(s.timerToken, t &+ 1)
    }
    func testOnlyLatestClaudeStopRemainsPending() {
        var s = CompletionPanelState(); s.enqueue(pendingEntry("P"))
        s.enqueue(claudeEntry("A")); s.enqueue(claudeEntry("B")); s.enqueue(claudeEntry("C"))
        XCTAssertEqual(s.pending.map(\.stableId), ["C"])
    }
    func testNonClaudeStopsStillFIFOWithinSamePriorityBucket() {
        var s = CompletionPanelState(); s.enqueue(claudeEntry("A")); s.enqueue(claudeEntry("B")); s.enqueue(claudeEntry("C"))
        XCTAssertEqual(s.front?.stableId, "C")
    }
    func testPendingPriorityOrdering() {
        var s = CompletionPanelState(); s.enqueue(pendingEntry("X")); s.enqueue(subagentEntry("S")); s.enqueue(claudeEntry("C"))
        XCTAssertEqual(s.pending.map(\.stableId), ["C", "S"])
    }
    func testDismissPromotesHighestPriority() {
        var s = CompletionPanelState(); s.enqueue(claudeEntry("A")); s.enqueue(subagentEntry("S")); s.enqueue(pendingEntry("P"))
        let t = s.timerToken; s.dismissFront(stableId: "P")
        XCTAssertEqual(s.front?.stableId, "A"); XCTAssertEqual(s.pending.first?.stableId, "S"); XCTAssertEqual(s.timerToken, t &+ 1)
    }
    func testDismissLastClearsFront() {
        var s = CompletionPanelState(); s.enqueue(claudeEntry("A")); let t = s.timerToken
        s.dismissFront(stableId: "A"); XCTAssertNil(s.front); XCTAssertEqual(s.timerToken, t)
    }
    func testDismissWrongIdIsNoOp() {
        var s = CompletionPanelState(); s.enqueue(claudeEntry("A")); let t = s.timerToken
        s.dismissFront(stableId: "Z"); XCTAssertEqual(s.front?.stableId, "A"); XCTAssertEqual(s.timerToken, t)
    }
    func testRecordSendFailureSetsError() {
        var s = CompletionPanelState(); s.enqueue(claudeEntry("A")); let t = s.timerToken
        s.recordSendFailure(stableId: "A", message: "fail")
        XCTAssertEqual(s.sendError?.stableId, "A"); XCTAssertEqual(s.timerToken, t)
    }
    func testRecordSendFailureWrongIdNoOp() {
        var s = CompletionPanelState(); s.enqueue(claudeEntry("A")); s.recordSendFailure(stableId: "A", message: "x")
        s.recordSendFailure(stableId: "Z", message: "y"); XCTAssertEqual(s.sendError?.message, "x")
    }
    func testDismissClearsSendError() {
        var s = CompletionPanelState(); s.enqueue(claudeEntry("A")); s.recordSendFailure(stableId: "A", message: "x")
        s.dismissFront(stableId: "A"); XCTAssertNil(s.sendError)
    }
    func testFlushDisabledClearsAll() {
        var s = CompletionPanelState(); s.enqueue(claudeEntry("A")); s.enqueue(claudeEntry("B"))
        s.recordSendFailure(stableId: "A", message: "x"); s.flush(enabled: false)
        XCTAssertNil(s.front); XCTAssertEqual(s.pendingCount, 0); XCTAssertNil(s.sendError)
    }
    func testFlushEnabledPreservesState() {
        var s = CompletionPanelState(); s.enqueue(claudeEntry("A")); s.flush(enabled: true)
        XCTAssertEqual(s.front?.stableId, "A")
    }
    func testSyncDropsDeadFrontAndPending() {
        var s = CompletionPanelState(); s.enqueue(pendingEntry("P")); s.enqueue(claudeEntry("A")); s.enqueue(claudeEntry("B"))
        s.syncWithCurrentWaiting(["B"]); XCTAssertEqual(s.front?.stableId, "B"); XCTAssertEqual(s.pendingCount, 0)
    }
    func testSyncDropsEntriesRejectedByRetainPredicate() {
        var s = CompletionPanelState(); s.enqueue(pendingEntry("P")); s.enqueue(claudeEntry("B")); s.enqueue(subagentEntry("S"))
        s.syncWithCurrentWaiting(["P", "B", "S"], shouldRetain: { $0.stableId == "B" })
        XCTAssertEqual(s.front?.stableId, "B"); XCTAssertEqual(s.pendingCount, 0)
    }
    func testSyncEmptyClearsAll() {
        var s = CompletionPanelState(); s.enqueue(claudeEntry("A")); s.enqueue(claudeEntry("B"))
        s.syncWithCurrentWaiting([]); XCTAssertNil(s.front); XCTAssertEqual(s.pendingCount, 0)
    }
    func testDedupInPending() {
        var s = CompletionPanelState(); s.enqueue(pendingEntry("P"))
        s.enqueue(claudeEntry("B", summary: "old")); s.enqueue(claudeEntry("B", summary: "new"))
        XCTAssertEqual(s.pendingCount, 1)
        if case .claudeStop(let sum) = s.pending.first!.variant { XCTAssertEqual(sum, "new") } else { XCTFail() }
    }
    func testVariantPriorityOrdering() {
        XCTAssertEqual(PanelVariant.pendingTool(request: .init(toolName:"x", argumentsSummary:"", riskLevel:.low)).priority, 30)
        XCTAssertEqual(PanelVariant.claudeStop(summary: "").priority, 20)
        XCTAssertEqual(PanelVariant.subagentDone(subagents: []).priority, 10)
    }
    func testVariantIsSticky() {
        XCTAssertTrue(PanelVariant.subagentDone(subagents: []).isSticky)
        XCTAssertFalse(PanelVariant.claudeStop(summary: "").isSticky)
        XCTAssertFalse(PanelVariant.pendingTool(request: .init(toolName:"x", argumentsSummary:"", riskLevel:.low)).isSticky)
    }
}
