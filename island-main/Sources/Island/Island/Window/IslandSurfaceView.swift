import AppKit
import QuartzCore
import SwiftUI

/// The Island's morphing surface, driven entirely by Core Animation.
///
/// The outline, its glass, the dark tint, the hairline and the content clip are all layers whose
/// `path`/`opacity` spring in the render server (`CASpringAnimation`). The app does no per-frame work
/// while the Island opens or closes — that is what makes the motion smooth. SwiftUI renders only the
/// content, laid out once at its final size, inside `contentHost`.
@MainActor
final class IslandSurfaceView: NSView {
    struct Geometry: Equatable {
        var width: CGFloat          // body width including ears
        var height: CGFloat
        var earRadius: CGFloat
        var bottomRadius: CGFloat
        var offsetX: CGFloat
        var glass: CGFloat          // 0 = solid black, 1 = full glass
        var clearGlass: Bool
        var visible: Bool
        var highContrast: Bool
    }

    enum Motion { case open, close, morph, none }

    let contentHost: NSView
    private let backgroundContainer = FlippedView()
    private let glassView: NSView
    private let tintLayer = CALayer()
    private let edgeLayer = CAShapeLayer()
    private let backgroundMask = CAShapeLayer()
    private let contentMask = CAShapeLayer()
    private(set) var current: Geometry?
    var reduceMotion = false
    var speed: Double = 1

    init(contentHost: NSView) {
        self.contentHost = contentHost
        if #available(macOS 26, *) {
            let g = NSGlassEffectView()
            g.style = .regular
            glassView = g
        } else {
            let v = NSVisualEffectView()
            v.material = .hudWindow
            v.blendingMode = .behindWindow
            v.state = .active
            v.appearance = NSAppearance(named: .darkAqua)
            glassView = v
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        backgroundContainer.wantsLayer = true
        backgroundContainer.layer?.mask = backgroundMask
        addSubview(backgroundContainer)
        backgroundContainer.addSubview(glassView)
        tintLayer.backgroundColor = NSColor.black.cgColor
        backgroundContainer.layer?.addSublayer(tintLayer)

        edgeLayer.fillColor = nil
        edgeLayer.lineWidth = 0.75
        edgeLayer.strokeColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.addSublayer(edgeLayer)

        contentHost.wantsLayer = true
        contentHost.layer?.mask = contentMask
        addSubview(contentHost)
        for l in [backgroundMask, contentMask, edgeLayer] { l.actions = Self.noImplicitActions }
        tintLayer.actions = Self.noImplicitActions
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        for v in [backgroundContainer, glassView, contentHost] { v.frame = bounds }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.frame = bounds
        for l in [backgroundMask, contentMask, edgeLayer] { l.frame = bounds }
        CATransaction.commit()
        if let current { apply(current, motion: .none) }
    }

    // MARK: Morph

    func apply(_ g: Geometry, motion: Motion) {
        let previous = current
        current = g
        guard bounds.width > 0 else { return }
        let canvas = CGRect(origin: .zero, size: bounds.size)
        let outline = shape(g, ears: true).path(in: canvas).cgPath
        let clip = shape(g, ears: false).path(in: canvas).cgPath
        let tint: Float = g.visible ? Float(g.clearGlass ? 0.42 - g.glass * 0.2 : 1 - g.glass * 0.45) : 0
        let glassOpacity: Float = g.visible ? Float(min(1, g.glass * 1.6)) : 0
        let edgeOpacity: Float = g.visible ? Float(g.highContrast ? 1 : (g.glass > 0.001 ? 1 : 0)) : 0
        edgeLayer.strokeColor = g.highContrast ? NSColor.white.withAlphaComponent(0.85).cgColor : NSColor.white.withAlphaComponent(0.14 * g.glass).cgColor
        edgeLayer.lineWidth = g.highContrast ? 1.5 : 0.75
        if #available(macOS 26, *), let glass = glassView as? NSGlassEffectView {
            glass.style = g.clearGlass ? .clear : .regular
        }

        let animation = motion == .none || previous == nil ? nil : spring(for: motion)
        animate(backgroundMask, "path", to: outline, with: animation)
        animate(edgeLayer, "path", to: outline, with: animation)
        animate(contentMask, "path", to: clip, with: animation)
        animate(tintLayer, "opacity", to: tint, with: animation)
        animate(glassView.layer, "opacity", to: glassOpacity, with: animation)
        animate(edgeLayer, "opacity", to: edgeOpacity, with: animation)
    }

    private func shape(_ g: Geometry, ears: Bool) -> IslandShape {
        let s = IslandShape(earRadius: g.earRadius, bottomRadius: g.bottomRadius, width: g.width, height: g.height, offsetX: g.offsetX)
        return ears ? s : s.withoutEars
    }

    /// Spring from the layer's *current on-screen* value, so interrupting a morph never jumps.
    private func animate(_ layer: CALayer?, _ key: String, to value: Any, with template: CASpringAnimation?) {
        guard let layer else { return }
        let from = layer.presentation()?.value(forKeyPath: key) ?? layer.value(forKeyPath: key)
        layer.setValue(value, forKeyPath: key)
        guard let template, let from else { layer.removeAnimation(forKey: key); return }
        let a = template.copy() as! CASpringAnimation
        a.keyPath = key
        a.fromValue = from
        a.toValue = value
        layer.add(a, forKey: key)
    }

    private func spring(for motion: Motion) -> CASpringAnimation {
        let a = CASpringAnimation()
        if reduceMotion {
            a.mass = 1; a.stiffness = 400; a.damping = 40 // critically damped, short
        } else {
            let s = max(0.5, min(2, speed))
            // Soft, liquid open with a gentle swell; a smooth, settled close.
            let (response, damping): (Double, Double) = switch motion {
            case .open: (0.46 / s, 0.74)
            case .close: (0.40 / s, 0.9)
            default: (0.42 / s, 0.84)
            }
            a.mass = 1
            a.stiffness = pow(2 * .pi / response, 2)
            a.damping = 4 * .pi * damping / response
        }
        a.initialVelocity = 0
        a.duration = a.settlingDuration
        a.fillMode = .backwards
        a.isRemovedOnCompletion = true
        return a
    }

    private static let noImplicitActions: [String: CAAction] = [
        "path": NSNull(), "opacity": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull(),
    ]
}

/// Top-left origin, so mask paths share the Island's coordinate space.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
