//
//  DeviceInteractive3DView.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Combine
import SceneKit
import SwiftUI

// MARK: - View Model

@MainActor
public final class DeviceInteractiveViewModel: ObservableObject {
    @Published public var resolvedScene: SCNScene?
    @Published public var spinAngle: Double = 0
    @Published public var dragRotationY: Double = 0
    @Published public var dragRotationX: Double = 0
    @Published public var isPulsing: Bool = false
    @Published public var isDragging: Bool = false

    private var currentKey: String?

    public init() {}

    public func handleTap(reduceMotion: Bool, onModelTapped: (() -> Void)?) {
        // Trigger haptic feedback
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)

        if reduceMotion {
            // Gentle scale pulse when reduce motion is enabled
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isPulsing = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                withAnimation(.easeInOut(duration: 0.2)) {
                    self?.isPulsing = false
                }
            }
        } else {
            // Bouncy spring 360-degree spin
            withAnimation(.spring(response: 0.58, dampingFraction: 0.65)) {
                self.spinAngle += 360
            }
        }

        onModelTapped?()
    }

    public func loadModel(for device: DeviceIdentity) async {
        guard currentKey != device.stableKey else { return }
        currentKey = device.stableKey

        // First resolve instant stand-in synchronously for zero perceived latency
        let standIn = DeviceModelResolver.shared.resolveCategoryStandIn(for: device)
        self.resolvedScene = standIn.scene

        // Then asynchronously check if an exact Tier 1 cached model exists
        let resolved = await DeviceModelResolver.shared.resolveModel(for: device)
        if resolved.scene !== standIn.scene {
            self.resolvedScene = resolved.scene
        }
    }
}

// MARK: - Interactive 3D View

/// An interactive 3D model container that wraps SceneKitDeviceView.
/// Supports:
/// - Click-to-spin with a bouncy spring animation and haptic feedback.
/// - Drag-to-rotate along azimuth and elevation.
/// - Full accessibility: respects Reduce Motion by replacing the 360° spin with a gentle scale pulse.
public struct DeviceInteractive3DView: View {
    public let device: DeviceIdentity
    public var size: CGFloat = 32
    public var rpm: Float = 18.0
    public var isPaused: Bool = false
    public var externalSpinTrigger: Int = 0
    public var onModelTapped: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var vm = DeviceInteractiveViewModel()

    public init(
        device: DeviceIdentity,
        size: CGFloat = 32,
        rpm: Float = 18.0,
        isPaused: Bool = false,
        externalSpinTrigger: Int = 0,
        onModelTapped: (() -> Void)? = nil
    ) {
        self.device = device
        self.size = size
        self.rpm = rpm
        self.isPaused = isPaused
        self.externalSpinTrigger = externalSpinTrigger
        self.onModelTapped = onModelTapped
    }

    public var body: some View {
        ZStack {
            if let scene = vm.resolvedScene {
                SceneKitDeviceView(
                    scene: scene,
                    isPaused: isPaused,
                    rpm: vm.isDragging ? 0 : rpm,
                    allowsCameraControl: false
                )
                .frame(width: size, height: size)
                .rotation3DEffect(
                    .degrees(vm.spinAngle + vm.dragRotationY),
                    axis: (x: 0.0, y: 1.0, z: 0.0),
                    perspective: 0.5
                )
                .rotation3DEffect(
                    .degrees(vm.dragRotationX),
                    axis: (x: 1.0, y: 0.0, z: 0.0),
                    perspective: 0.5
                )
                .scaleEffect(vm.isPulsing ? 1.1 : 1.0)
            } else {
                // Instant premium 3D vector fallback while scene resolves
                Premium3DIconView(
                    name: device.iconName,
                    size: size * 0.82,
                    interactive: false
                )
                .frame(width: size, height: size)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            vm.handleTap(reduceMotion: reduceMotion, onModelTapped: onModelTapped)
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    vm.isDragging = true
                    vm.dragRotationY = Double(value.translation.width) * 0.85
                    vm.dragRotationX = -Double(value.translation.height) * 0.55
                }
                .onEnded { _ in
                    vm.isDragging = false
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                        vm.dragRotationY = 0
                        vm.dragRotationX = 0
                    }
                }
        )
        .task(id: device.stableKey) {
            await vm.loadModel(for: device)
        }
        .onChange(of: externalSpinTrigger) {
            vm.handleTap(reduceMotion: reduceMotion, onModelTapped: onModelTapped)
        }
    }
}
