//
//  LiquidFlowContainerView.swift
//  LiquidDynamo
//
//  Step C: Presentation container hosting the interruptible liquid flow lifecycle.
//  Coordinates stream emergence, drop swelling, holding with cursor lean, and drain absorption.
//

import AppKit
import Defaults
import Foundation
import SwiftUI

public struct LiquidFlowContainerView<Content: View>: View {
    @ObservedObject private var flow = LiquidFlowCoordinator.shared
    @ObservedObject private var motion = IslandMotion.shared
    @ObservedObject private var engine = NotchSafeAreaEngine.shared

    public var tintColor: Color
    @ViewBuilder public let content: () -> Content

    @State private var timelineNow: Date = Date()
    @State private var dragOffset: CGFloat = 0.0

    public init(
        tintColor: Color = Color(red: 0.06, green: 0.75, blue: 0.52),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tintColor = tintColor
        self.content = content
    }

    public var body: some View {
        GeometryReader { proxy in
            let geom = engine.currentGeometry
            let notchLipY = max(24.0, geom.exclusionHeight)
            let notchCenterX = proxy.size.width / 2.0

            TimelineView(.animation(minimumInterval: flow.phase == .resting ? nil : 1.0 / 60.0)) { timeline in
                let time = CGFloat(timeline.date.timeIntervalSinceReferenceDate)
                let activeLobes = ContentDrivenBlobGenerator.generateLobes(
                    clusters: flow.clusters,
                    notchLipY: notchLipY,
                    notchCenterX: notchCenterX,
                    notchWidth: geom.rawNotchWidth > 0 ? geom.rawNotchWidth : 170.0,
                    emergenceProgress: flow.emergenceProgress,
                    seed: flow.currentSeed,
                    time: time
                )

                ZStack(alignment: .top) {
                    if flow.phase != .resting {
                        // 1. Organic Multi-Blob Liquid Glass Backdrop
                        LiquidBlobCanvasView(
                            blobs: activeLobes,
                            k: 18.0,
                            tintColor: tintColor,
                            notchLipY: notchLipY,
                            seed: flow.currentSeed,
                            time: time,
                            transparency: Defaults[.islandTransparency],
                            bgLuminance: 0.0,
                            forceFallback: false
                        )

                        // 2. Floating Content Inside Liquid
                        content()
                            .opacity(flow.contentAlpha)
                            .scaleEffect(
                                motion.isReduceMotionActive ? 1.0 : (0.80 + 0.20 * flow.massScale),
                                anchor: .top
                            )
                            .offset(y: dragOffset)
                            .padding(.top, notchLipY + 4)
                            .frame(maxWidth: .infinity, alignment: .top)
                            .allowsHitTesting(flow.phase == .hold)
                    }
                }
                .contentShape(
                    LiquidBlobShape(
                        blobs: activeLobes,
                        k: 18.0,
                        seed: flow.currentSeed,
                        time: time
                    )
                )
                .onHover { hovering in
                    flow.isHovering = hovering
                }
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { g in
                            if g.translation.height < 0 {
                                dragOffset = g.translation.height
                            }
                        }
                        .onEnded { g in
                            if g.translation.height < -20 || g.velocity.height < -100 {
                                flow.drain()
                            }
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                dragOffset = 0.0
                            }
                        }
                )
            }
        }
    }
}
