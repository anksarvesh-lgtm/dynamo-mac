//
//  NeonPixelCatView.swift
//  ClaudeIsland
//
//  Neon / cyberpunk variant of the pixel cat, used as the first-launch
//  analytics loading animation. Shares the exact shape with
//  PixelCharacterView (13x11 grid) but paints each "on" pixel with a
//  per-cell HSB color driven by position + time, producing a traveling
//  lime → cyan → magenta wave across the cat. A second blurred layer
//  underneath adds an outer-glow halo so the whole thing looks like a
//  neon sign.
//

import SwiftUI

struct NeonPixelCatView: View {
    // Same grid as PixelCharacterView so the cat looks identical in shape.
    static let gridW = 13
    static let gridH = 11
    static let P: CGFloat = 4
    static let canvasW: CGFloat = CGFloat(gridW) * P + 8
    static let canvasH: CGFloat = CGFloat(gridH) * P + 8

    /// Where the cat body's "on" pixels are. Extracted from the idle /
    /// thinking state of PixelCharacterView — the shape is static, only
    /// the colors change over time. We include the full head, ears,
    /// whiskers, nose and chin — every pixel that's normally lit in the
    /// original cat, minus the blink frames which are too short to matter.
    private static let onPixels: [(Int, Int)] = {
        var a: [(Int, Int)] = []
        // Row 0 — ear tips
        a += [(2, 0), (10, 0)]
        // Row 1 — ears
        a += [(1, 1), (2, 1), (3, 1), (9, 1), (10, 1), (11, 1)]
        // Row 2 — ears + stripe
        a += [(1, 2), (2, 2), (3, 2), (4, 2), (5, 2), (6, 2), (7, 2), (8, 2), (9, 2), (10, 2), (11, 2)]
        // Row 3 — head + stripe
        a += [(1, 3), (2, 3), (3, 3), (4, 3), (5, 3), (6, 3), (7, 3), (8, 3), (9, 3), (10, 3), (11, 3)]
        // Row 4 — head
        a += [(1, 4), (2, 4), (3, 4), (4, 4), (5, 4), (6, 4), (7, 4), (8, 4), (9, 4), (10, 4), (11, 4)]
        // Row 5 — eyes row
        a += [(0, 5), (1, 5), (2, 5), (3, 5), (4, 5), (5, 5), (6, 5), (7, 5), (8, 5), (9, 5), (10, 5), (11, 5), (12, 5)]
        // Row 6 — whiskers
        a += [(0, 6), (1, 6), (2, 6), (3, 6), (4, 6), (5, 6), (6, 6), (7, 6), (8, 6), (9, 6), (10, 6), (11, 6), (12, 6)]
        // Row 7 — nose row
        a += [(0, 7), (1, 7), (2, 7), (3, 7), (4, 7), (5, 7), (6, 7), (7, 7), (8, 7), (9, 7), (10, 7), (11, 7), (12, 7)]
        // Row 8 — lower face
        a += [(1, 8), (2, 8), (3, 8), (4, 8), (5, 8), (6, 8), (7, 8), (8, 8), (9, 8), (10, 8), (11, 8)]
        // Row 9 — chin
        a += [(2, 9), (3, 9), (4, 9), (5, 9), (6, 9), (7, 9), (8, 9), (9, 9), (10, 9)]
        // Row 10 — bottom
        a += [(3, 10), (4, 10), (5, 10), (6, 10), (7, 10), (8, 10), (9, 10)]
        return a
    }()

    /// The two "eye" pixels (drawn in black in the source to make the eyes
    /// pop). In neon mode we draw them as bright white cores so the cat
    /// looks "awake" without breaking the neon aesthetic.
    private static let eyePixels: [(Int, Int)] = [(3, 5), (9, 5)]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, _ in
                let t = timeline.date.timeIntervalSinceReferenceDate

                // Offset everything by (4, 4) so the glow halo around edge
                // pixels has room to bleed without getting clipped.
                let ox: CGFloat = 4
                let oy: CGFloat = 4

