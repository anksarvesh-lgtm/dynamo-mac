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
                    .lineLimit(1)
            } else {
                Text("\(Int(round(currentLevel * 100)))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Image(systemName: speakerIconName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tintColor)
            }
        }
        .padding(.horizontal, 6)
        .avoidsNotch(id: isLeadingWing ? "VolumeWingL" : "VolumeWingR")
    }

    // MARK: - 2. Blooming Droplet Presentation (Below Notch)

    private var bloomingDropletLayout: some View {
        HStack(spacing: 12) {
            // Volume Speaker Icon / Mute Button
            Button(action: {
                volumeManager.toggleMuteAction()
                triggerHapticTick()
            }) {
                Image(systemName: speakerIconName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(volumeManager.isMuted ? Color.red : Color.white)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(tintColor.opacity(0.20))
                    )
            }
            .buttonStyle(.plain)

            // Interactive Fluid Slider
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 8)

                    // Fill
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tintColor, tintColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * CGFloat(min(max(currentLevel, 0.0), 1.0))), height: 8)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            hub.isDraggingSlider = true
                            let progress = min(max(Double(value.location.x / geo.size.width), 0.0), 1.0)
                            dragLevel = progress
                            volumeManager.setAbsolute(Float32(progress))

                            // Step haptics every 10%
                            let step = Int(progress * 10)
                            if step != lastHapticStep {
                                lastHapticStep = step
                                triggerHapticTick()
                            }
                        }
                        .onEnded { _ in
                            hub.isDraggingSlider = false
                            dragLevel = nil
                            lastHapticStep = -1
                        }
                )
            }
            .frame(height: 20)

            // Percentage readout
            Text(volumeManager.isMuted ? "0%" : "\(Int(round(currentLevel * 100)))%")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 14)
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
