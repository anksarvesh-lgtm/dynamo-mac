//
//  Icon3DView.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Defaults
import SwiftUI

/// Observable animator managing tap interactions and 3D spring dynamics.
final class Icon3DAnimator: ObservableObject {
    @Published var rotationY: Double = 0
    @Published var scalePulse: CGFloat = 1.0
    @Published var opacityFade: Double = 1.0

    func triggerTap(reduceMotion: Bool, is3D: Bool, completion: (() -> Void)? = nil) {
        // Haptic feedback via NSHapticFeedbackManager
        if Defaults[.enableHaptics] {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }

        if reduceMotion {
            // Accessible fallback: gentle fade with no 3D rotation or aggressive scaling
            withAnimation(.easeInOut(duration: 0.12)) {
                opacityFade = 0.35
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                withAnimation(.easeInOut(duration: 0.18)) {
                    self?.opacityFade = 1.0
                }
            }
        } else if is3D {
            // Approach A: Spring scale pulse and 360-degree rotation around the Y axis
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                scalePulse = 0.86
            }
            withAnimation(.spring(response: 0.52, dampingFraction: 0.65)) {
                rotationY += 360
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                    self?.scalePulse = 1.0
                }
            }
        } else {
            // Flat mode: short tactile scale bounce
            withAnimation(.spring(response: 0.18, dampingFraction: 0.6)) {
                scalePulse = 0.90
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                    self?.scalePulse = 1.0
                }
            }
        }

        completion?()
    }
}

/// Reusable icon component rendering raised faux-3D SF Symbols with perspective spring rotation,
/// specular highlights, drop shadows, and reduce motion support.
struct Icon3DView: View {
    let icon: String
    let isSelected: Bool
    var size: CGFloat = 11
    var action: (() -> Void)? = nil

    @Default(.dockIconStyle) private var dockIconStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var animator = Icon3DAnimator()

    init(
        icon: String,
        isSelected: Bool = false,
        size: CGFloat = 11,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.isSelected = isSelected
        self.size = size
        self.action = action
    }

    var body: some View {
        Button {
            animator.triggerTap(
                reduceMotion: reduceMotion,
                is3D: dockIconStyle == .threeD,
                completion: action
            )
        } label: {
            ZStack {
                if dockIconStyle == .threeD {
                    threeDIconView
                } else {
                    flatIconView
                }
            }
            .frame(width: 26, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Flat Icon Mode
    @ViewBuilder
    private var flatIconView: some View {
        Image(systemName: icon)
            .font(.system(size: size, weight: isSelected ? .bold : .medium))
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.55))
            .scaleEffect(animator.scalePulse * (isSelected ? 1.04 : 1.0))
            .opacity(animator.opacityFade)
    }

    // MARK: - Premium 3D Icon Mode
    @ViewBuilder
    private var threeDIconView: some View {
        Premium3DIconView(
            name: icon,
            size: size + 3,
            isSelected: isSelected,
            interactive: false
        )
        .offset(y: isSelected ? -1.0 : 0)
        .scaleEffect(animator.scalePulse * (isSelected ? 1.08 : 1.0))
        .opacity(animator.opacityFade)
        .rotation3DEffect(
            .degrees(reduceMotion ? 0 : animator.rotationY),
            axis: (x: 0, y: 1, z: 0),
            anchor: .center,
            anchorZ: 0,
            perspective: 0.45
        )
    }
}
