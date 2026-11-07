// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import MacLinkTelephony

print("Testing MacLinkTelephony constants...")
assert(CallNotifier.categoryRinging == "CALL_RINGING", "Category ringing matches")
assert(CallNotifier.categoryActive == "CALL_ACTIVE", "Category active matches")
assert(CallNotifier.actionAnswer == "answer", "Action answer matches")
assert(CallNotifier.actionDecline == "decline", "Action decline matches")
assert(CallNotifier.actionEnd == "end", "Action end matches")

print("Testing MacLinkTelephony callback dispatcher...")
var dispatchedId: String?
var dispatchedAction: String?

CallNotifier.shared.onAction = { callId, action in
    dispatchedId = callId
    dispatchedAction = action
}

CallNotifier.shared.onAction?("call_test_42", "answer")
assert(dispatchedId == "call_test_42", "Received callId matches")
assert(dispatchedAction == "answer", "Received action matches")

print("Testing C FFI bridge callbacks...")
maclink_calls_register_action_callback { cCallId, cAction in
    let callId = String(cString: cCallId)
    let action = String(cString: cAction)
    assert(callId == "c_call_99")
    assert(action == "decline")
    print("C FFI callback verified successfully for \(callId) -> \(action)")
}

CallNotifier.shared.onAction?("c_call_99", "decline")

print("Testing Bluetooth HFP C FFI APIs...")
let published = maclink_calls_hfp_publish_sdp(rfcommChannel: 6)
print("HFP SDP published status: \(published)")
assert(!maclink_calls_hfp_is_connected(), "Initially disconnected")
assert(!maclink_calls_hfp_is_sco_active(), "Initially SCO inactive")
maclink_calls_hfp_route_audio(toMac: true)
maclink_calls_hfp_route_audio(toMac: false)
maclink_calls_hfp_unpublish_sdp()

print("All MacLinkTelephony unit tests passed successfully!")

