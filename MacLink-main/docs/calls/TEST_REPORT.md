# MacLink Calls: Phase 7 Test & Verification Report

**Date:** November 2, 2026  
**Environment:**  
- macOS 26.0 (Darwin 25.0.0 arm64)  
- Swift 6.2 (swiftlang-6.2.0.19.1 clang-1700.5.6.1)  
- Rust 1.85.0 / Cargo 1.85.0  
- Android Gradle Plugin / Kotlin 2.1.20 / Android SDK 35  

---

## 1. Test Matrix & Results

| Case | What to do | Expected result | Result | Evidence / Notes |
| :--- | :--- | :--- | :--- | :--- |
| **T1** | Incoming call, MacLink in foreground | Notification with buttons, in-window banner with Answer / Reject | **Not tested** *(requires paired physical phone/Mac)* | In-window banner implemented in `CallCard.qml`; notification banner implemented in `CallNotifier.swift`. |
| **T2** | Incoming call, MacLink window closed | Native macOS notification with Answer / Reject | **Not tested** *(requires paired physical phone/Mac)* | `UNUserNotificationCenter` background category `CALL_RINGING` with action identifiers `ACTION_ANSWER` and `ACTION_DECLINE` registered in `CallNotifier.swift`. |
| **T3** | Click Answer on Mac | Phone answers. Mac banner switches to "Active call" with duration and Hang up button | **Not tested** *(requires paired physical phone/Mac)* | Swift action triggers `c_call_answer` C FFI -> Rust `call_answer` -> `CallCommand::Answer` -> Android `TelecomManager.acceptRingingCall()`. Verified unit tests in `telephony-test`. |
| **T4** | Click Reject on Mac | Call rejected, notification dismissed, banner disappears | **Not tested** *(requires paired physical phone/Mac)* | Swift action triggers `c_call_decline` -> Rust `call_decline` -> `CallCommand::Reject` -> Android `TelecomManager.endCall()`. Verified unit tests in `telephony-test`. |
| **T5** | Dial a contact from Mac | Phone dials. Mac shows outgoing call banner | **Not tested** *(requires paired physical phone/Mac)* | QML `CallsPage.qml` contact row triggers `placeCall` -> `CallCommand::Dial` -> Android `CallController.placeCall()`. |
| **T6** | Dial a number from keypad | Phone dials | **Not tested** *(requires paired physical phone/Mac)* | Keypad dialer input passes sanitized string to `placeCall`. |
| **T7** | Try dialing an emergency number on Mac | Blocked on Mac, error banner, no packet sent to phone | **PASS** *(automated unit test)* | Verified in `maclink-protocol` (`messages::tests::call_v1_protocol_messages_and_validation`) and `TelephonyTests.kt` (`callControllerRejectsEmergencyNumbersAndUssd`). Phone number validator returns `Err("emergency_number")`. |
| **T8** | Try dialing a USSD code (`*#21#`) | Blocked on Mac, keypad refuses or errors | **PASS** *(automated unit test & QML)* | Rejection of `*` and `#` verified in `maclink-protocol` unit tests, `TelephonyTests.kt`, and `CallsPage.qml` `hasUssdChars` guard disabling Call button. |
| **T9** | Incoming call from Hindi contact name | Notification shows correct Unicode Devanagari text | **PASS** *(automated unit test)* | Verified in Android `TelephonyTests.kt` (`contactResolverCacheEvictionAndHindiNameHandling`) with Devanagari Unicode name "राहुल शर्मा" resolving correctly with LRU caching. |
| **T10** | Phone with setting "OFF" receives call | Mac receives no notification, can not answer | **Not tested** *(requires paired physical phone/Mac)* | Verified in logic: `TelephonySettings.isCallControlAllowed` defaults to `false`, and `CallStateMonitor` guards event broadcasting based on permission and toggle state. |
| **T11** | Multi-SIM phone: dial | Prompts for SIM or uses default, does not crash | **Not tested** *(requires paired physical phone/Mac)* | `CallController.kt` queries `TelecomManager.callCapablePhoneAccounts` and selects matching or default account handle gracefully without crashing. |
| **T12** | Rate limit test: spam 20 dials in 1 sec | Core drops extra dials, phone receives at most allowed rate | **PASS** *(automated unit test)* | Verified in `maclink-core` unit test `calls::tests::call_commands_are_rate_limited`: 5 commands permitted per 1000ms window, 6th and subsequent commands rejected. |
| **T13** | Call audio check | User talks on phone / phone headset. Mac audio unaffected | **Not tested** *(requires paired physical phone/Mac)* | Gated: Phase 0 concluded NO-GO for Mac Bluetooth HFP audio. Mac UI displays transparent notice that call audio remains on phone. |

---

## 2. Automated Test Execution Summary

1. **Rust Protocol Suite (`maclink-protocol`):**
   - Command: `cargo test -p maclink-protocol --lib`
   - Result: `63 passed; 0 failed; 0 ignored; finished in 0.10s`
2. **Rust Core Suite (`maclink-core`):**
   - Command: `cargo test -p maclink-core --lib`
   - Result: `114 passed; 0 failed; 0 ignored; finished in 0.93s`
3. **Android Telephony Suite (`app.maclink.android.telephony`):**
   - Command: `./gradlew testDebugUnitTest --tests "app.maclink.android.telephony.*"`
   - Result: `3 passed; 0 failed; 0 skipped; finished in 0.021s`
4. **Swift Telephony Suite (`MacLinkTelephony`):**
   - Command: `swift run telephony-test`
   - Result: `All MacLinkTelephony unit tests passed successfully!`
5. **Desktop CXX-Qt & QML Compilation:**
   - Command: `cargo check -p maclink-desktop`
   - Result: `Finished dev profile [unoptimized + debuginfo] in 45.17s`

