// SPDX-License-Identifier: MIT
import XCTest

@testable import NotchCore

/// A feature module that does no work, so the measurements cover only the engine.
@MainActor
private final class IdleFeature: NotchFeature {
    let id: FeatureID
    var phase: FeaturePhase = .stopped

    init(_ id: FeatureID) { self.id = id }
}

/// Performance baselines for the core. The plan's budgets are checked with Instruments on a
/// reference Mac; these keep regressions visible on every test run.
final class NotchEnginePerformanceTests: XCTestCase {
    /// 1,000 hover open/close cycles through the engine and feature host: reducer, feature lifecycle,
    /// timers, and signposts. Each run must end compact with no timer left behind (the Phase 2 exit).
    @MainActor
    func testThousandHoverCycles() {
        // Signpost intervals are measured in Instruments: XCTOSSignpostMetric takes minutes per run.
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let host = FeatureHost(FeatureID.allCases.map(IdleFeature.init))
            let engine = NotchEngine()
            engine.onPresentationChange = { _, new in
                host.update(presentations: [new], enabled: Set(FeatureID.allCases))
            }
            engine.send(.show)
            for _ in 0..<1_000 {
                engine.send(.pointerEntered)
                engine.send(.deadline(.hoverDwell))
                engine.send(.pointerExited)
                engine.send(.deadline(.collapseGrace))
            }
            XCTAssertEqual(engine.state.presentation, .compact)
            XCTAssertTrue(engine.pendingDeadlines.isEmpty)
        }
    }
}
