# Security Architecture

## 1. Threat Mitigation
1. **Unauthenticated Connection Defense:**
   - Incoming WebSocket connections must supply an authorized `X-MacLink-Session` header.
   - Any unknown session token is rejected at the transport gate.
2. **Replay Attack & Desynchronization Prevention:**
   - Monotonically increasing sequence counters on every frame.
   - Any packet with `sequence <= last_sequence` is immediately dropped.
3. **Clock-Drift Hardening:**
   - Packets with timestamp drift > 60 seconds relative to host clock are rejected.
4. **Command Injection Prevention:**
   - Strict allowlist of 18 event types.
   - Arbitrary shell scripts or unauthorized system invocations are not permitted over the protocol.
5. **Fail-Safe Release:**
   - Emergency input cleanup releases all pressed mouse buttons and keyboard modifiers on disconnect.

