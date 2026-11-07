import Foundation
import Testing

@testable import LedgeSystem

/// Which reader the media pipeline settles on.
///
/// The in-process MediaRemote probe is gated on macOS 26 and returns false, so
/// the branch behind it has never run on a real machine. It used to return the
/// *scripting* source when the probe succeeded — AppleScript only, no
/// system-wide coverage, no browsers — which meant the day a future macOS let
/// that read through, media coverage would quietly narrow rather than widen.
@Suite("Now playing source selection")
@MainActor
struct NowPlayingSelectorTests {

    /// Stands in for a working adapter without loading one.
    private func adapter() -> (dylib: URL, host: AdapterHost)? {
        nil
    }

    /// The regression the audit asked for: force the probe to succeed.
    @Test("A successful in-process probe does not stop adapter discovery")
    func probeSuccessStillSeeksTheAdapter() async {
        var adapterAsked = false
        let choice = await NowPlayingSourceSelector.choose(
            probe: { true },
            adapterProbe: {
                adapterAsked = true
                return nil
            }
        )
        #expect(adapterAsked, "discovery must continue past a probe with no reader behind it")
        #expect(choice.reason != "MediaRemote readable in-process",
            "no source may be described as an in-process reader while none exists")
    }

    @Test("With no adapter and no probe, it says so and uses AppleScript")
    func fallsBackToScripting() async {
        let choice = await NowPlayingSourceSelector.choose(
            probe: { false },
            adapterProbe: { nil }
        )
        #expect(choice.reason == "MediaRemote gated, using AppleScript")
        #expect(choice.source is ScriptingNowPlayingSource)
    }

    /// Whatever the probe said, the reason has to name the source that was
    /// actually chosen — the capability text in Settings is written from it.
    @Test("The reason describes the source that was returned")
    func reasonMatchesTheSource() async {
        for probeResult in [true, false] {
            let choice = await NowPlayingSourceSelector.choose(
                probe: { probeResult },
                adapterProbe: { nil }
            )
            #expect(choice.source is ScriptingNowPlayingSource)
            #expect(choice.reason.contains("AppleScript"),
                "probe=\(probeResult) returned a scripting source described as: \(choice.reason)")
        }
    }

    @Test("The forced stub still wins over everything")
    func forcedStub() async {
        let choice = await NowPlayingSourceSelector.choose(
            forceStub: true,
            probe: { true },
            adapterProbe: { nil }
        )
        #expect(choice.reason == "forced stub")
        #expect(choice.source is StubNowPlayingSource)
    }
}
