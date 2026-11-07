# Permission Guide

## 1. macOS Permissions
- **Accessibility (`AXIsProcessTrusted`):**
  - **Required for:** Synthesizing native `CGEvent` mouse moves, clicks, drag operations, and scroll actions.
  - **Prompting:** The user is guided with direct deep links to `System Settings > Privacy & Security > Accessibility`.
- **Input Monitoring:**
  - **Required for:** Background `CGEventTap` and global pointer observation.
  - **Prompting:** Direct link to `System Settings > Privacy & Security > Input Monitoring`.

## 2. Android Permissions
- `android.permission.INTERNET`: Connecting to local Mac WebSocket endpoint.
- `android.permission.ACCESS_NETWORK_STATE`: Detecting local Wi-Fi connectivity.
- `android.permission.VIBRATE`: Driving physical vibration motors and haptic actuators.
- No accessibility service is required on Android to operate the trackpad surface.

