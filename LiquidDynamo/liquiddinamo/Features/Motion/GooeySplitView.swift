//
//  GooeySplitView.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import SwiftUI

/// High-performance liquid metaball effect rendered in a SwiftUI Canvas.
/// Active ONLY during split/merge animations (~0.45s) so idle CPU is strictly 0%.
@available(*, deprecated, message: "Use Metal SDF multi-lobe signed-distance rendering (LiquidIslandCanvasView) instead.")
public struct GooeySplitView: View {
    @ObservedObject var island: IslandController = .shared
    @ObservedObject var motion: IslandMotion = .shared

    public init() {}

    public var body: some View {
        if island.isGooeyAnimating && !motion.isSimpleAnimationActive {
            GooeyMetaballCanvas(
                progress: island.splitProgress,
                mainSize: island.targetSize,
                bubbleSize: island.detachedBubbleSize,
                bubbleGap: island.detachedBubbleGap,
                topCornerRadius: island.topCornerRadius,
                bottomCornerRadius: island.bottomCornerRadius,
                isFloating: island.isFloatingDisplay
            )
            .allowsHitTesting(false)
        }
    }
}

/// Animatable canvas that draws the main notch shape and satellite bubble
/// with alpha thresholding and blur to create the liquid meniscus/bridge.
public struct GooeyMetaballCanvas: View, Animatable {
    public var progress: CGFloat // 0.0 (merged) to 1.0 (fully detached)
    public var mainSize: CGSize
    public var bubbleSize: CGSize
    public var bubbleGap: CGFloat
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat
    public var isFloating: Bool

    public var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    public var body: some View {
        Canvas { context, size in
            // Liquid metaball threshold filter: values with alpha >= 0.5 become solid black
            context.addFilter(.alphaThreshold(min: 0.5, color: .black))
            context.addFilter(.blur(radius: 8.0))

            context.drawLayer { ctx in
                let centerX = size.width / 2.0
                let topY: CGFloat = 0.0

                // 1. Draw Main Dynamic Island Pill
                let mainRect = CGRect(
                    x: centerX - mainSize.width / 2.0,
                    y: topY,
                    width: mainSize.width,
                    height: mainSize.height
                )
                let mainShape = DynamicIslandShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius,
                    isFloating: isFloating
                )
                ctx.fill(mainShape.path(in: mainRect), with: .color(.black))

                // 2. Draw Detached Bubble interpolating from right edge into detached position
                let startCenterX = centerX + (mainSize.width / 2.0) - (bubbleSize.width / 2.0)
                let endCenterX = centerX + (mainSize.width / 2.0) + bubbleGap + (bubbleSize.width / 2.0)
                let currentCenterX = startCenterX + (endCenterX - startCenterX) * progress
                let currentCenterY = topY + (bubbleSize.height / 2.0)

                let bubbleRect = CGRect(
                    x: currentCenterX - bubbleSize.width / 2.0,
                    y: currentCenterY - bubbleSize.height / 2.0,
                    width: bubbleSize.width,
                    height: bubbleSize.height
                )
                ctx.fill(Path(ellipseIn: bubbleRect), with: .color(.black))
            }
        }
    }
}
