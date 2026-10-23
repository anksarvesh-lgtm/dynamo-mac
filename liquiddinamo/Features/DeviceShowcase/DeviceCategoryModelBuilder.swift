//
//  DeviceCategoryModelBuilder.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Foundation
import SceneKit
import UniformTypeIdentifiers

// MARK: - Category Procedural Stand-in Builder

/// Builds procedural 3D models using SceneKit primitives as category stand-ins
/// when no custom or bundled USDZ model exists.
@MainActor
public enum DeviceCategoryModelBuilder {

    // MARK: - PBR Material Helper

    public static func makePBRMaterial(
        diffuse: NSColor,
        roughness: CGFloat = 0.35,
        metalness: CGFloat = 0.5,
        emission: NSColor? = nil
    ) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = diffuse
        mat.roughness.contents = roughness
        mat.metalness.contents = metalness
        if let emission = emission {
            mat.emission.contents = emission
        }
        return mat
    }

    // MARK: - Flat Card for Storage Devices

    /// Builds a premium 3D flat card displaying the macOS system volume icon from NSWorkspace.
    public static func buildStorageFlatCard(for device: DeviceIdentity? = nil) -> SCNScene {
        let scene = SCNScene()

        // Fetch high-resolution system volume icon
        let icon = NSWorkspace.shared.icon(for: .volume)
        icon.size = NSSize(width: 512, height: 512)

        let cardGeometry = SCNBox(width: 1.0, height: 1.0, length: 0.04, chamferRadius: 0.06)

        // Front Face: System Icon
        let frontMat = SCNMaterial()
        frontMat.diffuse.contents = icon
        frontMat.roughness.contents = 0.15
        frontMat.metalness.contents = 0.05

        // Rim / Sides: Anodized dark aluminum
        let sideMat = makePBRMaterial(
            diffuse: NSColor(calibratedWhite: 0.22, alpha: 1.0),
            roughness: 0.28,
            metalness: 0.85
        )

        // Back: Sleek matte space gray finish
        let backMat = makePBRMaterial(
            diffuse: NSColor(calibratedWhite: 0.16, alpha: 1.0),
            roughness: 0.45,
            metalness: 0.65
        )

        cardGeometry.materials = [frontMat, sideMat, backMat, sideMat, sideMat, sideMat]

        let cardNode = SCNNode(geometry: cardGeometry)
        cardNode.name = "storageFlatCard"
        scene.rootNode.addChildNode(cardNode)

        return scene
    }

    /// Builds a 3D turntable card featuring an isolated transparent product image.
    public static func buildProductImageCard(image: NSImage) -> SCNScene {
        let scene = SCNScene()
        let cardGeometry = SCNBox(width: 1.0, height: 1.0, length: 0.04, chamferRadius: 0.06)

        // Front Face: Transparent Cutout Product Image
        let frontMat = SCNMaterial()
        frontMat.diffuse.contents = image
        frontMat.roughness.contents = 0.25
        frontMat.metalness.contents = 0.1

        // Rim / Sides: Anodized dark aluminum
        let sideMat = makePBRMaterial(
            diffuse: NSColor(calibratedWhite: 0.22, alpha: 1.0),
            roughness: 0.28,
            metalness: 0.85
        )

        // Back: Sleek matte space gray finish
        let backMat = makePBRMaterial(
            diffuse: NSColor(calibratedWhite: 0.16, alpha: 1.0),
            roughness: 0.45,
            metalness: 0.65
        )

        cardGeometry.materials = [frontMat, sideMat, backMat, sideMat, sideMat, sideMat]

        let cardNode = SCNNode(geometry: cardGeometry)
        cardNode.name = "productImageCard"
        scene.rootNode.addChildNode(cardNode)

        return scene
    }

    // MARK: - Stylized Primitive Models

    public static func buildProceduralModel(for kind: DeviceKind) -> SCNScene {
        switch kind {
        case .airpods, .earbuds:
            return buildEarbudsWithCase()
        case .earphones, .neckband, .headphones:
            return buildHeadphones()
        case .speaker:
            return buildSpeaker()
        case .ssdDrive:
            return buildSSD()
        case .usbStick:
            return buildUSBStick()
        case .mouse, .trackpad:
            return buildMouse()
        case .keyboard:
            return buildKeyboard()
        case .phone:
            return buildPhone()
        case .androidPhone:
            return buildAndroidPhone()
        case .tablet:
            return buildTablet()
        case .monitor:
            return buildMonitor()
        case .gameController:
            return buildGameController()
        case .printer:
            return buildGeneric()
        case .charger:
            return buildCharger()
        case .generic:
            return buildGeneric()
        }
    }

    // MARK: 1. Earbuds with Case (Archetype)

    private static func buildEarbudsWithCase() -> SCNScene {
        let scene = SCNScene()
        let whiteGloss = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.96, alpha: 1.0), roughness: 0.12, metalness: 0.04)
        let chrome = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.85, alpha: 1.0), roughness: 0.05, metalness: 0.95)
        let acousticBlack = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.1, alpha: 1.0), roughness: 0.9, metalness: 0.0)
        let seamMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.75, alpha: 1.0), roughness: 0.5, metalness: 0.2)
        let ledMat = makePBRMaterial(diffuse: NSColor.systemGreen, roughness: 0.1, metalness: 0.0, emission: NSColor.systemGreen)

        // Case Body
        let caseBox = SCNNode(geometry: SCNBox(width: 0.64, height: 0.52, length: 0.30, chamferRadius: 0.10))
        caseBox.geometry?.materials = [whiteGloss]
        caseBox.position = SCNVector3(0, -0.15, 0)
        scene.rootNode.addChildNode(caseBox)

        // Case Lid Seam
        let seam = SCNNode(geometry: SCNBox(width: 0.645, height: 0.008, length: 0.305, chamferRadius: 0.002))
        seam.geometry?.materials = [seamMat]
        seam.position = SCNVector3(0, -0.04, 0)
        scene.rootNode.addChildNode(seam)

        // Front Status LED
        let led = SCNNode(geometry: SCNSphere(radius: 0.014))
        led.geometry?.materials = [ledMat]
        led.position = SCNVector3(0, -0.16, 0.152)
        scene.rootNode.addChildNode(led)

        // Two Earbuds resting slightly above the case
        for sign: Float in [-1.0, 1.0] {
            let bud = SCNNode()

            // Head dome
            let head = SCNNode(geometry: SCNSphere(radius: 0.15))
            head.geometry?.materials = [whiteGloss]
            bud.addChildNode(head)

            // In-ear tip
            let tip = SCNNode(geometry: SCNSphere(radius: 0.10))
            tip.geometry?.materials = [whiteGloss]
            tip.position = SCNVector3(-sign * 0.08, 0.02, 0.07)
            bud.addChildNode(tip)

            // Acoustic mesh dot
            let meshDot = SCNNode(geometry: SCNSphere(radius: 0.035))
            meshDot.geometry?.materials = [acousticBlack]
            meshDot.position = SCNVector3(-sign * 0.14, 0.03, 0.09)
            bud.addChildNode(meshDot)

            // Stem
            let stem = SCNNode(geometry: SCNCapsule(capRadius: 0.042, height: 0.28))
            stem.geometry?.materials = [whiteGloss]
            stem.position = SCNVector3(0, -0.16, 0)
            stem.eulerAngles = SCNVector3(0, 0, sign * 0.08)
            bud.addChildNode(stem)

            // Chrome charging ring
            let ring = SCNNode(geometry: SCNCylinder(radius: 0.044, height: 0.025))
            ring.geometry?.materials = [chrome]
            ring.position = SCNVector3(0, -0.28, 0)
            bud.addChildNode(ring)

            bud.position = SCNVector3(sign * 0.16, 0.22, 0.02)
            bud.eulerAngles = SCNVector3(0, -sign * 0.22, 0)
            scene.rootNode.addChildNode(bud)
        }

        return scene
    }

    // MARK: 2. Headphones (Over-ear studio archetype)

    private static func buildHeadphones() -> SCNScene {
        let scene = SCNScene()
        let darkMetal = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.22, alpha: 1.0), roughness: 0.35, metalness: 0.75)
        let padMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.12, alpha: 1.0), roughness: 0.85, metalness: 0.0)
        let chromeAccent = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.88, alpha: 1.0), roughness: 0.08, metalness: 0.95)

        for sign: Float in [-1.0, 1.0] {
            // Earcup outer housing
            let cup = SCNNode(geometry: SCNCylinder(radius: 0.27, height: 0.14))
            cup.geometry?.materials = [darkMetal]
            cup.eulerAngles = SCNVector3(0, 0, Float.pi / 2.0)
            cup.position = SCNVector3(sign * 0.40, -0.1, 0)

            // Chrome ring
            let ring = SCNNode(geometry: SCNCylinder(radius: 0.272, height: 0.015))
            ring.geometry?.materials = [chromeAccent]
            ring.eulerAngles = SCNVector3(0, 0, Float.pi / 2.0)
            ring.position = SCNVector3(sign * 0.44, -0.1, 0)

            // Earcup cushion pad
            let pad = SCNNode(geometry: SCNCylinder(radius: 0.27, height: 0.07))
            pad.geometry?.materials = [padMat]
            pad.eulerAngles = SCNVector3(0, 0, Float.pi / 2.0)
            pad.position = SCNVector3(sign * 0.32, -0.1, 0)

            scene.rootNode.addChildNode(cup)
            scene.rootNode.addChildNode(ring)
            scene.rootNode.addChildNode(pad)
        }

        // Headband arch
        let headband = SCNNode(geometry: SCNTorus(ringRadius: 0.43, pipeRadius: 0.038))
        headband.geometry?.materials = [darkMetal]
        headband.position = SCNVector3(0, 0.14, 0)
        scene.rootNode.addChildNode(headband)

        return scene
    }

    // MARK: 3. Speaker (Portable cylindrical speaker)

    private static func buildSpeaker() -> SCNScene {
        let scene = SCNScene()
        let meshMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.24, alpha: 1.0), roughness: 0.85, metalness: 0.1)
        let rubberMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.14, alpha: 1.0), roughness: 0.55, metalness: 0.0)
        let buttonMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.9, alpha: 1.0), roughness: 0.2, metalness: 0.2)

        // Main cylindrical mesh body
        let body = SCNNode(geometry: SCNCylinder(radius: 0.34, height: 0.82))
        body.geometry?.materials = [meshMat]
        scene.rootNode.addChildNode(body)

        // Top and bottom protective silicone caps
        for sign: Float in [-1.0, 1.0] {
            let cap = SCNNode(geometry: SCNCylinder(radius: 0.34, height: 0.08))
            cap.geometry?.materials = [rubberMat]
            cap.position = SCNVector3(0, sign * 0.43, 0)
            scene.rootNode.addChildNode(cap)
        }

        // Volume + button
        let plusH = SCNNode(geometry: SCNBox(width: 0.09, height: 0.02, length: 0.02, chamferRadius: 0.005))
        plusH.geometry?.materials = [buttonMat]
        let plusV = SCNNode(geometry: SCNBox(width: 0.02, height: 0.09, length: 0.02, chamferRadius: 0.005))
        plusV.geometry?.materials = [buttonMat]
        let plus = SCNNode()
        plus.addChildNode(plusH)
        plus.addChildNode(plusV)
        plus.position = SCNVector3(0, 0.12, 0.35)
        scene.rootNode.addChildNode(plus)

        // Volume - button
        let minus = SCNNode(geometry: SCNBox(width: 0.09, height: 0.02, length: 0.02, chamferRadius: 0.005))
        minus.geometry?.materials = [buttonMat]
        minus.position = SCNVector3(0, -0.12, 0.35)
        scene.rootNode.addChildNode(minus)

        return scene
    }

    // MARK: 4. SSD / Drive (Portable SSD archetype)

    private static func buildSSD() -> SCNScene {
        let scene = SCNScene()
        let darkMetal = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.22, alpha: 1.0), roughness: 0.3, metalness: 0.85)
        let slotMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.05, alpha: 1.0), roughness: 0.8, metalness: 0.0)
        let ledMat = makePBRMaterial(diffuse: NSColor.systemTeal, roughness: 0.1, metalness: 0.0, emission: NSColor.systemTeal)

        // Rounded aluminum chassis
        let drive = SCNNode(geometry: SCNBox(width: 0.65, height: 1.05, length: 0.12, chamferRadius: 0.04))
        drive.geometry?.materials = [darkMetal]
        scene.rootNode.addChildNode(drive)

        // USB-C slot cut-out
        let slot = SCNNode(geometry: SCNBox(width: 0.18, height: 0.04, length: 0.08, chamferRadius: 0.015))
        slot.geometry?.materials = [slotMat]
        slot.position = SCNVector3(0, -0.52, 0)
        scene.rootNode.addChildNode(slot)

        // LED dot indicator
        let led = SCNNode(geometry: SCNSphere(radius: 0.018))
        led.geometry?.materials = [ledMat]
        led.position = SCNVector3(0.2, 0.42, 0.065)
        scene.rootNode.addChildNode(led)

        return scene
    }

    // MARK: 5. USB Stick (Flash thumb drive)

    private static func buildUSBStick() -> SCNScene {
        let scene = SCNScene()
        let bodyMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.26, alpha: 1.0), roughness: 0.35, metalness: 0.75)
        let chromeMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.88, alpha: 1.0), roughness: 0.05, metalness: 0.95)
        let tongueMat = makePBRMaterial(diffuse: NSColor.systemBlue, roughness: 0.4, metalness: 0.0)

        // Thumb drive body
        let body = SCNNode(geometry: SCNBox(width: 0.35, height: 0.68, length: 0.13, chamferRadius: 0.025))
        body.geometry?.materials = [bodyMat]
        body.position = SCNVector3(0, -0.1, 0)
        scene.rootNode.addChildNode(body)

        // USB-A connector plug
        let plug = SCNNode(geometry: SCNBox(width: 0.26, height: 0.28, length: 0.09, chamferRadius: 0.008))
        plug.geometry?.materials = [chromeMat]
        plug.position = SCNVector3(0, 0.34, 0)
        scene.rootNode.addChildNode(plug)

        // Blue 3.0 connector tongue
        let tongue = SCNNode(geometry: SCNBox(width: 0.22, height: 0.18, length: 0.02, chamferRadius: 0.002))
        tongue.geometry?.materials = [tongueMat]
        tongue.position = SCNVector3(0, 0.35, 0.02)
        scene.rootNode.addChildNode(tongue)

        return scene
    }

    // MARK: 6. Mouse (Ergonomic mouse archetype)

    private static func buildMouse() -> SCNScene {
        let scene = SCNScene()
        let mouseMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.24, alpha: 1.0), roughness: 0.3, metalness: 0.5)
        let wheelMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.85, alpha: 1.0), roughness: 0.08, metalness: 0.95)
        let seamMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.08, alpha: 1.0), roughness: 0.9, metalness: 0.0)

        // Contoured dome body (scaled sphere)
        let dome = SCNNode(geometry: SCNSphere(radius: 0.48))
        dome.geometry?.materials = [mouseMat]
        dome.scale = SCNVector3(0.72, 0.42, 1.1)
        scene.rootNode.addChildNode(dome)

        // Metallic scroll wheel
        let wheel = SCNNode(geometry: SCNCylinder(radius: 0.08, height: 0.038))
        wheel.geometry?.materials = [wheelMat]
        wheel.eulerAngles = SCNVector3(0, 0, Float.pi / 2.0)
        wheel.position = SCNVector3(0, 0.14, -0.28)
        scene.rootNode.addChildNode(wheel)

        // Center split seam
        let seam = SCNNode(geometry: SCNBox(width: 0.008, height: 0.04, length: 0.38, chamferRadius: 0.001))
        seam.geometry?.materials = [seamMat]
        seam.position = SCNVector3(0, 0.15, -0.24)
        scene.rootNode.addChildNode(seam)

        return scene
    }

    // MARK: 7. Keyboard (Low-profile chiclet keyboard)

    private static func buildKeyboard() -> SCNScene {
        let scene = SCNScene()
        let chassisMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.26, alpha: 1.0), roughness: 0.3, metalness: 0.8)
        let keyMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.14, alpha: 1.0), roughness: 0.5, metalness: 0.0)

        // Angled base chassis
        let base = SCNNode(geometry: SCNBox(width: 1.15, height: 0.05, length: 0.56, chamferRadius: 0.02))
        base.geometry?.materials = [chassisMat]
        base.eulerAngles = SCNVector3(0.1, 0, 0)
        scene.rootNode.addChildNode(base)

        // Chiclet keycaps grid
        let rows = 4
        let cols = 9
        let startX: Float = -0.46
        let startZ: Float = -0.18
        let spacingX: Float = 0.115
        let spacingZ: Float = 0.115

        for r in 0..<rows {
            for c in 0..<cols {
                let key = SCNNode(geometry: SCNBox(width: 0.09, height: 0.025, length: 0.09, chamferRadius: 0.008))
                key.geometry?.materials = [keyMat]
                key.position = SCNVector3(
                    startX + Float(c) * spacingX,
                    0.038,
                    startZ + Float(r) * spacingZ
                )
                key.eulerAngles = SCNVector3(0.1, 0, 0)
                scene.rootNode.addChildNode(key)
            }
        }

        return scene
    }

    // MARK: 8. Phone (Glass & aluminum slab)

    private static func buildPhone() -> SCNScene {
        let scene = SCNScene()
        let frameMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.2, alpha: 1.0), roughness: 0.2, metalness: 0.9)
        let screenMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.04, alpha: 1.0), roughness: 0.05, metalness: 0.1)
        let lensMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.08, alpha: 1.0), roughness: 0.02, metalness: 0.8)

        // Chassis slab
        let phone = SCNNode(geometry: SCNBox(width: 0.62, height: 1.25, length: 0.065, chamferRadius: 0.05))
        phone.geometry?.materials = [screenMat, frameMat, frameMat, frameMat, frameMat, frameMat]
        scene.rootNode.addChildNode(phone)

        // Camera island on back
        let bump = SCNNode(geometry: SCNBox(width: 0.26, height: 0.26, length: 0.02, chamferRadius: 0.035))
        bump.geometry?.materials = [frameMat]
        bump.position = SCNVector3(-0.14, 0.44, -0.04)
        scene.rootNode.addChildNode(bump)

        // 3 Camera lenses
        let lensPositions: [SCNVector3] = [
            SCNVector3(-0.19, 0.48, -0.052),
            SCNVector3(-0.19, 0.40, -0.052),
            SCNVector3(-0.10, 0.44, -0.052)
        ]
        for pos in lensPositions {
            let lens = SCNNode(geometry: SCNCylinder(radius: 0.032, height: 0.012))
            lens.geometry?.materials = [lensMat]
            lens.eulerAngles = SCNVector3(Float.pi / 2.0, 0, 0)
            lens.position = pos
            scene.rootNode.addChildNode(lens)
        }

        return scene
    }

    // MARK: 9. Generic Device (Minimalist faceted tech badge)

    private static func buildGeneric() -> SCNScene {
        let scene = SCNScene()
        let slateMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.22, alpha: 1.0), roughness: 0.25, metalness: 0.8)
        let glowMat = makePBRMaterial(
            diffuse: NSColor.systemTeal,
            roughness: 0.1,
            metalness: 0.0,
            emission: NSColor.systemTeal
        )

        // Chamfered tech prism
        let prism = SCNNode(geometry: SCNBox(width: 0.75, height: 0.75, length: 0.35, chamferRadius: 0.08))
        prism.geometry?.materials = [slateMat]
        scene.rootNode.addChildNode(prism)

        // Center glowing accent ring
        let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.2, pipeRadius: 0.025))
        ring.geometry?.materials = [glowMat]
        ring.position = SCNVector3(0, 0, 0.17)
        scene.rootNode.addChildNode(ring)

        return scene
    }

    // MARK: 10. Android Phone (Authentic 3D Android Robot Logo)

    private static func buildAndroidPhone() -> SCNScene {
        let scene = SCNScene()
        // Signature Android Bugdroid Green (#3DDC84)
        let androidGreen = makePBRMaterial(
            diffuse: NSColor(srgbRed: 0.239, green: 0.863, blue: 0.518, alpha: 1.0),
            roughness: 0.22,
            metalness: 0.08
        )
        let eyeMat = makePBRMaterial(
            diffuse: NSColor(calibratedWhite: 0.98, alpha: 1.0),
            roughness: 0.10,
            metalness: 0.0,
            emission: NSColor(calibratedWhite: 0.90, alpha: 1.0)
        )

        let rootNode = SCNNode()

        // 1. Semi-spherical Dome Head
        let head = SCNNode(geometry: SCNSphere(radius: 0.30))
        head.geometry?.materials = [androidGreen]
        head.position = SCNVector3(0, 0.26, 0)
        rootNode.addChildNode(head)

        // 2. Head Flat Bottom Collar (so it looks like a clean half dome)
        let collar = SCNNode(geometry: SCNCylinder(radius: 0.30, height: 0.06))
        collar.geometry?.materials = [androidGreen]
        collar.position = SCNVector3(0, 0.23, 0)
        rootNode.addChildNode(collar)

        // 3. Two Expressive White Eyes
        let leftEye = SCNNode(geometry: SCNSphere(radius: 0.035))
        leftEye.geometry?.materials = [eyeMat]
        leftEye.position = SCNVector3(-0.11, 0.32, 0.26)
        rootNode.addChildNode(leftEye)

        let rightEye = SCNNode(geometry: SCNSphere(radius: 0.035))
        rightEye.geometry?.materials = [eyeMat]
        rightEye.position = SCNVector3(0.11, 0.32, 0.26)
        rootNode.addChildNode(rightEye)

        // 4. Two Angled Antennae
        let leftAntenna = SCNNode(geometry: SCNCylinder(radius: 0.016, height: 0.18))
        leftAntenna.geometry?.materials = [androidGreen]
        leftAntenna.position = SCNVector3(-0.13, 0.54, 0)
        leftAntenna.eulerAngles = SCNVector3(0, 0, Float.pi * 0.14)
        rootNode.addChildNode(leftAntenna)

        let rightAntenna = SCNNode(geometry: SCNCylinder(radius: 0.016, height: 0.18))
        rightAntenna.geometry?.materials = [androidGreen]
        rightAntenna.position = SCNVector3(0.13, 0.54, 0)
        rightAntenna.eulerAngles = SCNVector3(0, 0, -Float.pi * 0.14)
        rootNode.addChildNode(rightAntenna)

        // 5. Cylindrical Torso with Smooth Beveled Bottom
        let body = SCNNode(geometry: SCNCylinder(radius: 0.30, height: 0.44))
        body.geometry?.materials = [androidGreen]
        body.position = SCNVector3(0, -0.05, 0)
        rootNode.addChildNode(body)

        // 6. Pill Arms
        let leftArm = SCNNode(geometry: SCNCapsule(capRadius: 0.062, height: 0.34))
        leftArm.geometry?.materials = [androidGreen]
        leftArm.position = SCNVector3(-0.41, -0.06, 0)
        rootNode.addChildNode(leftArm)

        let rightArm = SCNNode(geometry: SCNCapsule(capRadius: 0.062, height: 0.34))
        rightArm.geometry?.materials = [androidGreen]
        rightArm.position = SCNVector3(0.41, -0.06, 0)
        rootNode.addChildNode(rightArm)

        // 7. Pill Legs
        let leftLeg = SCNNode(geometry: SCNCapsule(capRadius: 0.062, height: 0.24))
        leftLeg.geometry?.materials = [androidGreen]
        leftLeg.position = SCNVector3(-0.13, -0.38, 0)
        rootNode.addChildNode(leftLeg)

        let rightLeg = SCNNode(geometry: SCNCapsule(capRadius: 0.062, height: 0.24))
        rightLeg.geometry?.materials = [androidGreen]
        rightLeg.position = SCNVector3(0.13, -0.38, 0)
        rootNode.addChildNode(rightLeg)

        scene.rootNode.addChildNode(rootNode)
        return scene
    }

    // MARK: 11. Tablet (Generic ultra-slim slate archetype)

    private static func buildTablet() -> SCNScene {
        let scene = SCNScene()
        let frameMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.22, alpha: 1.0), roughness: 0.25, metalness: 0.85)
        let screenMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.03, alpha: 1.0), roughness: 0.05, metalness: 0.1)
        let lensMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.08, alpha: 1.0), roughness: 0.02, metalness: 0.8)

        // Slim wide tablet slab
        let tablet = SCNNode(geometry: SCNBox(width: 1.05, height: 1.45, length: 0.045, chamferRadius: 0.03))
        tablet.geometry?.materials = [screenMat, frameMat, frameMat, frameMat, frameMat, frameMat]
        scene.rootNode.addChildNode(tablet)

        // Front pinhole camera on top bezel
        let frontCam = SCNNode(geometry: SCNSphere(radius: 0.014))
        frontCam.geometry?.materials = [lensMat]
        frontCam.position = SCNVector3(0, 0.68, 0.024)
        scene.rootNode.addChildNode(frontCam)

        // Rear camera module in corner
        let rearCam = SCNNode(geometry: SCNBox(width: 0.12, height: 0.12, length: 0.016, chamferRadius: 0.02))
        rearCam.geometry?.materials = [frameMat]
        rearCam.position = SCNVector3(-0.40, 0.60, -0.03)
        scene.rootNode.addChildNode(rearCam)

        let lens = SCNNode(geometry: SCNCylinder(radius: 0.032, height: 0.012))
        lens.geometry?.materials = [lensMat]
        lens.eulerAngles = SCNVector3(Float.pi / 2.0, 0, 0)
        lens.position = SCNVector3(-0.40, 0.60, -0.04)
        scene.rootNode.addChildNode(lens)

        return scene
    }

    // MARK: 12. Monitor (Widescreen external display with pedestal)

    private static func buildMonitor() -> SCNScene {
        let scene = SCNScene()
        let metalMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.24, alpha: 1.0), roughness: 0.25, metalness: 0.85)
        let screenMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.06, alpha: 1.0), roughness: 0.15, metalness: 0.05)

        // Screen Panel
        let panel = SCNNode(geometry: SCNBox(width: 1.42, height: 0.88, length: 0.035, chamferRadius: 0.01))
        panel.geometry?.materials = [screenMat, metalMat, metalMat, metalMat, metalMat, metalMat]
        panel.position = SCNVector3(0, 0.12, 0)
        scene.rootNode.addChildNode(panel)

        // Stand Neck
        let neck = SCNNode(geometry: SCNBox(width: 0.09, height: 0.52, length: 0.04, chamferRadius: 0.01))
        neck.geometry?.materials = [metalMat]
        neck.position = SCNVector3(0, -0.22, -0.09)
        neck.eulerAngles = SCNVector3(-0.12, 0, 0)
        scene.rootNode.addChildNode(neck)

        // Desk Pedestal Base
        let base = SCNNode(geometry: SCNBox(width: 0.46, height: 0.018, length: 0.34, chamferRadius: 0.01))
        base.geometry?.materials = [metalMat]
        base.position = SCNVector3(0, -0.46, -0.04)
        scene.rootNode.addChildNode(base)

        return scene
    }

    // MARK: 13. Game Controller (Ergonomic twin-grip controller)

    private static func buildGameController() -> SCNScene {
        let scene = SCNScene()
        let bodyMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.20, alpha: 1.0), roughness: 0.38, metalness: 0.5)
        let accentMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.10, alpha: 1.0), roughness: 0.6, metalness: 0.0)
        let thumbstickMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.14, alpha: 1.0), roughness: 0.45, metalness: 0.2)
        let buttonMat = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.85, alpha: 1.0), roughness: 0.2, metalness: 0.1)

        // Center Chassis
        let center = SCNNode(geometry: SCNBox(width: 0.72, height: 0.44, length: 0.18, chamferRadius: 0.08))
        center.geometry?.materials = [bodyMat]
        scene.rootNode.addChildNode(center)

        // Left and Right Angled Hand Grips
        for sign: Float in [-1.0, 1.0] {
            let grip = SCNNode(geometry: SCNCapsule(capRadius: 0.11, height: 0.48))
            grip.geometry?.materials = [bodyMat]
            grip.position = SCNVector3(sign * 0.40, -0.15, 0.02)
            grip.eulerAngles = SCNVector3(0.15, 0, sign * 0.35)
            scene.rootNode.addChildNode(grip)
        }

        // Left D-Pad (cross)
        let dpadH = SCNNode(geometry: SCNBox(width: 0.14, height: 0.04, length: 0.025, chamferRadius: 0.005))
        dpadH.geometry?.materials = [accentMat]
        let dpadV = SCNNode(geometry: SCNBox(width: 0.04, height: 0.14, length: 0.025, chamferRadius: 0.005))
        dpadV.geometry?.materials = [accentMat]
        let dpad = SCNNode()
        dpad.addChildNode(dpadH)
        dpad.addChildNode(dpadV)
        dpad.position = SCNVector3(-0.20, -0.06, 0.10)
        scene.rootNode.addChildNode(dpad)

        // Dual Analog Thumbsticks
        for (xPos, yPos) in [(-0.10, 0.06), (0.12, -0.06)] {
            let stick = SCNNode(geometry: SCNCylinder(radius: 0.07, height: 0.05))
            stick.geometry?.materials = [thumbstickMat]
            stick.eulerAngles = SCNVector3(Float.pi / 2.0, 0, 0)
            stick.position = SCNVector3(Float(xPos), Float(yPos), 0.11)
            scene.rootNode.addChildNode(stick)
        }

        // Action Buttons (ABXY diamond)
        let buttonPositions: [(Float, Float)] = [
            (0.24, 0.12), (0.24, 0.00), (0.18, 0.06), (0.30, 0.06)
        ]
        for (bx, by) in buttonPositions {
            let btn = SCNNode(geometry: SCNSphere(radius: 0.022))
            btn.geometry?.materials = [buttonMat]
            btn.position = SCNVector3(bx, by, 0.10)
            scene.rootNode.addChildNode(btn)
        }

        return scene
    }

    // MARK: 14. Power Adapter / Charger
    private static func buildCharger() -> SCNScene {
        let scene = SCNScene()
        let whiteGloss = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.95, alpha: 1.0), roughness: 0.10, metalness: 0.05)
        let metalProng = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.88, alpha: 1.0), roughness: 0.15, metalness: 0.92)
        let portDark = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.12, alpha: 1.0), roughness: 0.80, metalness: 0.20)
        let glowGreen = makePBRMaterial(diffuse: NSColor(calibratedRed: 0.2, green: 0.95, blue: 0.4, alpha: 1.0), roughness: 0.1, metalness: 0.0, emission: NSColor(calibratedRed: 0.2, green: 0.95, blue: 0.4, alpha: 1.0))

        // Main Power Brick Body
        let brickGeom = SCNBox(width: 0.78, height: 0.78, length: 0.38, chamferRadius: 0.08)
        brickGeom.firstMaterial = whiteGloss
        let brickNode = SCNNode(geometry: brickGeom)
        scene.rootNode.addChildNode(brickNode)

        // Indented circular grip on body
        let gripGeom = SCNCylinder(radius: 0.18, height: 0.39)
        gripGeom.firstMaterial = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.92, alpha: 1.0), roughness: 0.35, metalness: 0.08)
        let gripNode = SCNNode(geometry: gripGeom)
        gripNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        scene.rootNode.addChildNode(gripNode)

        // Type-C / Cable Receptacle Port
        let portGeom = SCNBox(width: 0.28, height: 0.09, length: 0.06, chamferRadius: 0.03)
        portGeom.firstMaterial = portDark
        let portNode = SCNNode(geometry: portGeom)
        portNode.position = SCNVector3(0, -0.39, 0)
        scene.rootNode.addChildNode(portNode)

        // Status LED Indicator Dot
        let ledGeom = SCNSphere(radius: 0.025)
        ledGeom.firstMaterial = glowGreen
        let ledNode = SCNNode(geometry: ledGeom)
        ledNode.position = SCNVector3(0, -0.39, 0.10)
        scene.rootNode.addChildNode(ledNode)

        // Metal AC Wall Prongs
        let prongGeom = SCNBox(width: 0.04, height: 0.20, length: 0.02, chamferRadius: 0.005)
        prongGeom.firstMaterial = metalProng

        let prong1 = SCNNode(geometry: prongGeom)
        prong1.position = SCNVector3(-0.15, 0.45, 0)
        scene.rootNode.addChildNode(prong1)

        let prong2 = SCNNode(geometry: prongGeom)
        prong2.position = SCNVector3(0.15, 0.45, 0)
        scene.rootNode.addChildNode(prong2)

        return scene
    }
}
