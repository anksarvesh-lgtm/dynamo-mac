//
//  AirPodsSceneRenderer.swift
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

// MARK: - AirPods Scene Renderer

@MainActor
public final class AirPodsSceneRenderer: NSObject, ObservableObject {
    public let scnView: SCNView
    public let scene: SCNScene

    // Scene Nodes
    public let groupNode = SCNNode()
    public private(set) var leftBudNode = SCNNode()
    public private(set) var rightBudNode = SCNNode()
    public private(set) var caseNode = SCNNode()
    public private(set) var caseLidNode = SCNNode()

    // Lighting & Camera
    private let cameraNode = SCNNode()
    private let keyLightNode = SCNNode()
    private let fillLightNode = SCNNode()
    private let rimLightNode = SCNNode()
    private let ambientLightNode = SCNNode()

    // Materials cache for ear-detection dimming
    private var leftMaterials: [SCNMaterial] = []
    private var rightMaterials: [SCNMaterial] = []

    // State Tracking
    @Published public var warpProgress: Double = 0.0
    @Published public var dragOffset: CGSize = .zero
    @Published public var isVisible: Bool = false
    @Published public var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    public var previousConnectedState: Bool = false

    private var isLidOpenState: Bool = false
    private var isSpinningLeft: Bool = false
    private var isSpinningRight: Bool = false
    private var cancellables = Set<AnyCancellable>()

    public override init() {
        self.scnView = SCNView(frame: .zero)
        self.scene = SCNScene()

        super.init()

        setupView()
        setupLighting()
        setupCamera()
        setupNodes()
        loadOrBuildModels()
        setupIdleFloating()
    }

    // MARK: - View Setup

    private func setupView() {
        scnView.scene = scene
        scnView.backgroundColor = .clear
        scnView.rendersContinuously = true
        scnView.preferredFramesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = false
        scnView.isPlaying = true
    }

    // MARK: - Lighting Rig (Soft rim light against pure black notch)

    private func setupLighting() {
        // 1. Key Light: Soft warm-neutral directional light
        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.color = NSColor(calibratedWhite: 0.98, alpha: 1.0)
        keyLight.intensity = 850
        keyLightNode.light = keyLight
        keyLightNode.position = SCNVector3(2.0, 3.0, 2.5)
        keyLightNode.eulerAngles = SCNVector3(-Float.pi / 5.0, Float.pi / 4.0, 0)
        scene.rootNode.addChildNode(keyLightNode)

        // 2. Fill Light: Cool soft tone to lift dark undersides
        let fillLight = SCNLight()
        fillLight.type = .directional
        fillLight.color = NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.0, alpha: 1.0)
        fillLight.intensity = 380
        fillLightNode.light = fillLight
        fillLightNode.position = SCNVector3(-2.5, 1.0, 2.0)
        fillLightNode.eulerAngles = SCNVector3(-Float.pi / 8.0, -Float.pi / 3.0, 0)
        scene.rootNode.addChildNode(fillLightNode)

        // 3. Rim Light: Soft crisp backlight catching the glossy curves against notch black
        let rimLight = SCNLight()
        rimLight.type = .directional
        rimLight.color = NSColor(calibratedRed: 0.85, green: 0.92, blue: 1.0, alpha: 1.0)
        rimLight.intensity = 750
        rimLightNode.light = rimLight
        rimLightNode.position = SCNVector3(0.0, 2.8, -3.2)
        rimLightNode.eulerAngles = SCNVector3(Float.pi / 5.5, Float.pi, 0)
        scene.rootNode.addChildNode(rimLightNode)

