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
        case .earbuds:
            return buildEarbuds()
        case .headphones:
            return buildHeadphones()
        case .speaker:
            return buildSpeaker()
        case .ssdDrive:
            return buildSSD()
        case .usbStick:
            return buildUSBStick()
        case .mouse:
            return buildMouse()
        case .keyboard:
            return buildKeyboard()
        case .phone:
            return buildPhone()
        case .generic:
            return buildGeneric()
        }
    }

    // MARK: 1. Earbuds (AirPods archetype)

    private static func buildEarbuds() -> SCNScene {
        let scene = SCNScene()
        let whiteGloss = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.96, alpha: 1.0), roughness: 0.12, metalness: 0.04)
        let chrome = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.85, alpha: 1.0), roughness: 0.05, metalness: 0.95)
        let acousticBlack = makePBRMaterial(diffuse: NSColor(calibratedWhite: 0.1, alpha: 1.0), roughness: 0.9, metalness: 0.0)

        for sign: Float in [-1.0, 1.0] {
            let bud = SCNNode()

            // Head dome
            let head = SCNNode(geometry: SCNSphere(radius: 0.22))
            head.geometry?.materials = [whiteGloss]
            bud.addChildNode(head)

            // In-ear tip
            let tip = SCNNode(geometry: SCNSphere(radius: 0.15))
            tip.geometry?.materials = [whiteGloss]
            tip.position = SCNVector3(-sign * 0.12, 0.02, 0.1)
            bud.addChildNode(tip)

            // Acoustic mesh dot
            let meshDot = SCNNode(geometry: SCNSphere(radius: 0.05))
            meshDot.geometry?.materials = [acousticBlack]
            meshDot.position = SCNVector3(-sign * 0.21, 0.04, 0.14)
            bud.addChildNode(meshDot)

            // Stem
            let stem = SCNNode(geometry: SCNCapsule(capRadius: 0.062, height: 0.42))
            stem.geometry?.materials = [whiteGloss]
            stem.position = SCNVector3(0, -0.25, 0)
            stem.eulerAngles = SCNVector3(0, 0, sign * 0.12)
            bud.addChildNode(stem)

            // Chrome charging ring
            let ring = SCNNode(geometry: SCNCylinder(radius: 0.065, height: 0.04))
            ring.geometry?.materials = [chrome]
            ring.position = SCNVector3(0, -0.42, 0)
            bud.addChildNode(ring)

            bud.position = SCNVector3(sign * 0.26, 0.08, 0)
            bud.eulerAngles = SCNVector3(0, -sign * 0.28, 0)
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
}
