//
//  AirPodsSceneView.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import Combine
import Foundation
import SceneKit
import SwiftUI

// MARK: - AppKit SCNView Host for Interaction & Hit Testing

public final class AirPodsSCNContainerView: NSView {
    public weak var renderer: AirPodsSceneRenderer?
    public var onBudClick: ((CGPoint) -> Void)?
    public var onDragChanged: ((CGSize) -> Void)?
    public var onDragEnded: (() -> Void)?

    private var initialDragPoint: NSPoint?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        renderer?.scnView.frame = bounds
    }

    public override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        initialDragPoint = loc
        // Check bud click hit-test
        if let renderer = renderer {
            // SCNView coordinates have origin at top-left for hitTest in AppKit
            let scnPoint = CGPoint(x: loc.x, y: bounds.height - loc.y)
            let handled = renderer.handleBudClick(at: scnPoint)
            if handled {
                onBudClick?(scnPoint)
                return
            }
        }
        super.mouseDown(with: event)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let start = initialDragPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        let delta = CGSize(width: current.x - start.x, height: current.y - start.y)
        onDragChanged?(delta)
    }

    public override func mouseUp(with event: NSEvent) {
        initialDragPoint = nil
        onDragEnded?()
        super.mouseUp(with: event)
    }
}

// MARK: - NSViewRepresentable Wrapper

public struct AirPodsScene3DRepresentable: NSViewRepresentable {
    @ObservedObject public var renderer: AirPodsSceneRenderer
    public var onDragChanged: (CGSize) -> Void
    public var onDragEnded: () -> Void

    public func makeNSView(context: Context) -> AirPodsSCNContainerView {
        let container = AirPodsSCNContainerView()
        container.renderer = renderer
        container.onDragChanged = onDragChanged
        container.onDragEnded = onDragEnded

        let scnView = renderer.scnView
        scnView.removeFromSuperview()
        scnView.frame = container.bounds
        scnView.autoresizingMask = [.width, .height]
        container.addSubview(scnView)

        return container
    }

    public func updateNSView(_ container: AirPodsSCNContainerView, context: Context) {
        container.renderer = renderer
        container.onDragChanged = onDragChanged
        container.onDragEnded = onDragEnded
    }
}

// MARK: - Main AirPods Scene View

public struct AirPodsSceneView: View {
    @ObservedObject private var service = AirPodsService.shared
    @ObservedObject private var motion = IslandMotion.shared
    @StateObject private var renderer = AirPodsSceneRenderer()

    public var body: some View {
        ZStack {
            // 1. Deep Space Black Canvas (TimelineView capped at 30 fps, runs only while visible)
            AirPodsStarfieldCanvas(
                isVisible: renderer.isVisible,
                warpProgress: renderer.warpProgress,
                noiseMode: service.state.noiseMode,
                parallaxOffset: renderer.dragOffset,
                isLowPowerMode: renderer.isLowPowerMode,
                isReduceMotion: motion.isReduceMotionActive
            )
            .ignoresSafeArea()

            // 2. 3D SceneKit View
            AirPodsScene3DRepresentable(
                renderer: renderer,
                onDragChanged: { delta in
                    renderer.dragOffset = delta
                    let yaw = delta.width * 0.012
                    let pitch = -delta.height * 0.012
                    renderer.setGroupRotation(yaw: yaw, pitch: pitch)
                },
                onDragEnded: {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                        renderer.dragOffset = .zero
                    }
                    renderer.resetGroupRotation()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 3. Orbit Battery Arcs Layer
            orbitBatteryOverlays
        }
        .frame(minWidth: 380, minHeight: 200)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            renderer.isVisible = true
            service.acquireConsumer()
            renderer.previousConnectedState = service.state.isConnected

            if service.state.isConnected {
                renderer.triggerConnectTransition(lidOpen: service.state.lidOpen ?? true)
            }
        }
        .onDisappear {
            renderer.isVisible = false
            service.releaseConsumer()
        }
        .onChange(of: service.state.isConnected) { _, connected in
            if connected && !renderer.previousConnectedState {
                renderer.triggerConnectTransition(lidOpen: service.state.lidOpen ?? true)
            }
            renderer.previousConnectedState = connected
        }
        .onChange(of: service.state.lidOpen) { _, open in
            if let open = open {
                renderer.setCaseLid(open: open, animated: true)
            }
        }
        .onChange(of: service.state.leftInEar) { _, leftIn in
            renderer.updateEarDetection(leftInEar: leftIn, rightInEar: service.state.rightInEar)
        }
        .onChange(of: service.state.rightInEar) { _, rightIn in
            renderer.updateEarDetection(leftInEar: service.state.leftInEar, rightInEar: rightIn)
        }
        .onChange(of: service.state.pitch) { _, _ in
            if service.isHeadTrackingActive,
               let pitch = service.state.pitch,
               let yaw = service.state.yaw,
               let roll = service.state.roll {
                renderer.setHeadPose(pitch: CGFloat(pitch), yaw: CGFloat(yaw), roll: CGFloat(roll))
                renderer.dragOffset = CGSize(width: yaw * 35.0, height: -pitch * 35.0)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSProcessInfoPowerStateDidChange)) { _ in
            renderer.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            renderer.scnView.preferredFramesPerSecond = renderer.isLowPowerMode ? 30 : 60
        }
    }

    // MARK: - Orbit Battery Rings Overlay

    private var orbitBatteryOverlays: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left Bud Battery Orbit
            AirPodsOrbitRingView(
                title: "Left",
                level: service.state.leftBattery.level,
                isCharging: service.state.leftBattery.isCharging,
                isReduceMotion: motion.isReduceMotionActive,
                size: 68
            )
            .padding(.leading, 20)

            Spacer()

            // Case Unit Battery Orbit (Centered at bottom)
            VStack {
                Spacer()
                AirPodsOrbitRingView(
                    title: "Case",
                    level: service.state.caseBattery.level,
                    isCharging: service.state.caseBattery.isCharging,
                    isReduceMotion: motion.isReduceMotionActive,
                    size: 76
                )
                .padding(.bottom, 12)
            }

            Spacer()

            // Right Bud Battery Orbit
            AirPodsOrbitRingView(
                title: "Right",
                level: service.state.rightBattery.level,
                isCharging: service.state.rightBattery.isCharging,
                isReduceMotion: motion.isReduceMotionActive,
                size: 68
            )
            .padding(.trailing, 20)
        }
        .allowsHitTesting(false) // Let mouse interactions pass to 3D scene
    }
}
