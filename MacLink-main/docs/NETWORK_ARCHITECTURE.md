# Network Architecture

## 1. Discovery and Connection Lifecycle
1. **Discovery:**
   - Mac Companion advertises `_maclink-touchpad._tcp` on local network with TXT record `v=1`.
   - Android Companion runs `MacDiscovery` using `NsdManager` to discover available Macs.
2. **WebSocket Handshake:**
   - Android opens WebSocket connection to `ws://<mac_ip>:52400/touchpad` with headers `X-MacLink-Session` and `X-MacLink-Version: 1`.
3. **Session Enforcement:**
   - Single active remote controller policy enforced by default.
4. **Heartbeat & Latency:**
   - Android emits `CONNECTION_PING` every 2000ms.
   - Mac immediately replies with `CONNECTION_PONG`.
   - Android measures round-trip time (RTT) and displays it on the touchpad status bar.
5. **Reconnection:**
   - On socket drops, Android initiates exponential backoff reconnects (1s, 2s, 4s, up to 8s).
   - Mac server executes `emergencyInputCleanup()` immediately upon socket termination.

