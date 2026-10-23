//
//  OrganicFluidLevelView.swift
//  LiquidDynamo
//
//  Step D: Organic fluid level control replacing rigid Capsule/RoundedRectangle sliders.
//  Renders a flowing liquid meniscus track and fluid volume with organic surface wave.
//

import AppKit
import Defaults
import Foundation
import SwiftUI

public struct FluidLobe: Sendable, Equatable {
    public var center: CGPoint
    public var radiusX: CGFloat
    public var radiusY: CGFloat

    public init(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat) {
        self.center = center
        self.radiusX = radiusX
        self.radiusY = radiusY
    }
}

public struct OrganicFluidShape: Shape {
    public var progress: CGFloat
    public var wavePhase: CGFloat
    public var blobs: [FluidLobe]
    public var irregularity: CGFloat

    public init(progress: CGFloat = 1.0, wavePhase: CGFloat = 0.0) {
        self.progress = progress
        self.wavePhase = wavePhase
        self.blobs = []
        self.irregularity = 0.0
    }

    public init(blobs: [FluidLobe], irregularity: CGFloat = 0.15) {
        self.progress = 1.0
        self.wavePhase = 0.0
        self.blobs = blobs
        self.irregularity = irregularity
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, wavePhase) }
        set {
            progress = newValue.first
            wavePhase = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        if !blobs.isEmpty {
            for blob in blobs {
                let rx = blob.radiusX * (1.0 + irregularity * 0.5)
                let ry = blob.radiusY * (1.0 - irregularity * 0.3)
                let blobRect = CGRect(x: blob.center.x - rx, y: blob.center.y - ry, width: rx * 2.0, height: ry * 2.0)
                path.addEllipse(in: blobRect)
            }
            return path
        }
        let w = rect.width
        let h = rect.height
        let fillW = max(0.0, min(w, w * progress))

        guard fillW > 1.0 else { return path }

        let r = h / 2.0
        // Left droplet cap
        path.move(to: CGPoint(x: r, y: 0))
        path.addArc(
            center: CGPoint(x: r, y: r),
            radius: r,
            startAngle: .degrees(270),
            endAngle: .degrees(90),
            clockwise: true
        )

        // Bottom edge leading to right meniscus
        let rightX = fillW
        path.addLine(to: CGPoint(x: max(r, rightX - 3.0), y: h))

        // Right fluid meniscus: curved droplet head
        let wave = sin(wavePhase * 2.0 * .pi) * 1.5
        let meniscusCpX = rightX + 2.0 + wave
        path.addQuadCurve(
            to: CGPoint(x: max(r, rightX - 3.0), y: 0),
            control: CGPoint(x: meniscusCpX, y: r)
        )

        path.closeSubpath()
        return path
    }
}

public struct OrganicFluidLevelView: View {
    @Binding public var value: CGFloat
    public var tintColor: Color
    public var height: CGFloat
    public var onChange: ((CGFloat) -> Void)?

    @State private var isDragging: Bool = false
    @State private var wavePhase: CGFloat = 0.0

    public init(
        value: Binding<CGFloat>,
        tintColor: Color = Color.accentColor,
        height: CGFloat = 7.0,
        onChange: ((CGFloat) -> Void)? = nil
    ) {
        self._value = value
        self.tintColor = tintColor
        self.height = height
        self.onChange = onChange
    }

    public init(
        value: CGFloat,
        tintColor: Color = Color.accentColor,
        height: CGFloat = 7.0,
        onChange: ((CGFloat) -> Void)? = nil
    ) {
        self._value = .constant(value)
        self.tintColor = tintColor
        self.height = height
        self.onChange = onChange
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = min(height, geo.size.height)
            let clampedVal = max(0.0, min(1.0, value))

            ZStack(alignment: .leading) {
                // Background Track: Soft translucent fluid channel with natural meniscus
                OrganicFluidShape(progress: 1.0, wavePhase: 0.0)
                    .fill(Color.white.opacity(0.12))
                    .frame(height: h)

                // Foreground Fill: Vibrant glowing liquid level
                OrganicFluidShape(progress: clampedVal, wavePhase: wavePhase)
                    .fill(
                        LinearGradient(
                            colors: [
                                tintColor.opacity(0.85),
                                tintColor
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: h)
                    .shadow(
                        color: tintColor.opacity(isDragging ? 0.6 : 0.3),
                        radius: isDragging ? 5 : 2,
                        x: 0,
                        y: 1
                    )
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let newProgress = max(0.0, min(1.0, gesture.location.x / w))
                        value = newProgress
                        onChange?(newProgress)
                        wavePhase = (wavePhase + 0.1).truncatingRemainder(dividingBy: 1.0)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: max(14, height + 6))
    }
}
