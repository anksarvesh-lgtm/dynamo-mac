//
//  DeviceModelRenderer.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Combine
import Foundation
import SceneKit
import SwiftUI

// MARK: - DeviceModelRenderer Protocol

@MainActor
public protocol DeviceModelRenderer: AnyObject {
    var isPaused: Bool { get set }
    var turntableRPM: Float { get set }

    func loadModel(from fileURL: URL) throws
    func loadScene(_ scene: SCNScene)
    func setTurntableSpin(rpm: Float, animated: Bool)
    func pauseRendering()
    func resumeRendering()
    func resetCamera(animated: Bool)
}

// MARK: - SceneKit Device Renderer Implementation

@MainActor
public final class SceneKitDeviceRenderer: NSObject, DeviceModelRenderer, ObservableObject {
    public static let shared = SceneKitDeviceRenderer()

    public let scnView: SCNView
    public let scene: SCNScene

    private let turntableNode = SCNNode()
    private let cameraNode = SCNNode()
    private let keyLightNode = SCNNode()
    private let fillLightNode = SCNNode()
    private let rimLightNode = SCNNode()
    private let ambientLightNode = SCNNode()

    private var currentModelNode: SCNNode?
    private var cancellables = Set<AnyCancellable>()

    @Published public var isPaused: Bool = true {
        didSet {
            scnView.isPlaying = !isPaused
        }
    }

    @Published public var turntableRPM: Float = 18.0 {
        didSet {
            applyTurntableSpin()
        }
    }

    public override init() {
        self.scnView = SCNView(frame: .zero)
        self.scene = SCNScene()

        super.init()

        setupView()
        setupSceneHierarchy()
        setupLighting()
        setupCamera()
        setupNotchStateObserver()
    }

    // MARK: - View Configuration

    private func setupView() {
        scnView.scene = scene
        scnView.backgroundColor = .clear
        scnView.rendersContinuously = false
        scnView.preferredFramesPerSecond = 60
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = false
        scnView.isPlaying = false
    }

    // MARK: - Scene Hierarchy

    private func setupSceneHierarchy() {
        turntableNode.name = "turntableNode"
        scene.rootNode.addChildNode(turntableNode)
        applyTurntableSpin()
    }

    // MARK: - Lighting Rig

    private func setupLighting() {
        // 1. Key Light: Warm neutral directional light from top-right-front
        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.color = NSColor(calibratedWhite: 1.0, alpha: 1.0)
        keyLight.intensity = 1000
        keyLight.castsShadow = false
        keyLightNode.light = keyLight
        keyLightNode.position = SCNVector3(2.5, 3.5, 2.5)
        keyLightNode.eulerAngles = SCNVector3(-Float.pi / 5.0, Float.pi / 4.0, 0)
        scene.rootNode.addChildNode(keyLightNode)

        // 2. Fill Light: Soft cool light from bottom-left-front to illuminate shadows
        let fillLight = SCNLight()
        fillLight.type = .directional
        fillLight.color = NSColor(calibratedRed: 0.92, green: 0.96, blue: 1.0, alpha: 1.0)
        fillLight.intensity = 450
        fillLight.castsShadow = false
        fillLightNode.light = fillLight
        fillLightNode.position = SCNVector3(-3.0, 1.5, 2.0)
        fillLightNode.eulerAngles = SCNVector3(-Float.pi / 8.0, -Float.pi / 3.0, 0)
        scene.rootNode.addChildNode(fillLightNode)

        // 3. Rim / Edge Light: Crisp backlight for silhouette definition
        let rimLight = SCNLight()
        rimLight.type = .directional
        rimLight.color = NSColor(calibratedWhite: 1.0, alpha: 1.0)
        rimLight.intensity = 650
        rimLight.castsShadow = false
        rimLightNode.light = rimLight
        rimLightNode.position = SCNVector3(0.0, 2.5, -3.0)
        rimLightNode.eulerAngles = SCNVector3(Float.pi / 6.0, Float.pi, 0)
        scene.rootNode.addChildNode(rimLightNode)

        // 4. Ambient Light: Soft ambient base to prevent harsh black occlusions
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = NSColor(calibratedWhite: 0.35, alpha: 1.0)
        ambientLight.intensity = 200
        ambientLightNode.light = ambientLight
        scene.rootNode.addChildNode(ambientLightNode)
    }

