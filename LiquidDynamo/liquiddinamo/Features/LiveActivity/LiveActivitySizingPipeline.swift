//
//  LiveActivitySizingPipeline.swift
//  LiquidDynamo
//
//  Step 2 Auto-Sizing Pipeline for the Liquid Island Engine.
//  Measures intrinsic SwiftUI content dimensions and morphs the SDF liquid body lobe
//  without visual snaps, clipping, or jumps.
//

import Combine
import Foundation
import SwiftUI

// MARK: - 1. Content Size Preference Key

/// Captures the intrinsic size of any live activity child content view.
public struct ContentSizePreferenceKey: PreferenceKey {
    public static var defaultValue: CGSize = .zero

    public static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

// MARK: - 2. Content Measurement View Modifier

public struct IntrinsicContentMeasurer: ViewModifier {
    public var onSizeChange: (CGSize) -> Void

    public func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ContentSizePreferenceKey.self, value: geo.size)
                }
            )
            .onPreferenceChange(ContentSizePreferenceKey.self) { size in
                if size.width > 0 && size.height > 0 {
                    onSizeChange(size)
                }
            }
    }
}

public extension View {
    /// Dynamically measures the intrinsic size of this view and feeds it into the auto-sizing pipeline.
    func measureIntrinsicContentSize(_ onSizeChange: @escaping (CGSize) -> Void) -> some View {
        self.modifier(IntrinsicContentMeasurer(onSizeChange: onSizeChange))
    }
}

// MARK: - 3. Liquid Island Sizing Coordinator

/// Coordinates continuous spring interpolation between measured content dimensions
/// and the SDF body lobe geometry, enforcing safe notch bounds and zero-jump transitions.
@MainActor
public final class LiquidIslandSizingCoordinator: ObservableObject {
    public static let shared = LiquidIslandSizingCoordinator()

    // MARK: - Clamping Constraints
    public var minWidth: CGFloat = 220.0
    public var maxWidth: CGFloat = 460.0
    public var minHeight: CGFloat = 38.0
    public var maxHeight: CGFloat = 160.0

    public var horizontalPadding: CGFloat = 28.0
    public var verticalPadding: CGFloat = 14.0

    // MARK: - Dynamic State
    @Published public private(set) var measuredContentSize: CGSize = .zero
    @Published public private(set) var currentBodySize: CGSize = CGSize(width: 220, height: 38)
    @Published public private(set) var currentCenter: CGPoint = .zero
    @Published public private(set) var isContentRevealed: Bool = false
    @Published public private(set) var expansionProgress: CGFloat = 0.0

    private var activeAnimationTask: Task<Void, Never>?

    public init() {
        let geom = NotchSafeAreaEngine.shared.currentGeometry
        self.currentCenter = CGPoint(
            x: geom.screenFrame.width / 2.0,
            y: geom.notchHeight + 8.0 + (38.0 / 2.0)
        )
    }

    /// Ingests a newly measured content size from the preference key pipeline
    /// and morphs the body lobe smoothly using continuous springs.
    public func updateMeasuredSize(_ size: CGSize, animated: Bool = true) {
        guard size.width > 0 && size.height > 0 else { return }

        // Deduplicate tiny jitter (< 0.5 pt)
        if abs(size.width - measuredContentSize.width) < 0.5 &&
           abs(size.height - measuredContentSize.height) < 0.5 {
            return
        }

        self.measuredContentSize = size

        let geom = NotchSafeAreaEngine.shared.currentGeometry
        let availableWidth = min(maxWidth, max(minWidth, geom.screenFrame.width * 0.55))

        let targetW = min(max(size.width + horizontalPadding, minWidth), availableWidth)
        let targetH = min(max(size.height + verticalPadding, minHeight), maxHeight)
        let newSize = CGSize(width: targetW, height: targetH)

        let targetY = geom.notchHeight + 8.0 + (targetH / 2.0)
        let targetX = geom.screenFrame.width / 2.0
        let newCenter = CGPoint(x: targetX, y: targetY)

        if animated && !IslandMotion.shared.isReduceMotionActive {
            withAnimation(IslandMotion.shared.expandSpring) {
                self.currentBodySize = newSize
                self.currentCenter = newCenter
            }
        } else {
            self.currentBodySize = newSize
            self.currentCenter = newCenter
        }

        // Evaluate reveal gate
        evaluateContentReveal()
    }

    /// Evaluates whether the body has expanded sufficiently (>= 60%) to reveal the inner content.
    public func setExpansionProgress(_ progress: CGFloat) {
        self.expansionProgress = progress
        evaluateContentReveal()
    }

    private func evaluateContentReveal() {
        let shouldReveal = expansionProgress >= 0.60
        if isContentRevealed != shouldReveal {
            withAnimation(.easeOut(duration: 0.15)) {
                self.isContentRevealed = shouldReveal
            }
        }
    }

    /// Resets the coordinator to its compact/resting size.
    public func resetToResting() {
        let geom = NotchSafeAreaEngine.shared.currentGeometry
        let resting = CGSize(width: minWidth, height: minHeight)
        self.measuredContentSize = .zero
        self.currentBodySize = resting
        self.currentCenter = CGPoint(
            x: geom.screenFrame.width / 2.0,
            y: geom.notchHeight + 8.0 + (minHeight / 2.0)
        )
        self.isContentRevealed = false
        self.expansionProgress = 0.0
    }
}
