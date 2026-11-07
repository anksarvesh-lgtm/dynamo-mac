//
//  PhoneCommandDeckView.swift
//  LiquidDynamo
//
//  Exact MacLink command deck inside the expanded Dynamic Island:
//  Device telemetry, Quick Phone Deck toggles, Screen Mirroring launch,
//  and continuity controls.
//

import SwiftUI

public struct PhoneCommandDeckView: View {
    @ObservedObject var bridge = MacLinkBridgeService.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            // Header Bar
            HStack(spacing: 8) {
                Image(systemName: "iphone.gen3")
                    .foregroundColor(.green)
                    .font(.system(size: 13, weight: .bold))

                VStack(alignment: .leading, spacing: 1) {
                    Text(bridge.deviceName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Connected • QUIC & TLS 1.3 • Low-Latency")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                // Signal & Battery Glyphs
                HStack(spacing: 6) {
                    // Cellular Signal
                    HStack(spacing: 2) {
                        ForEach(1...4, id: \.self) { bar in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(bar <= bridge.cellularSignalBars ? Color.white : Color.white.opacity(0.2))
                                .frame(width: 2.5, height: CGFloat(3 + bar * 2))
                        }
                    }
                    Text(bridge.cellularNetworkType)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))

                    // Battery
                    HStack(spacing: 3) {
                        Text("\(bridge.batteryLevel)%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                        Image(systemName: bridge.isCharging ? "bolt.fill" : "battery.75")
                            .font(.system(size: 11))
                            .foregroundColor(bridge.isCharging ? .green : .white.opacity(0.8))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            // Quick Phone Deck Toggles
            HStack(spacing: 8) {
                deckToggleButton(
                    title: "Hotspot",
                    icon: "personalhotspot",
                    isActive: bridge.isHotspotActive
                ) {
                    bridge.toggleHotspot()
                }

                deckToggleButton(
                    title: "Silent",
                    icon: bridge.isSilentModeActive ? "bell.slash.fill" : "bell.fill",
                    isActive: bridge.isSilentModeActive
                ) {
                    bridge.toggleSilentMode()
                }

                deckToggleButton(
                    title: "Flashlight",
                    icon: bridge.isFlashlightActive ? "flashlight.on.fill" : "flashlight.off.fill",
                    isActive: bridge.isFlashlightActive
                ) {
                    bridge.toggleFlashlight()
                }

                deckToggleButton(
                    title: "DND",
                    icon: "moon.fill",
                    isActive: bridge.isDNDActive
                ) {
                    bridge.toggleDND()
                }
            }
            .padding(.horizontal, 14)

            // Primary Action Buttons
            HStack(spacing: 8) {
                // Mirror Screen
                Button {
                    bridge.startScreenMirroring()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.tv.fill")
                        Text(bridge.isMirroringActive ? "Stop Mirror" : "Mirror Screen")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.green.opacity(0.6))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Open ADB Files
                Button {
                    PhoneBridgeWindowController.shared.showWindow()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.gearshape")
                        Text("ADB Files")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.cyan.opacity(0.5))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Continuity Cam
                Button {
                    bridge.toggleContinuityCamera()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.fill")
                        Text("Webcam")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(bridge.isContinuityCamActive ? .cyan : .white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)

            // Test Incoming Call Trigger
            HStack {
                Text("Incoming Call Simulator:")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                Button("Test Call") {
                    bridge.simulateIncomingCall()
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.green)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
    }

    private func deckToggleButton(title: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(isActive ? .green : .white.opacity(0.7))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isActive ? .white : .white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isActive ? Color.green.opacity(0.25) : Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color.green.opacity(0.5) : Color.clear, lineWidth: 0.8)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