    // MARK: - Camera Rig

    private func setupCamera() {
        let camera = SCNCamera()
        camera.zNear = 0.05
        camera.zFar = 30.0
        camera.wantsHDR = true
        camera.fieldOfView = 36.0

        cameraNode.camera = camera
        cameraNode.name = "mainCamera"
        cameraNode.position = SCNVector3(0.0, 0.32, 2.15)
        cameraNode.eulerAngles = SCNVector3(-0.15, 0, 0) // Gentle downward beauty angle
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode
    }

    // MARK: - Notch State Observer

    private func setupNotchStateObserver() {
        // Pause rendering whenever the notch is closed and no popup is showing
        LiquidViewModel.shared.$notchState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                if state == .closed && !LiquidViewCoordinator.shared.expandingView.show {
                    self.pauseRendering()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Model Normalization & Loading

    /// Loads a 3D model from a local file URL (.usdz, .scn, etc.), normalizes it to a unit size,
    /// centers it at the origin, and anchors it to the turntable.
    public func loadModel(from fileURL: URL) throws {
        let loadedScene = try SCNScene(url: fileURL, options: [
            .checkConsistency: false,
            .createNormalsIfAbsent: true
        ])
        loadScene(loadedScene)
    }

    /// Loads an SCNScene hierarchy, normalizes it, and anchors it to the turntable.
    public func loadScene(_ incomingScene: SCNScene) {
        // Remove existing model nodes from turntable
        turntableNode.childNodes.forEach { $0.removeFromParentNode() }

        // Create container node for the incoming scene
        let wrapper = SCNNode()
        for child in incomingScene.rootNode.childNodes {
            // Avoid copying lights or cameras from the incoming scene
            if child.light != nil || child.camera != nil { continue }
            wrapper.addChildNode(child.clone())
        }

        Self.normalize(node: wrapper, targetSize: 1.0)
        turntableNode.addChildNode(wrapper)
        currentModelNode = wrapper

        // Trigger a single render pass even if paused so the initial frame displays
        scnView.setNeedsDisplay(scnView.bounds)
    }

    /// Centers the node at origin and scales its largest bounding dimension to targetSize.
    nonisolated public static func normalize(node: SCNNode, targetSize: Float = 1.0) {
        let (bMin, bMax) = node.boundingBox
        let dx = bMax.x - bMin.x
        let dy = bMax.y - bMin.y
        let dz = bMax.z - bMin.z
        let maxDim = max(dx, max(dy, dz))

        guard maxDim > 0.0001, !maxDim.isNaN, !maxDim.isInfinite else { return }

        let centerX = bMin.x + dx / 2.0
        let centerY = bMin.y + dy / 2.0
        let centerZ = bMin.z + dz / 2.0

        // Set pivot to the geometric center
        node.pivot = SCNMatrix4MakeTranslation(centerX, centerY, centerZ)

        // Scale largest dimension to targetSize
        let scaleFactor = CGFloat(targetSize) / maxDim
        node.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
        node.position = SCNVector3Zero
    }

    // MARK: - Turntable Controls

    public func setTurntableSpin(rpm: Float, animated: Bool) {
        self.turntableRPM = rpm
    }

    private func applyTurntableSpin() {
        turntableNode.removeAction(forKey: "turntableSpin")

        guard turntableRPM > 0.01 else { return }

        let duration = 60.0 / Double(turntableRPM)
        let rotateAction = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2.0, z: 0, duration: duration)
        let repeatAction = SCNAction.repeatForever(rotateAction)
        turntableNode.runAction(repeatAction, forKey: "turntableSpin")
    }

    // MARK: - Playback Lifecycle

    public func pauseRendering() {
        guard !isPaused else { return }
        isPaused = true
    }

    public func resumeRendering() {
        guard isPaused else { return }
        isPaused = false
    }

    public func resetCamera(animated: Bool) {
        let targetPos = SCNVector3(0.0, 0.32, 2.15)
        let targetAngles = SCNVector3(-0.15, 0, 0)

        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.4
            cameraNode.position = targetPos
            cameraNode.eulerAngles = targetAngles
            SCNTransaction.commit()
        } else {
            cameraNode.position = targetPos
            cameraNode.eulerAngles = targetAngles
        }
    }
}

