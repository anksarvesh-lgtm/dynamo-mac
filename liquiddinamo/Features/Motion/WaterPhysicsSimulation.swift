//
//  WaterPhysicsSimulation.swift
//  LiquidDynamo
//
//  Closed-loop water-physics simulation using Verlet integration,
//  area-conservation pressure forces, boundary springs, surface tension,
//  content soft barrier, and notch source pinning.
//

import AppKit
import Combine
import Foundation
import SwiftUI

// MARK: - 1. Water Physics Presets

public enum WaterPhysicsPreset: String, CaseIterable, Identifiable, Sendable {
    case water = "Water"
    case jelly = "Jelly"
    case honey = "Honey"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .water:
            return "Natural fluid sloshing, 2-3 oscillations, settles in ~0.8s with 5-10% overshoot."
        case .jelly:
            return "Rubbery, high surface tension, bouncy elastic oscillations."
        case .honey:
            return "Viscous, heavily damped creeping flow with near zero overshoot."
        }
    }
}

// MARK: - 2. Water Boundary Particle

public struct WaterParticle: Sendable {
    public var position: CGPoint
    public var prevPosition: CGPoint
    public var acceleration: CGPoint = .zero
    public var normal: CGPoint = .zero
    public var isPinned: Bool = false
    public var adhesion: CGFloat = 0.0
    public var rippleHeight: CGFloat = 0.0
    public var rippleVelocity: CGFloat = 0.0

    public init(position: CGPoint, prevPosition: CGPoint? = nil) {
        self.position = position
        self.prevPosition = prevPosition ?? position
    }
}

// MARK: - 3. Water Lifecycle State (Step C)

public enum WaterLifecycleState: String, CaseIterable, Identifiable, Sendable {
    case closed = "Closed"
    case opening = "Opening"
    case open = "Open"
    case closing = "Closing"

    public var id: String { rawValue }
}

// MARK: - 4. Physics Simulation Diagnostics

public struct WaterSimulationMetrics: Sendable {
    public var currentArea: CGFloat = 0.0
    public var targetArea: CGFloat = 0.0
    public var kineticEnergy: CGFloat = 0.0
    public var isSleeping: Bool = false
    public var overshootPercentage: CGFloat = 0.0
    public var settlingTimeSeconds: TimeInterval = 0.0
    public var oscillationCount: Int = 0
    public var subStepsPerFrame: Int = 4
    public var lifecycle: WaterLifecycleState = .open
    public var flowProgress: CGFloat = 1.0
}

// MARK: - 5. Water Physics Simulation Engine

@MainActor
public final class WaterPhysicsSimulation: ObservableObject {
    public static let shared = WaterPhysicsSimulation()

    // MARK: - Observable State
    @Published public private(set) var particles: [WaterParticle] = []
    @Published public private(set) var currentPath: Path = Path()
    @Published public private(set) var metrics: WaterSimulationMetrics = .init()
    @Published public var preset: WaterPhysicsPreset = .water {
        didSet { applyPreset(preset) }
    }

    // MARK: - Adjustable Physical Parameters (Sliders)
    @Published public var pointCount: Int = 72 {
        didSet {
            if pointCount != oldValue {
                rebuildParticles()
            }
        }
    }
    @Published public var gravity: CGFloat = 180.0
    @Published public var pressureStiffness: CGFloat = 1800.0
    @Published public var surfaceTension: CGFloat = 420.0
    @Published public var damping: CGFloat = 0.115
    @Published public var springStiffness: CGFloat = 420.0
    @Published public var barrierStiffness: CGFloat = 1200.0
    @Published public var timeStep: CGFloat = 1.0 / 240.0
    @Published public var speedMultiplier: CGFloat = 1.0 // 1.0x, 0.5x, 0.25x, 0.1x
    @Published public var seed: UInt64 = 42

    // Content target rectangle & geometry
    @Published public var contentRect: CGRect = CGRect(x: 280, y: 50, width: 240, height: 60) {
        didSet {
            if contentRect != oldValue {
                targetRectChanged()
            }
        }
    }
    @Published public var contentPadding: CGFloat = 18.0
    @Published public var notchLipY: CGFloat = 32.0
    @Published public var notchWidth: CGFloat = 190.0
    @Published public var canvasSize: CGSize = CGSize(width: 800, height: 450)
    @Published public var cursorPushEnabled: Bool = true
    @Published public var cursorPosition: CGPoint = .zero
    @Published public var isInteracting: Bool = false
    @Published public var isReduceMotion: Bool = false

    // MARK: - Lifecycle State (Step C)
    @Published public private(set) var lifecycleState: WaterLifecycleState = .open
    @Published public private(set) var flowProgress: CGFloat = 1.0
    @Published public private(set) var contentAlpha: CGFloat = 1.0
    @Published public var autoLifecycleObserver: Bool = true

