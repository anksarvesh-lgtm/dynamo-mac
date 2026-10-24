//
//  VolumeLiveActivityView.swift
//  LiquidDynamo
//
//  Migrated Volume Live Activity View for Step 2 of the Liquid Island Engine.
//  Provides both compact top band wing presentation and organic below-notch blooming droplet presentation.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

public struct VolumeLiveActivityView: View {
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject var hub = LiveActivityCenter.shared

    public var isCompactWing: Bool = false
    public var isLeadingWing: Bool = true
    public var onDismiss: () -> Void = {}

    @State private var dragLevel: Double? = nil
    @State private var lastHapticStep: Int = -1

    public init(
        isCompactWing: Bool = false,
        isLeadingWing: Bool = true,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.isCompactWing = isCompactWing
        self.isLeadingWing = isLeadingWing
        self.onDismiss = onDismiss
    }

    private var currentLevel: Double {
        if let drag = dragLevel {
            return drag
        }
        return volumeManager.isMuted ? 0.0 : Double(volumeManager.rawVolume)
    }

    private var speakerIconName: String {
        if volumeManager.isMuted || currentLevel <= 0.001 {
            return "speaker.slash.fill"
        } else if currentLevel > 0.66 {
            return "speaker.wave.3.fill"
        } else if currentLevel > 0.33 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.1.fill"
        }
    }

    private var tintColor: Color {
        volumeManager.isMuted ? Color.red : Color.accentColor
    }

    public var body: some View {
        if isCompactWing {
            compactWingLayout
        } else {
            bloomingDropletLayout
        }
    }

    // MARK: - 1. Compact Wing Presentation (Top Band)

    private var compactWingLayout: some View {
        HStack(spacing: 5) {
            if isLeadingWing {
                Image(systemName: speakerIconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tintColor)
                Text(volumeManager.isMuted ? "Muted" : "Volume")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                    .lineLimit(1)
            } else {
                Text("\(Int(round(currentLevel * 100)))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                Image(systemName: speakerIconName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tintColor)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            LiquidGlassSurface(
                shape: OrganicFluidShape(progress: 1.0, wavePhase: 0.0),
                isNotchAnchored: false,
                scrimFloor: 0.35
            )
        )
        .avoidsNotch(id: isLeadingWing ? "VolumeWingL" : "VolumeWingR")
    }

    // MARK: - 2. Blooming Droplet Presentation (Below Notch)

    private var bloomingDropletLayout: some View {
        HStack(spacing: 10) {
            // Volume Speaker Icon / Mute Button
            Button(action: {
                volumeManager.toggleMuteAction()
                triggerHapticTick()
            }) {
                Image(systemName: speakerIconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(volumeManager.isMuted ? Color.red : Color.white)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(tintColor.opacity(0.20))
                    )
            }
            .buttonStyle(.plain)

            // Percentage readout
            Text(volumeManager.isMuted ? "0%" : "\(Int(round(currentLevel * 100)))%")
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .monospacedDigit()
                .frame(minWidth: 32, alignment: .center)

            // Interactive Organic Fluid Slider (Miniature level indicator)
            OrganicFluidLevelView(
                value: Binding(
                    get: { CGFloat(currentLevel) },
                    set: { newVal in
                        dragLevel = Double(newVal)
                        volumeManager.setAbsolute(Float32(newVal))
                        let step = Int(newVal * 10)
                        if step != lastHapticStep {
                            lastHapticStep = step
                            triggerHapticTick()
                        }
                    }
                ),
                tintColor: tintColor,
                height: 7.0
            )
            .frame(width: 76, height: 18)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .avoidsNotch(id: "VolumeBloomingDroplet")
    }

    private func triggerHapticTick() {
        if Defaults[.enableHaptics] {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment,
                performanceTime: .default
            )
        }
    }
}
