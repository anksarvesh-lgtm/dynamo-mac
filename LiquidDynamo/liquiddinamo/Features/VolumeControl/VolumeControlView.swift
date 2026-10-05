//
//  VolumeControlView.swift
//  boringNotch
//
//  Created for Boring Notch
//

import SwiftUI

struct VolumeControlView: View {
    @ObservedObject var volumeManager = VolumeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Section title and Output Device Picker
            HStack(alignment: .center) {
                Label("SOUND OUTPUT", systemImage: "speaker.wave.2")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                // Output Device Picker Menu
                outputDeviceMenu
            }

            // Slider & Mute Row
            HStack(spacing: 10) {
                // Mute / Speaker Icon Button
                Button {
                    volumeManager.toggleMuteAction()
                } label: {
                    Image(systemName: speakerIconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(volumeManager.isMuted ? .red : .primary)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!volumeManager.hasVolumeControl)
                .help(volumeManager.isMuted ? "Unmute" : "Mute")

                // Volume Slider
                GeometryReader { geo in
                    let progress = CGFloat(volumeManager.isMuted ? 0 : volumeManager.rawVolume)
                    ZStack(alignment: .leading) {
                        // Track
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 8)

                        // Filled bar
                        Capsule()
                            .fill(
                                volumeManager.hasVolumeControl
                                    ? (volumeManager.isMuted ? Color.gray : Color.accentColor)
                                    : Color.gray.opacity(0.5)
                            )
                            .frame(width: max(0, min(geo.size.width * progress, geo.size.width)), height: 8)
                    }
                    .frame(height: geo.size.height, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                guard volumeManager.hasVolumeControl else { return }
                                let newProgress = max(0, min(1, Float32(gesture.location.x / geo.size.width)))
                                volumeManager.setAbsolute(newProgress)
                            }
                    )
                }
                .frame(height: 28)
                .disabled(!volumeManager.hasVolumeControl)

                // Volume Percentage Readout
                Text(volumePercentageText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(volumeManager.hasVolumeControl ? .primary : .secondary)
                    .frame(width: 42, alignment: .trailing)
            }

            // Disabled Volume Explanation (for HDMI / DisplayPort outputs)
            if !volumeManager.hasVolumeControl {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("The selected output device has no software volume controls.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, -2)
                .transition(.opacity)
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 20, tint: .indigo)
    }

    // MARK: - Subviews

    private var outputDeviceMenu: some View {
        Menu {
            ForEach(volumeManager.outputDevices) { device in
                Button {
                    volumeManager.setOutputDevice(device)
                } label: {
                    HStack {
                        Label(device.name, systemImage: device.iconName)
                        if device.id == volumeManager.currentOutputDevice?.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: volumeManager.currentOutputDevice?.iconName ?? "speaker.wave.2.fill")
                    .font(.system(size: 11))
                Text(volumeManager.currentOutputDevice?.name ?? "Default Output")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Helpers

    private var speakerIconName: String {
        if !volumeManager.hasVolumeControl || volumeManager.isMuted || volumeManager.rawVolume == 0 {
            return "speaker.slash.fill"
        } else if volumeManager.rawVolume < 0.33 {
            return "speaker.1.fill"
        } else if volumeManager.rawVolume < 0.66 {
            return "speaker.2.fill"
        } else {
            return "speaker.3.fill"
        }
    }

    private var volumePercentageText: String {
        guard volumeManager.hasVolumeControl else { return "--" }
        if volumeManager.isMuted {
            return "Mute"
        }
        return "\(Int(round(volumeManager.rawVolume * 100)))%"
    }
}
