//
//  LiquidIslandCanvasView.swift
//  LiquidDynamo
//
//  SwiftUI View integrating the Metal SDF Liquid Island Shader with automatic Canvas fallback.
//

import SwiftUI
import Defaults

public struct LiquidIslandCanvasView: View {
    public var lobes: [LiquidIslandLobe]
    public var k: CGFloat
    public var lighting: LiquidLightingConfig
    public var tintColor: Color
    public var waterConfig: LiquidWaterConfig
    public var forceFallback: Bool = false

    public init(
        lobes: [LiquidIslandLobe],
        k: CGFloat = 16.0,
        lighting: LiquidLightingConfig = .init(),
        tintColor: Color = Color(red: 0.06, green: 0.75, blue: 0.52),
        waterConfig: LiquidWaterConfig = .init(),
        forceFallback: Bool = false
    ) {
        self.lobes = lobes
        self.k = k
        self.lighting = lighting
        self.tintColor = tintColor
        self.waterConfig = waterConfig
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
        let kVal = Float(k)
        let currentWater: LiquidWaterConfig = {
            var cfg = waterConfig
            cfg.transparency = Float(Defaults[.islandTransparency])
            cfg.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            return cfg
        }()
        let wp1 = currentWater.waterParams1
        let wp2 = currentWater.waterParams2

        let rootLobe = lobes.first
        let bodyLobe = lobes.count > 1 ? lobes[1] : nil
        let isNotchAttached = rootLobe?.isActive ?? true

        let blobLobes = lobes.enumerated().map { (idx, l) in
            LiquidBlobLobe(
                id: idx,
                name: l.name,
                centerX: l.centerX,
                centerY: l.centerY,
                radiusX: max(2.0, l.halfWidth),
                radiusY: max(2.0, l.halfHeight),
                weight: 1.0,
                irregularity: 0.15,
                isActive: l.isActive
            )
        }

        ZStack {
            // Tier 1: Behind-window blur pass masked to the liquid island geometry
            if !currentWater.reduceTransparency && !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
                VisualEffectBackdropView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(
                        LiquidBlobShape(
                            blobs: blobLobes,
                            k: CGFloat(kVal),
                            seed: CGFloat(currentWater.seed),
                            time: CGFloat(currentWater.time)
                        )
                    )
            }

            Rectangle()
                .fill(Color.black.opacity(0.001))
                .colorEffect(
                    ShaderLibrary.liquidIsland(
                        .float4(0.0, 0.0, Float(size.width), Float(size.height)),
                        .floatArray(lobeFloats),
                        .float(kVal),
                        .float4(lighting.lightDirX, lighting.lightDirY, lighting.lightDirZ, lighting.tightPower),
                        .float4(lighting.tightSpecIntensity, lighting.broadSpecIntensity, lighting.fresnelIntensity, lighting.bevelWidth),
                        .color(tintColor),
                        .float4(wp1.0, wp1.1, wp1.2, wp1.3),
                        .float4(wp2.0, wp2.1, wp2.2, wp2.3)
                    )
                )
                .drawingGroup()

            // Increase Contrast Border
            if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
                LiquidBlobShape(
                    blobs: blobLobes,
                    k: CGFloat(kVal),
                    seed: CGFloat(currentWater.seed),
                    time: CGFloat(currentWater.time)
                )
                .stroke(Color.white, lineWidth: 1.5)
            }
        }
    }

    // MARK: - 2. SwiftUI Canvas Fallback View (macOS 14-25 Fallback / Reduce Transparency)

    @ViewBuilder
    private func canvasFallbackView(size: CGSize) -> some View {
        let isReduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let isIncreaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let tVal = isReduceTransparency ? 0.0 : Defaults[.islandTransparency]

        ZStack {
            // Behind-Window Blur for Fallback when transparency is permitted
            if !isReduceTransparency && !isIncreaseContrast {
                VisualEffectBackdropView(material: .hudWindow, blendingMode: .behindWindow)
            }

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
            .opacity(isReduceTransparency || isIncreaseContrast ? 1.0 : max(0.40, 1.0 - tVal * 0.55))

            // Notch seam guard: top 12pt is pure opaque black (#000000)
            VStack(spacing: 0) {
                Rectangle().fill(Color.black).frame(height: 12)
                LinearGradient(colors: [Color.black, Color.clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
                Spacer()
            }

            // Specular sheen and rim highlights overlay (suppressed in Reduce Transparency)
            if !isReduceTransparency {
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

            if isIncreaseContrast {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white, lineWidth: 1.5)
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
