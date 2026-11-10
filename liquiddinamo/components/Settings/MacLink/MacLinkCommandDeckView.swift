//
//  MacLinkCommandDeckView.swift
//  LiquidDynamo
//
//  MacLink Command Deck: Quick phone switches, volume slider, ring/silent mode,
//  and wireless control panel.
//

import AppKit
import SwiftUI

public struct MacLinkCommandDeckView: View {
    @ObservedObject private var bridge = MacLinkBridgeService.shared
    @State private var phoneVolume: Double = 0.75

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phone Command Deck")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("Wireless hardware controls and remote device switches for \(bridge.deviceName)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                // Volume Slider Card
                volumeCard

                // 2x2 Grid of Main Phone Switches
                switchesGrid

                // Secondary Settings & Modes
                secondarySwitchesGrid
            }
            .padding(24)
        }
    }

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.blue)
                Text("Phone Media Volume")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                Spacer()
                Text("\(Int(phoneVolume * 100))%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
            }

            Slider(value: $phoneVolume, in: 0...1)
                .tint(Color.blue)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.12).opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    private var switchesGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            toggleItem(
                title: "Mobile Hotspot",
                subtitle: bridge.isHotspotActive ? "Broadcasting 5GHz" : "Disabled",
                icon: "wifi",
                isOn: $bridge.isHotspotActive,
                activeColor: .orange
            )

            toggleItem(
                title: "Do Not Disturb",
                subtitle: bridge.isDNDActive ? "Notifications Silenced" : "All Calls Allowed",
                icon: "moon.fill",
                isOn: $bridge.isDNDActive,
                activeColor: .indigo
            )

            toggleItem(
                title: "Flashlight",
                subtitle: bridge.isFlashlightActive ? "LED Torch On" : "Off",
                icon: "flashlight.on.fill",
                isOn: $bridge.isFlashlightActive,
                activeColor: .yellow
            )

            toggleItem(
                title: "Silent Mode",
                subtitle: bridge.isSilentModeActive ? "Vibrate Only" : "Sound Enabled",
                icon: "bell.slash.fill",
                isOn: $bridge.isSilentModeActive,
                activeColor: .red
            )
        }
    }

    private func toggleItem(title: String, subtitle: String, icon: String, isOn: Binding<Bool>, activeColor: Color) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isOn.wrappedValue ? activeColor.opacity(0.25) : Color.white.opacity(0.08))
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isOn.wrappedValue ? activeColor : Color.white.opacity(0.45))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(isOn.wrappedValue ? activeColor : Color.white.opacity(0.5))
                }

                Spacer()

                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn.wrappedValue ? activeColor.opacity(0.12) : Color(white: 0.12).opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isOn.wrappedValue ? activeColor.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var secondarySwitchesGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Screen & Telephony Settings")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.7))

            HStack(spacing: 12) {
                actionCard(title: "Continuity Cam", icon: "video.fill", detail: "Use Phone as Mac Webcam") {
                    bridge.toggleContinuityCamera()
                }

                actionCard(title: "Simulate Call", icon: "phone.badge.plus", detail: "Trigger Notch Droplet Alert") {
                    bridge.simulateIncomingCall()
                }

                actionCard(title: "Backup Photos", icon: "arrow.triangle.2.circlepath.camera.fill", detail: "Sync Camera Roll to Mac") {
                    bridge.triggerPhotoBackup()
                }
            }
        }
    }

    private func actionCard(title: String, icon: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.blue)
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Color.white)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.12).opacity(0.45))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

