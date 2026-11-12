import Foundation

struct HUDTestsRunner {
    private var failures = 0

    mutating func expect(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
        if !condition {
            fputs("FAIL [\(file):\(line)]: \(message)\n", stderr)
            failures += 1
        }
    }

    private func encodeSystemKey(code: Int, state: Int, isRepeat: Bool = false) -> Int {
        (code << 16) | (state << 8) | (isRepeat ? 1 : 0)
    }

    mutating func run() {
        testSystemKeyDecoding()
        testEventTapActivationPolicy()
        testLevelFormattingAndGlow()
        testInterceptSafetyBackoffAndRecovery()

        if failures == 0 {
            print("HUDTests: ALL PASSED")
        } else {
            fputs("HUDTests: \(failures) FAILURE(S)\n", stderr)
            exit(1)
        }
    }

    mutating func testSystemKeyDecoding() {
        let volUpDown = HUDLogic.parseSystemDefinedKey(data1: encodeSystemKey(code: 0, state: 0x0A))
        expect(volUpDown == HUDKeyPress(key: .volumeUp, isDown: true, isRepeat: false), "Code 0 down should decode to volumeUp")

        let volDownRepeat = HUDLogic.parseSystemDefinedKey(data1: encodeSystemKey(code: 1, state: 0x0A, isRepeat: true))
        expect(volDownRepeat == HUDKeyPress(key: .volumeDown, isDown: true, isRepeat: true), "Code 1 repeat down should set isRepeat")

        let muteUp = HUDLogic.parseSystemDefinedKey(data1: encodeSystemKey(code: 7, state: 0x0B))
        expect(muteUp == HUDKeyPress(key: .mute, isDown: false, isRepeat: false), "Code 7 up should set isDown == false")

        let brightUp = HUDLogic.parseSystemDefinedKey(data1: encodeSystemKey(code: 2, state: 0x0A))
        expect(brightUp?.key == .brightnessUp && HUDLogic.hudKind(for: .brightnessUp) == .brightness, "Code 2 should map to brightness")

        let brightDown = HUDLogic.parseSystemDefinedKey(data1: encodeSystemKey(code: 3, state: 0x0A))
        expect(brightDown?.key == .brightnessDown, "Code 3 should decode to brightnessDown")

        let kbUp = HUDLogic.parseSystemDefinedKey(data1: encodeSystemKey(code: 21, state: 0x0A))
        let kbDown = HUDLogic.parseSystemDefinedKey(data1: encodeSystemKey(code: 22, state: 0x0A))
        expect(kbUp?.key == .keyboardBrightnessUp && HUDLogic.hudKind(for: .keyboardBrightnessUp) == .keyboardBacklight, "Code 21 maps to keyboardBrightnessUp")
        expect(kbDown?.key == .keyboardBrightnessDown, "Code 22 maps to keyboardBrightnessDown")

        expect(HUDLogic.parseSystemDefinedKey(data1: -1) == nil, "Negative data1 should be rejected")
        expect(HUDLogic.parseSystemDefinedKey(data1: encodeSystemKey(code: 16, state: 0x0A)) == nil, "Media play code 16 should pass through")
        expect(HUDLogic.parseSystemDefinedKey(data1: encodeSystemKey(code: 14, state: 0x0A)) == nil, "Eject key code 14 must not be trapped as brightness")
        expect(HUDLogic.parseSystemDefinedKey(data1: encodeSystemKey(code: 0, state: 0x0C)) == nil, "Unknown state byte should be ignored")
    }

    mutating func testEventTapActivationPolicy() {
        expect(!HUDLogic.shouldActivateEventTap(hideSystemOSD: false, legacyHUDReplacement: false), "Passive showNotchOSD alone must not activate event tap")
        expect(HUDLogic.shouldActivateEventTap(hideSystemOSD: true, legacyHUDReplacement: false), "hideSystemOSD should activate event tap")
        expect(HUDLogic.shouldActivateEventTap(hideSystemOSD: false, legacyHUDReplacement: true), "Legacy hudReplacement should activate event tap")
    }

