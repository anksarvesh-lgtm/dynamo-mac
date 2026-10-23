//
//  LiquidBlobField.swift
//  LiquidDynamo
//
//  Content-driven organic blob-field generator, CPU SDF evaluator, and SwiftUI Shape.
//  Replaces geometric rectangles/capsules with multi-blob fluid metaball unions.
//

import AppKit
import Foundation
import SwiftUI

// MARK: - 1. Liquid Blob Lobe Descriptor

/// Analytic oriented ellipse descriptor representing a fluid blob in the organic multi-blob field.
public struct LiquidBlobLobe: Identifiable, Sendable, Equatable {
    public let id: Int
    public var name: String
    public var centerX: CGFloat
    public var centerY: CGFloat
    public var radiusX: CGFloat
    public var radiusY: CGFloat
    public var rotation: CGFloat     // Orientation in radians
    public var weight: CGFloat       // Density/pull weight (default 1.0)
    public var irregularity: CGFloat // Boundary ripple amplitude (0.0 to 1.0)
    public var isActive: Bool

    public init(
        id: Int,
        name: String = "Blob",
        centerX: CGFloat,
        centerY: CGFloat,
        radiusX: CGFloat,
        radiusY: CGFloat,
        rotation: CGFloat = 0.0,
        weight: CGFloat = 1.0,
        irregularity: CGFloat = 0.15,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.centerX = centerX
        self.centerY = centerY
        self.radiusX = radiusX
        self.radiusY = radiusY
        self.rotation = rotation
        self.weight = weight
        self.irregularity = irregularity
        self.isActive = isActive
    }

    /// Converts blob parameters into 8 floats for the Metal buffer:
    /// [centerX, centerY, radiusX, radiusY, rotation, weight, irregularity, isActive]
    public func toFloat8() -> [Float] {
        return [
            Float(centerX),
            Float(centerY),
            Float(max(1.0, radiusX)),
            Float(max(1.0, radiusY)),
            Float(rotation),
            Float(weight),
            Float(irregularity),
            isActive ? 1.0 : 0.0
        ]
    }
}

// MARK: - 2. CPU Signed Distance Field Evaluator

/// High-performance CPU evaluator for the multi-blob field.
/// Guarantees that hit-testing and gesture tracking match the Metal shader exactly.
public struct LiquidBlobFieldEvaluator {
    /// Evaluates distance from point `p` to an oriented ellipse with semi-axes `ab` and orientation `angle`.
    public static func sdOrientedEllipse(
        p: CGPoint,
        center: CGPoint,
        radiusX: CGFloat,
        radiusY: CGFloat,
        angle: CGFloat,
        irregularity: CGFloat = 0.0,
        seed: CGFloat = 42.0,
        time: CGFloat = 0.0
    ) -> CGFloat {
        let dx = p.x - center.x
        let dy = p.y - center.y
        let cosA = cos(angle)
        let sinA = sin(angle)
        let prX = dx * cosA + dy * sinA
        let prY = -dx * sinA + dy * cosA

        let a = max(radiusX, 1.0)
        let b = max(radiusY, 1.0)

        let pAbsX = abs(prX)
        let pAbsY = abs(prY)

        let k0 = sqrt((pAbsX * pAbsX) / (a * a) + (pAbsY * pAbsY) / (b * b))
        let k1 = sqrt((pAbsX * pAbsX) / (a * a * a * a) + (pAbsY * pAbsY) / (b * b * b * b))

        var rawDist = (k0 < 0.001) ? -min(a, b) : (k0 * (k0 - 1.0) / max(k1, 0.0001))

        if irregularity > 0.001 {
            let phi = atan2(prY, prX)
            let wave = sin(3.0 * phi + seed * 0.17) * 0.45
                     + sin(5.0 * phi - time * 1.8 + seed * 0.31) * 0.30
                     + cos(2.0 * phi + 1.2) * 0.25
            let envelope = max(0.0, min(1.0, (12.0 - abs(rawDist)) / 12.0))
            rawDist -= wave * irregularity * 3.5 * envelope
        }

        return rawDist
    }

    /// Cubic polynomial smooth minimum for organic fluid necking.
    public static func smin(_ a: CGFloat, _ b: CGFloat, k: CGFloat) -> CGFloat {
        guard k > 0.001 else { return min(a, b) }
        let h = max(k - abs(a - b), 0.0) / k
        return min(a, b) - h * h * h * k * (1.0 / 6.0)
    }

    /// Evaluates the complete composite distance across all active blobs.
    public static func evaluate(
        point: CGPoint,
        blobs: [LiquidBlobLobe],
        k: CGFloat = 18.0,
        seed: CGFloat = 42.0,
        time: CGFloat = 0.0
    ) -> CGFloat {
        var d: CGFloat = 10000.0
        var hasActive = false

        for (i, blob) in blobs.enumerated() where blob.isActive {
            let blobD = sdOrientedEllipse(
                p: point,
                center: CGPoint(x: blob.centerX, y: blob.centerY),
                radiusX: blob.radiusX,
                radiusY: blob.radiusY,
                angle: blob.rotation,
                irregularity: blob.irregularity,
                seed: seed + CGFloat(i) * 13.7,
                time: time
            ) - (blob.weight - 1.0) * 4.0

            if !hasActive {
                d = blobD
                hasActive = true
            } else {
                d = smin(d, blobD, k: k)
            }
        }

        return hasActive ? d : 10000.0
    }
}