    private var sizingCancellable: AnyCancellable?
    private var stateCancellable: AnyCancellable?

    // Timing & Metrics measurement state
    private var stepStartTime: CFAbsoluteTime = 0
    private var lastFrameTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var initialAreaForStep: CGFloat = 0
    private var peakAreaForStep: CGFloat = 0
    private var previousAreaForRate: CGFloat = 0
    private var settlingRecorded: Bool = false
    private var previousAreaErrorSign: Int = 0
    private var zeroCrossingCount: Int = 0
    private var consecutiveSleepFrames: Int = 0
    private let sleepThreshold: CGFloat = 0.008

    public init() {
        applyPreset(.water)
        rebuildParticles()
    }

    // MARK: - Sizing Pipeline Integration (Step B)

    public var reduceMotionProvider: (() -> Bool)? = nil
    public var notchGeometryProvider: (() -> (notchHeight: CGFloat, notchWidth: CGFloat))? = nil

    /// Connects the water physics model to the real content sizing pipeline.
    public func startSizingPipelineObserver() {
        #if !DEBUG_STANDALONE
        sizingCancellable = IslandController.shared.$targetSize
            .receive(on: RunLoop.main)
            .sink { [weak self] newSize in
                self?.updateFromSizingPipeline(targetSize: newSize)
            }

        stateCancellable = IslandController.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                guard let self = self, self.autoLifecycleObserver else { return }
                if newState == .idle {
                    self.close()
                } else {
                    self.open()
                }
            }
        #endif
    }

    /// Updates target content geometry from measured content size.
    public func updateFromSizingPipeline(targetSize: CGSize) {
        guard targetSize.width > 0 && targetSize.height > 0 else { return }

        let lipY: CGFloat
        let nWidth: CGFloat
        if let custom = notchGeometryProvider?() {
            lipY = max(32.0, custom.notchHeight)
            nWidth = max(160.0, custom.notchWidth)
        } else {
            #if !DEBUG_STANDALONE
            let geom = NotchSafeAreaEngine.shared.currentGeometry
            lipY = max(32.0, geom.notchHeight)
            nWidth = max(160.0, geom.rawNotchWidth)
            #else
            lipY = 32.0
            nWidth = 190.0
            #endif
        }

        self.notchLipY = lipY
        self.notchWidth = nWidth

        let topY = lipY + 6.0
        let centerX = canvasSize.width * 0.5
        let newContentRect = CGRect(
            x: centerX - targetSize.width * 0.5,
            y: topY,
            width: targetSize.width,
            height: targetSize.height
        )

        updateContentRect(newContentRect)

        if lifecycleState == .closed || lifecycleState == .closing {
            open()
        }
    }

    /// Retargets the liquid to enclose a new content rectangle.
    public func updateContentRect(_ newRect: CGRect) {
        let isReduce: Bool
        if let provider = reduceMotionProvider {
            isReduce = provider()
        } else {
            #if !DEBUG_STANDALONE
            isReduce = IslandMotion.shared.isReduceMotionActive
            #else
            isReduce = false
            #endif
        }
        self.isReduceMotion = isReduce

        if isReduce {
            easeDirectlyToTarget(newRect)
            return
        }

        // Retarget smoothly without restarting particles or jumping
        if self.contentRect != newRect {
            self.contentRect = newRect
        }
    }

    // MARK: - Open & Close Lifecycle Operations (Step C)

    /// Opens the liquid with source flow emerging from the notch lip.
    public func open() {
        let isReduce: Bool
        if self.isReduceMotion {
            isReduce = true
        } else if let provider = reduceMotionProvider {
            isReduce = provider()
        } else {
            #if !DEBUG_STANDALONE
            isReduce = IslandMotion.shared.isReduceMotionActive
            #else
            isReduce = false
            #endif
        }
        self.isReduceMotion = isReduce

        if isReduce {
            easeDirectlyToTarget(contentRect)
            lifecycleState = .open
            flowProgress = 1.0
            contentAlpha = 1.0
            metrics.isSleeping = true
            return
        }

        if lifecycleState == .open {
            return
        }

        if lifecycleState == .closing {
            // Interrupt closing smoothly: reverse direction without restarting particles
            lifecycleState = .opening
            wake()
            return
        }

        if lifecycleState == .closed {
            // Start from compact source stream at notch lip
            lifecycleState = .opening
            flowProgress = 0.0
            contentAlpha = 0.0
            initializeSourceStream()
            wake()
        }
    }

    /// Drains the liquid back through the notch source with tapered tail and absorption ripple.
    public func close() {
        let isReduce: Bool
        if self.isReduceMotion {
            isReduce = true
        } else if let provider = reduceMotionProvider {
            isReduce = provider()
        } else {
            #if !DEBUG_STANDALONE
            isReduce = IslandMotion.shared.isReduceMotionActive
            #else
            isReduce = false
            #endif
        }
        self.isReduceMotion = isReduce

        if isReduce {
            snapToNotchMeniscus()
            lifecycleState = .closed
            flowProgress = 0.0
            contentAlpha = 0.0
            metrics.isSleeping = true
            return
        }

        if lifecycleState == .closed {
            return
        }

        if lifecycleState == .opening {
            // Interrupt opening smoothly: reverse direction without jumping
            lifecycleState = .closing
            wake()
            return
        }

        if lifecycleState == .open {
            lifecycleState = .closing
            wake()
        }
    }

    /// Alias for close() adhering to drain physics semantics.
    public func drain() {
        close()
    }

    /// Toggles between open and close lifecycle states.
    public func toggleLifecycle() {
        if lifecycleState == .closed || lifecycleState == .closing {
            open()
        } else {
            close()
        }
    }

    /// Configures particle loop as a resting source meniscus at the notch lip.
    public func snapToNotchMeniscus() {
        let n = max(64, min(96, particles.isEmpty ? pointCount : particles.count))
        let centerX = contentRect.midX
        let rx: CGFloat = min(notchWidth * 0.20, 26.0)
        let ry: CGFloat = 2.0

        if particles.count != n {
            particles = (0..<n).map { _ in WaterParticle(position: CGPoint(x: centerX, y: notchLipY)) }
        }

        for i in 0..<n {
            let theta = (CGFloat(i) / CGFloat(n)) * (2.0 * .pi)
            let px = centerX + rx * sin(theta)
            var py = notchLipY + max(0.0, ry * (1.0 - cos(theta)) * 0.5)

            var isPinned = false
            var adhesion: CGFloat = 0.0
            if i <= 2 || i >= n - 2 {
                py = notchLipY
                isPinned = true
                adhesion = 1.0
            }

            particles[i].position = CGPoint(x: px, y: py)
            particles[i].prevPosition = CGPoint(x: px, y: py)
            particles[i].acceleration = .zero
            particles[i].isPinned = isPinned
            particles[i].adhesion = adhesion
            particles[i].rippleHeight = 0
            particles[i].rippleVelocity = 0
        }

        recomputeNormals()
        updatePath()
    }

    /// Initializes a narrow source stream emerging from the notch lip.
    public func initializeSourceStream() {
        let n = max(64, min(96, pointCount))
        let centerX = contentRect.midX
        let rx: CGFloat = min(notchWidth * 0.18, 24.0)
        let ry: CGFloat = 22.0

        var newParticles: [WaterParticle] = []
        newParticles.reserveCapacity(n)

        for i in 0..<n {
            let theta = (CGFloat(i) / CGFloat(n)) * (2.0 * .pi)
            let px = centerX + rx * sin(theta)
            var py = notchLipY + ry * (1.0 - cos(theta)) * 0.5

            var isPinned = false
            var adhesion: CGFloat = 0.0
            if i <= 2 || i >= n - 2 {
                py = notchLipY
                isPinned = true
                adhesion = 1.0
            }

            var p = WaterParticle(position: CGPoint(x: px, y: py))
            p.isPinned = isPinned
            p.adhesion = adhesion
            newParticles.append(p)
        }

        self.particles = newParticles
        recomputeNormals()
        updatePath()
    }

    /// Reduce Motion: skip physics oscillations and directly ease to resting contour.
    public func easeDirectlyToTarget(_ newRect: CGRect) {
        self.contentRect = newRect
        guard particles.count >= 3 else {
            rebuildParticles()
            return
        }

        let center = CGPoint(x: newRect.midX, y: max(notchLipY + 40, newRect.midY))
        let rx = max(newRect.width * 0.5 + contentPadding, 50.0)
        let ry = max(newRect.height * 0.5 + contentPadding, 30.0)
        let notchLeft = center.x - (notchWidth * 0.45)
        let notchRight = center.x + (notchWidth * 0.45)

        for i in 0..<particles.count {
            let theta = (CGFloat(i) / CGFloat(particles.count)) * (2.0 * .pi)
            let px = center.x + rx * cos(theta)
            var py = center.y + ry * sin(theta)

            var isPinned = false
            var adhesion: CGFloat = 0.0

            if py <= notchLipY + 4.0 && px >= notchLeft && px <= notchRight {
                py = notchLipY
                isPinned = true
                adhesion = 1.0
            } else if py < notchLipY {
                py = notchLipY
            }

            particles[i].position = CGPoint(x: px, y: py)
            particles[i].prevPosition = CGPoint(x: px, y: py)
            particles[i].acceleration = .zero
            particles[i].isPinned = isPinned
            particles[i].adhesion = adhesion
            particles[i].rippleHeight = 0
            particles[i].rippleVelocity = 0
        }

        recomputeNormals()
        updatePath()
        let curArea = calculateEnclosedArea()
        peakAreaForStep = curArea
        metrics.currentArea = curArea
        metrics.targetArea = calculateTargetArea()
        metrics.overshootPercentage = 0.0
        metrics.kineticEnergy = 0.0
        metrics.isSleeping = true
    }

    // MARK: - Presets Application

    public func applyPreset(_ p: WaterPhysicsPreset) {
        switch p {
        case .water:
            gravity = 160.0
            pressureStiffness = 1850.0
            surfaceTension = 440.0
            damping = 0.155
            springStiffness = 380.0
            barrierStiffness = 1200.0
        case .jelly:
            gravity = 120.0
            pressureStiffness = 2600.0
            surfaceTension = 850.0
            damping = 0.068
            springStiffness = 880.0
            barrierStiffness = 1600.0
        case .honey:
            gravity = 240.0
            pressureStiffness = 1200.0
            surfaceTension = 300.0
            damping = 0.280
            springStiffness = 280.0
            barrierStiffness = 1000.0
        }
        wake()
    }

    // MARK: - Particle Loop Initialization

    public func rebuildParticles() {
        let count = max(64, min(96, pointCount))
        let center = CGPoint(x: contentRect.midX, y: max(notchLipY + 40, contentRect.midY))
        let rx = max(contentRect.width * 0.5 + contentPadding, 50.0)
        let ry = max(contentRect.height * 0.5 + contentPadding, 30.0)

        var newParticles: [WaterParticle] = []
        newParticles.reserveCapacity(count)

        let notchLeft = center.x - (notchWidth * 0.45)
        let notchRight = center.x + (notchWidth * 0.45)

        for i in 0..<count {
            // Angle around loop (counter-clockwise)
            let theta = (CGFloat(i) / CGFloat(count)) * (2.0 * .pi)
            let px = center.x + rx * cos(theta)
            var py = center.y + ry * sin(theta)

            // Pin top points adhering to the notch lip
            var isPinned = false
            var adhesion: CGFloat = 0.0

            if py <= notchLipY + 4.0 && px >= notchLeft && px <= notchRight {
                py = notchLipY
                isPinned = true
                adhesion = 1.0
            } else if py < notchLipY {
                py = notchLipY
            }

            var p = WaterParticle(position: CGPoint(x: px, y: py))
            p.isPinned = isPinned
            p.adhesion = adhesion
            newParticles.append(p)
        }

        self.particles = newParticles
        recomputeNormals()
        updatePath()
        targetRectChanged()
        wake()
    }

    public func wake() {
        lastFrameTime = CFAbsoluteTimeGetCurrent()
        metrics.isSleeping = false
        consecutiveSleepFrames = 0
    }

    /// Advances the simulation by elapsed frame time if not sleeping.
    public func stepFrameIfNeeded() {
        guard !metrics.isSleeping else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let dt = min(now - lastFrameTime, 0.05)
        lastFrameTime = now
        step(deltaTime: dt > 0.001 ? dt : (1.0 / 60.0))
    }

    private func targetRectChanged() {
        stepStartTime = CFAbsoluteTimeGetCurrent()
        initialAreaForStep = calculateEnclosedArea()
        peakAreaForStep = initialAreaForStep
        previousAreaForRate = initialAreaForStep
        settlingRecorded = false
        zeroCrossingCount = 0
        previousAreaErrorSign = 0
        wake()
    }

    // MARK: - Simulation Stepper (Fixed Timestep & Substepping)

    public func step(deltaTime: TimeInterval) {
        if metrics.isSleeping && !isInteracting {
            return
        }

        // Fixed physical dt = 1/240 s for exact symplectic Verlet conservation
        let physicsDt = timeStep
        // Number of substeps scaled by speedMultiplier for exact bit-for-bit slow-motion parity
        let effectiveDt = (deltaTime > 0 ? deltaTime : 1.0 / 60.0) * Double(speedMultiplier)
        let subSteps = max(1, min(16, Int(round(effectiveDt / Double(timeStep)))))

        for _ in 0..<subSteps {
            subStep(dt: physicsDt)
        }

        // Update rendered smooth path
        updatePath()

        // Energy and sleep check
        evaluateEnergyAndMetrics()
    }

    private func subStep(dt: CGFloat) {
        guard particles.count >= 3 else { return }

        let fullTargetArea = calculateTargetArea()

        // Advance lifecycle flow progress (calibrated so small, medium, and large reach 95% in 0.35s - 0.45s)
        if lifecycleState == .opening {
            let volumeRatio = min(1.0, max(0.0, (fullTargetArea - 22000.0) / 75000.0))
            let flowRate: CGFloat = 2.25 + 0.95 * volumeRatio
            flowProgress = min(1.0, flowProgress + flowRate * dt)
            if flowProgress >= 1.0 {
                lifecycleState = .open
            }
        } else if lifecycleState == .closing {
            let drainRate: CGFloat = 2.6 // ~0.38s to drain (smooth tapered funnel collapse)
            flowProgress = max(0.0, flowProgress - drainRate * dt)
            if flowProgress <= 0.02 {
                lifecycleState = .closed
                flowProgress = 0.0
                contentAlpha = 0.0
                snapToNotchMeniscus()
                // Last of the water absorbed with a small ripple across the notch meniscus
                sendRipple(at: CGPoint(x: contentRect.midX, y: notchLipY), impulse: 5.0)
                evaluateEnergyAndMetrics()
                metrics.isSleeping = true
                return
            }
        }

        let n = particles.count
        let currentArea = calculateEnclosedArea()
        let effectiveTargetArea = fullTargetArea * max(0.01, flowProgress)
        let areaError = effectiveTargetArea - currentArea

        // Track oscillations across target area
        let errorSign = areaError > 0 ? 1 : (areaError < 0 ? -1 : 0)
        if previousAreaErrorSign != 0 && errorSign != previousAreaErrorSign {
            zeroCrossingCount += 1
        }
        previousAreaErrorSign = errorSign

        if currentArea > peakAreaForStep {
            peakAreaForStep = currentArea
        }

        let linearScale = sqrt(max(100.0, effectiveTargetArea))
        let kp = pressureStiffness / 110.0
        // Derivative damping smoothly activates as volume approaches target area (70% - 100%)
        let kdActivation = max(0.0, min(1.0, (currentArea - fullTargetArea * 0.70) / max(100.0, fullTargetArea * 0.30)))
        let kdRatio = (0.040 + 0.160 * min(1.0, 52000.0 / max(100.0, fullTargetArea))) * kdActivation
        let kd = kp * kdRatio
        let areaRate = (currentArea - previousAreaForRate) / max(0.0001, dt)
        previousAreaForRate = currentArea
        let pressureMagnitude = (areaError / linearScale) * kp - (areaRate / linearScale) * kd
        let clampedPressure = max(-8000.0, min(8000.0, pressureMagnitude))

        // Content Safe Rect bounds with padding
        let safeMargin = contentPadding * 0.75
        let safeMinX = contentRect.minX - safeMargin
        let safeMaxX = contentRect.maxX + safeMargin
        let safeMinY = contentRect.minY - contentPadding * 0.25
        let safeMaxY = contentRect.maxY + safeMargin

        let targetW = contentRect.width + contentPadding * 2.0
        let targetH = contentRect.height + contentPadding * 2.0
        let targetPerimeter = 2.0 * (targetW + targetH) * 1.06
        let restScale = max(0.12, sqrt(max(0.01, flowProgress)))
        let restLength = (targetPerimeter / CGFloat(n)) * restScale

        // Barrier strength phased by lifecycle
        let barrierStrength: CGFloat
        switch lifecycleState {
        case .open:
            barrierStrength = 1.0
        case .closed:
            barrierStrength = 0.0
        case .opening:
            barrierStrength = max(0.0, min(1.0, (flowProgress - 0.25) / 0.75))
        case .closing:
            barrierStrength = max(0.0, min(1.0, (flowProgress - 0.20) / 0.80))
        }

        let notchCenterX = contentRect.midX

        // 1. Accumulate forces
        for i in 0..<n {
            if particles[i].isPinned {
                particles[i].acceleration = .zero
                continue
            }

            var f = CGPoint.zero

            // A. Gravity (pulls downward towards bottom of window for natural pooling)
            f.y += gravity

            // Downward source flow momentum during stream emergence
            if lifecycleState == .opening {
                f.y += (1.0 - flowProgress * 0.7) * 440.0
            }

            // B. Internal Pressure (pushes outward along surface normal)
            let normal = particles[i].normal
            f.x += normal.x * clampedPressure
            f.y += normal.y * clampedPressure

            // C. Surface Tension (Laplacian smoothing along the loop)
            let prevIdx = (i - 1 + n) % n
            let nextIdx = (i + 1) % n
            let pPrev = particles[prevIdx].position
            let pNext = particles[nextIdx].position
            let pCurr = particles[i].position

            let laplacianX = (pPrev.x + pNext.x) * 0.5 - pCurr.x
            let laplacianY = (pPrev.y + pNext.y) * 0.5 - pCurr.y
            let stCoeff = surfaceTension * (9.5 / max(4.0, restLength))
            f.x += laplacianX * stCoeff
            f.y += laplacianY * stCoeff

            // D. Boundary Springs connecting neighboring points
            let dPrevX = pPrev.x - pCurr.x
            let dPrevY = pPrev.y - pCurr.y
            let distPrev = max(0.01, hypot(dPrevX, dPrevY))
            let dNextX = pNext.x - pCurr.x
            let dNextY = pNext.y - pCurr.y
            let distNext = max(0.01, hypot(dNextX, dNextY))
            f.x += (dPrevX / distPrev) * (distPrev - restLength) * springStiffness * 0.5
            f.y += (dPrevY / distPrev) * (distPrev - restLength) * springStiffness * 0.5
            f.x += (dNextX / distNext) * (distNext - restLength) * springStiffness * 0.5
            f.y += (dNextY / distNext) * (distNext - restLength) * springStiffness * 0.5

            // E. Drain Suction Pull (Source drain behavior during closing: body shrinks, tail stretches to notch)
            if lifecycleState == .closing {
                let drainPullX = (1.0 - flowProgress * 0.2) * 950.0
                let drainPullY = (1.0 - flowProgress * 0.5) * 420.0
                let dx = notchCenterX - pCurr.x
                let dy = notchLipY - pCurr.y
                let dist = max(1.0, hypot(dx, dy))
                f.x += (dx / dist) * drainPullX
                f.y += (dy / dist) * drainPullY
            }

            // F. Soft Barrier: keep water outside the content safe rectangle
            if barrierStrength > 0.0 && pCurr.x > safeMinX && pCurr.x < safeMaxX && pCurr.y > safeMinY && pCurr.y < safeMaxY {
                let contentCenter = CGPoint(x: contentRect.midX, y: contentRect.midY)
                let halfW = max(20.0, contentRect.width * 0.5)
                let halfH = max(15.0, contentRect.height * 0.5)

                let normX = (pCurr.x - contentCenter.x) / halfW
                let normY = (pCurr.y - contentCenter.y) / halfH
                let normDist = max(0.01, hypot(normX, normY))

                let pushX = normX / normDist
                let pushY = normY > 0 ? (normY / normDist) : 0.0

                let penetration = max(0.0, 1.25 - normDist) * contentPadding * 3.0
                f.x += pushX * penetration * barrierStiffness * barrierStrength
                f.y += pushY * penetration * barrierStiffness * barrierStrength
            }

            // G. Optional Cursor Push & Ripple
            if cursorPushEnabled && cursorPosition != .zero {
                let dx = pCurr.x - cursorPosition.x
                let dy = pCurr.y - cursorPosition.y
                let distSq = dx * dx + dy * dy
                if distSq < 45.0 * 45.0 && distSq > 1.0 {
                    let dist = sqrt(distSq)
                    let force = (45.0 - dist) * 18.0
                    f.x += (dx / dist) * force
                    f.y += (dy / dist) * force
                }
            }

            // Clamp force to prevent physical instability / explosion
            let maxForce: CGFloat = 80000.0
            f.x = max(-maxForce, min(maxForce, f.x))
            f.y = max(-maxForce, min(maxForce, f.y))

            particles[i].acceleration = f
        }

        // 2. Verlet Integration with time-scaled damping and faster collapse
        let dt2 = dt * dt
        let effectiveDamping: CGFloat
        if lifecycleState == .closing {
            effectiveDamping = damping * 1.65 // Faster, heavily damped collapse
        } else if areaError < 0 {
            effectiveDamping = damping * 1.35 // Balanced overshoot braking above target volume
        } else {
            effectiveDamping = damping
        }
        let friction = pow(max(0.0, 1.0 - effectiveDamping), dt * 60.0)

        for i in 0..<n {
            guard !particles[i].isPinned else { continue }

            let pos = particles[i].position
            let prev = particles[i].prevPosition
            let acc = particles[i].acceleration

            // Max velocity clamping (scaled proportionally with physical dt to guarantee frame-rate & slow-mo parity)
            let maxVelPerSubstep: CGFloat = 5.7
            let maxDisp = maxVelPerSubstep * (dt / (1.0 / 240.0))
            var velX = (pos.x - prev.x) * friction
            var velY = (pos.y - prev.y) * friction
            velX = max(-maxDisp, min(maxDisp, velX))
            velY = max(-maxDisp, min(maxDisp, velY))

            var nextX = pos.x + velX + acc.x * dt2
            var nextY = pos.y + velY + acc.y * dt2

            // Hard constraints:
            // - Cannot enter physical notch zone (y >= notchLipY)
            if nextY < notchLipY {
                nextY = notchLipY
                velY = 0
            }

            // - Cannot encroach inside the content rectangle (guaranteed enclosure)
            if barrierStrength >= 0.7 {
                let minClearance: CGFloat = 6.0
                let contentSafeBox = contentRect.insetBy(dx: -minClearance, dy: -minClearance)
                if contentSafeBox.contains(CGPoint(x: nextX, y: nextY)) {
                    let halfW = max(20.0, contentSafeBox.width * 0.5)
                    let halfH = max(15.0, contentSafeBox.height * 0.5)
                    let normX = abs(nextX - contentSafeBox.midX) / halfW
                    let normY = abs(nextY - contentSafeBox.midY) / halfH

                    if normX >= normY || nextY <= contentSafeBox.midY {
                        if nextX < contentSafeBox.midX {
                            nextX = contentSafeBox.minX
                        } else {
                            nextX = contentSafeBox.maxX
                        }
                        velX = 0
                    } else {
                        nextY = contentSafeBox.maxY
                        velY = 0
                    }
                }
            }

            // Strict displacement per substep clamping to prevent velocity explosions or mid-flight jumps
            let dispX = nextX - pos.x
            let dispY = nextY - pos.y
            let disp = hypot(dispX, dispY)
            if disp > maxDisp {
                nextX = pos.x + (dispX / disp) * maxDisp
                nextY = pos.y + (dispY / disp) * maxDisp
            }

            // - Cannot leave canvas bounds
            nextX = max(10.0, min(canvasSize.width - 10.0, nextX))
            nextY = max(notchLipY, min(canvasSize.height - 10.0, nextY))

            particles[i].prevPosition = pos
            particles[i].position = CGPoint(x: nextX, y: nextY)
        }

        // 3. Gentle spring distance relaxation pass (Preserves perimeter cohesion)
        relaxSprings()

        // 4. Update normals
        recomputeNormals()

        // 5. Propagate boundary ripples
        propagateBoundaryWave(dt: dt)
    }

    private func relaxSprings() {
        let n = particles.count
        guard n > 2 else { return }

        let targetW = contentRect.width + contentPadding * 2.0
        let targetH = contentRect.height + contentPadding * 2.0
        let targetPerimeter = 2.0 * (targetW + targetH)
        let baseRestLength = targetPerimeter / CGFloat(n)
        let restScale = max(0.12, sqrt(max(0.01, flowProgress)))
        let restLength = baseRestLength * restScale

        let iterations = 1
        for _ in 0..<iterations {
            for i in 0..<n {
                let nextIdx = (i + 1) % n
                let p1 = particles[i].position
                let p2 = particles[nextIdx].position

                let dx = p2.x - p1.x
                let dy = p2.y - p1.y
                let dist = max(0.1, sqrt(dx * dx + dy * dy))
                let delta = dist - restLength

                let factor = (delta / dist) * 0.05
                let offsetX = dx * factor
                let offsetY = dy * factor

                if !particles[i].isPinned {
                    particles[i].position.x += offsetX
                    particles[i].position.y += offsetY
                }
                if !particles[nextIdx].isPinned {
                    particles[nextIdx].position.x -= offsetX
                    particles[nextIdx].position.y -= offsetY
                }
            }
        }

        // Hard boundary enforcement after spring relaxation
        for i in 0..<n {
            if particles[i].isPinned {
                particles[i].position.y = notchLipY
            } else if particles[i].position.y < notchLipY {
                particles[i].position.y = notchLipY
            }
        }
    }

    private func propagateBoundaryWave(dt: CGFloat) {
        let n = particles.count
        let waveSpeed: CGFloat = 160.0
        let waveDamping: CGFloat = 0.96

        for i in 0..<n {
            let prevIdx = (i - 1 + n) % n
            let nextIdx = (i + 1) % n
            let laplacian = particles[prevIdx].rippleHeight + particles[nextIdx].rippleHeight - 2.0 * particles[i].rippleHeight
            particles[i].rippleVelocity += laplacian * waveSpeed * dt
            particles[i].rippleVelocity *= waveDamping
            particles[i].rippleHeight += particles[i].rippleVelocity * dt
            particles[i].rippleHeight = max(-8.0, min(8.0, particles[i].rippleHeight))
        }
    }

    public func sendRipple(at point: CGPoint, impulse: CGFloat = 5.0) {
        wake()
        // Find closest boundary particle and add impulse
        var closestIdx = 0
        var closestDist: CGFloat = .infinity
        for (i, p) in particles.enumerated() {
            let d = hypot(p.position.x - point.x, p.position.y - point.y)
            if d < closestDist {
                closestDist = d
                closestIdx = i
            }
        }
        if closestIdx < particles.count {
            particles[closestIdx].rippleVelocity += impulse
        }
    }

    // MARK: - Geometry & Metrics Calculations

    public func calculateTargetArea() -> CGFloat {
        let w = contentRect.width + contentPadding * 2.0
        let h = contentRect.height + contentPadding * 2.0
        // Elliptic/organic bulge allowance (~1.12x rectangular area)
        return w * h * 1.12
    }

    public func calculateEnclosedArea() -> CGFloat {
        guard particles.count >= 3 else { return 0 }
        var area: CGFloat = 0.0
        let n = particles.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += particles[i].position.x * particles[j].position.y
            area -= particles[j].position.x * particles[i].position.y
        }
        return abs(area) * 0.5
    }

    private func recomputeNormals() {
        let n = particles.count
        guard n >= 3 else { return }

        for i in 0..<n {
            let prev = particles[(i - 1 + n) % n].position
            let next = particles[(i + 1) % n].position

            let tx = next.x - prev.x
            let ty = next.y - prev.y
            let len = max(0.001, sqrt(tx * tx + ty * ty))

            // Outward normal for counter-clockwise contour: (ty, -tx)
            particles[i].normal = CGPoint(x: ty / len, y: -tx / len)
        }
    }

    private func updatePath() {
        guard particles.count >= 3 else {
            currentPath = Path()
            return
        }

        var path = Path()
        let n = particles.count

        // Render cubic Catmull-Rom spline through boundary points
        let p0 = particles[0].position
        path.move(to: p0)

        for i in 0..<n {
            let pPrev = particles[(i - 1 + n) % n].position
            let pCurr = particles[i].position
            let pNext = particles[(i + 1) % n].position
            let pNextNext = particles[(i + 2) % n].position

            // Add boundary wave displacement along normal
            let waveOffset = particles[i].rippleHeight
            let displacedCurr = CGPoint(
                x: pCurr.x + particles[i].normal.x * waveOffset,
                y: pCurr.y + particles[i].normal.y * waveOffset
            )

            let cp1 = CGPoint(
                x: displacedCurr.x + (pNext.x - pPrev.x) / 6.0,
                y: max(notchLipY, displacedCurr.y + (pNext.y - pPrev.y) / 6.0)
            )
            let cp2 = CGPoint(
                x: pNext.x - (pNextNext.x - displacedCurr.x) / 6.0,
                y: max(notchLipY, pNext.y - (pNextNext.y - displacedCurr.y) / 6.0)
            )

            path.addCurve(to: pNext, control1: cp1, control2: cp2)
        }

        path.closeSubpath()
        self.currentPath = path
    }

    private func evaluateEnergyAndMetrics() {
        var totalEnergy: CGFloat = 0.0
        for p in particles {
            let dx = p.position.x - p.prevPosition.x
            let dy = p.position.y - p.prevPosition.y
            totalEnergy += (dx * dx + dy * dy)
        }

        let avgEnergy = totalEnergy / CGFloat(max(1, particles.count))
        let curArea = calculateEnclosedArea()
        let tgtArea = calculateTargetArea() * max(0.01, flowProgress)

        // Measure overshoot percentage
        let stepOvershoot = max(0.0, (peakAreaForStep - tgtArea) / max(100.0, tgtArea)) * 100.0

        // Measure settling time
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - stepStartTime
        let areaDiffRatio = abs(curArea - tgtArea) / max(100.0, tgtArea)

        if areaDiffRatio < 0.03 && avgEnergy < sleepThreshold && !settlingRecorded && elapsed > 0.25 {
            settlingRecorded = true
            metrics.settlingTimeSeconds = elapsed
        }

        // Update contentAlpha based on lifecycle phase
        switch lifecycleState {
        case .open:
            contentAlpha = 1.0
        case .closed:
            contentAlpha = 0.0
        case .opening:
            contentAlpha = max(0.0, min(1.0, (flowProgress - 0.35) / 0.65))
        case .closing:
            contentAlpha = max(0.0, min(1.0, (flowProgress - 0.20) / 0.80))
        }

        metrics.lifecycle = lifecycleState
        metrics.flowProgress = flowProgress

        if lifecycleState == .closed {
            metrics.isSleeping = true
            consecutiveSleepFrames = 20
        } else if avgEnergy < sleepThreshold && !isInteracting && (lifecycleState == .open) {
            consecutiveSleepFrames += 1
            if consecutiveSleepFrames > 12 {
                metrics.isSleeping = true
            }
        } else {
            consecutiveSleepFrames = 0
            metrics.isSleeping = false
        }

        metrics.currentArea = curArea
        metrics.targetArea = tgtArea
        metrics.kineticEnergy = avgEnergy
        metrics.overshootPercentage = stepOvershoot
        metrics.oscillationCount = zeroCrossingCount
    }
}
