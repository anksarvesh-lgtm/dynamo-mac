//
//  LiquidBlobCanvasView.swift
//  LiquidDynamo
//
//  Step B: Multi-blob fluid renderer integrating the Metal SDF Liquid Blob Shader
//  with content-driven ellipse metaballs, source blend, and CPU hit testing.
//

import AppKit
import Defaults
import Foundation
import SwiftUI

public struct LiquidBlobCanvasView: View {
    public var blobs: [LiquidBlobLobe]
    public var k: CGFloat
    public var lighting: LiquidLightingConfig
    public var tintColor: Color
    public var notchLipY: CGFloat
    public var seed: CGFloat
    public var time: CGFloat
    public var transparency: CGFloat
    public var bgLuminance: CGFloat
    public var forceFallback: Bool

    public init(
        blobs: [LiquidBlobLobe],
        k: CGFloat = 18.0,
        lighting: LiquidLightingConfig = .init(),
        tintColor: Color = Color(red: 0.06, green: 0.75, blue: 0.52),
        notchLipY: CGFloat = 32.0,
        seed: CGFloat = 42.0,
        time: CGFloat = 0.0,
        transparency: CGFloat = 0.60,
        bgLuminance: CGFloat = 0.0,
        forceFallback: Bool = false
    ) {
        self.blobs = blobs
        self.k = k
        self.lighting = lighting
        self.tintColor = tintColor
        self.notchLipY = notchLipY
        self.seed = seed
        self.time = time
        self.transparency = transparency
        self.bgLuminance = bgLuminance
        self.forceFallback = forceFallback
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

            ZStack {
                // Tier 1: Behind-window blur pass masked to the organic blob field
                if !reduceTransparency && !increaseContrast && !forceFallback {
                    VisualEffectBackdropView(material: .hudWindow, blendingMode: .behindWindow)
                        .clipShape(
                            LiquidBlobShape(
                                blobs: blobs,
                                k: k,
                                seed: seed,
                                time: time
                            )
                        )
                }

                // Tier 2: Metal Shader multi-blob field
                if !forceFallback {
                    metalBlobShaderView(size: size)
                } else {
                    canvasBlobFallbackView(size: size)
                }

                // Tier 3: Accessibility High Contrast perimeter stroke
                if increaseContrast {
                    LiquidBlobShape(
                        blobs: blobs,
                        k: k,
                        seed: seed,
                        time: time
                    )
                    .stroke(Color.white, lineWidth: 1.5)
                }
            }
            .contentShape(
                LiquidBlobShape(
                    blobs: blobs,
                    k: k,
                    seed: seed,
                    time: time
                )
            )
        }
    }

    // MARK: - Metal Shader Pass

    @ViewBuilder
    private func metalBlobShaderView(size: CGSize) -> some View {
        let flatBlobs = flatBlobFloats()
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let effTransparency = reduceTransparency ? 0.0 : Float(transparency)

        Rectangle()
            .fill(Color.black.opacity(0.001))
            .colorEffect(
                ShaderLibrary.liquidBlobField(
                    .float4(0.0, 0.0, Float(size.width), Float(size.height)),
                    .floatArray(flatBlobs),
                    .float(Float(k)),
                    .float4(lighting.lightDirX, lighting.lightDirY, lighting.lightDirZ, lighting.tightPower),
                    .float4(lighting.tightSpecIntensity, lighting.broadSpecIntensity, lighting.fresnelIntensity, lighting.bevelWidth),
                    .color(tintColor),
                    .float4(Float(bgLuminance), Float(notchLipY), Float(time), Float(seed)),
                    .float4(14.0, 0.65, 0.0, effTransparency)
                )
            )
            .drawingGroup()
    }

    // MARK: - Canvas Fallback Pass

    @ViewBuilder
    private func canvasBlobFallbackView(size: CGSize) -> some View {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let shape = LiquidBlobShape(blobs: blobs, k: k, seed: seed, time: time)

        ZStack {
            shape
                .fill(reduceTransparency ? Color(white: 0.08) : Color.black.opacity(0.7))

            // Notch source black gradient
            VStack(spacing: 0) {
                Rectangle().fill(Color.black).frame(height: notchLipY)
                LinearGradient(colors: [Color.black, Color.clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
                Spacer()
            }
            .clipShape(shape)

            if !reduceTransparency {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.4), tintColor.opacity(0.5), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
        }
    }

    private func flatBlobFloats() -> [Float] {
        var arr: [Float] = []
        arr.reserveCapacity(128)
        for i in 0..<16 {
            if i < blobs.count {
                arr.append(contentsOf: blobs[i].toFloat8())
            } else {
                arr.append(contentsOf: [0, 0, 1, 1, 0, 1, 0, 0])
            }
        }
        return arr
    }
}
