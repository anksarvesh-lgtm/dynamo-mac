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
                    .lineLimit(1)
            } else {
                Text("\(Int(round(currentLevel * 100)))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tintColor)
            }
        }
        .padding(.horizontal, 6)
        .avoidsNotch(id: isLeadingWing ? "BrightnessWingL" : "BrightnessWingR")
    }

    // MARK: - 2. Blooming Droplet Presentation (Below Notch)

    private var bloomingDropletLayout: some View {
        HStack(spacing: 12) {
            // Sun or Backlight Icon
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tintColor)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(tintColor.opacity(0.20))
                )

            // Interactive Fluid Slider
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 8)

                    // Fill with warm sun gradient
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tintColor, tintColor.opacity(0.75)],
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
            .frame(height: 20)

            // Percentage readout
            Text("\(Int(round(currentLevel * 100)))%")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 14)
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
