//
//  LiquidIslandCanvasView.swift
//  LiquidDynamo
//
//  SwiftUI View integrating the Metal SDF Liquid Island Shader with automatic Canvas fallback.
//

import SwiftUI

public struct LiquidIslandCanvasView: View {
    public var lobes: [LiquidIslandLobe]
    public var k: CGFloat
    public var lighting: LiquidLightingConfig
    public var tintColor: Color
    public var forceFallback: Bool = false

    public init(
        lobes: [LiquidIslandLobe],
        k: CGFloat = 16.0,
        lighting: LiquidLightingConfig = .init(),
        tintColor: Color = Color(red: 0.06, green: 0.75, blue: 0.52),
        forceFallback: Bool = false
    ) {
        self.lobes = lobes
        self.k = k
        self.lighting = lighting
        self.tintColor = tintColor
        self.forceFallback = forceFallback
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if !forceFallback && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                metalShaderView(size: size)
            } else {
                canvasFallbackView(size: size)
            }
        }
    }

    // MARK: - 1. Primary Metal Shader View (macOS 14+)

    @ViewBuilder
    private func metalShaderView(size: CGSize) -> some View {
        let lobeFloats = flatLobeFloats()
        let count = Float(min(lobes.count, 8))
        let kVal = Float(k)

        Rectangle()
            .fill(Color.black.opacity(0.001))
            .colorEffect(
                ShaderLibrary.liquidIsland(
                    .float4(0.0, 0.0, Float(size.width), Float(size.height)),
                    .floatArray(lobeFloats),
                    .float(count),
                    .float(kVal),
                    .float4(lighting.lightDirX, lighting.lightDirY, lighting.lightDirZ, lighting.tightPower),
                    .float4(lighting.tightSpecIntensity, lighting.broadSpecIntensity, lighting.fresnelIntensity, lighting.innerDepthIntensity),
                    .color(tintColor)
                )
            )
            .drawingGroup()
    }

    // MARK: - 2. SwiftUI Canvas Fallback View (macOS 14-25 Fallback / Reduce Transparency)

    @ViewBuilder
    private func canvasFallbackView(size: CGSize) -> some View {
        ZStack {
            // Gooey metaball layer using blur and alpha threshold
            Canvas { context, _ in
                context.addFilter(.alphaThreshold(min: 0.5, color: .black))
                context.addFilter(.blur(radius: max(2.0, min(14.0, k * 0.45))))

                context.drawLayer { ctx in
                    for lobe in lobes where lobe.isActive {
                        let rect = CGRect(
                            x: lobe.centerX - lobe.halfWidth,
                            y: lobe.centerY - lobe.halfHeight,
                            width: lobe.halfWidth * 2.0,
                            height: lobe.halfHeight * 2.0
                        )
                        ctx.fill(Path(roundedRect: rect, cornerRadius: lobe.cornerRadius), with: .color(.black))
                    }
                }
            }

            // Specular sheen and rim highlights overlay
            ForEach(lobes.filter { $0.isActive }) { lobe in
                let rect = CGRect(
                    x: lobe.centerX - lobe.halfWidth,
                    y: lobe.centerY - lobe.halfHeight,
                    width: lobe.halfWidth * 2.0,
                    height: lobe.halfHeight * 2.0
                )
                RoundedRectangle(cornerRadius: lobe.cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(Double(lighting.tightSpecIntensity) * 0.8),
                                tintColor.opacity(Double(lighting.fresnelIntensity) * 0.6),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: lobe.centerX, y: lobe.centerY)
            }
        }
    }

    private func flatLobeFloats() -> [Float] {
        var arr: [Float] = []
        arr.reserveCapacity(64)
        for i in 0..<8 {
            if i < lobes.count {
                arr.append(contentsOf: lobes[i].toFloat8())
            } else {
                arr.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])
            }
        }
        return arr
    }
}