                // PASS 1 — outer glow halo. Draw every pixel slightly
                // larger, heavily blurred, at low alpha. The blur makes
                // the whole cat radiate a soft neon aura.
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 3.5))
                    for (x, y) in Self.onPixels {
                        let c = Self.neonColor(x: x, y: y, time: t, layer: .halo)
                        let rect = CGRect(
                            x: CGFloat(x) * Self.P + ox - 1.5,
                            y: CGFloat(y) * Self.P + oy - 1.5,
                            width: Self.P + 3,
                            height: Self.P + 3
                        )
                        layer.fill(Path(rect), with: .color(c))
                    }
                }

                // PASS 2 — crisp core pixels. These are the actual sharp
                // pixel art on top of the glow halo.
                for (x, y) in Self.onPixels {
                    let c = Self.neonColor(x: x, y: y, time: t, layer: .core)
                    let rect = CGRect(
                        x: CGFloat(x) * Self.P + ox,
                        y: CGFloat(y) * Self.P + oy,
                        width: Self.P,
                        height: Self.P
                    )
                    ctx.fill(Path(rect), with: .color(c))
                }

                // PASS 3 — eye highlights. Bright white cores so you can
                // actually see the cat has eyes under the neon wash.
                for (x, y) in Self.eyePixels {
                    let rect = CGRect(
                        x: CGFloat(x) * Self.P + ox,
                        y: CGFloat(y) * Self.P + oy,
                        width: Self.P,
                        height: Self.P
                    )
                    ctx.fill(Path(rect), with: .color(.white))
                }
            }
            .frame(width: Self.canvasW, height: Self.canvasH)
        }
    }

    // MARK: - Neon color generator

    private enum ColorLayer { case halo, core }

    /// Per-pixel color. Hue is **fixed to lime** (CodeIsland brand
    /// `#CAFF00`, hue ≈ 0.2) — every pixel stays the same color family.
    /// What varies is the per-pixel **brightness / alpha**: each cell has
    /// its own pseudo-random time-varying intensity, so the cat looks
    /// like a neon sign where the tubes flicker independently.
    private static func neonColor(x: Int, y: Int, time: Double, layer: ColorLayer) -> Color {
        // Pseudo-random phase offset per pixel, derived from its (x, y)
        // grid coordinates. Using two large-ish primes scrambles adjacent
        // pixels enough that they look uncorrelated.
        let seed = Double(x &* 7919 &+ y &* 104729)

        // Stack three sine waves at different frequencies + the per-pixel
        // phase offset. Summing multiple waves gives a more organic,
        // non-repeating flicker than a single sine.
        let w1 = sin(time * 1.9 + seed * 0.00073)
        let w2 = sin(time * 3.1 + seed * 0.00041)
        let w3 = sin(time * 0.8 + seed * 0.00019)
        let combined = (w1 + w2 + w3) / 3.0  // -1 .. 1

        // Map combined wave into a brightness range. Min 0.35 so the cat
        // silhouette is always visible; max 1.0 for fully-lit cells.
        let intensity = 0.35 + (combined + 1.0) * 0.5 * 0.65  // 0.35..1.0

        // Fixed lime hue from CodeIsland brand color #CAFF00.
        // HSB of #CAFF00 ≈ hue 0.211, sat 1.0, brightness 1.0.
        let hue = 0.211

        switch layer {
        case .halo:
            // Halo uses the same lime hue, a bit dimmer, lower alpha so
            // the blur pass spreads it into a soft outer glow.
            return Color(hue: hue, saturation: 1.0, brightness: intensity * 0.9, opacity: 0.45 * intensity)
        case .core:
            // Core: full-strength lime, alpha tracks intensity so faint
            // cells drop to a dim glow rather than going fully black.
            return Color(hue: hue, saturation: 1.0, brightness: intensity, opacity: 0.55 + intensity * 0.45)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
        NeonPixelCatView()
            .scaleEffect(3)
    }
    .frame(width: 400, height: 300)
}
