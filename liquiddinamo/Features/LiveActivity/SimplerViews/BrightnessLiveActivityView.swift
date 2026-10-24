//
//  BrightnessLiveActivityView.swift
//  LiquidDynamo
//
//  Migrated Brightness Live Activity View for Step 2 of the Liquid Island Engine.
//  Provides both compact top band wing presentation and organic below-notch blooming droplet presentation.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

public struct BrightnessLiveActivityView: View {
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var hub = LiveActivityCenter.shared

    public var isKeyboardBacklight: Bool = false
    public var isCompactWing: Bool = false
    public var isLeadingWing: Bool = true
    public var onDismiss: () -> Void = {}

    @State private var dragLevel: Double? = nil
    @State private var lastHapticStep: Int = -1

    public init(
        isKeyboardBacklight: Bool = false,
        isCompactWing: Bool = false,
        isLeadingWing: Bool = true,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.isKeyboardBacklight = isKeyboardBacklight
        self.isCompactWing = isCompactWing
        self.isLeadingWing = isLeadingWing
        self.onDismiss = onDismiss
    }

    private var currentLevel: Double {
        if let drag = dragLevel {
            return drag
        }
        if isKeyboardBacklight {
            return Double(KeyboardBacklightManager.shared.rawBrightness)
        }
        return Double(brightnessManager.rawBrightness)
    }

    private var iconName: String {
        if isKeyboardBacklight {
            return "keyboard.fill"
        }
        return currentLevel > 0.5 ? "sun.max.fill" : "sun.min.fill"
    }

    private var tintColor: Color {
        isKeyboardBacklight ? Color.purple : Color.orange
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
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tintColor)
                Text(isKeyboardBacklight ? "Backlight" : "Brightness")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                    .lineLimit(1)
            } else {
                Text("\(Int(round(currentLevel * 100)))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tintColor)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            OrganicFluidShape(
                blobs: [FluidLobe(center: CGPoint(x: 20, y: 10), radiusX: 18, radiusY: 9)],
                irregularity: 0.15
            )
            .fill(Color.white.opacity(0.12))
        )
        .avoidsNotch(id: isLeadingWing ? "BrightnessWingL" : "BrightnessWingR")
    }

    // MARK: - 2. Blooming Droplet Presentation (Below Notch)

    private var bloomingDropletLayout: some View {
        HStack(spacing: 10) {
            // Sun or Backlight Icon
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tintColor)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(tintColor.opacity(0.20))
                )

            // Percentage readout
            Text("\(Int(round(currentLevel * 100)))%")
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .monospacedDigit()
                .frame(minWidth: 32, alignment: .center)

            // Interactive Fluid Slider
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    OrganicFluidLevelView(
                        value: CGFloat(min(max(currentLevel, 0.0), 1.0)),
                        tintColor: tintColor,
                        height: 7
                    )
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            hub.isDraggingSlider = true
                            let progress = min(max(Double(value.location.x / geo.size.width), 0.0), 1.0)
                            dragLevel = progress

                            if isKeyboardBacklight {
                                KeyboardBacklightManager.shared.setAbsolute(value: Float32(progress))
                            } else {
                                brightnessManager.setAbsolute(value: Float32(progress))
                            }

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
            .frame(width: 76, height: 18)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .avoidsNotch(id: "BrightnessBloomingDroplet")
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
