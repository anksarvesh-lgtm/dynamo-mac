import AppKit
import SwiftUI

/// Island material. Compact/idle states stay pure black so the Island is indistinguishable from the
/// hardware notch; the expanded surface blends toward Liquid Glass by `glassIntensity`.
/// Reduce Transparency → solid. Increase Contrast → visible outline.
struct IslandBackground: View {
    var shape: IslandShape
    /// 0 = solid black, 1 = full glass.
    var glassAmount: Double
    /// Lighter, more see-through glass (compact).
    var clear = false
    var reduceTransparency: Bool
    var highContrast: Bool

    var body: some View {
        let glass = reduceTransparency ? 0 : max(0, min(1, glassAmount))
        ZStack {
            if glass > 0.001 {
                GlassLayer(shape: shape, clear: clear)
                    .opacity(min(1, glass * 1.6))
            }
            shape.fill(Color.black.opacity(clear ? 0.42 - glass * 0.2 : 1 - glass * 0.45))
            if glass > 0.001 {
                // A single hairline edge — the glass itself provides the depth.
                shape.stroke(.white.opacity(0.14 * glass), lineWidth: 0.75)
            }
            if highContrast {
                shape.stroke(Color.white.opacity(0.85), lineWidth: 1.5)
            }
        }
    }
}

/// Liquid Glass on macOS 26+, behind-window vibrancy on earlier systems.
private struct GlassLayer: View {
    var shape: IslandShape
    var clear = false
    var body: some View {
        if #available(macOS 26, *) {
            Color.clear.glassEffect(clear ? .clear.tint(.black.opacity(0.18)) : .regular.tint(.black.opacity(0.25)), in: shape)
        } else {
            VisualEffectBackground(material: .hudWindow).clipShape(shape)
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}