        // 4. Ambient Light: Soft baseline
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = NSColor(calibratedWhite: 0.28, alpha: 1.0)
        ambientLight.intensity = 180
        ambientLightNode.light = ambientLight
        scene.rootNode.addChildNode(ambientLightNode)
    }

    // MARK: - Camera

    private func setupCamera() {
        let camera = SCNCamera()
        camera.zNear = 0.05
        camera.zFar = 25.0
        camera.wantsHDR = true
        camera.fieldOfView = 34.0

        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0.0, 0.05, 2.40)
        cameraNode.eulerAngles = SCNVector3(-0.06, 0, 0)
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode
    }

    // MARK: - Hierarchy Setup

    private func setupNodes() {
        groupNode.name = "airPodsGroupNode"
        scene.rootNode.addChildNode(groupNode)

        leftBudNode.name = "leftBud"
        leftBudNode.position = SCNVector3(-0.36, 0.08, 0.0)
        leftBudNode.eulerAngles = SCNVector3(0.08, 0.22, -0.12)
        groupNode.addChildNode(leftBudNode)

        rightBudNode.name = "rightBud"
        rightBudNode.position = SCNVector3(0.36, 0.08, 0.0)
        rightBudNode.eulerAngles = SCNVector3(0.08, -0.22, 0.12)
        groupNode.addChildNode(rightBudNode)

        caseNode.name = "case"
        caseNode.position = SCNVector3(0.0, -0.20, -0.05)
        groupNode.addChildNode(caseNode)
    }

    // MARK: - Model Loading or Procedural Stand-ins

    private func loadOrBuildModels() {
        // 1. Try loading licensed or user USDZ models from Resources/Models/AirPods/
        let leftURL = findModelURL(names: ["left_bud", "left", "LeftBud", "Left"])
        let rightURL = findModelURL(names: ["right_bud", "right", "RightBud", "Right"])
        let caseURL = findModelURL(names: ["case", "case_body", "Case", "CaseBody"])

        var loadedLeft = false
        var loadedRight = false
        var loadedCase = false

        if let leftURL = leftURL, let scene = try? SCNScene(url: leftURL, options: nil) {
            attachUSDZ(scene: scene, to: leftBudNode, targetSize: 0.48)
            loadedLeft = true
        }
        if let rightURL = rightURL, let scene = try? SCNScene(url: rightURL, options: nil) {
            attachUSDZ(scene: scene, to: rightBudNode, targetSize: 0.48)
            loadedRight = true
        }
        if let caseURL = caseURL, let scene = try? SCNScene(url: caseURL, options: nil) {
            attachUSDZ(scene: scene, to: caseNode, targetSize: 0.62)
            loadedCase = true
        }

        // 2. Procedural stand-in fallback if USDZ is missing
        if !loadedLeft {
            buildProceduralBud(isLeft: true, targetNode: leftBudNode)
        }
        if !loadedRight {
            buildProceduralBud(isLeft: false, targetNode: rightBudNode)
        }
        if !loadedCase {
            buildProceduralCase(targetNode: caseNode)
        }
    }

    private func findModelURL(names: [String]) -> URL? {
        let bundle = Bundle.main
        for name in names {
            if let url = bundle.url(forResource: name, withExtension: "usdz", subdirectory: "Models/AirPods") {
                return url
            }
            if let url = bundle.url(forResource: name, withExtension: "usdz", subdirectory: "Resources/Models/AirPods") {
                return url
            }
            if let url = bundle.url(forResource: name, withExtension: "usdz") {
                return url
            }
        }
        return nil
    }

    private func attachUSDZ(scene: SCNScene, to targetNode: SCNNode, targetSize: Float) {
        targetNode.childNodes.forEach { $0.removeFromParentNode() }
        let wrapper = SCNNode()
        for child in scene.rootNode.childNodes {
            if child.light == nil && child.camera == nil {
                wrapper.addChildNode(child.clone())
            }
        }
        Self.normalize(node: wrapper, targetSize: targetSize)
        targetNode.addChildNode(wrapper)
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

    // MARK: - Procedural Geometry

    private func makePBR(diffuse: NSColor, roughness: CGFloat, metalness: CGFloat, emission: NSColor? = nil) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = diffuse
        mat.roughness.contents = roughness
        mat.metalness.contents = metalness
        if let em = emission {
            mat.emission.contents = em
        }
        return mat
    }

    private func buildProceduralBud(isLeft: Bool, targetNode: SCNNode) {
        targetNode.childNodes.forEach { $0.removeFromParentNode() }

        let sign: Float = isLeft ? -1.0 : 1.0
        let whiteGloss = makePBR(diffuse: NSColor(calibratedWhite: 0.95, alpha: 1.0), roughness: 0.12, metalness: 0.05)
        let softTip = makePBR(diffuse: NSColor(calibratedWhite: 0.90, alpha: 1.0), roughness: 0.35, metalness: 0.02)
        let chrome = makePBR(diffuse: NSColor(calibratedWhite: 0.85, alpha: 1.0), roughness: 0.06, metalness: 0.95)
        let acousticBlack = makePBR(diffuse: NSColor(calibratedWhite: 0.12, alpha: 1.0), roughness: 0.85, metalness: 0.0)

        if isLeft {
            leftMaterials = [whiteGloss, softTip, chrome]
        } else {
            rightMaterials = [whiteGloss, softTip, chrome]
        }

        // Head Dome
        let head = SCNNode(geometry: SCNSphere(radius: 0.13))
        head.geometry?.materials = [whiteGloss]
        head.position = SCNVector3(0, 0.08, 0)
        targetNode.addChildNode(head)

        // In-ear Soft Tip (pointing slightly inward)
        let tip = SCNNode(geometry: SCNSphere(radius: 0.085))
        tip.geometry?.materials = [softTip]
        tip.position = SCNVector3(-sign * 0.075, 0.09, 0.06)
        targetNode.addChildNode(tip)

        // Acoustic Vent
        let vent = SCNNode(geometry: SCNSphere(radius: 0.028))
        vent.geometry?.materials = [acousticBlack]
        vent.position = SCNVector3(-sign * 0.12, 0.10, 0.08)
        targetNode.addChildNode(vent)

        // Stem
        let stem = SCNNode(geometry: SCNCapsule(capRadius: 0.038, height: 0.26))
        stem.geometry?.materials = [whiteGloss]
        stem.position = SCNVector3(0, -0.07, 0)
        stem.eulerAngles = SCNVector3(0, 0, sign * 0.09)
        targetNode.addChildNode(stem)

        // Chrome Base Contact
        let contact = SCNNode(geometry: SCNCylinder(radius: 0.039, height: 0.022))
        contact.geometry?.materials = [chrome]
        contact.position = SCNVector3(0, -0.19, 0)
        targetNode.addChildNode(contact)
    }

    private func buildProceduralCase(targetNode: SCNNode) {
        targetNode.childNodes.forEach { $0.removeFromParentNode() }

        let whiteGloss = makePBR(diffuse: NSColor(calibratedWhite: 0.94, alpha: 1.0), roughness: 0.14, metalness: 0.05)
        let ledAmberGreen = makePBR(diffuse: NSColor(calibratedRed: 0.3, green: 0.9, blue: 0.4, alpha: 1.0), roughness: 0.2, metalness: 0.1, emission: NSColor(calibratedRed: 0.2, green: 0.8, blue: 0.3, alpha: 1.0))

        // 1. Lower Case Body
        let bodyGeo = SCNBox(width: 0.48, height: 0.30, length: 0.22, chamferRadius: 0.07)
        bodyGeo.materials = [whiteGloss]
        let bodyNode = SCNNode(geometry: bodyGeo)
        bodyNode.position = SCNVector3(0, -0.06, 0)
        targetNode.addChildNode(bodyNode)

        // Status LED indicator dot on front
        let ledNode = SCNNode(geometry: SCNSphere(radius: 0.012))
        ledNode.geometry?.materials = [ledAmberGreen]
        ledNode.position = SCNVector3(0, -0.02, 0.112)
        bodyNode.addChildNode(ledNode)

        // 2. Hinged Lid Node
        // Pivot is placed at the top-rear edge so it opens backwards
        let lidGeo = SCNBox(width: 0.48, height: 0.14, length: 0.22, chamferRadius: 0.06)
        lidGeo.materials = [whiteGloss]
        let lidMeshNode = SCNNode(geometry: lidGeo)
        lidMeshNode.position = SCNVector3(0, 0.07, 0.11)

        caseLidNode.position = SCNVector3(0, 0.09, -0.11) // Hinge line
        caseLidNode.addChildNode(lidMeshNode)
        targetNode.addChildNode(caseLidNode)
    }

    // MARK: - Zero Gravity Idle Floating (Gentle bob & drift)

    private func setupIdleFloating() {
        let isReduce = IslandMotion.shared.isReduceMotionActive
        let bobDist: CGFloat = isReduce ? 0.008 : 0.025

        // Left Bud Bob
        let leftBobUp = SCNAction.moveBy(x: 0, y: bobDist, z: 0, duration: 2.2)
        leftBobUp.timingMode = .easeInEaseOut
        let leftBobDown = SCNAction.moveBy(x: 0, y: -bobDist, z: 0, duration: 2.2)
        leftBobDown.timingMode = .easeInEaseOut
        leftBudNode.runAction(SCNAction.repeatForever(SCNAction.sequence([leftBobUp, leftBobDown])))

        // Right Bud Bob (offset phase)
        let rightBobDown = SCNAction.moveBy(x: 0, y: -bobDist, z: 0, duration: 2.5)
        rightBobDown.timingMode = .easeInEaseOut
        let rightBobUp = SCNAction.moveBy(x: 0, y: bobDist, z: 0, duration: 2.5)
        rightBobUp.timingMode = .easeInEaseOut
        rightBudNode.runAction(SCNAction.repeatForever(SCNAction.sequence([rightBobDown, rightBobUp])))

        // Case subtle slow drift
        let caseDrift = SCNAction.moveBy(x: 0, y: bobDist * 0.5, z: 0, duration: 3.2)
        caseDrift.timingMode = .easeInEaseOut
        let caseDriftRev = SCNAction.moveBy(x: 0, y: -bobDist * 0.5, z: 0, duration: 3.2)
        caseDriftRev.timingMode = .easeInEaseOut
        caseNode.runAction(SCNAction.repeatForever(SCNAction.sequence([caseDrift, caseDriftRev])))
    }

    // MARK: - On Connect Transition: Fly In From Depth & Lid Open

    public func playConnectFlyIn(lidOpen: Bool = true) {
        let isReduce = IslandMotion.shared.isReduceMotionActive

        if isReduce {
            // Respect Reduce Motion: simple soft fade-in in place
            leftBudNode.opacity = 0.0
            rightBudNode.opacity = 0.0
            SCNTransaction.begin()
            SCNTransaction.animationDuration = IslandMotion.shared.reduceMotionDuration
            leftBudNode.opacity = 1.0
            rightBudNode.opacity = 1.0
            SCNTransaction.commit()
        } else {
            // Fly in from depth (z = -3.0) and settle with the alert spring curve
            let targetLeftPos = SCNVector3(-0.36, 0.08, 0.0)
            let targetRightPos = SCNVector3(0.36, 0.08, 0.0)

            leftBudNode.position = SCNVector3(-0.36, 0.08, -2.8)
            rightBudNode.position = SCNVector3(0.36, 0.08, -2.8)
            leftBudNode.scale = SCNVector3(0.3, 0.3, 0.3)
            rightBudNode.scale = SCNVector3(0.3, 0.3, 0.3)

            let duration = IslandMotion.shared.alertPopResponse

            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            leftBudNode.position = targetLeftPos
            rightBudNode.position = targetRightPos
            leftBudNode.scale = SCNVector3(1.0, 1.0, 1.0)
            rightBudNode.scale = SCNVector3(1.0, 1.0, 1.0)
            SCNTransaction.commit()
        }

        if lidOpen {
            setCaseLid(open: true, animated: true)
        }
    }

    // MARK: - Connect Warp & Fly-in Transition
    public func triggerConnectTransition(lidOpen: Bool = true) {
        guard !IslandMotion.shared.isReduceMotionActive else {
            playConnectFlyIn(lidOpen: lidOpen)
            return
        }

        // 1. Brief warp effect: stars stretch outward for ~0.5s
        withAnimation(.easeOut(duration: 0.22)) {
            warpProgress = 1.0
        }

        // Settle warp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.easeInOut(duration: 0.28)) {
                self.warpProgress = 0.0
            }
        }

        // 2. Buds fly in from depth and settle with alert spring
        playConnectFlyIn(lidOpen: lidOpen)
    }

    // MARK: - Case Lid Control

    public func setCaseLid(open: Bool, animated: Bool) {
        guard isLidOpenState != open else { return }
        isLidOpenState = open

        let targetAngle: CGFloat = open ? -1.45 : 0.0 // ~83 degrees open backwards
        if animated && !IslandMotion.shared.isReduceMotionActive {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.42
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            caseLidNode.eulerAngles.x = targetAngle
            SCNTransaction.commit()
        } else {
            caseLidNode.eulerAngles.x = targetAngle
        }
    }

    // MARK: - Ear Detection (Dim & Drift)

    public func updateEarDetection(leftInEar: Bool?, rightInEar: Bool?) {
        let isReduce = IslandMotion.shared.isReduceMotionActive

        // Left Bud
        if let leftIn = leftInEar {
            let targetX: CGFloat = leftIn ? -0.36 : -0.52
            let targetZ: CGFloat = leftIn ? 0.0 : 0.18
            let targetOpacity: CGFloat = leftIn ? 1.0 : 0.42

            SCNTransaction.begin()
            SCNTransaction.animationDuration = isReduce ? 0.15 : 0.38
            leftBudNode.position.x = targetX
            leftBudNode.position.z = targetZ
            leftBudNode.opacity = targetOpacity
            SCNTransaction.commit()
        }

        // Right Bud
        if let rightIn = rightInEar {
            let targetX: CGFloat = rightIn ? 0.36 : 0.52
            let targetZ: CGFloat = rightIn ? 0.0 : 0.18
            let targetOpacity: CGFloat = rightIn ? 1.0 : 0.42

            SCNTransaction.begin()
            SCNTransaction.animationDuration = isReduce ? 0.15 : 0.38
            rightBudNode.position.x = targetX
            rightBudNode.position.z = targetZ
            rightBudNode.opacity = targetOpacity
            SCNTransaction.commit()
        }
    }

    // MARK: - User Interactions: Click to Spin & Group Drag

    public func handleBudClick(at point: CGPoint) -> Bool {
        let hitResults = scnView.hitTest(point, options: [:])
        for hit in hitResults {
            var node: SCNNode? = hit.node
            while let current = node {
                if current == leftBudNode {
                    spinBud(leftBudNode, isLeft: true)
                    return true
                } else if current == rightBudNode {
                    spinBud(rightBudNode, isLeft: false)
                    return true
                } else if current == caseNode {
                    // Toggle lid on case click
                    setCaseLid(open: !isLidOpenState, animated: true)
                    return true
                }
                node = current.parent
            }
        }
        return false
    }

    private func spinBud(_ node: SCNNode, isLeft: Bool) {
        guard !IslandMotion.shared.isReduceMotionActive else {
            // In reduce motion, do a gentle brightness flash
            let flash = SCNAction.sequence([
                SCNAction.fadeOpacity(to: 0.6, duration: 0.1),
                SCNAction.fadeOpacity(to: 1.0, duration: 0.1)
            ])
            node.runAction(flash)
            return
        }

        let spinAction = SCNAction.rotateBy(
            x: 0,
            y: CGFloat.pi * 2.0 * (isLeft ? -1.0 : 1.0),
            z: 0,
            duration: 0.65
        )
        spinAction.timingMode = .easeInEaseOut
        node.runAction(spinAction)
    }

    public func setGroupRotation(yaw: CGFloat, pitch: CGFloat) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.05
        groupNode.eulerAngles = SCNVector3(pitch, yaw, 0)
        SCNTransaction.commit()
    }

    public func setHeadPose(pitch: CGFloat, yaw: CGFloat, roll: CGFloat) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.04
        groupNode.eulerAngles = SCNVector3(pitch, yaw, -roll)
        SCNTransaction.commit()
    }

    public func resetGroupRotation() {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.4
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        groupNode.eulerAngles = SCNVector3Zero
        SCNTransaction.commit()
    }
}