// MARK: - 3. Liquid Blob Shape (SwiftUI Shape for Hit-Testing & Clipping)

/// SwiftUI Shape generated from the multi-blob field contour.
/// Evaluates the exact CPU SDF boundary so hover and click hit-testing works strictly
/// on the liquid fluid itself and never on transparent empty space.
public struct LiquidBlobShape: Shape {
    public var blobs: [LiquidBlobLobe]
    public var k: CGFloat
    public var seed: CGFloat
    public var time: CGFloat
    public var samplePointsCount: Int

    public init(
        blobs: [LiquidBlobLobe],
        k: CGFloat = 18.0,
        seed: CGFloat = 42.0,
        time: CGFloat = 0.0,
        samplePointsCount: Int = 48
    ) {
        self.blobs = blobs
        self.k = k
        self.seed = seed
        self.time = time
        self.samplePointsCount = samplePointsCount
    }

    public func path(in rect: CGRect) -> Path {
        let activeBlobs = blobs.filter { $0.isActive }
        guard !activeBlobs.isEmpty else { return Path() }

        // Compute centroid of active blobs
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var totalWeight: CGFloat = 0
        for b in activeBlobs {
            let w = max(0.1, b.weight)
            sumX += b.centerX * w
            sumY += b.centerY * w
            totalWeight += w
        }
        let center = CGPoint(x: sumX / totalWeight, y: sumY / totalWeight)

        // Find boundary radius along N radial directions via fast secant/binary search
        var perimeterPoints: [CGPoint] = []
        perimeterPoints.reserveCapacity(samplePointsCount)

        let step = (2.0 * .pi) / CGFloat(samplePointsCount)
        for i in 0..<samplePointsCount {
            let angle = CGFloat(i) * step
            let dir = CGPoint(x: cos(angle), y: sin(angle))

            // Ray march from center outward to find zero-crossing d(p) == 0
            var r: CGFloat = 10.0
            var maxR: CGFloat = 300.0
            for _ in 0..<8 {
                let testPoint = CGPoint(x: center.x + dir.x * r, y: center.y + dir.y * r)
                let dist = LiquidBlobFieldEvaluator.evaluate(
                    point: testPoint,
                    blobs: activeBlobs,
                    k: k,
                    seed: seed,
                    time: time
                )
                if abs(dist) < 0.75 { break }
                r += dist * 0.92
                if r > maxR { r = maxR; break }
                if r < 1.0 { r = 1.0; break }
            }
            perimeterPoints.append(CGPoint(x: center.x + dir.x * r, y: center.y + dir.y * r))
        }

        // Construct smooth closed Catmull-Rom spline / Bézier curve through boundary points
        var path = Path()
        guard perimeterPoints.count >= 3 else { return path }

        path.move(to: perimeterPoints[0])
        let n = perimeterPoints.count
        for i in 0..<n {
            let p0 = perimeterPoints[(i - 1 + n) % n]
            let p1 = perimeterPoints[i]
            let p2 = perimeterPoints[(i + 1) % n]
            let p3 = perimeterPoints[(i + 2) % n]

            // Catmull-Rom to Cubic Bézier control points conversion
            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6.0,
                y: p1.y + (p2.y - p0.y) / 6.0
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6.0,
                y: p2.y - (p3.y - p1.y) / 6.0
            )
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        path.closeSubpath()
        return path
    }

    /// Evaluates if a given point is strictly inside the liquid mass.
    public func contains(point: CGPoint) -> Bool {
        return LiquidBlobFieldEvaluator.evaluate(
            point: point,
            blobs: blobs,
            k: k,
            seed: seed,
            time: time
        ) <= 0.0
    }
}

// MARK: - 4. Content-Driven Lobe Generator

/// Generates a fluid collection of blobs driven entirely by measured layout elements.
/// Combines a flow stream from the hardware notch down into content-enclosing ellipse lobes.
public struct ContentDrivenBlobGenerator {
    /// Measured content cluster descriptor for layout elements (icon, title, subtitle, controls, slider).
    public struct ContentCluster: Sendable {
        public var id: String
        public var center: CGPoint
        public var size: CGSize
        public var kind: ClusterKind

        public enum ClusterKind: Sendable {
            case icon
            case textLine
            case controlGroup
            case sliderLevel
            case swellingDroplet
        }

        public init(id: String, center: CGPoint, size: CGSize, kind: ClusterKind) {
            self.id = id
            self.center = center
            self.size = size
            self.kind = kind
        }
    }