    mutating func testLevelFormattingAndGlow() {
        expect(abs(HUDLogic.step(fine: false) - (1.0 / 16.0)) < 1e-9, "Normal step should be 1/16")
        expect(abs(HUDLogic.step(fine: true) - (1.0 / 64.0)) < 1e-9, "Fine step should be 1/64")

        expect(HUDLogic.filledSegments(level: -0.25) == 0, "Negative level clamps to 0 segments")
        expect(HUDLogic.filledSegments(level: 0.5) == 8, "0.5 fills 8 of 16 segments")
        expect(HUDLogic.filledSegments(level: 1.4) == 16, "Overflow clamps to 16 segments")
        expect(HUDLogic.filledSegments(level: 0.5, isMuted: true) == 0, "Muted volume fills 0 segments")
        expect(HUDLogic.filledSegments(level: 0.5, total: 0) == 0, "Zero segment count yields 0")

        expect(HUDLogic.glowStage(level: 0.8) == .normal, "0.80 stays normal glow stage")
        expect(HUDLogic.glowStage(level: 0.81) == .hot, "Above 0.80 transitions to hot glow stage")
        expect(HUDLogic.glowStage(level: 0.95, isMuted: true) == .normal, "Muted stays normal glow stage")

        expect(HUDLogic.percentText(level: 0.0, isMuted: true) == "Muted", "Muted reads as 'Muted'")
        expect(HUDLogic.percentText(level: 0.65, isMuted: true) == "Muted", "Muted nonzero level still reads as 'Muted'")
        expect(HUDLogic.percentText(level: 0.654, isMuted: false) == "65%", "Rounded percentage string")
        expect(HUDLogic.percentText(level: 1.5, isMuted: false) == "100%", "Clamps upper percentage to 100%")
        expect(HUDLogic.percentText(level: -0.3, isMuted: false) == "0%", "Clamps lower percentage to 0%")

        let clampedEvent = LiquidHUDEvent(kind: .brightness, level: 2.0)
        expect(clampedEvent.level == 1.0, "LiquidHUDEvent clamps level into 0...1")
    }

    mutating func testInterceptSafetyBackoffAndRecovery() {
        var safety = InterceptSafety.State.armed
        expect(InterceptSafety.isIntercepting(safety, keyClass: .volume), "Initially armed for volume")
        expect(InterceptSafety.isIntercepting(safety, keyClass: .brightness), "Initially armed for brightness")

        // Single fluke failure keeps interception active
        safety = InterceptSafety.recording(safety, keyClass: .volume, changed: false, atRail: false)
        expect(safety.failures[.volume] == 1, "First failure records count 1")
        expect(InterceptSafety.isIntercepting(safety, keyClass: .volume), "Single failure should not lock out yet")

        // Rail hit resets prior failure counter
        safety = InterceptSafety.recording(safety, keyClass: .volume, changed: false, atRail: true)
        expect(safety.failures[.volume] == 0, "atRail hit clears failure counter")
        expect(InterceptSafety.isIntercepting(safety, keyClass: .volume), "atRail remains intercepting")

        // Two consecutive genuine failures back off volume without disturbing brightness
        safety = InterceptSafety.recording(safety, keyClass: .volume, changed: false, atRail: false)
        safety = InterceptSafety.recording(safety, keyClass: .volume, changed: false, atRail: false)
        expect(!InterceptSafety.isIntercepting(safety, keyClass: .volume), "Two failures must back off volume interception")
        expect(InterceptSafety.isIntercepting(safety, keyClass: .brightness), "Brightness remains unaffected by volume backoff")

        // Class-scoped reset clears only volume
        safety = InterceptSafety.recording(safety, keyClass: .brightness, changed: false, atRail: false)
        safety = InterceptSafety.recording(safety, keyClass: .brightness, changed: false, atRail: false)
        expect(!InterceptSafety.isIntercepting(safety, keyClass: .brightness), "Two failures must back off brightness")

        safety = InterceptSafety.reset(safety, keyClass: .volume)
        expect(InterceptSafety.isIntercepting(safety, keyClass: .volume), "Volume class reset re-arms volume")
        expect(!InterceptSafety.isIntercepting(safety, keyClass: .brightness), "Volume class reset preserves brightness backoff")

        // Full reset clears all classes
        safety = InterceptSafety.reset(safety)
        expect(safety == .armed, "Full reset returns armed state")
    }
}

var hudTestsRunner = HUDTestsRunner()
hudTestsRunner.run()
