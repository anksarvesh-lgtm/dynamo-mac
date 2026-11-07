import Testing

@testable import LedgeSystem

@Suite("Brightness polling")
struct BrightnessControllerTests {

    @Test("Failed reads spend the fast-poll budget")
    func failedReadsReturnToIdle() {
        var polling = BrightnessPollingState()
        polling.reset(level: 0.5)

        let change = polling.observe(0.6, manualStep: 0.045)
        #expect(change == .init(cadence: .active, levelToPublish: 0.6))

        for _ in 1..<BrightnessPollingState.quickPollCount {
            #expect(polling.observe(nil, manualStep: 0.045).cadence == nil)
        }
        #expect(polling.observe(nil, manualStep: 0.045).cadence == .idle)
        #expect(polling.quickPollsRemaining == 0)
    }

    @Test("Valid readings adapt between fast and idle polling")
    func validReadingsAdaptCadence() {
        var polling = BrightnessPollingState()
        polling.reset(level: 0.5)

        #expect(polling.observe(0.56, manualStep: 0.045).cadence == .active)
        for _ in 1..<BrightnessPollingState.quickPollCount {
            #expect(polling.observe(0.56, manualStep: 0.045).cadence == nil)
        }
        #expect(polling.observe(0.56, manualStep: 0.045).cadence == .idle)

        let nextChange = polling.observe(0.62, manualStep: 0.045)
        #expect(nextChange == .init(cadence: .active, levelToPublish: 0.62))
    }
}