    /// Synthesizes up to 16 organic blobs given content clusters, notch geometry, emergence progress, and seed.
    public static func generateLobes(
        clusters: [ContentCluster],
        notchLipY: CGFloat,
        notchCenterX: CGFloat,
        notchWidth: CGFloat,
        emergenceProgress: CGFloat = 1.0, // 0.0 = resting in notch, 1.0 = fully emerged
        seed: CGFloat = 42.0,
        time: CGFloat = 0.0
    ) -> [LiquidBlobLobe] {
        var lobes: [LiquidBlobLobe] = []
        lobes.reserveCapacity(16)
        var nextId = 0

        let progress = max(0.0, min(1.0, emergenceProgress))
        guard progress > 0.01 else {
            return []
        }

        // Deterministic pseudo-random variation based on per-appearance seed
        let seedOffset1 = sin(seed * 1.37) * 4.0
        let seedOffset2 = cos(seed * 2.19) * 3.0
        let seedRotation = sin(seed * 0.73) * 0.06

        // Find primary content center of mass
        let targetY: CGFloat
        if let firstCluster = clusters.first {
            targetY = firstCluster.center.y
        } else {
            targetY = notchLipY + 44.0
        }

        // MARK: - Stream Chain: 3 blobs bridging from hardware notch down to content mass
        // Blob 0: Source nozzle right at notch bottom edge (starts pure black)
        let nozzleRadiusX = max(18.0, min(notchWidth * 0.38, 48.0 + CGFloat(clusters.count) * 4.0))
        let nozzleRadiusY = 12.0 * progress
        lobes.append(
            LiquidBlobLobe(
                id: nextId,
                name: "Stream Nozzle",
                centerX: notchCenterX + seedOffset1 * 0.3,
                centerY: notchLipY + 2.0,
                radiusX: nozzleRadiusX,
                radiusY: max(4.0, nozzleRadiusY),
                rotation: 0.0,
                weight: 1.15,
                irregularity: 0.12,
                isActive: progress > 0.05
            )
        )
        nextId += 1

        // Blob 1: Stream neck (stretched flow connection)
        let neckY = notchLipY + (targetY - notchLipY) * 0.42 * progress
        let neckThickness = max(10.0, 18.0 * progress + CGFloat(clusters.count) * 2.0)
        lobes.append(
            LiquidBlobLobe(
                id: nextId,
                name: "Stream Neck",
                centerX: notchCenterX + seedOffset2 * 0.5 * progress,
                centerY: neckY,
                radiusX: neckThickness,
                radiusY: max(8.0, (targetY - notchLipY) * 0.32 * progress),
                rotation: seedRotation * 0.8,
                weight: 0.95,
                irregularity: 0.20,
                isActive: progress > 0.15
            )
        )
        nextId += 1

        // Blob 2: Swelling bridge connecting neck to content
        let bridgeY = notchLipY + (targetY - notchLipY) * 0.78 * progress
        lobes.append(
            LiquidBlobLobe(
                id: nextId,
                name: "Stream Swell",
                centerX: notchCenterX - seedOffset1 * 0.3 * progress,
                centerY: bridgeY,
                radiusX: neckThickness * 1.35,
                radiusY: 16.0 * progress,
                rotation: -seedRotation * 0.6,
                weight: 1.05,
                irregularity: 0.18,
                isActive: progress > 0.25
            )
        )
        nextId += 1

        // MARK: - Content Enclosing Blobs
        for cluster in clusters {
            guard nextId < 16 else { break }

            let paddingX: CGFloat
            let paddingY: CGFloat
            let rot: CGFloat
            let irreg: CGFloat
            let weight: CGFloat

            switch cluster.kind {
            case .icon:
                paddingX = 14.0
                paddingY = 14.0
                rot = seedRotation
                irreg = 0.14
                weight = 1.1
            case .textLine:
                paddingX = 16.0
                paddingY = 10.0
                rot = seedRotation * 0.4
                irreg = 0.18
                weight = 1.0
            case .controlGroup:
                paddingX = 14.0
                paddingY = 12.0
                rot = -seedRotation * 0.5
                irreg = 0.15
                weight = 1.05
            case .sliderLevel:
                paddingX = 12.0
                paddingY = 8.0
                rot = 0.0
                irreg = 0.10
                weight = 0.95
            case .swellingDroplet:
                paddingX = 20.0
                paddingY = 18.0
                rot = seedRotation * 1.2
                irreg = 0.25
                weight = 1.25
            }

            let rx = max(12.0, (cluster.size.width / 2.0 + paddingX) * progress)
            let ry = max(10.0, (cluster.size.height / 2.0 + paddingY) * progress)

            lobes.append(
                LiquidBlobLobe(
                    id: nextId,
                    name: "Content \(cluster.id)",
                    centerX: cluster.center.x,
                    centerY: cluster.center.y,
                    radiusX: rx,
                    radiusY: ry,
                    rotation: rot,
                    weight: weight,
                    irregularity: irreg,
                    isActive: progress > 0.10
                )
            )
            nextId += 1
        }

        // Fill remaining lobe slots up to 16 with inactive placeholders
        while nextId < 16 {
            lobes.append(
                LiquidBlobLobe(
                    id: nextId,
                    name: "Unused",
                    centerX: 0,
                    centerY: 0,
                    radiusX: 1,
                    radiusY: 1,
                    isActive: false
                )
            )
            nextId += 1
        }

        return lobes
    }
}