// MARK: - AppKit Container View

public final class SceneKitHostingContainerView: NSView {
    public weak var hostedSCNView: SCNView?

    public override func layout() {
        super.layout()
        hostedSCNView?.frame = bounds
    }

    public override func viewDidHide() {
        super.viewDidHide()
        SceneKitDeviceRenderer.shared.pauseRendering()
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        if LiquidViewModel.shared.notchState == .open || LiquidViewCoordinator.shared.expandingView.show {
            SceneKitDeviceRenderer.shared.resumeRendering()
        }
    }
}

// MARK: - SwiftUI NSViewRepresentable

public struct SceneKitDeviceView: NSViewRepresentable {
    public var scene: SCNScene?
    public var modelURL: URL?
    public var isPaused: Bool
    public var rpm: Float
    public var allowsCameraControl: Bool

    public init(
        scene: SCNScene? = nil,
        modelURL: URL? = nil,
        isPaused: Bool = false,
        rpm: Float = 18.0,
        allowsCameraControl: Bool = false
    ) {
        self.scene = scene
        self.modelURL = modelURL
        self.isPaused = isPaused
        self.rpm = rpm
        self.allowsCameraControl = allowsCameraControl
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> SceneKitHostingContainerView {
        let container = SceneKitHostingContainerView()
        let renderer = SceneKitDeviceRenderer.shared
        let scnView = renderer.scnView

        scnView.removeFromSuperview()
        scnView.frame = container.bounds
        scnView.autoresizingMask = [.width, .height]
        scnView.allowsCameraControl = allowsCameraControl
        container.addSubview(scnView)
        container.hostedSCNView = scnView

        context.coordinator.updateModel(scene: scene, modelURL: modelURL)
        context.coordinator.updatePlayback(isPaused: isPaused, rpm: rpm)

        return container
    }

    public func updateNSView(_ container: SceneKitHostingContainerView, context: Context) {
        let renderer = SceneKitDeviceRenderer.shared
        renderer.scnView.allowsCameraControl = allowsCameraControl

        context.coordinator.updateModel(scene: scene, modelURL: modelURL)
        context.coordinator.updatePlayback(isPaused: isPaused, rpm: rpm)
    }

    public static func dismantleNSView(_ container: SceneKitHostingContainerView, coordinator: Coordinator) {
        let renderer = SceneKitDeviceRenderer.shared
        renderer.pauseRendering()
        renderer.scnView.removeFromSuperview()
    }

    @MainActor
    public class Coordinator {
        var parent: SceneKitDeviceView
        private var lastURL: URL?
        private var lastScene: SCNScene?

        init(_ parent: SceneKitDeviceView) {
            self.parent = parent
        }

        func updateModel(scene: SCNScene?, modelURL: URL?) {
            let renderer = SceneKitDeviceRenderer.shared

            if let modelURL = modelURL, modelURL != lastURL {
                self.lastURL = modelURL
                self.lastScene = nil
                try? renderer.loadModel(from: modelURL)
            } else if let scene = scene, scene !== lastScene {
                self.lastScene = scene
                self.lastURL = nil
                renderer.loadScene(scene)
            }
        }

        func updatePlayback(isPaused: Bool, rpm: Float) {
            let renderer = SceneKitDeviceRenderer.shared
            renderer.turntableRPM = rpm

            // Enforce pause if notch is collapsed and no popup is displaying
            let notchCollapsed = LiquidViewModel.shared.notchState == .closed && !LiquidViewCoordinator.shared.expandingView.show
            if isPaused || notchCollapsed {
                renderer.pauseRendering()
            } else {
                renderer.resumeRendering()
            }
        }
    }
}
